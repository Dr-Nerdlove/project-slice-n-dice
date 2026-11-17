class_name ServerCore
extends RefCounted
## The authoritative game server: owns the Sim, steps it at 60 Hz, and talks to up to four clients through
## a NetEndpoint. No nodes, no wall clock: the caller calls tick() once per 60 Hz step.
##
## Inputs: a client sends one input per tick with a sequence number (plus the previous few, in case a
## packet is lost). The server keeps a small jitter buffer per player, consumes one input per tick and
## tells the client in every snapshot which sequence number it has consumed last, so the client can
## re-simulate the inputs the server has not seen yet.
##
## The buffer adds to how late every action of a player happens on the server, so its target size is adaptive per
## player: it starts at JITTER_START and grows by one when the buffer runs dry (an underrun: the last input has to
## be repeated, which the client may have predicted differently) or inputs arrive in a burst; it shrinks by one
## after SHRINK_AFTER quiet ticks, and a buffer that stays above its target is trimmed (TRIM_AFTER).

const SNAPSHOT_EVERY := 2          # ticks between snapshots (30 Hz)
const JITTER_MIN := 1              # the smallest target
const JITTER_START := 1            # inputs a player's buffer collects before its first input is used (and its target at first)
const JITTER_MAX := 5              # the target a player's buffer can grow to (inputs waiting; MAX_BUFFER stays the hard limit)
const TRIM_AFTER := 30             # ticks in which the buffer never ran down to its target: one input too many is dropped
const SHRINK_AFTER := 300          # ticks without an underrun or a burst: the target shrinks by one ...
const SHRINK_MAX := 3600           # ... but every growth doubles that wait (up to this), so a link that needs the
                                   # bigger buffer does not run dry again every few seconds
const BURST := 3                   # this many new inputs in one tick count as a burst
const MAX_BUFFER := 8              # more waiting inputs than this: the oldest are dropped (bounded delay)
const NEUTRAL_AFTER := 30          # ticks without any new input: stop repeating the last one
const REBUFFER_AFTER := 30         # ticks without any new input: collect the target number of inputs again
const HELLO_TIMEOUT := 300         # ticks a new connection may stay silent before it is dropped
const IDLE_TIMEOUT := 1800         # ticks (30 s) without any input from a joined player: the slot is freed
const MAX_PENDING := 8             # connections that have not said hello yet
const MAX_TICKS_PER_FRAME := 5     # after a long stall `run` catches up a little, never in a spiral

var cfg: Config
var sim: Sim
var net: NetEndpoint
var slots: Array[Slot] = []
var current_inputs: Array[SimInput] = []   # the input each player had in the last tick
var bots: Array[Bot] = []
var log_fn: Callable = Callable()
## False: a client's modifier choice (T_MODS) is ignored, so every player plays with the server's own values. The
## local host of a real game (Play) sets this; `--server` and the Online tab of the sandbox keep the default.
var accept_client_mods := true

## Counters (tests and the status line).
var dropped_packets := 0
var stale_inputs := 0
var trimmed_inputs := 0                    # inputs dropped because a player's buffer stayed above its target
var underruns := 0
var rejected := 0
var delay_sum := 0                         # over all used inputs: server ticks between an input's arrival and its use
var delay_count := 0
var skipped_inputs := 0                    # input numbers the server never received (lost, not covered by redundancy)
var last_snapshot_bytes := 0

var _acc := 0.0                    # seconds not yet turned into ticks (see `run`)
var _pending := {}                 # peer -> ticks since connecting (no hello yet)
var _peer_slot := {}               # peer -> slot index


class Slot extends RefCounted:
	var peer := -1
	var buffer := {}               # input seq -> SimInput
	var arrived := {}              # input seq -> server tick of its arrival (for the delay statistics)
	var last_consumed := 0
	var started := false
	var last_input := SimInput.new()
	var starved := 0
	var target := JITTER_START     # inputs that should be waiting when one is used
	var calm := 0                  # ticks since the last underrun or burst
	var shrink_wait := SHRINK_AFTER   # calm ticks needed before the target shrinks
	var excess := 0                # consecutive ticks with more than `target` inputs waiting
	var new_inputs := 0            # inputs that arrived since the last tick used one
	var idle := 0                  # ticks since the last valid input packet
	var token := ""                # the client's identity token (lets a dropped player come back to this slot)
	var away := false              # the player dropped during a match: the slot is held, the figure stands still

	func reset() -> void:
		peer = -1
		token = ""
		away = false
		buffer.clear()
		arrived.clear()
		last_consumed = 0
		started = false
		last_input = SimInput.new()
		starved = 0
		target = JITTER_START
		calm = 0
		shrink_wait = SHRINK_AFTER
		excess = 0
		new_inputs = 0
		idle = 0


