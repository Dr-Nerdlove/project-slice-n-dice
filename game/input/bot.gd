class_name Bot
extends RefCounted
## Produces the same SimInput struct as a human. Reads sim state, never writes it.

enum Phase { IDLE, CHARGING, WAIT_OUT, TAP, HOLD }

const THROW_CLEARANCE := 0.2   # half width of a yo-yo's line of flight when the bot checks for a wall in the way
const NAV_EVERY := 0.2         # seconds between two path searches
## Hot Potato: the carrier waits only this long before a throw; a bot that does not carry the bomb runs when the
## carrier is within POTATO_FLEE_DIST metres, picks its escape point among POTATO_FLEE_POINTS spots round it at two
## distances, and throws at others (not at the carrier) only POTATO_RARE_CHANCE of the time.
const POTATO_WAIT := Vector2(0.3, 0.8)
const POTATO_FLEE_DIST := 7.0
const POTATO_FLEE_POINTS := 16
const POTATO_FLEE_STEPS := [3.0, 6.0]
const POTATO_RARE_CHANCE := 0.15

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
var _nav_t := 0.0             # seconds until the next path search (the waypoint is kept in between)
var _nav_point := Vector2.ZERO
var _nav_goal := Vector2.ZERO
var _pad_t := 0.0             # seconds until the next look at the trampolines (Bounce House)
var _pad_pick := -1           # the trampoline the bot is walking to, or -1
var _aim_pig := false         # the throw being charged goes at the piggy bank
var _was_carrier := false     # Hot Potato: carried the bomb in the last think
var _rare_ok := false         # Hot Potato: this attack wait may end in a throw at somebody who is not the carrier
var _flee_t := 0.0            # Hot Potato: seconds until the escape point is chosen again
var _flee_point := Vector2.ZERO


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
	var potato: bool = sim.mode is HotPotato and sim.mode.phase == MatchMode.Phase.PLAY
	var carrier: bool = potato and sim.mode.bomb_holder == idx
	if carrier != _was_carrier:
		_was_carrier = carrier
		if carrier:
			attack_wait = minf(attack_wait, rng.randf_range(POTATO_WAIT.x, POTATO_WAIT.y))
	var nearest := _nearest_enemy(sim, me)
	var dist := me.pos.distance_to(nearest.pos) if nearest != null else 1000.0
	# A throw goes only at an enemy with a clear line: a wall in between makes the bot walk instead.
	var target := _nearest_visible_enemy(sim, me)
	if potato:
		target = _nearest_potato_prey(sim, me) if carrier else _potato_target(sim, me)
		dist = me.pos.distance_to(target.pos) if target != null else 1000.0
	var to_target := Vector2.ZERO
	if target != null:
		to_target = target.pos - me.pos
		dist = minf(dist, to_target.length())

	var walk := _wander(sim, me, dt)
	if potato:
		walk = _potato_walk(sim, me, walk, carrier, target, dt)
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
	var pig := MapDef.PIG_RECT.get_center()
	var d := me.pos.distance_to(pig)
	if d >= cfg.effective_max_range() * 0.95:
		return false
	# the shelves round the pig: no throw through a wall (the check stops 2.2 m short of the pig's middle, before its own block)
	var stop := pig + (me.pos - pig).normalized() * 2.2
	return d <= 2.2 or NavGrid.for_sim(sim).line_clear(me.pos, stop, THROW_CLEARANCE)


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


## Lava Mats. On a marked mat: along the walking path to the nearest spot on a safe one (inside the zone if possible), at full
## speed. Next to marked mats: pushed away from their edges.
func _lava_steer(sim: Sim, me: SimPlayer, zone: Rect2, dt: float) -> Vector2:
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
		# around the walls of the floor plan, not straight into them
		return (_steer_point(sim, me, best, dt) - me.pos).normalized() * Config.BOT_LAVA_WEIGHT
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
		if o == me or not (o.enabled and o.alive) or not sim.mode.harms(me.id, o.id):
			continue   # a teammate is no enemy and no danger
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


## Bounce House: where to walk. Normally `goal`; when the walk to it is long and a trampoline that is not a bad idea
## (`_pad_bad`) is close on foot and lands the bot much nearer to it, the trampoline. Decided every BOT_PAD_EVERY seconds.
func _pad_goal(sim: Sim, me: SimPlayer, goal: Vector2, zone: Rect2, dt: float) -> Vector2:
	if me.air_t > 0.0:
		_pad_pick = -1
		_pad_t = 0.0
		return goal
	_pad_t -= dt
	if _pad_t <= 0.0:
		_pad_t = Config.BOT_PAD_EVERY
		_pad_pick = -1
		var grid := NavGrid.for_sim(sim)
		var best := grid.path_length(me.pos, goal) - Config.BOT_PAD_GAIN
		for k in MapDef.PADS.size():
			if _pad_bad(sim, me, k, zone):
				continue
			var to_pad := grid.path_length(me.pos, MapDef.PADS[k][0])
			if to_pad > Config.BOT_PAD_REACH:
				continue
			var total := to_pad + grid.path_length(MapDef.PADS[k][1], goal)
			if total < best:
				best = total
				_pad_pick = k
	return MapDef.PADS[_pad_pick][0] if _pad_pick >= 0 else goal


func _to_idle() -> void:
	_aim_pig = false
	phase = Phase.IDLE
	phase_t = 0.0
	attack_wait = rng.randf_range(Config.BOT_ATTACK_WAIT.x, Config.BOT_ATTACK_WAIT.y)
	if _was_carrier:
		attack_wait = rng.randf_range(POTATO_WAIT.x, POTATO_WAIT.y)
	_rare_ok = rng.randf() < POTATO_RARE_CHANCE


