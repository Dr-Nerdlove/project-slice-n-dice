class_name ClientCore
extends RefCounted
## Client side of the netcode: predicts the own character and yo-yo by running the same Sim locally, and
## corrects it when the authoritative snapshot of the server arrives.
##
## Every tick: the local input gets a sequence number, is sent (with the previous few inputs, against
## packet loss) and the local sim steps with it at once, so the own actions react without waiting for the
## network. The other players are stepped with their last input known from the server.
## On a snapshot: load the server state (which already contains all inputs up to the acked sequence
## number), then re-simulate the inputs the server has not seen yet.

enum State { CONNECTING, ONLINE, FAILED, CLOSED }

const CONNECT_TIMEOUT := 6.0       # seconds without a first snapshot
const PING_EVERY := 30             # ticks
const MAX_PENDING := 600           # unacknowledged inputs kept at most (10 s)
const PEAK_WINDOW := 120           # ticks over which correction_peak is held

var net: NetEndpoint
var state := State.CONNECTING
var fail_reason := ""              # "version", "full", "timeout", "refused" or "closed"
var slot := -1
var cfg: Config                    # the server's configuration (set on welcome)
var sim: Sim                       # the predicted sim (set on welcome, valid while ONLINE)
var events: Array = []             # events of the newest local tick (never of re-simulated ticks)

## For the HUD.
var ping_ms := 0.0
var correction := 0.0              # metres: how far the last snapshot moved the predicted own position
var correction_peak := 0.0         # largest correction of the last PEAK_WINDOW ticks
var redundancy := NetProto.REDUNDANCY

## Counters.
var snapshots_applied := 0
var snapshots_dropped := 0
var dropped_packets := 0

var seq := 0
var pending: Array = []            # [{"seq": int, "input": SimInput}] sent but not yet acknowledged
var last_snapshot_tick := -1
var acked := 0

var _others: Array[SimInput] = []
var _wanted_mods: Dictionary = Mods.empty_levels()
var _mods_dirty := true
var _time_ms := 0.0
var _connect_elapsed := 0.0
var _peak_age := 0
var _ticks := 0
var _net_closed := false


func _init(endpoint: NetEndpoint) -> void:
	net = endpoint
	for i in Config.NUM_PLAYERS:
		_others.append(SimInput.new())


func pending_inputs() -> int:
	return pending.size()


## The modifier levels the local player wants; sent to the server when they change.
func set_mods(levels: Dictionary) -> void:
	var clean := Mods.sanitize(levels)
	if clean != _wanted_mods:
		_wanted_mods = clean
		_mods_dirty = true


## Leaves the game (or gives up connecting) and releases the socket. Safe to call in any state.
func close() -> void:
	_shutdown()
	if state == State.CONNECTING or state == State.ONLINE:
		state = State.CLOSED
		fail_reason = "closed"


func _shutdown() -> void:
	if not _net_closed:
		_net_closed = true
		net.close()


## Handles everything that arrived from the network. `dt` (seconds) only drives the connect timeout.
func poll(dt := 0.0) -> void:
	if state == State.FAILED or state == State.CLOSED:
		return
	for ev: Dictionary in net.poll():
		match ev["kind"]:
			NetEndpoint.Kind.CONNECT:
				net.send(1, NetProto.pack([NetProto.T_HELLO, NetProto.VERSION]), true)
			NetEndpoint.Kind.DISCONNECT:
				if state == State.CONNECTING and sim == null:
					_end(State.FAILED, "unreachable")
				else:
					_end(State.CLOSED, "closed")
			NetEndpoint.Kind.PACKET:
				_on_packet(ev["data"])
		if state == State.FAILED or state == State.CLOSED:
			return
	if state == State.CONNECTING:
		_connect_elapsed += dt
		if _connect_elapsed > CONNECT_TIMEOUT:
			_end(State.FAILED, "timeout")


func _end(new_state: int, reason: String) -> void:
	if state == State.FAILED or state == State.CLOSED:
		return
	state = new_state
	if fail_reason == "":
		fail_reason = reason
	_shutdown()


