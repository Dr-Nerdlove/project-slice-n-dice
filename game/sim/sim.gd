class_name Sim
extends RefCounted
## Deterministic fixed-tick simulation. No nodes, no input singleton, no wall clock.
## Call step(inputs) exactly once per tick (Config.TICK_RATE). All state is plain data.

const HS := SimHead.S
## Variables that are not part of the snapshot: configuration, static layout, per-tick output, rng (handled by hand).
const STATE_SKIP := ["cfg", "rng", "statics", "wall_count", "events"]

var cfg: Config
var rng := RandomNumberGenerator.new()
var tick := 0
var players: Array[SimPlayer] = []
var statics: Array[Rect2] = []   # outer walls first, then obstacles
var wall_count := 4
var crate_pos := Vector2.ZERO
var prev_crate_pos := Vector2.ZERO
var box_active := true
var box_timer := 0.0
var wires: Array[SimWire] = []
var shards: Array[SimShard] = []
## The toy train: position of the locomotive along `TrainTrack` (metres) and its value one tick earlier.
var train_s := 0.0
var prev_train_s := 0.0
## Events of the last tick (dictionaries with "type"): kill, bounce, ricochet, box_break, respawn,
## explosion, wire, stun. A kill by the train has "killer": -1 and "cause": "train".
var events: Array = []

var _hit := false  # scratch flag set by head sweeps


func _init(config: Config, seed_value: int) -> void:
	cfg = config
	rng.seed = seed_value
	var a := Config.ARENA_SIZE
	var t := Config.WALL_THICKNESS
	statics.append(Rect2(-t, -t, a.x + 2.0 * t, t))
	statics.append(Rect2(-t, a.y, a.x + 2.0 * t, t))
	statics.append(Rect2(-t, 0.0, t, a.y))
	statics.append(Rect2(a.x, 0.0, t, a.y))
	wall_count = statics.size()
	for o in Config.OBSTACLES:
		statics.append(o)
	crate_pos = Config.CRATE_START
	prev_crate_pos = crate_pos
	for i in Config.NUM_PLAYERS:
		var p := SimPlayer.new()
		p.id = i
		p.skin = i % Config.SKIN_COUNT
		p.pos = Config.SPAWNS[i]
		p.dash_charges = cfg.dash_charges
		p.prev_pos = p.pos
		p.heads[0].pos = p.pos
		p.heads[0].prev_pos = p.pos
		p.facing = (Vector2(a.x, a.y) * 0.5 - p.pos).normalized()
		p.aim_dir = p.facing
		players.append(p)


## Complete mutable state as plain data (survives var_to_bytes). Not included: cfg, static layout, events.
func save_state() -> Dictionary:
	var d := StateIO.dump(self)
	d["rng_seed"] = rng.seed
	d["rng_state"] = rng.state
	return d


## Overwrites the state in place (existing SimPlayer / SimHead objects are kept where the counts match).
func load_state(d: Dictionary) -> void:
	StateIO.restore(self, d)
	rng.seed = d["rng_seed"]
	rng.state = d["rng_state"]


func crate_rect() -> Rect2:
	var h := Vector2(Config.CRATE_HALF, Config.CRATE_HALF)
	return Rect2(crate_pos - h, h * 2.0)


func box_rect() -> Rect2:
	var h := Vector2(Config.BOX_HALF, Config.BOX_HALF)
	return Rect2(Config.BOX_POS - h, h * 2.0)


func set_player_enabled(i: int, on: bool) -> void:
	var p := players[i]
	if p.enabled == on:
		return
	p.enabled = on
	_reset_yoyo(p)
	p.alive = false
	p.respawn_t = 0.0


## Sets which figure a player shows (presentation only; never read by the simulation).
func set_skin(i: int, k: int) -> void:
	players[i].skin = posmod(k, Config.SKIN_COUNT)


## Sets the modifier levels of a player (id -> 0..3). Cheap to call every frame.
func apply_mods(i: int, levels: Dictionary) -> void:
	var p := players[i]
	if p.mods == levels:
		return
	var old_dash := lv(p, "extradash")
	p.mods = levels.duplicate()
	if lv(p, "extradash") != old_dash:
		p.dash_charges = dash_max(p)
		p.dash_cd = 0.0


func step(inputs: Array) -> void:
	events.clear()
	tick += 1
	var dt := 1.0 / Config.TICK_RATE
	prev_crate_pos = crate_pos
	for p in players:
		p.prev_pos = p.pos
		for h in p.heads:
			h.prev_pos = h.pos
	for i in players.size():
		if players[i].enabled:
			_step_player(players[i], inputs[i], dt)
	_separate_players()
	_step_train(dt)
	_collide_heads()
	_step_shards(dt)
	_step_wires(dt)
	_check_kills()
	_step_box(dt)


# ---------------------------------------------------------------- queries

func lv(p: SimPlayer, id: String) -> int:
	return p.mods.get(id, 0)


## Modifier number at the player's level (`fallback` while the modifier is off).
func mv(p: SimPlayer, id: String, key: String, fallback: float) -> float:
	var l := lv(p, id)
	return Mods.n(id, key, l) if l > 0 else fallback


func head_r(p: SimPlayer) -> float:
	return cfg.head_radius * mv(p, "bighead", "radius_mult", 1.0)


func dash_max(p: SimPlayer) -> int:
	return cfg.dash_charges + int(mv(p, "extradash", "charges", 0.0))


func dash_cooldown_of(p: SimPlayer) -> float:
	return cfg.dash_cooldown * mv(p, "extradash", "cooldown_mult", 1.0)


func dash_distance_of(p: SimPlayer) -> float:
	return cfg.dash_distance * mv(p, "extradash", "distance_mult", 1.0)


func heads_wanted(p: SimPlayer) -> int:
	return int(mv(p, "twin", "heads", 1.0))


## True when both modifiers of synergy `key` are on for this player.
func syn(p: SimPlayer, key: String) -> bool:
	return Mods.syn_active(key, p.mods)


## Synergy number (0 while the synergy is off).
func syn_n(p: SimPlayer, key: String, name: String) -> float:
	return Mods.syn_n(key, name, p.mods)


## Size factor of the head when a synergy lets other things grow with it (Dicker Brocken), else 1.
func bighead_factor(p: SimPlayer, key: String) -> float:
	return mv(p, "bighead", "radius_mult", 1.0) if syn(p, key) else 1.0


## Explosion radius of this player's explosions (Dicker Brocken + Sprengkopf makes them bigger).
func blast_radius(p: SimPlayer, base: float) -> float:
	var f := syn_n(p, "bighead_warhead", "radius_mult")
	return base * (f if f > 0.0 else 1.0)


