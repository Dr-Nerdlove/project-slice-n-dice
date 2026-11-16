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
var _urgent := false          # set by `_wander`: running from a marked mat, so no slow walking while charging
var _aim_pig := false         # the throw being charged goes at the piggy bank


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

	var walk := _wander(sim, me, dt)
	inp.move = walk * (0.3 if phase == Phase.CHARGING and not _urgent else 1.0)

	match phase:
		Phase.IDLE:
			attack_wait -= dt
			var dash_roll := rng.randf()   # always drawn, so the random sequence does not depend on the train
			if dash_roll < Config.BOT_DASH_CHANCE and not _train_near(sim, me, cfg.dash_distance) \
					and not _map_hazard_near(sim, me, cfg.dash_distance):
				inp.dash = true
			if attack_wait <= 0.0 and me.hand_index() >= 0 and not me.pulling and _pig_wanted(sim, me, dist):
				# Piggy Bank: coins on the pig, nobody close: throw at it (not every time, so the pot can grow).
				var pig_d := me.pos.distance_to(MapDef.PIG_RECT.get_center())
				if rng.randf() < Config.BOT_PIG_CHANCE * sim.pig_coins / float(MapDef.PIG_MAX):
					goal_t = clampf((pig_d - cfg.effective_min_range()) \
							/ maxf(0.01, cfg.effective_max_range() - cfg.effective_min_range()), 0.0, 1.0) * cfg.charge_time + 0.05
					aim_err = rng.randf_range(-Config.BOT_AIM_ERROR, Config.BOT_AIM_ERROR) * 0.3
					_aim_pig = true
					phase = Phase.CHARGING
					phase_t = 0.0
				else:
					attack_wait = 1.0
			elif attack_wait <= 0.0 and me.hand_index() >= 0 and not me.pulling and target != null \
					and dist < cfg.effective_max_range() * Config.BOT_ATTACK_RANGE_FACTOR:
				var ratio := clampf((dist - cfg.effective_min_range()) \
						/ maxf(0.01, cfg.effective_max_range() - cfg.effective_min_range()), 0.0, 1.0)
				goal_t = ratio * cfg.charge_time + 0.05
				aim_err = rng.randf_range(-Config.BOT_AIM_ERROR, Config.BOT_AIM_ERROR)
				_aim_pig = false
				phase = Phase.CHARGING
				phase_t = 0.0
		Phase.CHARGING:
			inp.aim_held = true
			if _aim_pig:
				inp.aim = (MapDef.PIG_RECT.get_center() - me.pos).normalized().rotated(aim_err)
			elif target != null:
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
				# Extra yo-yos (Twin): throw the next one soon, or call them all back after a moment.
				phase_t += dt
				if phase_t >= goal_t:
					phase_t = 0.0
					if rng.randf() < Config.BOT_THROW_MORE_CHANCE:
						phase = Phase.IDLE
						attack_wait = Config.BOT_NEXT_THROW_WAIT
					elif Mods.n("twin", "pull_free", sim.lv(me, "twin")) > 0.0 and me.count_state(SimHead.S.OUT) > 0 \
							and rng.randf() < Config.BOT_PULL_CHANCE:
						phase = Phase.HOLD  # Twin III: pull to the lying yo-yo with one still in hand
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


## True when a train car is closer than the avoidance distance plus `extra` (a dash must not carry the bot into it).
func _train_near(sim: Sim, me: SimPlayer, extra: float) -> bool:
	if not sim.train_on():
		return false
	for k in TrainTrack.CARS:
		if me.pos.distance_to(TrainTrack.point(TrainTrack.car_s(sim.train_s, k))) < Config.BOT_TRAIN_AVOID_DIST + extra:
			return true
	return false


## Piggy Bank: true when a throw at the pig makes sense: coins on it, in range, and no enemy close (`enemy_dist`).
func _pig_wanted(sim: Sim, me: SimPlayer, enemy_dist: float) -> bool:
	if sim.map_id != MapDef.Id.PIGGY or sim.pig_coins <= 0 or enemy_dist < Config.BOT_PIG_ENEMY_DIST:
		return false
	return me.pos.distance_to(MapDef.PIG_RECT.get_center()) < cfg.effective_max_range() * 0.95