func _init(config: Config, endpoint: NetEndpoint, seed_value := 1, with_bots := false) -> void:
	cfg = config
	net = endpoint
	sim = Sim.new(cfg, seed_value)
	for i in Config.NUM_PLAYERS:
		slots.append(Slot.new())
		current_inputs.append(SimInput.new())
		sim.set_player_enabled(i, with_bots and i < cfg.player_count)
		if with_bots:
			bots.append(Bot.new(i, cfg, seed_value + 1 + i))


func players_online() -> int:
	return _peer_slot.size()


## Slots held for players who dropped during a match (they can come back with their token until the match ends).
func away_slots() -> Array:
	var out := []
	for i in slots.size():
		if slots[i].away:
			out.append(i)
	return out


func _log(text: String) -> void:
	if log_fn.is_valid():
		log_fn.call(text)


## Handles everything that arrived from the network.
func pump() -> void:
	for ev: Dictionary in net.poll():
		var peer: int = ev["peer"]
		match ev["kind"]:
			NetEndpoint.Kind.CONNECT:
				if _pending.size() >= MAX_PENDING:
					net.disconnect_peer(peer)
				else:
					_pending[peer] = 0
			NetEndpoint.Kind.DISCONNECT:
				_on_leave(peer)
			NetEndpoint.Kind.PACKET:
				_on_packet(peer, ev["data"])


## Frame driver for hosts that live in a node (dedicated server, local host): network in every frame, then as
## many fixed 60 Hz ticks as `delta` allows, at most MAX_TICKS_PER_FRAME.
func run(delta: float) -> void:
	pump()
	var dt := 1.0 / Config.TICK_RATE
	_acc = minf(_acc + delta, dt * MAX_TICKS_PER_FRAME)
	while _acc >= dt:
		_acc -= dt
		tick()


## One 60 Hz step: network in, inputs, sim, snapshots out.
func tick() -> void:
	pump()
	for peer: int in _pending.keys():
		_pending[peer] += 1
		if _pending[peer] > HELLO_TIMEOUT:
			_pending.erase(peer)
			net.disconnect_peer(peer)
	var dt := 1.0 / Config.TICK_RATE
	for i in slots.size():
		if slots[i].peer >= 0:
			slots[i].idle += 1
			if slots[i].idle > IDLE_TIMEOUT:
				var idle_peer: int = slots[i].peer
				_log("player %d timed out (no input for %d s)" % [i + 1, IDLE_TIMEOUT / Config.TICK_RATE])
				net.disconnect_peer(idle_peer)
				_on_leave(idle_peer)
	var inputs: Array = []
	for i in slots.size():
		var inp: SimInput
		if slots[i].peer >= 0:
			inp = _next_input(slots[i])
		elif not bots.is_empty() and not slots[i].away:
			inp = bots[i].think(sim, dt)
		else:
			inp = SimInput.new()
		current_inputs[i] = inp
		inputs.append(inp)
	if sim.mode.phase == MatchMode.Phase.SHOP:
		for i in slots.size():
			if slots[i].away:
				sim.shop_done(i)   # nobody there to shop
			elif slots[i].peer < 0 and not bots.is_empty():
				Bot.shop(sim, i)
	sim.step(inputs)
	var ph := sim.mode.phase
	if ph == MatchMode.Phase.MATCH_OVER or ph == MatchMode.Phase.OFF:
		_free_away_slots()
	if sim.tick % SNAPSHOT_EVERY == 0:
		_send_snapshots()
	net.flush()