## The string of a head that is out: player -> pins -> head.
func string_path(p: SimPlayer, h: SimHead) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(p.pos)
	pts.append_array(h.pins)
	pts.append(h.pos)
	return pts


static func path_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## Length of the string between the first pin (or the head) and the head: the part the player cannot shorten.
func _rest_after_first(h: SimHead) -> float:
	if h.pins.is_empty():
		return 0.0
	var total := 0.0
	for i in range(1, h.pins.size()):
		total += h.pins[i - 1].distance_to(h.pins[i])
	return total + h.pins[h.pins.size() - 1].distance_to(h.pos)


## +1 = the arc bulges to the left of the travel direction, -1 = right (move input at that moment, default left).
func arc_side_for(p: SimPlayer, travel: Vector2) -> float:
	var left := Vector2(travel.y, -travel.x)
	if p.last_move.length() > Config.MOVE_DEADZONE and p.last_move.dot(left) < 0.0:
		return -1.0
	return 1.0


static func curve_point(origin: Vector2, target: Vector2, side: float, bulge: float, t: float) -> Vector2:
	var chord := target - origin
	var dirv := chord.normalized() if chord.length() > 0.001 else Vector2.RIGHT
	var left := Vector2(dirv.y, -dirv.x)
	return origin.lerp(target, t) + left * side * bulge * 4.0 * t * (1.0 - t)


## Bulge of an arced throw over `dist` metres (0 = no arc: modifier off or throw too short).
func throw_bulge_for(p: SimPlayer, dist: float) -> float:
	var l := lv(p, "arc")
	if l <= 0 or dist < Mods.ARC_MIN_CHORD:
		return 0.0
	return minf(Mods.n("arc", "bulge", l), dist * Mods.ARC_THROW_MAX_RATIO)


## Radius of the lethal body (0 when the body is not a weapon right now).
func body_lethal_r(p: SimPlayer) -> float:
	if not p.body_is_moving_weapon() or mv(p, "elastic", "body_lethal", 0.0) <= 0.0:
		return 0.0
	return cfg.player_radius * mv(p, "elastic", "body_mult", 1.0)


func _flight_pass(p: SimPlayer) -> int:
	return int(mv(p, "pierce", "pass_flight", 0.0))


func _retract_pass(p: SimPlayer) -> int:
	return int(mv(p, "pierce", "pass_retract", 0.0))


func charge_range(p: SimPlayer) -> float:
	var t := clampf(p.charge_t / cfg.charge_time, 0.0, 1.0)
	var base := lerpf(cfg.effective_min_range(), cfg.effective_max_range(), t)
	return base * (1.0 + mv(p, "pierce", "range_pct", 0.0) / 100.0)


## Landing distance of the current charge, shortened by walls (for the aim line).
func aim_range(p: SimPlayer) -> float:
	var full := charge_range(p)
	var end := _sweep_head(p.pos, p.aim_dir * full, head_r(p), false, _flight_pass(p))
	return (end - p.pos).length()


## Preview of the flight of the current charge (for the aim line): points from the player to where it ends.
func aim_path(p: SimPlayer) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(p.pos)
	var full := charge_range(p)
	var bulge := throw_bulge_for(p, full)
	if bulge <= 0.0:
		pts.append(p.pos + p.aim_dir * aim_range(p))
		return pts
	var target := p.pos + p.aim_dir * full
	var side := arc_side_for(p, p.aim_dir)
	var r := head_r(p)
	var pass_level := _flight_pass(p)
	for i in range(1, Mods.ARC_THROW_SAMPLES + 1):
		var want := curve_point(p.pos, target, side, bulge, float(i) / Mods.ARC_THROW_SAMPLES)
		var res := _resolve_head(want, r, false, pass_level)
		pts.append(res)
		if (res - want).length_squared() > 1e-10:
			break
	return pts


# ---------------------------------------------------------------- player

func _sync_heads(p: SimPlayer) -> void:
	var want := heads_wanted(p)
	while p.heads.size() < want:
		var h := SimHead.new()
		h.pos = p.pos
		h.prev_pos = p.pos
		p.heads.append(h)
	while p.heads.size() > want:
		p.heads.pop_back()
	if p.pull_target >= p.heads.size():
		p.pulling = false
		p.pull_target = 0


func _step_player(p: SimPlayer, inp: SimInput, dt: float) -> void:
	_sync_heads(p)
	if not p.alive:
		p.respawn_t -= dt
		p.held_prev = inp.aim_held
		if p.respawn_t <= 0.0:
			_respawn(p)
		return

	p.last_move = inp.move
	var held := inp.aim_held
	var pressed := held and not p.held_prev
	var released := (not held) and p.held_prev
	p.held_prev = held

	_step_dash_charges(p, dt)
	for h in p.heads:
		if h.state == HS.FLIGHT:
			_step_flight(p, h, dt)
		elif h.state == HS.RETRACT:
			_step_retract(p, h, dt)

	if p.stun_t > 0.0:
		# Stumbling: no movement, no dash, no yo-yo control. Heads that are out keep doing their thing.
		p.stun_t = maxf(0.0, p.stun_t - dt)
		p.charging = false
		p.pulling = false
		p.press_active = false
		p.dash_t = 0.0
		p.fling_left = 0.0
	else:
		var before := p.pos
		if p.fling_left > 0.0:
			_step_fling(p, dt)
		elif not p.pulling:
			_move_player(p, inp, dt)
		var delta := p.pos - before
		for i in p.heads.size():
			var h := p.heads[i]
			if h.state == HS.OUT and not (p.pulling and i == p.pull_target):
				_apply_out_variant(p, h, delta)
		_step_yoyo_input(p, inp, pressed, held, released, dt)

	for h in p.heads:
		if h.state == HS.HAND:
			h.pos = p.pos


func _move_player(p: SimPlayer, inp: SimInput, dt: float) -> void:
	var mvec := inp.move.limit_length(1.0)
	if mvec.length() > Config.MOVE_DEADZONE:
		p.facing = mvec.normalized()
	if inp.dash and p.dash_charges > 0 and p.dash_t <= 0.0:
		p.dash_t = cfg.dash_duration
		if p.dash_charges >= dash_max(p):
			p.dash_cd = dash_cooldown_of(p)  # the refill timer starts with the first spent charge
		p.dash_charges -= 1
		p.dash_dir = p.facing
	var delta := Vector2.ZERO
	if p.dash_t > 0.0:
		var slice := minf(dt, p.dash_t)
		delta = p.dash_dir * (dash_distance_of(p) / cfg.dash_duration) * slice
		p.dash_t -= dt
	else:
		var speed := cfg.player_speed
		if p.charging:
			speed *= cfg.charge_speed_mult
		delta = mvec * speed * dt
	_slide_player(p, delta)


