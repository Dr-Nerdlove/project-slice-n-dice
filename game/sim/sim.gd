class_name Sim
extends RefCounted
## Deterministic fixed-tick simulation. No nodes, no input singleton, no wall clock.
## Call step(inputs) exactly once per tick (Config.TICK_RATE). All state is plain data.

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
## Events of the last tick (dictionaries with "type"): kill, bounce, box_break, respawn.
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
		p.pos = Config.SPAWNS[i]
		p.dash_charges = cfg.dash_charges
		p.prev_pos = p.pos
		p.head = p.pos
		p.prev_head = p.pos
		p.facing = (Vector2(a.x, a.y) * 0.5 - p.pos).normalized()
		p.aim_dir = p.facing
		players.append(p)


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


func step(inputs: Array) -> void:
	events.clear()
	tick += 1
	var dt := 1.0 / Config.TICK_RATE
	prev_crate_pos = crate_pos
	for p in players:
		p.prev_pos = p.pos
		p.prev_head = p.head
	for i in players.size():
		if players[i].enabled:
			_step_player(players[i], inputs[i], dt)
	_separate_players()
	_collide_heads()
	_check_kills()
	_step_box(dt)


# ---------------------------------------------------------------- queries

func charge_range(p: SimPlayer) -> float:
	var t := clampf(p.charge_t / cfg.charge_time, 0.0, 1.0)
	return lerpf(cfg.effective_min_range(), cfg.effective_max_range(), t)


## Landing distance of the current charge, shortened by walls (for the aim line).
func aim_range(p: SimPlayer) -> float:
	var full := charge_range(p)
	var end := _sweep_head(p.pos, p.aim_dir * full, cfg.head_radius, false)
	return (end - p.pos).length()


# ---------------------------------------------------------------- player

func _step_player(p: SimPlayer, inp: SimInput, dt: float) -> void:
	if not p.alive:
		p.respawn_t -= dt
		p.held_prev = inp.aim_held
		if p.respawn_t <= 0.0:
			_respawn(p)
		return

	var held := inp.aim_held
	var pressed := held and not p.held_prev
	var released := (not held) and p.held_prev
	p.held_prev = held

	var before := p.pos
	if p.ystate != SimPlayer.Yo.PULL:
		_move_player(p, inp, dt)
	if p.ystate == SimPlayer.Yo.OUT:
		_apply_out_variant(p, p.pos - before)

	if p.ystate == SimPlayer.Yo.READY and pressed:
		p.ystate = SimPlayer.Yo.CHARGING
		p.charge_t = 0.0
		p.aimed = false
		p.aim_dir = p.facing

	match p.ystate:
		SimPlayer.Yo.CHARGING:
			_step_charging(p, inp, released, dt)
		SimPlayer.Yo.FLIGHT:
			_track_press(p, pressed, held, dt, true)
			_step_flight(p, dt)
		SimPlayer.Yo.OUT:
			_step_out(p, pressed, held, dt)
		SimPlayer.Yo.PULL:
			_step_pull(p, held, dt)
		SimPlayer.Yo.RETRACT:
			_track_press(p, pressed, held, dt, false)
			_step_retract(p, dt)

	if p.ystate == SimPlayer.Yo.READY or p.ystate == SimPlayer.Yo.CHARGING:
		p.head = p.pos


func _move_player(p: SimPlayer, inp: SimInput, dt: float) -> void:
	_step_dash_charges(p, dt)
	var mv := inp.move.limit_length(1.0)
	if mv.length() > Config.MOVE_DEADZONE:
		p.facing = mv.normalized()
	if inp.dash and p.dash_charges > 0 and p.dash_t <= 0.0:
		p.dash_t = cfg.dash_duration
		if p.dash_charges >= cfg.dash_charges:
			p.dash_cd = cfg.dash_cooldown  # the refill timer starts with the first spent charge
		p.dash_charges -= 1
		p.dash_dir = p.facing
	var delta := Vector2.ZERO
	if p.dash_t > 0.0:
		var slice := minf(dt, p.dash_t)
		delta = p.dash_dir * (cfg.dash_distance / cfg.dash_duration) * slice
		p.dash_t -= dt
	else:
		var speed := cfg.player_speed
		if p.ystate == SimPlayer.Yo.CHARGING:
			speed *= cfg.charge_speed_mult
		delta = mv * speed * dt
	_slide_player(p, delta)


## Charges refill one at a time, each taking dash_cooldown.
func _step_dash_charges(p: SimPlayer, dt: float) -> void:
	var mx := cfg.dash_charges
	p.dash_charges = mini(p.dash_charges, mx)
	if p.dash_charges >= mx:
		p.dash_cd = 0.0
		return
	if p.dash_cd <= 0.0:
		p.dash_cd = cfg.dash_cooldown
	p.dash_cd -= dt
	if p.dash_cd <= 0.0:
		p.dash_charges += 1
		p.dash_cd = cfg.dash_cooldown if p.dash_charges < mx else 0.0


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