func _next_input(s: Slot) -> SimInput:
	while s.buffer.size() > MAX_BUFFER:
		_drop_oldest(s, false)
		stale_inputs += 1
	# Adapt the target: a burst of arrivals grows it, quiet ticks shrink it again.
	s.calm += 1
	if s.new_inputs >= BURST:
		_grow(s)
	s.new_inputs = 0
	if s.calm >= s.shrink_wait:
		s.calm = 0
		if s.target > JITTER_MIN:
			s.target -= 1
			s.shrink_wait = maxi(s.shrink_wait / 2, SHRINK_AFTER)
	if not s.started and s.buffer.size() >= s.target:
		s.started = true
	# A buffer that never ran down to its target holds an input too many: drop the oldest.
	if s.started and s.buffer.size() > s.target:
		s.excess += 1
		if s.excess >= TRIM_AFTER:
			s.excess = 0
			_drop_oldest(s, true)
			trimmed_inputs += 1
	else:
		s.excess = 0
	if s.started and not s.buffer.is_empty():
		var seq := _lowest(s.buffer)
		var inp: SimInput = s.buffer[seq]
		s.buffer.erase(seq)
		delay_sum += sim.tick - int(s.arrived[seq])
		delay_count += 1
		s.arrived.erase(seq)
		skipped_inputs += seq - s.last_consumed - 1   # a gap (lost input) is skipped
		s.last_consumed = seq
		s.last_input = inp
		s.starved = 0
		return inp
	# Nothing to use: repeat the last input for a while, then stand still.
	if s.started:
		s.starved += 1
		underruns += 1
		if s.starved == 1:
			_grow(s)
		if s.starved > NEUTRAL_AFTER:
			s.last_input = SimInput.new()
		if s.starved > REBUFFER_AFTER:
			s.started = false
		return s.last_input.repeated()   # a dash is an edge: never repeated
	return SimInput.new()


func _grow(s: Slot) -> void:
	s.target = mini(s.target + 1, JITTER_MAX)
	s.calm = 0
	s.shrink_wait = mini(s.shrink_wait * 2, SHRINK_MAX)


## Drops the oldest waiting input. A dash in it is handed on to the next one (it is an edge: it must not be lost).
## `acknowledge`: the input counts as used (the client may stop re-simulating it, and it is no gap).
func _drop_oldest(s: Slot, acknowledge: bool) -> void:
	var old := _lowest(s.buffer)
	var inp: SimInput = s.buffer[old]
	s.buffer.erase(old)
	s.arrived.erase(old)
	if inp.dash and not s.buffer.is_empty():
		(s.buffer[_lowest(s.buffer)] as SimInput).dash = true
	if acknowledge:
		s.last_consumed = old


static func _lowest(buffer: Dictionary) -> int:
	var best := -1
	for k: int in buffer:
		if best < 0 or k < best:
			best = k
	return best


func _send_snapshots() -> void:
	if _peer_slot.is_empty():
		return
	var enc: Array = []
	for inp in current_inputs:
		enc.append(NetProto.encode_input(inp))
	var body := NetProto.snapshot_body(enc, sim.save_state())
	last_snapshot_bytes = body.size() + NetProto.SNAPSHOT_HEADER
	for peer: int in _peer_slot:
		var s: Slot = slots[_peer_slot[peer]]
		net.send(peer, NetProto.snapshot_packet(sim.tick, s.last_consumed, body), false)


func _reject(peer: int, reason: String) -> void:
	rejected += 1
	net.send(peer, NetProto.pack([NetProto.T_REJECT, reason]), true)
	net.disconnect_peer(peer)
	_pending.erase(peer)


## The match is over (or left): the places held for absent players are given up.
func _free_away_slots() -> void:
	for i in slots.size():
		if slots[i].away:
			slots[i].reset()
			if bots.is_empty():
				sim.set_player_enabled(i, false)
			_log("player %d: held place freed" % (i + 1))


func _on_leave(peer: int) -> void:
	_pending.erase(peer)
	if not _peer_slot.has(peer):
		return
	var i: int = _peer_slot[peer]
	_peer_slot.erase(peer)
	if match_locked() and i < sim.mode.roster.size() and sim.mode.roster[i] and slots[i].token != "":
		var tok: String = slots[i].token
		slots[i].reset()
		slots[i].token = tok
		slots[i].away = true
		_log("player %d dropped, place kept (%d online)" % [i + 1, _peer_slot.size()])
		return
	slots[i].reset()
	if bots.is_empty():
		sim.set_player_enabled(i, false)
	_log("player %d left (%d online)" % [i + 1, _peer_slot.size()])