func _on_packet(data: PackedByteArray) -> void:
	if data.size() > 0 and data[0] == NetProto.K_SNAPSHOT:
		var snap := NetProto.read_snapshot(data)
		if snap.is_empty():
			dropped_packets += 1
		else:
			_on_snapshot(snap)
		return
	var msg := NetProto.unpack(data, NetProto.MAX_SERVER_PACKET)
	if msg.is_empty():
		dropped_packets += 1
		return
	match msg[0]:
		NetProto.T_WELCOME:
			_on_welcome(msg)
		NetProto.T_REJECT:
			_end(State.FAILED, str(msg[1]) if msg.size() == 2 else "refused")
		NetProto.T_PONG:
			if msg.size() == 2 and (msg[1] is int or msg[1] is float):
				var rtt := maxf(_time_ms - float(msg[1]), 0.0)
				ping_ms = rtt if ping_ms == 0.0 else lerpf(ping_ms, rtt, 0.2)


func _on_welcome(msg: Array) -> void:
	if sim != null or msg.size() != 4 or msg[1] != NetProto.VERSION or not (msg[2] is int) \
			or not (msg[3] is Dictionary) or msg[2] < 0 or msg[2] >= Config.NUM_PLAYERS:
		dropped_packets += 1
		return
	slot = msg[2]
	cfg = Config.new()
	cfg.from_dict(msg[3])
	sim = Sim.new(cfg, 0)


func _on_snapshot(snap: Dictionary) -> void:
	if sim == null:
		return   # the welcome is still on its way
	var t: int = snap["tick"]
	if t <= last_snapshot_tick:
		snapshots_dropped += 1
		return
	last_snapshot_tick = t
	var inputs: Array = snap["inputs"]
	if inputs.size() == Config.NUM_PLAYERS:
		for i in Config.NUM_PLAYERS:
			var inp := NetProto.decode_input(inputs[i])
			if inp != null:
				_others[i] = inp
	var me := sim.players[slot]
	var before := me.pos
	var had_prediction := state == State.ONLINE
	sim.load_state(snap["state"])
	acked = snap["acked"]
	while not pending.is_empty() and pending[0]["seq"] <= acked:
		pending.pop_front()
	sim.apply_mods(slot, _wanted_mods)
	for p: Dictionary in pending:
		sim.step(_inputs_with(p["input"]))
	snapshots_applied += 1
	if had_prediction:
		correction = before.distance_to(me.pos)
		correction_peak = maxf(correction_peak, correction)
	state = State.ONLINE


func _inputs_with(own: SimInput) -> Array:
	var inputs: Array = []
	for i in Config.NUM_PLAYERS:
		inputs.append(own if i == slot else _others[i])
	return inputs


## One 60 Hz step with the local input. Call poll() first (every frame or every tick).
func tick(local: SimInput) -> void:
	if state != State.ONLINE:
		return
	var inp := NetProto.clamp_input(local)
	seq += 1
	pending.append({"seq": seq, "input": inp})
	if pending.size() > MAX_PENDING:
		pending.pop_front()
	_send_input()
	if _mods_dirty:
		_mods_dirty = false
		net.send(1, NetProto.pack([NetProto.T_MODS, _wanted_mods]), true)
		sim.apply_mods(slot, _wanted_mods)
	sim.step(_inputs_with(inp))
	events = sim.events.duplicate()
	_time_ms += 1000.0 / Config.TICK_RATE
	_ticks += 1
	if _ticks % PING_EVERY == 0:
		net.send(1, NetProto.pack([NetProto.T_PING, int(_time_ms)]), false)
	_peak_age += 1
	if _peak_age > PEAK_WINDOW:
		_peak_age = 0
		correction_peak = correction
	net.flush()


func _send_input() -> void:
	var list: Array = []
	var n := mini(maxi(redundancy, 1), pending.size())
	for k in n:
		list.append(NetProto.encode_input(pending[pending.size() - 1 - k]["input"]))
	net.send(1, NetProto.pack([NetProto.T_INPUT, seq, list]), false)