## True when a dash of length `extra` could carry the bot into trouble on this map: any marked mat (Lava Mats), a
## trampoline that would throw it somewhere bad (Bounce House).
func _map_hazard_near(sim: Sim, me: SimPlayer, extra: float) -> bool:
	match sim.map_id:
		MapDef.Id.LAVA:
			return not sim.lava_cells.is_empty()
		MapDef.Id.BOUNCE:
			var zone := sim.zone_rect().grow(-Config.BOT_ZONE_MARGIN) if sim.mode.phase == MatchMode.Phase.PLAY else Rect2()
			for k in MapDef.PADS.size():
				if _pad_bad(sim, me, k, zone) and me.pos.distance_to(MapDef.PADS[k][0]) < MapDef.PAD_RADIUS + extra + 0.5:
					return true
	return false


## Lava Mats. On a marked mat: straight to the nearest spot on a safe one (inside the zone if possible), at full
## speed. Next to marked mats: pushed away from their edges.
func _lava_steer(sim: Sim, me: SimPlayer, zone: Rect2) -> Vector2:
	if sim.lava_cells.is_empty():
		return Vector2.ZERO
	if sim.lava_cells.has(MapDef.lava_cell(me.pos)):
		var best := me.pos
		var best_d := 1e9
		for c in MapDef.LAVA_COLS * MapDef.LAVA_ROWS:
			if sim.lava_cells.has(c):
				continue
			var r := MapDef.lava_rect(c).grow(-(sim.cfg.player_radius + 0.4))
			var q := Vector2(clampf(me.pos.x, r.position.x, r.end.x), clampf(me.pos.y, r.position.y, r.end.y))
			var d := q.distance_to(me.pos)
			if zone != Rect2() and not zone.has_point(q):
				d += 4.0
			for s in sim.statics:
				if s.grow(sim.cfg.player_radius).has_point(q):
					d += 4.0   # a block stands there
			if d < best_d:
				best_d = d
				best = q
		_urgent = true
		return (best - me.pos).normalized() * Config.BOT_LAVA_WEIGHT
	var push := Vector2.ZERO
	for c in sim.lava_cells:
		var r := MapDef.lava_rect(c)
		var closest := Vector2(clampf(me.pos.x, r.position.x, r.end.x), clampf(me.pos.y, r.position.y, r.end.y))
		var away := me.pos - closest
		var d := away.length()
		if d < Config.BOT_LAVA_AVOID_DIST and d > 0.001:
			push += away / d * (1.0 - d / Config.BOT_LAVA_AVOID_DIST) * Config.BOT_LAVA_WEIGHT
	return push


## Bounce House: is trampoline `k` a bad idea right now? Its landing spot is outside the zone (`zone`: the bots' safe
## rectangle, empty outside a round) or a deadly yo-yo of somebody else lies on it.
func _pad_bad(sim: Sim, me: SimPlayer, k: int, zone: Rect2) -> bool:
	var land: Vector2 = MapDef.PADS[k][1]
	if zone != Rect2() and not zone.has_point(land):
		return true
	for o in sim.players:
		if o == me or not (o.enabled and o.alive):
			continue
		for h in o.heads:
			if h.lethal() and h.pos.distance_to(land) < Config.BOT_PAD_HEAD_DIST:
				return true
	return false


## Bounce House: pushed away from the rim of every trampoline that is a bad idea.
func _pad_steer(sim: Sim, me: SimPlayer, zone: Rect2) -> Vector2:
	var push := Vector2.ZERO
	for k in MapDef.PADS.size():
		var away: Vector2 = me.pos - MapDef.PADS[k][0]
		var d := away.length() - MapDef.PAD_RADIUS
		if d < Config.BOT_PAD_AVOID_DIST and away.length() > 0.001 and _pad_bad(sim, me, k, zone):
			push += away.normalized() * (1.0 - maxf(d, 0.0) / Config.BOT_PAD_AVOID_DIST) * Config.BOT_PAD_WEIGHT
	return push


