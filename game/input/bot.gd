class_name Bot
extends RefCounted
## Produces the same SimInput struct as a human. Reads sim state, never writes it.

enum Phase { IDLE, CHARGING, WAIT_OUT, TAP, HOLD }

var idx := 0
var cfg: Config
var rng := RandomNumberGenerator.new()
var phase: int = Phase.IDLE
var phase_t := 0.0
var goal_t := 0.0
var aim_err := 0.0
var attack_wait := 1.0
var wander_target := Vector2.ZERO
var wander_t := 0.0
var _last_alive := true


func _init(index: int, config: Config, seed_value: int) -> void:
	idx = index
	cfg = config
	rng.seed = seed_value
	attack_wait = rng.randf_range(Config.BOT_ATTACK_WAIT.x, Config.BOT_ATTACK_WAIT.y)


func think(sim: Sim, dt: float) -> SimInput:
	var inp := SimInput.new()
	var me := sim.players[idx]
	if not me.alive:
		_last_alive = false
		return inp
	if not _last_alive:
		_last_alive = true
		phase = Phase.IDLE
		attack_wait = rng.randf_range(Config.BOT_ATTACK_WAIT.x, Config.BOT_ATTACK_WAIT.y)
	var target := _nearest_enemy(sim, me)
	var to_target := Vector2.ZERO
	var dist := 1000.0
	if target != null:
		to_target = target.pos - me.pos
		dist = to_target.length()

	inp.move = _wander(sim, me, dt) * (0.3 if phase == Phase.CHARGING else 1.0)

	match phase:
		Phase.IDLE:
			attack_wait -= dt
			if rng.randf() < Config.BOT_DASH_CHANCE:
				inp.dash = true
			if attack_wait <= 0.0 and me.hand_index() >= 0 and not me.pulling and target != null \
					and dist < cfg.effective_max_range() * Config.BOT_ATTACK_RANGE_FACTOR:
				var ratio := clampf((dist - cfg.effective_min_range()) \
						/ maxf(0.01, cfg.effective_max_range() - cfg.effective_min_range()), 0.0, 1.0)
				goal_t = ratio * cfg.charge_time + 0.05
				aim_err = rng.randf_range(-Config.BOT_AIM_ERROR, Config.BOT_AIM_ERROR)
				phase = Phase.CHARGING
				phase_t = 0.0
		Phase.CHARGING:
			inp.aim_held = true
			if target != null:
				inp.aim = to_target.normalized().rotated(aim_err)
			else:
				inp.aim = me.facing
			phase_t += dt
			if phase_t >= goal_t:
				inp.aim_held = false
				inp.aim = Vector2.ZERO
				phase = Phase.WAIT_OUT
				phase_t = 0.0
				goal_t = rng.randf_range(Config.BOT_RETRACT_WAIT.x, Config.BOT_RETRACT_WAIT.y)
		Phase.WAIT_OUT:
			var outs := me.heads.size() - me.count_state(SimHead.S.HAND)
			if outs == 0:
				_to_idle()
			elif me.hand_index() >= 0:
				# Extra yo-yos (Zwilling): throw the next one soon, or call them all back after a moment.
				phase_t += dt
				if phase_t >= goal_t:
					phase_t = 0.0
					if rng.randf() < Config.BOT_THROW_MORE_CHANCE:
						phase = Phase.IDLE
						attack_wait = Config.BOT_NEXT_THROW_WAIT
					elif Mods.n("twin", "pull_free", sim.lv(me, "twin")) > 0.0 and me.count_state(SimHead.S.OUT) > 0 \
							and rng.randf() < Config.BOT_PULL_CHANCE:
						phase = Phase.HOLD  # Zwilling III: pull to the lying yo-yo with one still in hand
					else:
						phase = Phase.TAP
			elif me.count_state(SimHead.S.OUT) == me.heads.size():
				phase_t += dt
				if phase_t >= goal_t:
					phase_t = 0.0
					if rng.randf() < Config.BOT_PULL_CHANCE:
						phase = Phase.HOLD
					else:
						phase = Phase.TAP
		Phase.TAP:
			inp.aim_held = true
			phase_t += dt
			if phase_t >= cfg.tap_threshold * 0.5:
				inp.aim_held = false
				_to_idle()
		Phase.HOLD:
			inp.aim_held = true
			phase_t += dt
			var pull_over := phase_t >= cfg.tap_threshold + 0.15 and not me.pulling
			if pull_over or phase_t >= cfg.tap_threshold + Config.BOT_PULL_HOLD_EXTRA * 3.0:
				inp.aim_held = false
				_to_idle()
	return inp


func _to_idle() -> void:
	phase = Phase.IDLE
	phase_t = 0.0
	attack_wait = rng.randf_range(Config.BOT_ATTACK_WAIT.x, Config.BOT_ATTACK_WAIT.y)


func _nearest_enemy(sim: Sim, me: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_d := 1e9
	for o in sim.players:
		if o == me or not (o.enabled and o.alive):
			continue
		var d := o.pos.distance_to(me.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


func _wander(sim: Sim, me: SimPlayer, dt: float) -> Vector2:
	wander_t -= dt
	if wander_t <= 0.0 or me.pos.distance_to(wander_target) < 1.0:
		wander_t = rng.randf_range(Config.BOT_WANDER_TIME.x, Config.BOT_WANDER_TIME.y)
		wander_target = Vector2(
			rng.randf_range(Config.BOT_MARGIN, Config.ARENA_SIZE.x - Config.BOT_MARGIN),
			rng.randf_range(Config.BOT_MARGIN, Config.ARENA_SIZE.y - Config.BOT_MARGIN))
	var dir := (wander_target - me.pos).normalized() * Config.BOT_MOVE_SCALE
	for s in sim.statics:
		var closest := Vector2(clampf(me.pos.x, s.position.x, s.end.x), clampf(me.pos.y, s.position.y, s.end.y))
		var away := me.pos - closest
		var d := away.length()
		if d < Config.BOT_AVOID_DIST and d > 0.001:
			dir += away / d * (1.0 - d / Config.BOT_AVOID_DIST) * Config.BOT_AVOID_WEIGHT
	return dir.limit_length(1.0)