## Charges refill one at a time, each taking the dash cooldown.
func _step_dash_charges(p: SimPlayer, dt: float) -> void:
	var mx := dash_max(p)
	var cd := dash_cooldown_of(p)
	p.dash_charges = mini(p.dash_charges, mx)
	if p.dash_charges >= mx:
		p.dash_cd = 0.0
		return
	if p.dash_cd <= 0.0:
		p.dash_cd = cd
	p.dash_cd -= dt
	if p.dash_cd <= 0.0:
		p.dash_charges += 1
		p.dash_cd = cd if p.dash_charges < mx else 0.0


func _slide_player(p: SimPlayer, delta: Vector2) -> void:
	var r := cfg.player_radius
	var n := maxi(1, ceili(delta.length() / (r * Config.SUBSTEP_FACTOR)))
	var sv := delta / float(n)
	var pos := p.pos
	for _i in n:
		pos = _collide_player(pos + sv, r)
	p.pos = pos


func _collide_player(pos: Vector2, r: float) -> Vector2:
	pos = _push_statics(pos, r)
	if box_active:
		pos += Collide.push_out_rect(pos, r, box_rect())
	pos = _push_statics(pos, r)
	pos = _crate_vs_circle(pos, r, Config.CRATE_PUSH_RATIO)
	return _push_statics(pos, r)


## `count` limits the statics that are tested (the outer walls come first); -1 = all.
func _push_statics(pos: Vector2, r: float, count := -1) -> Vector2:
	var n := statics.size() if count < 0 else count
	for _i in 2:
		for k in n:
			pos += Collide.push_out_rect(pos, r, statics[k])
	return pos


## Pushes the crate out of the way of a circle. Returns the circle position after the
## part of the overlap the crate could not absorb. `ratio` = share of the overlap taken by the crate.
func _crate_vs_circle(pos: Vector2, r: float, ratio: float) -> Vector2:
	var corr := Collide.push_out_rect(pos, r, crate_rect())
	if corr == Vector2.ZERO:
		return pos
	var new_crate := _resolve_crate(crate_pos - corr * ratio)
	var actual := new_crate - crate_pos
	crate_pos = new_crate
	return pos + corr + actual


func _resolve_crate(cp: Vector2) -> Vector2:
	var h := Vector2(Config.CRATE_HALF, Config.CRATE_HALF)
	for _i in 2:
		for s in statics:
			cp += Collide.push_out_rect_rect(Rect2(cp - h, h * 2.0), s)
		if box_active:
			cp += Collide.push_out_rect_rect(Rect2(cp - h, h * 2.0), box_rect())
	return cp


func _separate_players() -> void:
	var r := cfg.player_radius
	for i in players.size():
		var a := players[i]
		if not (a.enabled and a.alive):
			continue
		for j in range(i + 1, players.size()):
			var b := players[j]
			if not (b.enabled and b.alive):
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= 2.0 * r:
				continue
			var n := d / dist if dist > 0.0001 else Vector2.RIGHT
			var push := n * (2.0 * r - dist) * Config.PLAYER_SEPARATION_SHARE
			a.pos = _collide_player(a.pos - push, r)
			b.pos = _collide_player(b.pos + push, r)


# ---------------------------------------------------------------- yo-yo input

## Player-level yo-yo control: charging, tapping, pulling. Heads move in _step_flight / _step_retract.
func _step_yoyo_input(p: SimPlayer, inp: SimInput, pressed: bool, held: bool, released: bool, dt: float) -> void:
	if p.pulling:
		_step_pull(p, held, dt)
		return
	var hand := p.hand_index()
	if not p.charging and hand >= 0:
		p.press_active = false
		if pressed:
			p.charging = true
			p.charge_t = 0.0
			p.aimed = false
			p.aim_dir = p.facing
	if p.charging:
		_step_charging(p, inp, released, dt)
	elif hand < 0:
		_step_out_input(p, inp, pressed, held, dt)


func _step_charging(p: SimPlayer, inp: SimInput, released: bool, dt: float) -> void:
	if inp.aim.length() >= cfg.aim_deadzone:
		p.aim_dir = inp.aim.normalized()
		p.aimed = true
	if not released:
		p.charge_t += dt
		# Zwilling III: an undeflected press that reaches the tap threshold pulls to the lying yo-yo.
		if not p.aimed and p.charge_t >= cfg.tap_threshold and _can_free_pull(p):
			p.charging = false
			_begin_pull(p, _pick_pull_target(p, inp.move))
		return
	p.charging = false
	var hand := p.hand_index()
	if not p.aimed and p.charge_t < cfg.tap_threshold and p.any_out():
		_retract_all(p)  # a plain tap while a yo-yo is out calls them all back, even with one in hand
	elif hand < 0 or (not p.aimed and p.charge_t < cfg.accidental_hold_time):
		pass  # accidental touch: cancel, no throw
	else:
		_throw(p, p.heads[hand])


func _throw(p: SimPlayer, h: SimHead) -> void:
	h.state = HS.FLIGHT
	h.throw_dir = p.aim_dir
	h.flight_dist = charge_range(p)
	h.flown = 0.0
	h.bounces = 0
	h.speed_mult = 1.0
	h.queued_retract = false
	h.pins.clear()
	h.pin_acc = 0.0
	h.meet_on = false
	h.pos = p.pos
	h.prev_pos = p.pos
	p.facing = p.aim_dir
	# Bogenwurf: the throw flies a curve and lands at the aimed point.
	var bulge := throw_bulge_for(p, h.flight_dist)
	h.throw_curved = bulge > 0.0
	if h.throw_curved:
		h.throw_origin = p.pos
		h.throw_target = p.pos + p.aim_dir * h.flight_dist
		h.throw_side = arc_side_for(p, p.aim_dir)
		h.throw_bulge = bulge
		h.throw_len = h.flight_dist + 8.0 / 3.0 * bulge * bulge / h.flight_dist
		h.flight_dist = h.throw_len


## A press while no yo-yo is in hand: a short tap retracts, a hold pulls once all have landed.
## A press that starts during flight / retract keeps counting, so it is not lost at the landing.
func _step_out_input(p: SimPlayer, inp: SimInput, pressed: bool, held: bool, dt: float) -> void:
	if pressed:
		p.press_active = true
		p.press_t = 0.0
	if not p.press_active:
		return
	if held:
		p.press_t += dt
		if p.press_t >= cfg.tap_threshold and p.count_state(HS.OUT) == p.heads.size():
			_begin_pull(p, _pick_pull_target(p, inp.move))
	else:
		p.press_active = false
		if p.press_t < cfg.tap_threshold:
			_retract_all(p)


