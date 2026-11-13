class_name ServerCore
extends RefCounted
## The authoritative game server: owns the Sim, steps it at 60 Hz, and talks to up to four clients through
## a NetEndpoint. No nodes, no wall clock: the caller calls tick() once per 60 Hz step.
##
## Inputs: a client sends one input per tick with a sequence number (plus the previous few, in case a
## packet is lost). The server keeps a small jitter buffer per player, consumes one input per tick and
## tells the client in every snapshot which sequence number it has consumed last, so the client can
## re-simulate the inputs the server has not seen yet.

const SNAPSHOT_EVERY := 2          # ticks between snapshots (30 Hz)
const JITTER_TICKS := 3            # inputs to collect before a player's first input is used
const MAX_BUFFER := 8              # more waiting inputs than this: the oldest are dropped (bounded delay)
const NEUTRAL_AFTER := 30          # ticks without any new input: stop repeating the last one
const REBUFFER_AFTER := 30         # ticks without any new input: collect JITTER_TICKS inputs again
const HELLO_TIMEOUT := 300         # ticks a new connection may stay silent before it is dropped
const MAX_PENDING := 8             # connections that have not said hello yet

var cfg: Config
var sim: Sim
var net: NetEndpoint
var slots: Array[Slot] = []
var current_inputs: Array[SimInput] = []   # the input each player had in the last tick
var bots: Array[Bot] = []
var log_fn: Callable = Callable()

## Counters (tests and the status line).
var dropped_packets := 0
var stale_inputs := 0
var underruns := 0
var rejected := 0
var skipped_inputs := 0                    # input numbers the server never received (lost, not covered by redundancy)
var last_snapshot_bytes := 0

var _pending := {}                 # peer -> ticks since connecting (no hello yet)
var _peer_slot := {}               # peer -> slot index


class Slot extends RefCounted:
	var peer := -1
	var buffer := {}               # input seq -> SimInput
	var last_consumed := 0
	var started := false
	var last_input := SimInput.new()
	var starved := 0

	func reset() -> void:
		peer = -1
		buffer.clear()
		last_consumed = 0
		started = false
		last_input = SimInput.new()
		starved = 0


func _init(config: Config, endpoint: NetEndpoint, seed_value := 1, with_bots := false) -> void:
	cfg = config
	net = endpoint
	sim = Sim.new(cfg, seed_value)
	for i in Config.NUM_PLAYERS:
		slots.append(Slot.new())
		current_inputs.append(SimInput.new())
		sim.set_player_enabled(i, with_bots)
		if with_bots:
			bots.append(Bot.new(i, cfg, seed_value + 1 + i))


func players_online() -> int:
	return _peer_slot.size()


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


## One 60 Hz step: network in, inputs, sim, snapshots out.
func tick() -> void:
	pump()
	for peer: int in _pending.keys():
		_pending[peer] += 1
		if _pending[peer] > HELLO_TIMEOUT:
			_pending.erase(peer)
			net.disconnect_peer(peer)
	var dt := 1.0 / Config.TICK_RATE
	var inputs: Array = []
	for i in slots.size():
		var inp: SimInput
		if slots[i].peer >= 0:
			inp = _next_input(slots[i])
		elif not bots.is_empty():
			inp = bots[i].think(sim, dt)
		else:
			inp = SimInput.new()
		current_inputs[i] = inp
		inputs.append(inp)
	sim.step(inputs)
	if sim.tick % SNAPSHOT_EVERY == 0:
		_send_snapshots()
	net.flush()


func _next_input(s: Slot) -> SimInput:
	while s.buffer.size() > MAX_BUFFER:
		s.buffer.erase(_lowest(s.buffer))
		stale_inputs += 1
	if not s.started and s.buffer.size() >= JITTER_TICKS:
		s.started = true
	if s.started and not s.buffer.is_empty():
		var seq := _lowest(s.buffer)
		var inp: SimInput = s.buffer[seq]
		s.buffer.erase(seq)
		skipped_inputs += seq - s.last_consumed - 1   # a gap (lost input) is skipped
		s.last_consumed = seq
		s.last_input = inp
		s.starved = 0
		return inp
	# Nothing to use: repeat the last input for a while, then stand still.
	if s.started:
		s.starved += 1
		underruns += 1
		if s.starved > NEUTRAL_AFTER:
			s.last_input = SimInput.new()
		if s.starved > REBUFFER_AFTER:
			s.started = false
		return s.last_input.repeated()   # a dash is an edge: never repeated
	return SimInput.new()


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


func _on_leave(peer: int) -> void:
	_pending.erase(peer)
	if not _peer_slot.has(peer):
		return
	var i: int = _peer_slot[peer]
	_peer_slot.erase(peer)
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
			if msg.size() == 2 and msg[1] is Dictionary:
				sim.apply_mods(i, Mods.sanitize(msg[1]))
			else:
				dropped_packets += 1
		NetProto.T_PING:
			if msg.size() == 2 and (msg[1] is int or (msg[1] is float and is_finite(msg[1]))):
				net.send(peer, NetProto.pack([NetProto.T_PONG, msg[1]]), false)
			else:
				dropped_packets += 1
		_:
			dropped_packets += 1


func _on_hello(peer: int, msg: Array) -> void:
	if msg.size() != 2 or not (msg[1] is int):
		dropped_packets += 1
		return
	if msg[1] != NetProto.VERSION:
		_log("refused a client: protocol version %s, expected %d" % [str(msg[1]), NetProto.VERSION])
		_reject(peer, "version")
		return
	var free := -1
	for k in slots.size():
		if slots[k].peer < 0:
			free = k
			break
	if free < 0:
		_log("refused a client: server full")
		_reject(peer, "full")
		return
	_pending.erase(peer)
	slots[free].reset()
	slots[free].peer = peer
	_peer_slot[peer] = free
	sim.set_player_enabled(free, true)
	net.send(peer, NetProto.pack([NetProto.T_WELCOME, NetProto.VERSION, free, cfg.to_dict()]), true)
	_log("player %d joined (%d online)" % [free + 1, _peer_slot.size()])


func _on_input(s: Slot, msg: Array) -> void:
	if msg.size() != 3 or not (msg[1] is int) or not (msg[2] is Array):
		dropped_packets += 1
		return
	var seq: int = msg[1]
	var list: Array = msg[2]
	if seq < 1 or seq > NetProto.MAX_SEQ or list.is_empty() or list.size() > NetProto.MAX_INPUTS_PER_PACKET:
		dropped_packets += 1
		return
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