func _push_statics(pos: Vector2, r: float) -> Vector2:
	for _i in 2:
		for s in statics:
			pos += Collide.push_out_rect(pos, r, s)
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


# ---------------------------------------------------------------- yo-yo

func _step_charging(p: SimPlayer, inp: SimInput, released: bool, dt: float) -> void:
	if inp.aim.length() >= cfg.aim_deadzone:
		p.aim_dir = inp.aim.normalized()
		p.aimed = true
	if released:
		if not p.aimed and p.charge_t < cfg.accidental_hold_time:
			p.ystate = SimPlayer.Yo.READY  # accidental touch: cancel, no throw
		else:
			p.ystate = SimPlayer.Yo.FLIGHT
			p.throw_dir = p.aim_dir
			p.flight_dist = charge_range(p)
			p.flown = 0.0
			p.head = p.pos
			p.facing = p.aim_dir
	else:
		p.charge_t += dt


func _step_flight(p: SimPlayer, dt: float) -> void:
	var mv := minf(cfg.flight_speed * dt, p.flight_dist - p.flown)
	_hit = false
	p.head = _sweep_head(p.head, p.throw_dir * mv, cfg.head_radius, true)
	p.flown += mv
	if _hit or p.flown >= p.flight_dist - 0.00001:
		_land(p)


## The head lies still. A press that is still running keeps counting (press_active / press_t),
## a short tap made during the flight retracts the head right away.
func _land(p: SimPlayer) -> void:
	p.ystate = SimPlayer.Yo.OUT
	if p.tap_buffered:
		p.tap_buffered = false
		p.press_active = false
		p.ystate = SimPlayer.Yo.RETRACT


## Follows a press that starts while the head is moving, so it is not lost at the landing.
func _track_press(p: SimPlayer, pressed: bool, held: bool, dt: float, buffer_tap: bool) -> void:
	if pressed:
		p.press_active = true
		p.press_t = 0.0
	if not p.press_active:
		return
	if held:
		p.press_t += dt
	else:
		p.press_active = false
		if buffer_tap and p.press_t < cfg.tap_threshold:
			p.tap_buffered = true


func _step_out(p: SimPlayer, pressed: bool, held: bool, dt: float) -> void:
	if pressed:
		p.press_active = true
		p.press_t = 0.0
	if not p.press_active:
		return
	if held:
		p.press_t += dt
		if p.press_t >= cfg.tap_threshold:
			p.ystate = SimPlayer.Yo.PULL
	else:
		p.press_active = false
		p.ystate = SimPlayer.Yo.RETRACT  # short tap


func _step_pull(p: SimPlayer, held: bool, dt: float) -> void:
	if not held:
		p.ystate = SimPlayer.Yo.OUT
		p.press_active = false
		return
	var catch_dist := cfg.player_radius + cfg.head_radius + Config.CATCH_MARGIN
	var to_head := p.head - p.pos
	var d := to_head.length()
	if d > 0.0001:
		p.facing = to_head / d
	if d > catch_dist:
		_slide_player(p, to_head / d * minf(cfg.pull_speed * dt, d))
	if p.pos.distance_to(p.head) <= catch_dist:
		p.ystate = SimPlayer.Yo.READY
		p.head = p.pos


func _step_retract(p: SimPlayer, dt: float) -> void:
	var to_p := p.pos - p.head
	var d := to_p.length()
	var step := cfg.retract_speed * dt
	if d <= step:
		p.ystate = SimPlayer.Yo.READY
		p.head = p.pos
		p.press_active = false
		return
	var dir := to_p / d
	var start := p.head
	p.head = _sweep_retract(start, dir * step)
	# Blocked by a wall / obstacle / jammed crate: lie there again instead of jittering in place.
	if (p.head - start).dot(dir) < step * Config.RETRACT_MIN_PROGRESS:
		p.ystate = SimPlayer.Yo.OUT


## Moves a retracting head: stopped by walls and obstacles, drags the crate, breaks the box and passes on.
func _sweep_retract(pos: Vector2, delta: Vector2) -> Vector2:
	var r := cfg.head_radius
	var n := maxi(1, ceili(delta.length() / (r * Config.SUBSTEP_FACTOR)))
	var sv := delta / float(n)
	for _i in n:
		pos = _push_statics(pos + sv, r)
		if box_active and Collide.push_out_rect(pos, r, box_rect()) != Vector2.ZERO:
			_break_box()
		pos = _crate_vs_circle(pos, r, 1.0)
		pos = _push_statics(pos, r)
	return pos