func _to_idle() -> void:
	_aim_pig = false
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
	var zone := Rect2()
	if sim.mode.phase == MatchMode.Phase.PLAY:
		# The target stays inside the (shrinking) zone with a margin, because its edges move in.
		zone = sim.zone_rect().grow(-Config.BOT_ZONE_MARGIN)
		wander_target = Vector2(clampf(wander_target.x, zone.position.x, zone.end.x), clampf(wander_target.y, zone.position.y, zone.end.y))
	var dir := (wander_target - me.pos).normalized() * Config.BOT_MOVE_SCALE
	for s in sim.statics:
		var closest := Vector2(clampf(me.pos.x, s.position.x, s.end.x), clampf(me.pos.y, s.position.y, s.end.y))
		var away := me.pos - closest
		var d := away.length()
		if d < Config.BOT_AVOID_DIST and d > 0.001:
			dir += away / d * (1.0 - d / Config.BOT_AVOID_DIST) * Config.BOT_AVOID_WEIGHT
	if sim.train_on():
		for k in TrainTrack.CARS:
			var cs := TrainTrack.car_s(sim.train_s, k)
			var rel := me.pos - TrainTrack.point(cs)
			var d := rel.length()
			if d >= Config.BOT_TRAIN_AVOID_DIST:
				continue
			# Step off the rails sideways (running ahead of the train would not outrun it), and away from the car.
			var td := TrainTrack.dir(cs)
			var side := rel - td * rel.dot(td)
			side = side.normalized() if side.length() > 0.05 else Vector2(-td.y, td.x)
			var w := (1.0 - d / Config.BOT_TRAIN_AVOID_DIST) * Config.BOT_TRAIN_AVOID_WEIGHT
			dir += (side + rel.normalized() * 0.5) * w
	_urgent = false
	match sim.map_id:
		MapDef.Id.LAVA:
			dir += _lava_steer(sim, me, zone)
		MapDef.Id.BOUNCE:
			dir += _pad_steer(sim, me, zone)
	if zone != Rect2():
		# Outside the margin: steer back in.
		var z := zone
		var inside := Vector2(clampf(me.pos.x, z.position.x, z.end.x), clampf(me.pos.y, z.position.y, z.end.y))
		if inside != me.pos:
			dir += (inside - me.pos).normalized() * 3.0
	return dir.limit_length(1.0)


## The shop for bot slot `i` (called once the shop has been open Economy.BOT_SHOP_DELAY seconds; it only uses the
## sim's shop commands, so the server stays the judge). Buys what it can afford, a copy of an owned modifier first,
## then the dearer one; rerolls up to Economy.BOT_REROLLS times while nothing on offer is affordable and a reroll
## still leaves enough for the cheapest modifier; then it is done.
static func shop(sim: Sim, i: int) -> void:
	var m := sim.mode
	if m.phase != MatchMode.Phase.SHOP or not m.roster[i] or m.shop_ready[i] \
			or m.phase_t < Economy.BOT_SHOP_DELAY:
		return
	var cheapest := 1 << 30
	for t: int in Mods.PRICES:
		cheapest = mini(cheapest, Mods.PRICES[t])
	var rerolls := 0
	for _guard in 32:
		var best := -1
		var best_score := -1
		for k in m.offers[i].size():
			var id: String = m.offers[i][k]
			if id == "" or Mods.price(id) > m.coins[i] or not m.can_take(i, id):
				continue
			var score: int = (100 if m.owned[i].has(id) else 0) + Mods.price(id)
			if score > best_score:
				best = k
				best_score = score
		if best >= 0:
			sim.shop_buy(i, best, m.shop_seq[i])
		elif rerolls < Economy.BOT_REROLLS and m.coins[i] >= Economy.REROLL_PRICE + cheapest:
			rerolls += 1
			sim.shop_reroll(i, m.shop_seq[i])
		else:
			break
	sim.shop_done(i)