func _retract_all(p: SimPlayer) -> void:
	# Zwilling II (Kreuzfeuer): with both heads out they first meet in the middle.
	if mv(p, "twin", "cross", 0.0) > 0.0 and p.heads.size() == 2 and p.count_state(HS.OUT) == 2:
		var a := p.heads[0]
		var b := p.heads[1]
		var mid := (a.pos + b.pos) * 0.5
		var r := head_r(p)
		var pass_level := _retract_pass(p)
		if a.pos.distance_to(b.pos) >= Mods.CROSS_MIN_GAP and _segment_clear(a.pos, mid, r, pass_level) \
				and _segment_clear(b.pos, mid, r, pass_level):
			_start_retract(p, a, mid)
			_start_retract(p, b, mid)
			return
	for h in p.heads:
		if h.state == HS.OUT:
			_start_retract(p, h)
		elif h.state == HS.FLIGHT:
			h.queued_retract = true


## True when a head of radius r can travel the straight line a -> b without touching anything solid.
func _segment_clear(a: Vector2, b: Vector2, r: float, pass_level: int) -> bool:
	var count := wall_count if pass_level >= 1 else -1
	var n := maxi(1, ceili(a.distance_to(b) / (r * Config.SUBSTEP_FACTOR)))
	for i in range(1, n + 1):
		var q := a.lerp(b, float(i) / n)
		for k in (statics.size() if count < 0 else count):
			if Collide.push_out_rect(q, r, statics[k]) != Vector2.ZERO:
				return false
		if pass_level < 2 and Collide.push_out_rect(q, r, crate_rect()) != Vector2.ZERO:
			return false
	return true


## Zwilling III: one head in hand and the others lying still, so a plain hold can pull to a lying one.
func _can_free_pull(p: SimPlayer) -> bool:
	if mv(p, "twin", "pull_free", 0.0) <= 0.0 or p.count_state(HS.OUT) == 0:
		return false
	return p.count_state(HS.OUT) + p.count_state(HS.HAND) == p.heads.size()


## The lying head that lies most in the move direction (smallest angle); without move input the nearest.
func _pick_pull_target(p: SimPlayer, move: Vector2) -> int:
	var best := 0
	var best_score := 1e9
	var use_dir := move.length() > Config.MOVE_DEADZONE
	for i in p.heads.size():
		if p.heads[i].state != HS.OUT:
			continue
		var to_h := p.heads[i].pos - p.pos
		var score := absf(move.angle_to(to_h)) if use_dir else to_h.length()
		if score < best_score:
			best_score = score
			best = i
	return best


func _begin_pull(p: SimPlayer, target: int) -> void:
	p.pulling = true
	p.pull_target = target
	# Stolperdraht: the string stays behind as a wire when a pull starts, too.
	if lv(p, "tripwire") > 0 and target < p.heads.size():
		_lay_wire(p, p.heads[target])


func _step_pull(p: SimPlayer, held: bool, dt: float) -> void:
	var h: SimHead = p.heads[p.pull_target] if p.pull_target < p.heads.size() else null
	if not held or h == null or h.state != HS.OUT:
		p.pulling = false
		p.press_active = false
		return
	var catch_dist := cfg.player_radius + head_r(p) + Config.CATCH_MARGIN
	var speed := cfg.pull_speed * mv(p, "elastic", "pull_mult", 1.0)
	var budget := speed * dt
	# The player follows the string: through the pins (each is dropped when passed), then to the head.
	for _i in 2 * h.pins.size() + 2:
		if budget <= 0.00001:
			break
		var has_pin := not h.pins.is_empty()
		var goal := h.pins[0] if has_pin else h.pos
		var to_goal := goal - p.pos
		var d := to_goal.length()
		if has_pin and d <= Mods.PIN_REACH:
			h.pins.remove_at(0)
			continue
		if d > 0.0001:
			p.facing = to_goal / d
		if not has_pin and d <= catch_dist:
			break
		var move := minf(budget, d)
		budget -= move
		if move <= 0.0:
			break
		var before := p.pos
		_slide_player(p, to_goal / d * move)
		if has_pin:
			var stuck := move > Mods.PIN_STUCK_MIN_MOVE and (p.pos - before).dot(to_goal / d) < move * Mods.PIN_STUCK_PROGRESS
			if stuck or p.pos.distance_to(goal) <= Mods.PIN_REACH:
				h.pins.remove_at(0)  # reached it, or it cannot be reached (blocked): give the pin up
		else:
			break
	if h.pins.is_empty() and p.pos.distance_to(h.pos) <= catch_dist:
		p.pulling = false
		_to_hand(p, h)
		var fd := mv(p, "elastic", "fling_dist", 0.0)
		if fd > 0.0:
			p.fling_left = fd
			p.fling_dir = p.facing
			p.fling_speed = mv(p, "elastic", "fling_speed", 0.0)


func _to_hand(p: SimPlayer, h: SimHead) -> void:
	h.state = HS.HAND
	h.pos = p.pos
	h.pins.clear()
	h.meet_on = false
	h.throw_curved = false


## Gummiband: the player is flung onward after catching the head. Stopped by walls.
func _step_fling(p: SimPlayer, dt: float) -> void:
	var step := minf(p.fling_speed * dt, p.fling_left)
	var before := p.pos
	_slide_player(p, p.fling_dir * step)
	p.fling_left -= step
	p.facing = p.fling_dir
	if (p.pos - before).dot(p.fling_dir) < step * Mods.FLING_MIN_PROGRESS:
		p.fling_left = 0.0


# ---------------------------------------------------------------- yo-yo heads

func _set_out(h: SimHead) -> void:
	h.state = HS.OUT
	h.limit = 1e9
	h.circ_pending = false
	h.circ_left = 0.0
	h.circ_free = false
	h.meet_on = false
	h.throw_curved = false


## The head lies still. A queued tap (made during flight) retracts it right away.
func _land(p: SimPlayer, h: SimHead) -> void:
	var was_flight := h.state == HS.FLIGHT
	_set_out(h)
	if was_flight:
		var l := lv(p, "warhead")
		if l > 0:
			_explode(p, h.pos, blast_radius(p, Mods.n("warhead", "radius", l)))
	if h.queued_retract:
		h.queued_retract = false
		p.press_active = false
		_start_retract(p, h)


