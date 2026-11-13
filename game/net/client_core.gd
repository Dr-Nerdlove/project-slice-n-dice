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
##
## What is DRAWN of the other players is not that predicted sim (every change of their input would make them
## snap) but an interpolation between two received snapshots, a little in the past: see prepare_display().

enum State { CONNECTING, ONLINE, FAILED, CLOSED }

const CONNECT_TIMEOUT := 6.0       # seconds without a first snapshot
const PING_EVERY := 30             # ticks
const MAX_PENDING := 600           # unacknowledged inputs kept at most (10 s)
const PEAK_WINDOW := 120           # ticks over which correction_peak is held

## Display of the other players (snapshot interpolation). All times are in server ticks.
const INTERP_DELAY := 4.0          # the render time runs this far behind the newest snapshot (2 snapshot intervals)
const INTERP_EXTRA_MAX := 8.0      # the delay grows by at most this much when snapshots arrive late or are lost
const INTERP_EXTRA_DECAY := 0.005  # ... and shrinks back by this much per tick (0.3 ticks per second)
const INTERP_NUDGE := 0.05         # share of the timing error corrected per tick ...
const INTERP_NUDGE_MAX := 0.25     # ... but never more than this: the render clock runs 0.75x..1.25x, it never jumps
const INTERP_RESET_GAP := 30.0     # a timing error bigger than this (a long stall) is jumped over
const INTERP_EST_PULL := 0.02      # the server time estimate sinks by this much per late snapshot (clock drift)
const INTERP_MAX_STEP := 6.0       # metres: a bigger move between two snapshots is a teleport (respawn), not interpolated
const SNAP_BUFFER := 40            # snapshots kept (about 1.3 s)

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

## Display of the other players. `display_sim` is valid after prepare_display() while smooth_others is on and
## at least one snapshot is buffered (else null: draw the predicted sim). Its prev_* positions are those of
## the earlier snapshot, so a view that lerps prev_pos -> pos with `display_alpha` shows the interpolation.
var smooth_others := true
var display_sim: Sim
var display_alpha := 1.0

## Counters.
var snapshots_applied := 0
var snapshots_dropped := 0
var dropped_packets := 0

var seq := 0
var pending: Array = []            # [{"seq": int, "input": SimInput}] sent but not yet acknowledged
var last_snapshot_tick := -1
var acked := 0

var _others: Array[SimInput] = []
var _snaps: Array = []             # [{"tick": int, "state": Dictionary}] ascending, for the interpolation
var _est := -1.0                   # estimate of the newest server tick right now (advances 1 per local tick)
var _render_t := -1.0              # render time of the other players, server ticks
var _extra := 0.0                  # extra interpolation delay for jitter / loss, ticks
var _disp_pair := Vector2i(-1, -1) # ticks of the snapshots display_sim was built from
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
				_others[i] = inp.repeated()   # the snapshot already contains this tick's dash
	_buffer_snapshot(t, snap["state"])
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


## Keeps the snapshot for the interpolation and keeps the render clock in step with the arrival times.
func _buffer_snapshot(t: int, state: Dictionary) -> void:
	var first := _snaps.is_empty()
	var gap := 0
	if not first:
		gap = t - int(_snaps.back()["tick"])
	_snaps.append({"tick": t, "state": state})
	while _snaps.size() > SNAP_BUFFER:
		_snaps.pop_front()
	if first or t - _est > INTERP_RESET_GAP or _est - t > INTERP_RESET_GAP * 4.0:
		_est = float(t)
		_render_t = _est - INTERP_DELAY - _extra
		return
	if float(t) >= _est:
		_est = float(t)
	else:
		var late := _est - float(t)
		_extra = maxf(_extra, minf(late, INTERP_EXTRA_MAX))
		_est -= minf(late, INTERP_EST_PULL)
	if gap > ServerCore.SNAPSHOT_EVERY:
		_extra = maxf(_extra, minf(float(gap - ServerCore.SNAPSHOT_EVERY), INTERP_EXTRA_MAX))   # snapshots were lost