func _on_packet(peer: int, data: PackedByteArray) -> void:
	var msg := NetProto.unpack(data, NetProto.MAX_CLIENT_PACKET)
	if msg.is_empty():
		dropped_packets += 1
		return
	var type: int = msg[0]
	if _pending.has(peer):
		if type == NetProto.T_HELLO:
			_on_hello(peer, msg)
		else:
			dropped_packets += 1
		return
	if not _peer_slot.has(peer):
		dropped_packets += 1
		return
	var i: int = _peer_slot[peer]
	match type:
		NetProto.T_INPUT:
			_on_input(slots[i], msg)
		NetProto.T_MODS:
			if not accept_client_mods or sim.mode.phase != MatchMode.Phase.OFF:
				pass   # fixed values, or a match: its modifiers come only from the shop
			elif msg.size() == 2 and msg[1] is Dictionary:
				sim.apply_mods(i, Mods.sanitize(msg[1]))
			else:
				dropped_packets += 1
		NetProto.T_SKIN:
			if msg.size() == 2 and msg[1] is int and msg[1] >= 0 and msg[1] < Config.SKIN_COUNT:
				_take_skin(i, msg[1])
			else:
				dropped_packets += 1
		NetProto.T_COLOR:
			if msg.size() == 2 and msg[1] is int and msg[1] >= 0 and msg[1] < Config.COLOR_COUNT:
				sim.set_color(i, msg[1])
			else:
				dropped_packets += 1
		NetProto.T_TEAM:
			if msg.size() != 1 or not request_team_switch(i):
				dropped_packets += 1
		NetProto.T_SHOP:
			if msg.size() == 4 and msg[1] is int and msg[2] is int and msg[3] is int:
				apply_shop(i, msg[1], msg[2], msg[3])
			else:
				dropped_packets += 1
		NetProto.T_PING:
			if msg.size() == 2 and (msg[1] is int or (msg[1] is float and is_finite(msg[1]))):
				net.send(peer, NetProto.pack([NetProto.T_PONG, msg[1]]), false)
			else:
				dropped_packets += 1
		_:
			dropped_packets += 1


## Teams: moves human slot `i` to the other team by swapping teams with a seat there that is not a human (a bot or an
## empty seat inside the room). Only before a match or after one; false (refused) otherwise or when every seat on the
## other team is a human.
func request_team_switch(i: int) -> bool:
	var ph := sim.mode.phase
	if not sim.mode.is_team_mode() or (ph != MatchMode.Phase.OFF and ph != MatchMode.Phase.MATCH_OVER):
		return false
	if i < 0 or i >= cfg.player_count:
		return false
	for j in mini(slots.size(), cfg.player_count):
		if sim.mode.team_of(j) != sim.mode.team_of(i) and not _is_human(j):
			return sim.swap_team(i, j)
	return false


func _is_human(k: int) -> bool:
	return slots[k].peer >= 0 or slots[k].away


## One shop action of slot `i` (from the network or the host's own client); the sim checks everything.
func apply_shop(i: int, action: int, arg: int, seq: int) -> bool:
	match action:
		NetProto.SHOP_BUY:
			return sim.shop_buy(i, arg, seq)
		NetProto.SHOP_REROLL:
			return sim.shop_reroll(i, seq)
		NetProto.SHOP_DONE:
			return sim.shop_done(i)
		NetProto.SHOP_SELL:
			if arg < 0 or arg >= Mods.ORDER.size():
				return false
			return sim.shop_sell(i, Mods.ORDER[arg], seq)
		NetProto.SHOP_LOCK:
			return sim.shop_lock(i, arg, seq)
	return false


## Starts a match with the players connected now (false: fewer than two).
func start_match(target: int) -> bool:
	return sim.start_match(target)


## True while a match is running (countdown, play, result): nobody new may join. Free play and a finished match are open.
func match_locked() -> bool:
	return sim.mode.running()


