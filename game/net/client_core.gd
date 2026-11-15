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
## The exception are their yo-yo heads that are not in the hand and their shards: a thrown head needs no
## further input to fly, so they are drawn from the predicted sim, in the present, where the server will decide
## about hits (else the victim would be killed before the head visibly arrives).

enum State { CONNECTING, ONLINE, FAILED, CLOSED }

const CONNECT_TIMEOUT := 6.0       # seconds without a first snapshot
const LOST_TIMEOUT := 3.0          # seconds of poll time without any snapshot while ONLINE: the connection counts as lost
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
const HEAD_CATCHUP_TICKS := 6      # a displayed head that changes its source (or is corrected) slides over this many ticks (100 ms)
const HEAD_MAX_OFFSET := 6.0       # metres: a bigger visual offset is a teleport and dropped at once

var net: NetEndpoint
var state := State.CONNECTING
var fail_reason := ""              # "version", "full", "started", "timeout", "refused" or "closed"
var slot := -1
var token := ""                    # the install's identity (main.gd sets NetStore.token() before connecting); sent in the hello. A fresh random one by default
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
var predict_heads := true          # draw other players' heads that are out, and their shards, from the predicted sim
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
var _interp_heads: Array = []      # per player, per head: [state, pos, prev_pos, pins] as interpolated (display_sim is overwritten per frame)
var _interp_shards: Array = []     # the interpolated shards of display_sim
var _vis := {}                     # player * 8 + head -> {kind, shown, off, step, left}: visual offset of a displayed head
var _wanted_mods: Dictionary = Mods.empty_levels()
var _mods_dirty := true
var _wanted_skin := -1   # -1: never chosen, keep the server's default
var _skin_dirty := false
var _time_ms := 0.0
var _connect_elapsed := 0.0
var _silent := 0.0                 # seconds since the last snapshot (while ONLINE)
var _peak_age := 0
var _ticks := 0
var _net_closed := false


func _init(endpoint: NetEndpoint) -> void:
	net = endpoint
	token = Crypto.new().generate_random_bytes(16).hex_encode()
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


## The figure the local player wants; sent to the server when it changes.
func set_skin(k: int) -> void:
	var clean := posmod(k, Config.SKIN_COUNT)
	if clean != _wanted_skin:
		_wanted_skin = clean
		_skin_dirty = true


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
				net.send(1, NetProto.pack([NetProto.T_HELLO, NetProto.VERSION, token]), true)
			NetEndpoint.Kind.DISCONNECT:
				if state == State.CONNECTING and sim == null:
					_end(State.FAILED, "unreachable")
				elif state == State.ONLINE:
					_end(State.FAILED, "lost")   # no goodbye from the server (it would have sent a reject first)
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
	elif state == State.ONLINE:
		_silent += dt
		if _silent > LOST_TIMEOUT:
			_end(State.FAILED, "lost")


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
	_silent = 0.0
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
	var heads_before := _heads_out() if had_prediction else {}
	sim.load_state(snap["state"])
	acked = snap["acked"]
	while not pending.is_empty() and pending[0]["seq"] <= acked:
		pending.pop_front()
	sim.apply_mods(slot, _wanted_mods)
	if _wanted_skin >= 0:
		sim.set_skin(slot, _wanted_skin)
	for p: Dictionary in pending:
		sim.step(_inputs_with(p["input"]))
	snapshots_applied += 1
	if had_prediction:
		correction = before.distance_to(me.pos)
		correction_peak = maxf(correction_peak, correction)
		_carry_head_corrections(heads_before)
	state = State.ONLINE


## Positions of the other players' heads that are out in the predicted sim: player * 8 + head -> position.
func _heads_out() -> Dictionary:
	var out := {}
	for i in sim.players.size():
		var p := sim.players[i]
		if i == slot or not (p.enabled and p.alive):
			continue
		for k in p.heads.size():
			if p.heads[k].state != SimHead.S.HAND:
				out[i * 8 + k] = p.heads[k].pos
	return out


## A snapshot moved a predicted enemy head (the prediction was wrong): the displayed head keeps where it was and
## slides to the corrected path over HEAD_CATCHUP_TICKS instead of popping.
func _carry_head_corrections(before: Dictionary) -> void:
	for key: int in before:
		var rec: Variant = _vis.get(key)
		var p := sim.players[key / 8]
		if rec == null or rec["kind"] != 1 or key % 8 >= p.heads.size():
			continue
		var h := p.heads[key % 8]
		if not p.alive or h.state == SimHead.S.HAND:
			continue
		var d: Vector2 = (before[key] as Vector2) - h.pos
		if d.length() < 0.001:
			continue
		_set_offset(rec, Vector2.ZERO if d.length() > HEAD_MAX_OFFSET else rec["off"] + d)


static func _set_offset(rec: Dictionary, off: Vector2) -> void:
	rec["off"] = off
	rec["step"] = off / float(HEAD_CATCHUP_TICKS)
	rec["left"] = HEAD_CATCHUP_TICKS if off != Vector2.ZERO else 0


## One local tick of the visual offsets sliding to zero.
func _decay_offsets() -> void:
	for rec: Dictionary in _vis.values():
		if rec["left"] > 0:
			rec["off"] -= rec["step"]
			rec["left"] -= 1
			if rec["left"] == 0:
				rec["off"] = Vector2.ZERO


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
		_vis.clear()
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
		_save_interpolated()
	_apply_predicted(frac)