## The current interpolation delay in milliseconds (for the HUD).
func interp_delay_ms() -> float:
	return (INTERP_DELAY + _extra) * 1000.0 / Config.TICK_RATE


## Advances the render clock by one tick towards its target; never jumps except over a long stall.
func _step_render_clock() -> void:
	if _est < 0.0:
		return
	_est += 1.0
	_extra = maxf(_extra - INTERP_EXTRA_DECAY, 0.0)
	var err := (_est - INTERP_DELAY - _extra) - (_render_t + 1.0)   # how far the clock would be off after a normal step
	if absf(err) > INTERP_RESET_GAP:
		_render_t += 1.0 + err
	else:
		_render_t += 1.0 + clampf(err * INTERP_NUDGE, -INTERP_NUDGE_MAX, INTERP_NUDGE_MAX)


## Builds display_sim for the render time (call once per rendered frame, `frac` is how far the frame is
## into the current local tick, 0..1). With smooth_others off, or before the first snapshot, it is null.
func prepare_display(frac: float) -> void:
	if not smooth_others or _snaps.is_empty() or sim == null:
		display_sim = null
		return
	var rt := _render_t - 1.0 + clampf(frac, 0.0, 1.0)
	var hi := _snaps.size() - 1
	for k in _snaps.size():
		if float(_snaps[k]["tick"]) >= rt:
			hi = k
			break
	var lo := maxi(hi - 1, 0)
	var a_tick: int = _snaps[lo]["tick"]
	var b_tick: int = _snaps[hi]["tick"]
	if hi == lo or rt >= float(b_tick):
		display_alpha = 1.0       # the buffer ran dry (or the render time is before it): hold, never run past it
	else:
		display_alpha = clampf((rt - float(a_tick)) / float(b_tick - a_tick), 0.0, 1.0)
	if display_sim == null:
		display_sim = Sim.new(cfg, 0)
		_disp_pair = Vector2i(-1, -1)
	if _disp_pair != Vector2i(a_tick, b_tick):
		_disp_pair = Vector2i(a_tick, b_tick)
		display_sim.load_state(_snaps[hi]["state"])
		_set_previous(display_sim, _snaps[lo]["state"])


## Overwrites the prev_* positions of `s` (loaded with the later snapshot) with the positions of the earlier
## snapshot `before`, so lerping prev -> current by alpha interpolates. Teleports (respawn, big gaps) are not
## interpolated.
static func _set_previous(s: Sim, before: Dictionary) -> void:
	var old_players: Array = before["players"]
	for i in s.players.size():
		var p := s.players[i]
		p.prev_pos = p.pos
		for h in p.heads:
			h.prev_pos = h.pos
		if i >= old_players.size():
			continue
		var o: Dictionary = old_players[i]
		if not (o["alive"] and p.alive and o["enabled"] and p.enabled):
			continue
		if (o["pos"] as Vector2).distance_to(p.pos) <= INTERP_MAX_STEP:
			p.prev_pos = o["pos"]
		var old_heads: Array = o["heads"]
		for k in mini(p.heads.size(), old_heads.size()):
			var oh: Dictionary = old_heads[k]
			if (oh["pos"] as Vector2).distance_to(p.heads[k].pos) <= INTERP_MAX_STEP:
				p.heads[k].prev_pos = oh["pos"]
	var old_shards: Array = before["shards"]
	for sh in s.shards:
		sh.prev_pos = sh.pos
		for o: Dictionary in old_shards:
			if o["owner_id"] == sh.owner_id and (o["dir"] as Vector2).is_equal_approx(sh.dir) \
					and (o["pos"] as Vector2).distance_to(sh.pos) <= INTERP_MAX_STEP:
				sh.prev_pos = o["pos"]
				break


## Where the other player `i` is drawn (what the view lerps to), for tests and tools. Own slot: predicted.
func displayed_pos(i: int, frac: float) -> Vector2:
	prepare_display(frac)
	if display_sim == null or i == slot:
		var p := sim.players[i]
		return p.prev_pos.lerp(p.pos, frac)
	var d := display_sim.players[i]
	return d.prev_pos.lerp(d.pos, display_alpha)


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
	_step_render_clock()
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