func _step_flight(p: SimPlayer, h: SimHead, dt: float) -> void:
	var r := head_r(p)
	var pass_level := _flight_pass(p)
	var bounce_l := lv(p, "bounce")
	var max_bounces := int(Mods.n("bounce", "bounces", bounce_l)) if bounce_l > 0 else 0
	var move := minf(cfg.flight_speed * h.speed_mult * dt, h.flight_dist - h.flown)
	var n := maxi(1, ceili(move / (r * Config.SUBSTEP_FACTOR)))
	var step := move / float(n)
	var landed := false
	for _i in n:
		var start: Vector2
		if h.throw_curved:
			var t := minf((h.flown + step) / h.throw_len, 1.0)
			start = curve_point(h.throw_origin, h.throw_target, h.throw_side, h.throw_bulge, t)
			if (start - h.pos).length_squared() > 1e-10:
				h.throw_dir = (start - h.pos).normalized()
		else:
			start = h.pos + h.throw_dir * step
		var res := _resolve_head(start, r, true, pass_level)
		h.flown += step
		var moved := res.distance_to(h.pos)
		h.pos = res
		if (res - start).length_squared() > 1e-10:
			if h.bounces < max_bounces:
				var nrm := (res - start).normalized()
				if h.throw_dir.dot(nrm) < 0.0:
					h.throw_dir = (h.throw_dir - 2.0 * h.throw_dir.dot(nrm) * nrm).normalized()
				h.throw_curved = false  # after a bounce it flies straight on
				h.bounces += 1
				h.pins.append(res)  # the string now bends here
				h.pin_acc = 0.0
				h.flight_dist += Mods.n("bounce", "bonus_dist", bounce_l)
				if h.bounces == 1:
					h.speed_mult = 1.0 + Mods.n("bounce", "speed_pct", bounce_l) / 100.0
				events.append({"type": "ricochet", "pos": res})
			else:
				landed = true
				break
		elif h.throw_curved:
			# The curve is recorded: the string lies on the flown path.
			h.pin_acc += moved
			if h.pin_acc >= Mods.PATH_PIN_SPACING:
				h.pins.append(res)
				h.pin_acc = 0.0
	if landed or h.flown >= h.flight_dist - 0.00001:
		if not h.pins.is_empty() and h.pins[h.pins.size() - 1].distance_to(h.pos) < Mods.PIN_REACH:
			h.pins.resize(h.pins.size() - 1)  # a pin right at the head adds nothing
		if pass_level >= 1:
			_pierce_exit(h, r, pass_level)
		_land(p, h)


func _inside_pierced(pos: Vector2, r: float, pass_level: int) -> bool:
	for k in range(wall_count, statics.size()):
		if Collide.push_out_rect(pos, r, statics[k]) != Vector2.ZERO:
			return true
	return pass_level >= 2 and Collide.push_out_rect(pos, r, crate_rect()) != Vector2.ZERO


## A pierced head that would land inside a block continues to the far side of it.
func _pierce_exit(h: SimHead, r: float, pass_level: int) -> void:
	for _i in Mods.PIERCE_EXIT_MAX_STEPS:
		if not _inside_pierced(h.pos, r, pass_level):
			return
		var nxt := h.pos + h.throw_dir * Mods.PIERCE_EXIT_STEP
		h.pos = _push_statics(nxt, r, wall_count)
		if (h.pos - nxt).length_squared() > 1e-10:
			return  # reached an outer wall


## `meet` (not INF): Kreuzfeuer, fly to that point first and return from there.
func _start_retract(p: SimPlayer, h: SimHead, meet := Vector2.INF) -> void:
	h.state = HS.RETRACT
	h.limit = 1e9
	h.circ_pending = false
	h.circ_left = 0.0
	h.circ_free = false
	h.meet_on = false
	# --- Stolperdraht ---
	if lv(p, "tripwire") > 0:
		_lay_wire(p, h)
	# --- Splitter ---
	var l := lv(p, "shards")
	if l > 0:
		_spawn_shards(p, h, l)
	# --- Sprengkopf: second explosion where the retract starts ---
	l = lv(p, "warhead")
	if l > 0 and Mods.n("warhead", "retract_blast", l) > 0.0:
		_explode(p, h.pos, blast_radius(p, Mods.n("warhead", "radius", l)))
	if meet != Vector2.INF:
		h.pins.clear()  # the way to the meeting point is a straight line
		h.meet_on = true
		h.meet = meet
		return
	# Bogenwurf III: the circle starts once the head is close enough on its way home along the string.
	var al := lv(p, "arc")
	h.circ_pending = al > 0 and Mods.n("arc", "circle", al) > 0.0


## Radius of the Bogenwurf III circle around the player: at most circle_max_r and at most the distance to the
## nearest outer wall minus the head radius, but never below circle_min_r (only then the head may slide along a wall).
func circle_radius(p: SimPlayer, r: float) -> float:
	var l := lv(p, "arc")
	var a := Config.ARENA_SIZE
	var wall := minf(minf(p.pos.x, a.x - p.pos.x), minf(p.pos.y, a.y - p.pos.y))
	return maxf(minf(Mods.n("arc", "circle_max_r", l), wall - r), Mods.n("arc", "circle_min_r", l))


func _step_retract(p: SimPlayer, h: SimHead, dt: float) -> void:
	var r := head_r(p)
	var pass_level := _retract_pass(p)
	var step := cfg.retract_speed * mv(p, "arc", "retract_mult", 1.0) * mv(p, "twin", "retract_mult", 1.0) * dt
	if h.meet_on:
		_step_meet(p, h, r, pass_level, step)
		return
	if h.circ_pending and h.pos.distance_to(p.pos) <= circle_radius(p, r):
		h.circ_pending = false
		var d := h.pos.distance_to(p.pos)
		if d >= Mods.ARC_MIN_CHORD:
			h.circ_left = TAU
			h.circ_angle = (h.pos - p.pos).angle()
			h.circ_r = d
			h.circ_side = arc_side_for(p, (p.pos - h.pos) / d)
	if h.circ_left > 0.0:
		_step_circle(p, h, r, dt)
		return
	if h.circ_free:
		if _inside_pierced(h.pos, r, 2):
			pass_level = 2  # the circle ended inside a block: leave it first
		else:
			h.circ_free = false
	_step_retract_pins(p, h, r, pass_level, step)


## Retract along the string: back through the pins (each is dropped when passed, its remaining distance carries
## on to the next segment in the same tick), then to the player.
func _step_retract_pins(p: SimPlayer, h: SimHead, r: float, pass_level: int, step: float) -> void:
	var budget := step
	for _i in h.pins.size() + 1:
		if budget <= 0.00001:
			return
		var has_pin := not h.pins.is_empty()
		var goal := h.pins[h.pins.size() - 1] if has_pin else p.pos
		var to := goal - h.pos
		var d := to.length()
		if d <= budget:
			if not has_pin:
				_to_hand(p, h)
				p.press_active = false
				return
			h.pos = _sweep_retract(h.pos, to, r, pass_level)
			if h.pos.distance_to(goal) > 0.05:
				_set_out(h)  # something solid got in the way
				return
			h.pos = goal
			h.pins.resize(h.pins.size() - 1)
			budget -= d
			continue
		var dir := to / d
		var start := h.pos
		h.pos = _sweep_retract(start, dir * budget, r, pass_level)
		if (h.pos - start).dot(dir) < budget * Config.RETRACT_MIN_PROGRESS:
			_set_out(h)
		return