func _save_interpolated() -> void:
	_interp_heads.clear()
	for p in display_sim.players:
		var l: Array = []
		for h in p.heads:
			l.append([h.state, h.pos, h.prev_pos, h.pins])
		_interp_heads.append(l)
	_interp_shards = display_sim.shards.duplicate()


## Where the yo-yo is drawn while it is in the hand (as the view does it, without the sideways spread of several).
static func _hand_pos(s: Sim, p: SimPlayer, body: Vector2) -> Vector2:
	var face := p.aim_dir if p.charging else p.facing
	return body + face * (s.cfg.player_radius + s.head_r(p) * 0.4)


## Puts the other players' heads and shards into display_sim: the interpolated ones, except heads that are out
## in the predicted sim (the present: a thrown head flies without further input) and the others' shards.
## A head whose source changes (thrown: hand -> predicted; landed in the hand: predicted -> hand) or that a
## snapshot corrected keeps a visual offset that slides to zero over HEAD_CATCHUP_TICKS, so it never pops and is
## never further from its true place than that offset. The string is drawn by the view from the interpolated body
## through the head's pins (taken from the predicted head) to the displayed head, so it stays continuous.
func _apply_predicted(frac: float) -> void:
	for i in display_sim.players.size():
		var dp := display_sim.players[i]
		var pp := sim.players[i]
		var saved: Array = _interp_heads[i] if i < _interp_heads.size() else []
		var body := dp.prev_pos.lerp(dp.pos, display_alpha)
		for k in dp.heads.size():
			var h := dp.heads[k]
			var key := i * 8 + k
			if k < saved.size():
				h.state = saved[k][0]
				h.pos = saved[k][1]
				h.prev_pos = saved[k][2]
				h.pins = saved[k][3]
			if not predict_heads or i == slot or k >= pp.heads.size() or not (dp.enabled and dp.alive and pp.enabled and pp.alive):
				_vis.erase(key)
				continue
			var ph := pp.heads[k]
			var kind := 1 if ph.state != SimHead.S.HAND else 0
			var src: Vector2
			if kind == 1:
				src = ph.prev_pos.lerp(ph.pos, frac)
			else:
				src = _hand_pos(display_sim, dp, body)
			var rec: Variant = _vis.get(key)
			if rec == null:
				rec = {"kind": kind, "shown": src, "off": Vector2.ZERO, "step": Vector2.ZERO, "left": 0}
				_vis[key] = rec
			elif rec["kind"] != kind:
				var off: Vector2 = (rec["shown"] as Vector2) - src
				_set_offset(rec, Vector2.ZERO if off.length() > HEAD_MAX_OFFSET else off)
				rec["kind"] = kind
			var shown: Vector2 = src + (rec["off"] as Vector2)
			rec["shown"] = shown
			if kind == 1:
				h.state = ph.state
				h.pins = ph.pins
			elif rec["off"] != Vector2.ZERO:
				h.state = SimHead.S.RETRACT   # sliding into the hand: drawn as a head on its way home
				h.pins = PackedVector2Array()
			else:
				h.state = SimHead.S.HAND
			h.pos = shown
			h.prev_pos = shown
	if predict_heads:
		display_sim.shards.clear()
		for s in sim.shards:
			if s.owner_id == slot:
				continue
			var c := SimShard.new()
			c.owner_id = s.owner_id
			c.radius = s.radius
			c.pos = s.prev_pos.lerp(s.pos, frac)
			c.prev_pos = c.pos
			display_sim.shards.append(c)
	else:
		display_sim.shards = _interp_shards.duplicate()


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


## Where the yo-yo head `k` of player `i` is drawn right now (what the view shows), for tests and tools.
func displayed_head_pos(i: int, k: int, frac: float) -> Vector2:
	prepare_display(frac)
	if display_sim == null or i == slot:
		var p := sim.players[i]
		var h := p.heads[k]
		if h.state == SimHead.S.HAND:
			return _hand_pos(sim, p, p.prev_pos.lerp(p.pos, frac))
		return h.prev_pos.lerp(h.pos, frac)
	var d := display_sim.players[i]
	var dh := d.heads[k]
	if dh.state == SimHead.S.HAND:
		return _hand_pos(display_sim, d, d.prev_pos.lerp(d.pos, display_alpha))
	return dh.prev_pos.lerp(dh.pos, display_alpha)


## The other players' shards as drawn right now: [{"owner": int, "pos": Vector2, "radius": float}], for tests and tools.
func displayed_other_shards(frac: float) -> Array:
	prepare_display(frac)
	var out: Array = []
	if display_sim == null:
		for s in sim.shards:
			if s.owner_id != slot:
				out.append({"owner": s.owner_id, "pos": s.prev_pos.lerp(s.pos, frac), "radius": s.radius})
		return out
	for s in display_sim.shards:
		if s.owner_id != slot:
			out.append({"owner": s.owner_id, "pos": s.prev_pos.lerp(s.pos, display_alpha), "radius": s.radius})
	return out


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
	if _skin_dirty:
		_skin_dirty = false
		net.send(1, NetProto.pack([NetProto.T_SKIN, _wanted_skin]), true)
		sim.set_skin(slot, _wanted_skin)
	sim.step(_inputs_with(inp))
	events = sim.events.duplicate()
	_time_ms += 1000.0 / Config.TICK_RATE
	_step_render_clock()
	_decay_offsets()
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