func _apply_out_variant(p: SimPlayer, player_delta: Vector2) -> void:
	var r := cfg.head_radius
	var length := cfg.string_length
	match cfg.out_variant:
		Config.OutVariant.RIGID:
			if player_delta != Vector2.ZERO:
				p.head = _sweep_head(p.head, player_delta, r, false)
		Config.OutVariant.DRAG:
			var off := p.pos - p.head
			var d := off.length()
			if d > length:
				p.head = _sweep_head(p.head, off / d * (d - length), r, false)
	# The string is never longer than its length: pull the player back if the head could not follow.
	var off2 := p.pos - p.head
	var d2 := off2.length()
	if d2 > length:
		p.pos = _collide_player(p.head + off2 / d2 * length, cfg.player_radius)


func _sweep_head(pos: Vector2, delta: Vector2, r: float, breaks_box: bool) -> Vector2:
	var n := maxi(1, ceili(delta.length() / (r * Config.SUBSTEP_FACTOR)))
	var sv := delta / float(n)
	for _i in n:
		var start := pos + sv
		pos = _resolve_head(start, r, breaks_box)
		if (pos - start).length_squared() > 1e-10:
			_hit = true
	return pos


func _resolve_head(pos: Vector2, r: float, breaks_box: bool) -> Vector2:
	pos = _push_statics(pos, r)
	if box_active:
		var c := Collide.push_out_rect(pos, r, box_rect())
		if c != Vector2.ZERO:
			if breaks_box:
				_break_box()
			else:
				pos += c
	pos += Collide.push_out_rect(pos, r, crate_rect())
	return _push_statics(pos, r)


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
	var r := cfg.head_radius
	var blocked := rect.intersects(crate_rect())
	for p in players:
		if not (p.enabled and p.alive):
			continue
		if Collide.push_out_rect(p.pos, cfg.player_radius, rect) != Vector2.ZERO:
			blocked = true
		if p.head_is_lethal() and Collide.push_out_rect(p.head, r, rect) != Vector2.ZERO:
			blocked = true
	if not blocked:
		box_active = true


func _collide_heads() -> void:
	var r := cfg.head_radius
	for i in players.size():
		var a := players[i]
		if not (a.enabled and a.alive and a.head_is_lethal()):
			continue
		for j in range(i + 1, players.size()):
			var b := players[j]
			if not (b.enabled and b.alive and b.head_is_lethal()):
				continue
			var d := a.head - b.head
			var dist := d.length()
			if dist >= 2.0 * r:
				continue
			var n := d / dist if dist > 0.0001 else Vector2.RIGHT
			var a_moving := a.ystate == SimPlayer.Yo.FLIGHT or a.ystate == SimPlayer.Yo.RETRACT
			var b_moving := b.ystate == SimPlayer.Yo.FLIGHT or b.ystate == SimPlayer.Yo.RETRACT
			var knock := (2.0 * r - dist) * 0.5
			if a_moving or b_moving:
				knock += Config.HEAD_BOUNCE_EXTRA
				events.append({"type": "bounce", "pos": (a.head + b.head) * 0.5})
			a.head = _sweep_head(a.head, n * knock, r, false)
			b.head = _sweep_head(b.head, -n * knock, r, false)
			if a_moving:
				_land(a)
			if b_moving:
				_land(b)


func _check_kills() -> void:
	var reach := cfg.head_radius + cfg.player_radius
	for a in players:
		if not (a.enabled and a.alive and a.head_is_lethal()):
			continue
		for v in players:
			if v == a or not (v.enabled and v.alive):
				continue
			# Swept check along this tick's head path, so a fast head cannot skip over a player.
			var nearest := Geometry2D.get_closest_point_to_segment(v.pos, a.prev_head, a.head)
			if nearest.distance_to(v.pos) < reach:
				_kill(v, a)


func _kill(victim: SimPlayer, killer: SimPlayer) -> void:
	victim.alive = false
	victim.deaths += 1
	killer.kills += 1
	victim.respawn_t = cfg.respawn_time
	_reset_yoyo(victim)
	events.append({"type": "kill", "pos": victim.pos, "victim": victim.id, "killer": killer.id})


func _reset_yoyo(p: SimPlayer) -> void:
	p.ystate = SimPlayer.Yo.READY
	p.head = p.pos
	p.prev_head = p.pos
	p.charge_t = 0.0
	p.press_active = false
	p.press_t = 0.0
	p.tap_buffered = false
	p.dash_t = 0.0


func _respawn(p: SimPlayer) -> void:
	var best := Config.SPAWNS[0]
	var best_score := -1.0
	for s in Config.SPAWNS:
		var nearest := 1000.0
		for o in players:
			if o == p or not (o.enabled and o.alive):
				continue
			nearest = minf(nearest, s.distance_to(o.pos))
			if o.head_is_lethal():
				nearest = minf(nearest, s.distance_to(o.head))
		var score := nearest + rng.randf() * Config.SPAWN_NOISE
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
	p.dash_charges = cfg.dash_charges
	events.append({"type": "respawn", "pos": best, "player": p.id})