## Kreuzfeuer: fly to the meeting point; from there the head returns straight to the player.
func _step_meet(p: SimPlayer, h: SimHead, r: float, pass_level: int, step: float) -> void:
	var to := h.meet - h.pos
	var d := to.length()
	var start := h.pos
	if d <= step:
		h.pos = _sweep_retract(start, to, r, pass_level)
		if h.pos.distance_to(h.meet) > 0.05:
			_set_out(h)
			return
		h.pos = h.meet
		h.meet_on = false  # from here the heads return straight to the player
		return
	var dir := to / d
	h.pos = _sweep_retract(start, dir * step, r, pass_level)
	if (h.pos - start).dot(dir) < step * Config.RETRACT_MIN_PROGRESS:
		_set_out(h)


## Bogenwurf level 3: one full circle around the player's current position, then home along what is left of
## the string. The head passes through blocks and the crate. The radius shrinks when the player is near an outer
## wall; only in the floor case the head is clamped to the arena and slides along the wall.
func _step_circle(p: SimPlayer, h: SimHead, r: float, dt: float) -> void:
	var da := minf(TAU / mv(p, "arc", "circle_time", 1.1) * dt, h.circ_left)
	h.circ_left -= da
	h.circ_angle += h.circ_side * da
	h.circ_r = move_toward(h.circ_r, minf(h.circ_r, circle_radius(p, r)), Mods.CIRCLE_R_RATE * dt)
	var target := p.pos + Vector2.from_angle(h.circ_angle) * h.circ_r
	var a := Config.ARENA_SIZE
	target = Vector2(clampf(target.x, r, a.x - r), clampf(target.y, r, a.y - r))
	h.pos = _sweep_retract(h.pos, target - h.pos, r, 2)
	if h.circ_left <= 0.0:
		h.circ_left = 0.0
		h.circ_free = true


## Moves a retracting head: stopped by walls and obstacles (unless pierced), drags the crate,
## breaks the box and passes on.
func _sweep_retract(pos: Vector2, delta: Vector2, r: float, pass_level: int) -> Vector2:
	var n := maxi(1, ceili(delta.length() / (r * Config.SUBSTEP_FACTOR)))
	var sv := delta / float(n)
	var count := wall_count if pass_level >= 1 else -1
	for _i in n:
		pos = _push_statics(pos + sv, r, count)
		if box_active and Collide.push_out_rect(pos, r, box_rect()) != Vector2.ZERO:
			_break_box()
		if pass_level < 2:
			pos = _crate_vs_circle(pos, r, 1.0)
			pos = _push_train(pos, r)
		pos = _push_statics(pos, r, count)
	return pos


func _apply_out_variant(p: SimPlayer, h: SimHead, player_delta: Vector2) -> void:
	var r := head_r(p)
	var length := cfg.string_length
	# A head that landed beyond the string keeps that longer string until the player comes closer.
	h.limit = minf(h.limit, maxf(length, path_length(string_path(p, h))))
	length = h.limit
	match cfg.out_variant:
		Config.OutVariant.RIGID:
			if player_delta != Vector2.ZERO:
				h.pins.clear()  # the string is straight as soon as the player moves
				h.pos = _sweep_head(h.pos, player_delta, r, false)
		Config.OutVariant.DRAG:
			_drag_head(p, h, r, length)
	# The string is never longer than its limit: pull the player back if the head could not follow.
	var first := h.pins[0] if not h.pins.is_empty() else h.pos
	var max_off := maxf(length - _rest_after_first(h), 0.0)
	var off := p.pos - first
	var d := off.length()
	if d > max_off and d > 0.0001:
		p.pos = _collide_player(first + off / d * max_off, cfg.player_radius)


## The head is dragged along the string towards its nearest pin (and on to the next ones) until the string fits.
func _drag_head(p: SimPlayer, h: SimHead, r: float, length: float) -> void:
	for _i in h.pins.size() + 1:
		var excess := path_length(string_path(p, h)) - length
		if excess <= 0.0001:
			return
		var has_pin := not h.pins.is_empty()
		var goal := h.pins[h.pins.size() - 1] if has_pin else p.pos
		var to := goal - h.pos
		var d := to.length()
		if d < 0.0001:
			if not has_pin:
				return
			h.pins.resize(h.pins.size() - 1)
			continue
		var move := minf(excess, d)
		h.pos = _sweep_head(h.pos, to / d * move, r, false)
		if has_pin and move >= d - 0.0001 and h.pos.distance_to(goal) <= 0.05:
			h.pins.resize(h.pins.size() - 1)
			continue
		return


## pass_level: 0 = stopped by everything, 1 = passes obstacle blocks, 2 = also passes the crate.
func _sweep_head(pos: Vector2, delta: Vector2, r: float, breaks_box: bool, pass_level := 0) -> Vector2:
	var n := maxi(1, ceili(delta.length() / (r * Config.SUBSTEP_FACTOR)))
	var sv := delta / float(n)
	for _i in n:
		var start := pos + sv
		pos = _resolve_head(start, r, breaks_box, pass_level)
		if (pos - start).length_squared() > 1e-10:
			_hit = true
	return pos


func _resolve_head(pos: Vector2, r: float, breaks_box: bool, pass_level := 0) -> Vector2:
	var count := wall_count if pass_level >= 1 else -1
	pos = _push_statics(pos, r, count)
	if box_active:
		var c := Collide.push_out_rect(pos, r, box_rect())
		if c != Vector2.ZERO:
			if breaks_box:
				_break_box()
			else:
				pos += c
	if pass_level < 2:
		pos += Collide.push_out_rect(pos, r, crate_rect())
		pos = _push_train(pos, r)
	return _push_statics(pos, r, count)


func _break_box() -> void:
	box_active = false
	box_timer = Config.BOX_RESPAWN_TIME
	events.append({"type": "box_break", "pos": Config.BOX_POS})


func _step_box(dt: float) -> void:
	if box_active:
		return
	box_timer -= dt
	if box_timer > 0.0:
		return
	var rect := box_rect()
	var blocked := rect.intersects(crate_rect())
	for p in players:
		if not (p.enabled and p.alive):
			continue
		if Collide.push_out_rect(p.pos, cfg.player_radius, rect) != Vector2.ZERO:
			blocked = true
		var r := head_r(p)
		for h in p.heads:
			if h.lethal() and Collide.push_out_rect(h.pos, r, rect) != Vector2.ZERO:
				blocked = true
	if not blocked:
		box_active = true


# ---------------------------------------------------------------- weapons of the modifiers