func _on_hello(peer: int, msg: Array) -> void:
	if msg.size() != 3 or not (msg[1] is int) or not NetProto.valid_token(msg[2]):
		dropped_packets += 1
		return
	var token: String = msg[2]
	if msg[1] != NetProto.VERSION:
		_log("refused a client: protocol version %s, expected %d" % [str(msg[1]), NetProto.VERSION])
		_reject(peer, "version")
		return
	# A returning player: the same token gets its old slot back, also during a match.
	for k in slots.size():
		if slots[k].token == token and (slots[k].away or slots[k].peer >= 0):
			var old_peer: int = slots[k].peer
			if old_peer >= 0:
				# The server has not noticed the drop yet: the new connection takes over.
				_peer_slot.erase(old_peer)
				net.disconnect_peer(old_peer)
			slots[k].reset()
			slots[k].token = token
			slots[k].peer = peer
			_pending.erase(peer)
			_peer_slot[peer] = k
			sim.set_player_enabled(k, true)
			net.send(peer, NetProto.pack([NetProto.T_WELCOME, NetProto.VERSION, k, cfg.to_dict()]), true)
			_log("player %d rejoined (%d online)" % [k + 1, _peer_slot.size()])
			return
	if match_locked():
		_log("refused a client: match already started")
		_reject(peer, "started")
		return
	var free := -1
	var want_team := _team_with_fewer_humans()   # Teams: the joiner helps the team with fewer humans (-1: no teams)
	for only_team in [want_team, -1]:   # first a free seat there, else any free seat
		for k in mini(slots.size(), cfg.player_count):   # the room holds `player_count` players
			if slots[k].peer < 0 and not slots[k].away and (only_team < 0 or sim.mode.team_of(k) == only_team):
				free = k
				break
		if free >= 0:
			break
	if free < 0:
		_log("refused a client: server full")
		_reject(peer, "full")
		return
	_pending.erase(peer)
	slots[free].reset()
	slots[free].token = token
	slots[free].peer = peer
	_peer_slot[peer] = free
	sim.set_player_enabled(free, true)
	net.send(peer, NetProto.pack([NetProto.T_WELCOME, NetProto.VERSION, free, cfg.to_dict()]), true)
	_log("player %d joined (%d online)" % [free + 1, _peer_slot.size()])


## A player asks for a figure. A free one is taken; one held by another human moves the asker to the next free one;
## one held by a BOT is taken from the bot (it gets another free figure), so humans are never blocked by bots.
func _take_skin(i: int, k: int) -> void:
	for o in Config.NUM_PLAYERS:
		var s: Slot = slots[o]
		if o != i and sim.players[o].enabled and sim.players[o].skin == k and s.peer < 0 and not s.away:
			sim.players[i].skin = k   # briefly shared; the bot then moves on
			sim.set_skin(o, k)
			return
	sim.set_skin(i, k)


## Teams: the team with fewer human players (ties: team 0); -1 without teams.
func _team_with_fewer_humans() -> int:
	if not sim.mode.is_team_mode():
		return -1
	var n := [0, 0]
	for k in mini(slots.size(), cfg.player_count):
		if _is_human(k):
			n[sim.mode.team_of(k)] += 1
	return 0 if n[0] <= n[1] else 1


func _on_input(s: Slot, msg: Array) -> void:
	if msg.size() != 3 or not (msg[1] is int) or not (msg[2] is Array):
		dropped_packets += 1
		return
	var seq: int = msg[1]
	var list: Array = msg[2]
	if seq < 1 or seq > NetProto.MAX_SEQ or list.is_empty() or list.size() > NetProto.MAX_INPUTS_PER_PACKET:
		dropped_packets += 1
		return
	s.idle = 0
	var decoded: Array[SimInput] = []
	for a: Variant in list:
		var inp := NetProto.decode_input(a)
		if inp == null:
			dropped_packets += 1
			return
		decoded.append(inp)
	for k in decoded.size():
		var q := seq - k
		if q > s.last_consumed and not s.buffer.has(q):
			s.buffer[q] = decoded[k]
			s.arrived[q] = sim.tick
			s.new_inputs += 1