## Hot Potato, a bot that does not carry the bomb: throws at the carrier (a stun) when it has a clear line, otherwise
## rarely (`_rare_ok`) at the nearest player it sees.
func _potato_target(sim: Sim, me: SimPlayer) -> SimPlayer:
	var c := sim.players[sim.mode.bomb_holder] if sim.mode.bomb_holder >= 0 else null
	if c != null and c != me and c.enabled and c.alive and NavGrid.for_sim(sim).line_clear(me.pos, c.pos, THROW_CLEARANCE):
		return c
	return _nearest_visible_enemy(sim, me) if _rare_ok else null


## Hot Potato walking. The carrier goes for the nearest player he can see (not the one who just passed him the
## bomb); anybody else runs to a free spot away from the carrier while he is closer than POTATO_FLEE_DIST.
func _potato_walk(sim: Sim, me: SimPlayer, walk: Vector2, carrier: bool, target: SimPlayer, dt: float) -> Vector2:
	var m: HotPotato = sim.mode
	if carrier:
		var prey := _nearest_potato_prey(sim, me)
		if prey == null:
			return walk
		return ((_steer_point(sim, me, prey.pos, dt) - me.pos).normalized() + walk * 0.2).limit_length(1.0)
	var c := sim.players[m.bomb_holder] if m.bomb_holder >= 0 else null
	if c == null or not (c.enabled and c.alive) or me.pos.distance_to(c.pos) > POTATO_FLEE_DIST:
		return walk
	_flee_t -= dt
	if _flee_t <= 0.0:
		_flee_t = NAV_EVERY
		_flee_point = _flee_spot(sim, me, c.pos)
	var away := (_flee_point - me.pos).normalized()
	return (away + walk * 0.25).limit_length(1.0)


## The player a carrier hunts: nearest that can be reached in a straight line, skipping the tag-back lock.
func _nearest_potato_prey(sim: Sim, me: SimPlayer) -> SimPlayer:
	var m: HotPotato = sim.mode
	var grid := NavGrid.for_sim(sim)
	var best: SimPlayer = null
	var best_d := 1e9
	for o in sim.players:
		if o == me or not (o.enabled and o.alive) or m.tagback_locked(o.id):
			continue
		var d := o.pos.distance_to(me.pos)
		if d < best_d and grid.line_clear(me.pos, o.pos, THROW_CLEARANCE):
			best_d = d
			best = o
	return best


## A spot round the bot that is reachable in a straight line, inside the arena margin and as far from `from` as possible.
func _flee_spot(sim: Sim, me: SimPlayer, from: Vector2) -> Vector2:
	var grid := NavGrid.for_sim(sim)
	var best := me.pos
	var best_d := me.pos.distance_to(from)
	for step: float in POTATO_FLEE_STEPS:
		for k in POTATO_FLEE_POINTS:
			var q := me.pos + Vector2.RIGHT.rotated(TAU * k / POTATO_FLEE_POINTS) * step
			q = Vector2(clampf(q.x, Config.BOT_MARGIN, Config.ARENA_SIZE.x - Config.BOT_MARGIN),
					clampf(q.y, Config.BOT_MARGIN, Config.ARENA_SIZE.y - Config.BOT_MARGIN))
			if not grid.line_clear(me.pos, q):
				continue
			var d := q.distance_to(from)
			if d > best_d + 0.01:
				best_d = d
				best = q
	return best


func _nearest_enemy(sim: Sim, me: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_d := 1e9
	for o in sim.players:
		if o == me or not (o.enabled and o.alive) or not sim.mode.harms(me.id, o.id):
			continue   # a teammate is no enemy and no danger
		var d := o.pos.distance_to(me.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


## The nearest enemy that a yo-yo can fly to in a straight line (no wall between), or null.
func _nearest_visible_enemy(sim: Sim, me: SimPlayer) -> SimPlayer:
	var grid := NavGrid.for_sim(sim)
	var best: SimPlayer = null
	var best_d := 1e9
	for o in sim.players:
		if o == me or not (o.enabled and o.alive) or not sim.mode.harms(me.id, o.id):
			continue   # a teammate is no enemy and no danger
		var d := o.pos.distance_to(me.pos)
		if d < best_d and grid.line_clear(me.pos, o.pos, THROW_CLEARANCE):
			best_d = d
			best = o
	return best


## Where to walk to reach `goal`: the goal itself with a clear walking line, else the next waypoint of a path
## around the walls (searched again every NAV_EVERY seconds or when the goal moves to another cell).
func _steer_point(sim: Sim, me: SimPlayer, goal: Vector2, dt: float) -> Vector2:
	var grid := NavGrid.for_sim(sim)
	if grid.line_clear(me.pos, goal):
		_nav_t = 0.0
		return goal
	_nav_t -= dt
	if _nav_t <= 0.0 or NavGrid.cell_of(goal) != NavGrid.cell_of(_nav_goal) or me.pos.distance_to(_nav_point) < 0.3:
		_nav_t = NAV_EVERY
		_nav_goal = goal
		_nav_point = grid.next_point(me.pos, goal)
	return _nav_point


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
	wander_target = NavGrid.for_sim(sim).snap(wander_target)   # never a spot inside a wall
	var goal := wander_target
	if sim.map_id == MapDef.Id.BOUNCE:
		goal = _pad_goal(sim, me, goal, zone, dt)
	var dir := (_steer_point(sim, me, goal, dt) - me.pos).normalized() * Config.BOT_MOVE_SCALE
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
			dir += _lava_steer(sim, me, zone, dt)
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