func _explode(owner: SimPlayer, pos: Vector2, radius: float) -> void:
	events.append({"type": "explosion", "pos": pos, "radius": radius, "owner": owner.id})
	if box_active and Collide.push_out_rect(pos, radius, box_rect()) != Vector2.ZERO:
		_break_box()
	for v in players:
		if v != owner and v.enabled and v.alive and pos.distance_to(v.pos) - cfg.player_radius < radius:
			_kill(v, owner)


## Lays the current string of head `h` on the ground as a wire (Stolperdraht).
func _lay_wire(p: SimPlayer, h: SimHead) -> void:
	var pts := string_path(p, h)
	if path_length(pts) >= Mods.WIRE_MIN_LENGTH:
		_add_wire(p, pts, lv(p, "tripwire"))


func _add_wire(p: SimPlayer, pts: PackedVector2Array, l: int) -> void:
	var max_wires := int(Mods.n("tripwire", "max_wires", l))
	var mine: Array[SimWire] = []
	for w in wires:
		if w.owner_id == p.id:
			mine.append(w)
	while mine.size() >= max_wires:
		wires.erase(mine.pop_front())
	var w := SimWire.new()
	w.pts = pts
	w.half_width = Mods.WIRE_HALF_WIDTH * bighead_factor(p, "bighead_tripwire")
	w.owner_id = p.id
	w.ttl = Mods.n("tripwire", "wire_time", l)
	w.lethal = Mods.n("tripwire", "lethal", l) > 0.0
	w.stun = Mods.n("tripwire", "stun_time", l)
	wires.append(w)


## Closest point of the polyline `pts` to `q`.
static func closest_on_path(q: Vector2, pts: PackedVector2Array) -> Vector2:
	var best := pts[0]
	var best_d := 1e18
	for i in range(1, pts.size()):
		var c := Geometry2D.get_closest_point_to_segment(q, pts[i - 1], pts[i])
		var d := c.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = c
	return best


func _step_wires(dt: float) -> void:
	var k := wires.size() - 1
	while k >= 0:
		var w := wires[k]
		var reach := cfg.player_radius + w.half_width
		w.ttl -= dt
		var used := w.ttl <= 0.0
		if not used:
			for v in players:
				if v.id == w.owner_id or not (v.enabled and v.alive):
					continue
				if not w.lethal and v.stun_t > 0.0:
					continue
				var nearest := closest_on_path(v.pos, w.pts)
				if nearest.distance_to(v.pos) < reach:
					if w.lethal:
						_kill(v, players[w.owner_id])
					else:
						_stun(v, w.stun)
					events.append({"type": "wire", "pos": nearest, "owner": w.owner_id})
					used = true
					break
		if used:
			wires.remove_at(k)
		k -= 1


func _stun(v: SimPlayer, t: float) -> void:
	v.stun_t = t
	v.charging = false
	v.pulling = false
	v.press_active = false
	v.fling_left = 0.0
	v.dash_t = 0.0
	events.append({"type": "stun", "pos": v.pos, "victim": v.id})


func _spawn_shards(p: SimPlayer, h: SimHead, l: int) -> void:
	var count := int(Mods.n("shards", "count", l))
	var away := h.pos - p.pos
	var base := away.angle() if away.length() > 0.001 else p.facing.angle()
	for k in count:
		var s := SimShard.new()
		s.pos = h.pos
		s.prev_pos = h.pos
		s.dir = Vector2.from_angle(base + TAU * k / float(count))
		s.range_left = Mods.n("shards", "range", l)
		s.speed = Mods.n("shards", "speed", l)
		s.radius = Mods.n("shards", "radius", l) * bighead_factor(p, "shards_bighead")
		s.bounces_left = int(Mods.n("shards", "bounces", l))
		if syn(p, "shards_bounce"):
			s.bounces_left += int(Mods.n("bounce", "bounces", lv(p, "bounce")))
		if syn(p, "shards_pierce"):
			s.pass_level = _flight_pass(p)
		s.blast = blast_radius(p, syn_n(p, "shards_warhead", "radius"))
		s.owner_id = p.id
		shards.append(s)


func _step_shards(dt: float) -> void:
	var k := shards.size() - 1
	while k >= 0:
		var s := shards[k]
		var dead := _step_shard(s, dt)
		if dead:
			shards.remove_at(k)
			if s.blast > 0.0:
				_explode(players[s.owner_id], s.pos, s.blast)  # Splitter + Sprengkopf
		k -= 1


## Returns true when the shard is used up.
func _step_shard(s: SimShard, dt: float) -> bool:
	var move := minf(s.speed * dt, s.range_left)
	s.prev_pos = s.pos
	var target := s.pos + s.dir * move
	var res := _push_statics(target, s.radius, wall_count if s.pass_level >= 1 else -1)
	if s.pass_level < 2:
		res += Collide.push_out_rect(res, s.radius, crate_rect())
	var blocked := (res - target).length_squared() > 1e-10
	if box_active and Collide.push_out_rect(res, s.radius, box_rect()) != Vector2.ZERO:
		_break_box()
		blocked = true
		res = target
	# Kills along the path of this tick.
	var owner := players[s.owner_id]
	for v in players:
		if v == owner or not (v.enabled and v.alive):
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(v.pos, s.prev_pos, res)
		if nearest.distance_to(v.pos) < s.radius + cfg.player_radius:
			_kill(v, owner)
	s.pos = res
	s.range_left -= move
	if blocked:
		if s.bounces_left > 0 and (res - target).length_squared() > 1e-10:
			var nrm := (res - target).normalized()
			if s.dir.dot(nrm) < 0.0:
				s.dir = (s.dir - 2.0 * s.dir.dot(nrm) * nrm).normalized()
			s.bounces_left -= 1
		else:
			return true
	return s.range_left <= 0.00001


func _collide_heads() -> void:
	for i in players.size():
		var a := players[i]
		if not (a.enabled and a.alive and a.any_out()):
			continue
		for j in range(i + 1, players.size()):
			var b := players[j]
			if not (b.enabled and b.alive and b.any_out()):
				continue
			for ha in a.heads:
				if not ha.lethal():
					continue
				for hb in b.heads:
					if hb.lethal():
						_head_vs_head(a, ha, b, hb)


func _head_vs_head(a: SimPlayer, ha: SimHead, b: SimPlayer, hb: SimHead) -> void:
	var ra := head_r(a)
	var rb := head_r(b)
	var d := ha.pos - hb.pos
	var dist := d.length()
	if dist >= ra + rb:
		return
	var n := d / dist if dist > 0.0001 else Vector2.RIGHT
	var a_unstoppable := mv(a, "pierce", "duel", 0.0) > 0.0
	var b_unstoppable := mv(b, "pierce", "duel", 0.0) > 0.0
	var a_moving := ha.state == HS.FLIGHT or ha.state == HS.RETRACT
	var b_moving := hb.state == HS.FLIGHT or hb.state == HS.RETRACT
	if a_unstoppable != b_unstoppable:
		# The unstoppable head carries on; the other one is knocked away and lies OUT.
		var knock := ra + rb - dist + mv(a if a_unstoppable else b, "pierce", "duel_knock", 0.0)
		events.append({"type": "bounce", "pos": (ha.pos + hb.pos) * 0.5})
		if a_unstoppable:
			hb.pos = _sweep_head(hb.pos, -n * knock, rb, false)
			_land(b, hb)
		else:
			ha.pos = _sweep_head(ha.pos, n * knock, ra, false)
			_land(a, ha)
		return
	var knock2 := (ra + rb - dist) * 0.5
	if a_moving or b_moving:
		knock2 += Config.HEAD_BOUNCE_EXTRA
		events.append({"type": "bounce", "pos": (ha.pos + hb.pos) * 0.5})
	ha.pos = _sweep_head(ha.pos, n * knock2, ra, false)
	hb.pos = _sweep_head(hb.pos, -n * knock2, rb, false)
	if a_moving:
		_land(a, ha)
	if b_moving:
		_land(b, hb)


func _check_kills() -> void:
	var pr := cfg.player_radius
	for a in players:
		if not (a.enabled and a.alive):
			continue
		var reach := head_r(a) + pr
		for h in a.heads:
			if not h.lethal():
				continue
			for v in players:
				if v == a or not (v.enabled and v.alive):
					continue
				# Swept check along this tick's head path, so a fast head cannot skip over a player.
				var nearest := Geometry2D.get_closest_point_to_segment(v.pos, h.prev_pos, h.pos)
				if nearest.distance_to(v.pos) < reach:
					_kill(v, a)
		var br := body_lethal_r(a)
		if br > 0.0 and a.alive:
			for v in players:
				if v == a or not (v.enabled and v.alive):
					continue
				var nearest := Geometry2D.get_closest_point_to_segment(v.pos, a.prev_pos, a.pos)
				if nearest.distance_to(v.pos) < br + pr + Mods.BODY_LETHAL_MARGIN:
					_kill(v, a)


## `killer` null = the train: a death for the victim, a kill for nobody.
func _kill(victim: SimPlayer, killer: SimPlayer) -> void:
	victim.alive = false
	victim.deaths += 1
	if killer != null:
		killer.kills += 1
	victim.respawn_t = cfg.respawn_time
	_reset_yoyo(victim)
	var e := {"type": "kill", "pos": victim.pos, "victim": victim.id, "killer": -1 if killer == null else killer.id}
	if killer == null:
		e["cause"] = "train"
	events.append(e)


## Pushes a circle out of every train car (the cars are solid for yo-yo heads, like the crate). Unchanged when
## the train is off. Identical centres are pushed along the car's travel direction.
func _push_train(pos: Vector2, r: float) -> Vector2:
	if cfg.train_speed <= 0.0:
		return pos
	for k in TrainTrack.CARS:
		var cs := TrainTrack.car_s(train_s, k)
		var c := TrainTrack.point(cs)
		var d := pos - c
		var reach := TrainTrack.CAR_RADIUS + r
		var l2 := d.length_squared()
		if l2 >= reach * reach:
			continue
		if l2 < 1e-12:
			pos = c + TrainTrack.dir(cs) * reach
		else:
			pos = c + d / sqrt(l2) * reach
	return pos


## Moves the train along its loop. The cars shove the crate aside, run living players over and are solid for
## yo-yo heads (a flying head stops or bounces, a retracting one lies down, a lying one is shoved aside; the
## shove can kill). Strings, wires and shards pass over them. Speed 0 = no train at all.
func _step_train(dt: float) -> void:
	if cfg.train_speed <= 0.0:
		prev_train_s = train_s
		return
	prev_train_s = train_s
	train_s += cfg.train_speed * dt
	if train_s >= TrainTrack.LENGTH:
		train_s -= TrainTrack.LENGTH
		prev_train_s -= TrainTrack.LENGTH
	var reach := TrainTrack.CAR_RADIUS + cfg.player_radius * Config.TRAIN_HIT_SHARE
	for k in TrainTrack.CARS:
		var c := TrainTrack.point(TrainTrack.car_s(train_s, k))
		_crate_vs_circle(c, TrainTrack.CAR_RADIUS, 1.0)
		for v in players:
			if v.enabled and v.alive and v.pos.distance_to(c) < reach:
				_kill(v, null)
		for v in players:
			if not (v.enabled and v.alive):
				continue
			var hr := head_r(v)
			for h in v.heads:
				if h.state != HS.OUT:
					continue
				var pushed := _push_train(h.pos, hr)
				if pushed != h.pos:
					h.pos = _sweep_head(h.pos, pushed - h.pos, hr, false)


## True when a player standing at `pos` would be run over right now.
func train_unsafe(pos: Vector2) -> bool:
	if cfg.train_speed <= 0.0:
		return false
	var reach := TrainTrack.CAR_RADIUS + cfg.player_radius * Config.TRAIN_HIT_SHARE
	for k in TrainTrack.CARS:
		if pos.distance_to(TrainTrack.point(TrainTrack.car_s(train_s, k))) < reach:
			return true
	return false


func _reset_yoyo(p: SimPlayer) -> void:
	for h in p.heads:
		h.state = HS.HAND
		h.pos = p.pos
		h.prev_pos = p.pos
		h.queued_retract = false
		h.circ_pending = false
		h.circ_left = 0.0
		h.circ_free = false
		h.pins.clear()
		h.meet_on = false
		h.throw_curved = false
	p.charging = false
	p.pulling = false
	p.charge_t = 0.0
	p.press_active = false
	p.press_t = 0.0
	p.dash_t = 0.0
	p.stun_t = 0.0
	p.fling_left = 0.0


func _respawn(p: SimPlayer) -> void:
	var best := Config.SPAWNS[0]
	var best_score := -1.0
	for s in Config.SPAWNS:
		var nearest := 1000.0
		for o in players:
			if o == p or not (o.enabled and o.alive):
				continue
			nearest = minf(nearest, s.distance_to(o.pos))
			for h in o.heads:
				if h.lethal():
					nearest = minf(nearest, s.distance_to(h.pos))
		var score := nearest + rng.randf() * Config.SPAWN_NOISE
		if train_unsafe(s):
			score -= 1000.0
		if score > best_score:
			best_score = score
			best = s
	p.alive = true
	p.pos = best
	p.prev_pos = best
	_reset_yoyo(p)
	p.facing = (Config.ARENA_SIZE * 0.5 - best).normalized()
	p.aim_dir = p.facing
	p.dash_cd = 0.0
	p.dash_charges = dash_max(p)
	events.append({"type": "respawn", "pos": best, "player": p.id})
