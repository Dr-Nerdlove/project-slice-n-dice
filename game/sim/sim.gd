class_name Sim
extends RefCounted
## Deterministic fixed-tick simulation. No nodes, no input singleton, no wall clock.
## Call step(inputs) exactly once per tick (Config.TICK_RATE). All state is plain data.

const HS := SimHead.S
## Variables that are not part of the snapshot: configuration, static layout, per-tick output, rng (handled by hand).
const STATE_SKIP := ["cfg", "rng", "statics", "wall_count", "events", "_built_map"]

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
## The map (MapDef.Id) and the state of its twist. `map_t` is the twist's clock: seconds of play since the round (or
## the sim) began; belts, lava waves and magnets are pure functions of it. Rules: the section "maps" below.
var map_id := 0
var map_t := 0.0
var lava_cells := PackedInt32Array()   # Lava Mats: the mats that blink or burn right now (sorted cell numbers)
var lava_wave := 0                     # Lava Mats: waves drawn so far this round
var pig_coins := 0                     # Piggy Bank: coins on the pig's back
var pig_t := 0.0                       # Piggy Bank: seconds towards the next coin
## Rounds and score. Phase OFF (the default) is free play with respawns; `start_match` begins a match.
var mode: MatchMode = LastStanding.new()   # replaced in _init by the class of `Config.game_mode`
## Events of the last tick (dictionaries with "type"): kill, bounce, ricochet, box_break, respawn,
## explosion, wire, stun, bomb_pass (from, to), bomb_explode (pos, victim), round_start, round_end ("scorer"), match_over ("winner"). A kill by the train has "killer": -1 and "cause": "train", a death by the own explosion "killer": -1 and "cause": "self".
var events: Array = []

var _head_hit := false  # scratch flag set by head sweeps
var _built_map := -1  # the map `statics` was built for


## `mode_kind`: a `Config.GameMode` that overrides `config.game_mode` (Training forces free for all); -1 = the config's.
func _init(config: Config, seed_value: int, mode_kind := -1) -> void:
	cfg = config
	mode = MatchMode.create(config.game_mode if mode_kind < 0 else mode_kind)
	rng.seed = seed_value
	var a := Config.ARENA_SIZE
	map_id = MapDef.valid(cfg.map)
	_build_statics()
	crate_pos = MapDef.crate_start(map_id)
	prev_crate_pos = crate_pos
	for i in Config.NUM_PLAYERS:
		var p := SimPlayer.new()
		p.id = i
		p.skin = i % Config.SKIN_COUNT
		p.color = i % Config.COLOR_COUNT
		if mode.is_team_mode():
			p.color = mode.allowed_colors(i)[i / 2]   # slot i: team i % 2, place i / 2 in it
		p.enabled = i < cfg.player_count   # the others are switched on by whoever fills the slots (bots, joiners)
		if not p.enabled:
			p.alive = false
		p.pos = MapDef.spawns(map_id)[i]
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
	if map_id != _built_map:
		map_id = MapDef.valid(map_id)
		_build_statics()   # a snapshot of another map: the layout follows
	rng.seed = d["rng_seed"]
	rng.state = d["rng_state"]


func crate_rect() -> Rect2:
	var h := Vector2(Config.CRATE_HALF, Config.CRATE_HALF)
	return Rect2(crate_pos - h, h * 2.0)


func box_rect() -> Rect2:
	var h := Vector2(Config.BOX_HALF, Config.BOX_HALF)
	return Rect2(MapDef.box_pos(map_id) - h, h * 2.0)


func set_player_enabled(i: int, on: bool) -> void:
	var p := players[i]
	if p.enabled == on:
		return
	p.enabled = on
	if on:
		_resolve_color(i)
	_reset_yoyo(p)
	p.alive = false
	p.respawn_t = 0.0


## Sets which figure a player shows (presentation only; never read by the simulation).
func set_skin(i: int, k: int) -> void:
	players[i].skin = posmod(k, Config.SKIN_COUNT)


## Sets a player's colour (presentation only). k wraps into range; when another ENABLED player has it, the next free
## colour is taken instead (k+1, k+2 ... wrapping), so enabled players never share a colour.
func set_color(i: int, k: int) -> void:
	players[i].color = posmod(k, Config.COLOR_COUNT)
	_resolve_color(i)


func _resolve_color(i: int) -> void:
	var p := players[i]
	var pool: Array = mode.allowed_colors(i)
	var start := pool.find(p.color)
	if start < 0:   # the colour is not in this player's half (a team change): the next one of the half
		start = 0
		for k in pool.size():
			if pool[k] >= p.color:
				start = k
				break
	for step in pool.size():
		var c: int = pool[(start + step) % pool.size()]
		var taken := false
		for o in players:
			if o != p and o.enabled and o.color == c:
				taken = true
				break
		if not taken:
			p.color = c
			return


## Offline: player 0 gets colour k, every other slot the remaining colours in order (idempotent, all unique).
func assign_colors(k: int) -> void:
	var mine := posmod(k, Config.COLOR_COUNT)
	if mode.is_team_mode():
		for p in players:
			p.color = -1   # nobody holds a colour while they are handed out
		players[0].color = mine
		for i in players.size():
			if i > 0:
				players[i].color = mode.allowed_colors(i)[0]
			_resolve_color(i)
		return
	players[0].color = mine
	var c := 0
	for i in range(1, players.size()):
		if c == mine:
			c += 1
		players[i].color = c % Config.COLOR_COUNT
		c += 1


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


## True when a match can start with the players enabled right now: free for all needs two, Teams needs the same
## number (at least one) on each team.
func can_start() -> bool:
	var n := 0
	var per_team := [0, 0]
	for i in players.size():
		if players[i].enabled:
			n += 1
			if mode.is_team_mode():
				per_team[mode.team_of(i)] += 1
	if mode.is_team_mode():
		return per_team[0] >= 1 and per_team[0] == per_team[1]
	return n >= 2


## Teams: slots `i` and `j` on different teams exchange their teams (a player and a bot, or an empty seat), so the
## sizes of the teams stay as they are. The two exchange colours, so each colour lands in its new half. False when not Teams, out of range
## or on the same team.
func swap_team(i: int, j: int) -> bool:
	if not mode.is_team_mode() or i == j or i < 0 or j < 0 or i >= players.size() or j >= players.size():
		return false
	var t: Array = mode.team
	if t[i] == t[j]:
		return false
	var tmp: int = t[i]
	t[i] = t[j]
	t[j] = tmp
	var c: int = players[i].color   # the colours change places: each lands in its new half, still unique
	players[i].color = players[j].color
	players[j].color = c
	_resolve_color(i)
	_resolve_color(j)
	return true


## Starts a match for the players enabled right now (`can_start`). A target that is not offered
## becomes the default. Also the rematch: points are zeroed.
func start_match(target: int) -> bool:
	if not can_start():
		return false
	mode.target = target if MatchMode.TARGETS.has(target) else MatchMode.DEFAULT_TARGET
	for i in players.size():
		mode.roster[i] = players[i].enabled
		mode.points[i] = 0
		mode.coins[i] = 0
		mode.earned[i] = 0
		mode.owned[i] = {}
		mode.offers[i] = []
		mode.locked[i] = []
		mode.shop_ready[i] = false
		mode.shop_seq[i] = 0
		apply_mods(i, {})
	mode.round = 1
	mode.map_bag = []
	mode.map_bag_i = 0
	mode.last_scorer = -1
	mode.winner = -1
	_start_round()
	return true


## The spawn point for the next starting player and its index added to `given`: the first one is drawn with the
## sim's rng, every further one is the free point farthest from all points already given (ties: lowest index), so
## players start as far apart as the map allows.
func _next_spawn(spawns: Array, given: Array[int]) -> int:
	var pick := 0
	if given.is_empty():
		pick = rng.randi_range(0, spawns.size() - 1)
	else:
		var best_d := -1.0
		for k in spawns.size():
			if given.has(k):
				continue
			var d := INF
			for g in given:
				d = minf(d, (spawns[k] as Vector2).distance_to(spawns[g]))
			if d > best_d + 1e-9:
				best_d = d
				pick = k
	given.append(pick)
	return pick


## Fresh arena for the next round: roster players alive on spread-out spawn points, everybody else out.
func _start_round() -> void:
	if cfg.map == Config.MAP_ROTATE:
		var next_map := _next_rotation_map()
		if next_map != map_id:
			set_map(next_map)
	wires.clear()
	shards.clear()
	crate_pos = MapDef.crate_start(map_id)
	prev_crate_pos = crate_pos
	box_active = true
	box_timer = 0.0
	train_s = 0.0
	prev_train_s = 0.0
	_reset_map_state()
	mode.zone_t = 0.0
	mode.zone_spot = rng.randi_range(0, MapDef.zone_spots(map_id).size() - 1)
	mode.begin_round_coins()
	var spawns: Array = MapDef.spawns(map_id)
	var given: Array[int] = []   # indices of the spawn points handed out so far
	var centre := Config.ARENA_SIZE * 0.5
	for i in players.size():
		var p := players[i]
		if not (mode.roster[i] and p.enabled):
			p.alive = false
			p.respawn_t = 0.0
			_reset_yoyo(p)
			continue
		var at: Vector2 = spawns[_next_spawn(spawns, given)]
		p.alive = true
		p.zone_t = 0.0
		p.air_t = 0.0
		p.pos = at
		p.prev_pos = at
		_reset_yoyo(p)
		p.stun_t = 0.0
		p.facing = (centre - at).normalized()
		p.aim_dir = p.facing
		p.dash_cd = 0.0
		p.dash_charges = dash_max(p)
	mode.phase = MatchMode.Phase.COUNTDOWN
	mode.phase_t = 0.0
	events.append({"type": "round_start", "round": mode.round})


func _step_match(dt: float) -> void:
	var m := mode
	m.phase_t += dt
	match m.phase:
		MatchMode.Phase.COUNTDOWN:
			if m.phase_t >= MatchMode.COUNTDOWN_TIME:
				m.phase = MatchMode.Phase.PLAY
				m.phase_t = 0.0
		MatchMode.Phase.RESULT:
			if m.phase_t >= MatchMode.RESULT_TIME:
				_open_shop()
		MatchMode.Phase.SHOP:
			if m.phase_t >= Economy.SHOP_TIME or _all_shopped():
				m.round += 1
				_start_round()


# ---------------------------------------------------------------- shop

func _open_shop() -> void:
	var m := mode
	m.phase = MatchMode.Phase.SHOP
	m.phase_t = 0.0
	for i in players.size():
		m.shop_ready[i] = false
		if m.roster[i]:
			_roll_offers(i)   # keeps the locked offers
		else:
			m.offers[i] = []
			m.locked[i] = []
	events.append({"type": "shop_open", "round": m.round})


## True when every roster player still in the game is done.
func _all_shopped() -> bool:
	for i in players.size():
		if mode.roster[i] and players[i].enabled and not mode.shop_ready[i]:
			return false
	return true


## Draws up to Economy.OFFERS different modifiers slot `i` can take, from the sim's rng (deterministic). Locked offers
## that can still be taken stay where they are; the rest is redrawn without repeating a kept one.
func _roll_offers(i: int) -> void:
	var m := mode
	var out: Array = []
	var lock: Array = []
	var used: Array[String] = []
	for k in Economy.OFFERS:
		var id := ""
		if m.is_locked(i, k) and k < m.offers[i].size():
			id = m.offers[i][k]
		var keep: bool = id != "" and m.can_take(i, id)
		out.append(id if keep else null)
		lock.append(keep)
		if keep:
			used.append(id)
	var pool: Array[String] = []
	for id in Mods.ORDER:
		if m.can_take(i, id) and not used.has(id):
			pool.append(id)
	for k in out.size():
		if out[k] == null:
			out[k] = pool.pop_at(rng.randi_range(0, pool.size() - 1)) if not pool.is_empty() else ""
	while not out.is_empty() and out[out.size() - 1] == "":
		out.pop_back()
	lock.resize(out.size())
	m.offers[i] = out
	m.locked[i] = lock


func _shop_open_for(i: int, seq: int) -> bool:
	return mode.phase == MatchMode.Phase.SHOP and i >= 0 and i < players.size() and mode.roster[i] \
			and players[i].enabled and not mode.shop_ready[i] and seq == mode.shop_seq[i]


## Buys offer `k` for slot `i`. `seq` must be the slot's current `mode.shop_seq` (a repeated request is refused).
func shop_buy(i: int, k: int, seq: int) -> bool:
	if not _shop_open_for(i, seq) or k < 0 or k >= mode.offers[i].size():
		return false
	var id: String = mode.offers[i][k]
	if id == "" or not mode.can_take(i, id) or mode.coins[i] < Mods.price(id):
		return false
	mode.coins[i] -= Mods.price(id)
	mode.owned[i][id] = int(mode.owned[i].get(id, 0)) + 1
	mode.offers[i][k] = ""
	if k < mode.locked[i].size():
		mode.locked[i][k] = false
	mode.shop_seq[i] += 1
	apply_mods(i, mode.levels_of(i))
	return true


## New offers for Economy.REROLL_PRICE coins.
func shop_reroll(i: int, seq: int) -> bool:
	if not _shop_open_for(i, seq) or mode.coins[i] < Economy.REROLL_PRICE:
		return false
	mode.coins[i] -= Economy.REROLL_PRICE
	mode.shop_seq[i] += 1
	_roll_offers(i)
	return true


## Sells modifier `id` of slot `i` with all its copies for half the price of each (rounded down); the build slot is free.
func shop_sell(i: int, id: String, seq: int) -> bool:
	if not _shop_open_for(i, seq) or not mode.owned[i].has(id):
		return false
	mode.coins[i] += mode.sell_refund(i, id)
	mode.owned[i].erase(id)
	mode.shop_seq[i] += 1
	apply_mods(i, mode.levels_of(i))
	return true


## Toggles the (free) lock of offer `k`: a locked offer survives rerolls and stays for the next shop.
func shop_lock(i: int, k: int, seq: int) -> bool:
	if not _shop_open_for(i, seq) or k < 0 or k >= mode.offers[i].size() or mode.offers[i][k] == "":
		return false
	var lock: Array = mode.locked[i]
	lock.resize(mode.offers[i].size())
	lock[k] = not mode.is_locked(i, k)
	mode.locked[i] = lock
	mode.shop_seq[i] += 1
	return true


## Slot `i` is done shopping (no more buying this shop). The shop closes early when everybody is.
func shop_done(i: int) -> bool:
	if mode.phase != MatchMode.Phase.SHOP or i < 0 or i >= players.size() or not mode.roster[i] or mode.shop_ready[i]:
		return false
	mode.shop_ready[i] = true
	mode.shop_seq[i] += 1
	return true


## After a PLAY tick: ends the round when the mode says so.
func _check_round_end() -> void:
	var m := mode
	if not m.round_over(self):
		return
	var scorer := m.round_scorer(self)
	m.award_coins(scorer)
	for i in m.roster.size():
		if m.roster[i] and m.scores(i, scorer):
			m.points[i] += 1
	m.last_scorer = scorer
	m.phase_t = 0.0
	events.append({"type": "round_end", "scorer": scorer, "round": m.round})
	var w := m.match_winner(self)
	if w >= 0:
		m.winner = w
		m.phase = MatchMode.Phase.MATCH_OVER
		events.append({"type": "match_over", "winner": w})
	else:
		m.phase = MatchMode.Phase.RESULT


func step(inputs: Array) -> void:
	events.clear()
	tick += 1
	var dt := 1.0 / Config.TICK_RATE
	prev_crate_pos = crate_pos
	prev_train_s = train_s
	for p in players:
		p.prev_pos = p.pos
		for h in p.heads:
			h.prev_pos = h.pos
	if mode.frozen():
		_step_match(dt)
		return
	for i in players.size():
		if players[i].enabled:
			_step_player(players[i], inputs[i], dt)
	_separate_players()
	_step_train(dt)
	_step_map(dt)
	if mode.phase == MatchMode.Phase.PLAY:
		mode.phase_t += dt   # time into the round (the frozen phases count theirs in _step_match)
	if mode.phase == MatchMode.Phase.PLAY and mode.uses_zone():
		_step_zone(dt)
	_collide_heads()
	_step_shards(dt)
	_step_wires(dt)
	_check_kills()
	_step_box(dt)
	if mode.phase == MatchMode.Phase.PLAY:
		mode.step(self, dt)
		_check_round_end()


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


func dash_distance_of(_p: SimPlayer) -> float:
	return cfg.dash_distance


## Extra Dash level 3: the dash passes through the blocks, the crate and the box (not the outer walls).
func dash_phases(p: SimPlayer) -> bool:
	return mv(p, "extradash", "phase", 0.0) > 0.0


func heads_wanted(p: SimPlayer) -> int:
	return int(mv(p, "twin", "heads", 1.0))


## True when both modifiers of synergy `key` are on for this player.
func syn(p: SimPlayer, key: String) -> bool:
	return Mods.syn_active(key, p.mods)


## Synergy number (0 while the synergy is off).
func syn_n(p: SimPlayer, key: String, name: String) -> float:
	return Mods.syn_n(key, name, p.mods)


## Size factor of the head when a synergy lets other things grow with it (Big Chunk), else 1.
func bighead_factor(p: SimPlayer, key: String) -> float:
	return mv(p, "bighead", "radius_mult", 1.0) if syn(p, key) else 1.0


## Explosion radius of this player's explosions (Big Chunk + Warhead makes them bigger).
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
	return base * (1.0 + mv(p, "pierce", "range_pct", 0.0) / 100.0) * (1.0 + mv(p, "steer", "range_pct", 0.0) / 100.0)


## Landing distance of the current charge, shortened by walls (for the aim line).
func aim_range(p: SimPlayer) -> float:
	var full := charge_range(p)
	var end := _sweep_head(p.pos, p.aim_dir * full, head_r(p), false, _flight_pass(p))
	return (end - p.pos).length()


## Preview of the flight of the current charge (for the aim line): points from the player to where it ends.
## Always a straight line (Steered Throw bends the flight only after the throw).
func aim_path(p: SimPlayer) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(p.pos)
	if map_id == MapDef.Id.MAGNETS:
		_magnet_aim_path(p, pts)
	else:
		pts.append(p.pos + p.aim_dir * aim_range(p))
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
		p.held_prev = inp.aim_held
		if mode.phase != MatchMode.Phase.OFF:
			return   # in a match the dead stay out until the next round
		p.respawn_t -= dt
		if p.respawn_t <= 0.0:
			_respawn(p)
		return
	if p.air_t > 0.0:
		p.held_prev = inp.aim_held
		_step_air(p, dt)   # Bounce House: in the air nothing is steered
		return

	p.last_move = inp.move
	var held := inp.aim_held
	var pressed := held and not p.held_prev
	var released := (not held) and p.held_prev
	p.held_prev = held

	_step_dash_charges(p, dt)
	var steer := _steer_stick(p, inp)
	for h in p.heads:
		if h.state == HS.FLIGHT:
			_step_flight(p, h, dt, steer)
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
				if steer != Vector2.ZERO and mv(p, "steer", "tk", 0.0) > 0.0:
					_step_telekinesis(p, h, steer, dt)
				_apply_out_variant(p, h, delta)
		_pickup_touched_heads(p)
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
	var phase := false
	if p.dash_t > 0.0:
		var slice := minf(dt, p.dash_t)
		delta = p.dash_dir * (dash_distance_of(p) / cfg.dash_duration) * slice
		p.dash_t -= dt
		phase = dash_phases(p)
	else:
		var speed := cfg.player_speed
		if p.charging:
			speed *= cfg.charge_speed_mult
		speed *= mode.speed_mult(p.id)
		delta = mvec * speed * dt
	_slide_player(p, delta, phase)
	if phase and p.dash_t <= 0.0:
		_dash_exit(p)


## A phasing dash that ends inside a block, the crate or the box continues in its direction until the player is
## free. If an outer wall is in the way, it tries the opposite direction from where the dash ended; if that fails
## too, the normal push-out decides.
func _dash_exit(p: SimPlayer) -> void:
	var r := cfg.player_radius
	var start := p.pos
	for dir in [p.dash_dir, -p.dash_dir]:
		p.pos = start
		for _i in Mods.DASH_EXIT_MAX_STEPS:
			if not _inside_obstacle(p.pos, r):
				return
			var nxt: Vector2 = p.pos + dir * Mods.DASH_EXIT_STEP
			p.pos = _push_statics(nxt, r, wall_count)
			if (p.pos - nxt).length_squared() > 1e-10:
				break  # reached an outer wall
	p.pos = _collide_player(start, r)


func _inside_obstacle(pos: Vector2, r: float) -> bool:
	for k in range(wall_count, statics.size()):
		if Collide.push_out_rect(pos, r, statics[k]) != Vector2.ZERO:
			return true
	if box_active and Collide.push_out_rect(pos, r, box_rect()) != Vector2.ZERO:
		return true
	return Collide.push_out_rect(pos, r, crate_rect()) != Vector2.ZERO


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


func _slide_player(p: SimPlayer, delta: Vector2, phase := false) -> void:
	var r := cfg.player_radius
	var n := maxi(1, ceili(delta.length() / (r * Config.SUBSTEP_FACTOR)))
	var sv := delta / float(n)
	var pos := p.pos
	for _i in n:
		pos = _push_statics(pos + sv, r, wall_count) if phase else _collide_player(pos + sv, r)
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


func _phasing(p: SimPlayer) -> bool:
	return p.dash_t > 0.0 and dash_phases(p)


func _separate_players() -> void:
	var r := cfg.player_radius
	for i in players.size():
		var a := players[i]
		if not _hittable(a):
			continue
		for j in range(i + 1, players.size()):
			var b := players[j]
			if not _hittable(b):
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= 2.0 * r:
				continue
			var n := d / dist if dist > 0.0001 else Vector2.RIGHT
			var push := n * (2.0 * r - dist) * Config.PLAYER_SEPARATION_SHARE
			a.pos = _push_statics(a.pos - push, r, wall_count) if _phasing(a) else _collide_player(a.pos - push, r)
			b.pos = _push_statics(b.pos + push, r, wall_count) if _phasing(b) else _collide_player(b.pos + push, r)


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
		# Twin III: an undeflected press that reaches the tap threshold pulls to the lying yo-yo.
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
	h.turning = false
	h.meet_on = false
	h.pos = p.pos
	h.prev_pos = p.pos
	p.facing = p.aim_dir


## A press while no yo-yo is in hand: a short tap retracts, a hold pulls once all have landed.
## A press that starts during flight / retract keeps counting, so it is not lost at the landing.
func _step_out_input(p: SimPlayer, inp: SimInput, pressed: bool, held: bool, dt: float) -> void:
	if pressed:
		p.press_active = true
		p.press_t = 0.0
		p.press_steered = false
	if _steer_stick(p, inp) != Vector2.ZERO:
		p.press_steered = true  # Steered Throw: a press that steers neither taps nor pulls
	if not p.press_active:
		return
	if held:
		p.press_t += dt
		if p.press_t >= cfg.tap_threshold and p.count_state(HS.OUT) == p.heads.size() and not p.press_steered:
			_begin_pull(p, _pick_pull_target(p, inp.move))
	else:
		p.press_active = false
		if p.press_t < cfg.tap_threshold and not p.press_steered:
			_retract_all(p)


func _retract_all(p: SimPlayer) -> void:
	# Twin II (Crossfire): with both heads out they first meet in the middle.
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


## Twin III: one head in hand and the others lying still, so a plain hold can pull to a lying one.
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
	# Tripwire: the string stays behind as a wire when a pull starts, too.
	if lv(p, "tripwire") > 0 and target < p.heads.size():
		_lay_wire(p, p.heads[target])


func _step_pull(p: SimPlayer, held: bool, dt: float) -> void:
	var h: SimHead = p.heads[p.pull_target] if p.pull_target < p.heads.size() else null
	if not held or h == null or h.state != HS.OUT:
		p.pulling = false
		p.press_active = false
		return
	var catch_dist := _catch_dist(p)
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


## How close the player must be to a lying head to catch it (pull arrival and walking over it).
func _catch_dist(p: SimPlayer) -> float:
	return cfg.player_radius + head_r(p) + Config.CATCH_MARGIN


## Walking over your own lying head picks it up. Not a retract: no shards, wire or blast.
func _pickup_touched_heads(p: SimPlayer) -> void:
	var catch_dist := _catch_dist(p)
	var picked := false
	for i in p.heads.size():
		var h := p.heads[i]
		if p.pulling and i == p.pull_target:
			continue  # _step_pull catches its target itself (Rubber Band fling)
		if h.state == HS.OUT and p.pos.distance_to(h.pos) <= catch_dist:
			events.append({"type": "pickup", "pos": h.pos, "player": p.id})
			_to_hand(p, h)
			picked = true
	# Like a retract arrival: once nothing is out any more, a still-held press must not carry on.
	if picked and not p.any_out():
		p.press_active = false


func _to_hand(p: SimPlayer, h: SimHead) -> void:
	h.state = HS.HAND
	h.pos = p.pos
	h.pins.clear()
	h.meet_on = false
	h.turning = false


## Rubber Band: the player is flung onward after catching the head. Stopped by walls.
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
	h.meet_on = false
	h.turning = false


## The head lies still. A queued tap (made during flight) retracts it right away.
func _land(p: SimPlayer, h: SimHead) -> void:
	var was_flight := h.state == HS.FLIGHT
	_set_out(h)
	if was_flight:
		var l := lv(p, "warhead")
		if l > 0:
			_explode(p, h.pos, blast_radius(p, Mods.n("warhead", "radius", l)))
			if not p.alive:
				return  # blew itself up: the yo-yo is reset, nothing more to do
	if h.queued_retract:
		h.queued_retract = false
		p.press_active = false
		_start_retract(p, h)


## `steer`: the aim stick while Steered Throw may use it (zero = no steering this tick, see `_steer_stick`).
func _step_flight(p: SimPlayer, h: SimHead, dt: float, steer := Vector2.ZERO) -> void:
	var r := head_r(p)
	var pass_level := _flight_pass(p)
	var bounce_l := lv(p, "bounce")
	var max_bounces := int(Mods.n("bounce", "bounces", bounce_l)) if bounce_l > 0 else 0
	var move := minf(cfg.flight_speed * h.speed_mult * dt, h.flight_dist - h.flown)
	var n := maxi(1, ceili(move / (r * Config.SUBSTEP_FACTOR)))
	var step := move / float(n)
	# Steered Throw: the flight direction turns towards the stick; the turn of this tick is shared by the sub-steps.
	var turn_max := 0.0
	if steer != Vector2.ZERO:
		turn_max = deg_to_rad(mv(p, "steer", "turn_rate", 0.0)) * dt / float(n)
	var landed := false
	for _i in n:
		var before_dir := h.throw_dir
		if turn_max > 0.0:
			h.throw_dir = h.throw_dir.rotated(clampf(h.throw_dir.angle_to(steer), -turn_max, turn_max))
		if map_id == MapDef.Id.MAGNETS:
			h.throw_dir = MapDef.magnet_bend(h.pos, h.throw_dir, map_t, dt / float(n))
		var bent := absf(before_dir.angle_to(h.throw_dir)) > Mods.STEER_MIN_TURN
		var from := h.pos
		var start := from + h.throw_dir * step
		var res := _resolve_head(start, r, true, pass_level)
		h.flown += step
		var moved := res.distance_to(h.pos)
		h.pos = res
		if map_id == MapDef.Id.PIGGY:
			_pig_touch(p, h, r)
		if (res - start).length_squared() > 1e-10:
			if h.bounces < max_bounces:
				var nrm := (res - start).normalized()
				if h.throw_dir.dot(nrm) < 0.0:
					h.throw_dir = (h.throw_dir - 2.0 * h.throw_dir.dot(nrm) * nrm).normalized()
				h.bounces += 1
				h.pins.append(res)  # the string now bends here
				h.pin_acc = 0.0
				h.turning = false
				h.flight_dist += Mods.n("bounce", "bonus_dist", bounce_l)
				if h.bounces == 1:
					h.speed_mult = 1.0 + Mods.n("bounce", "speed_pct", bounce_l) / 100.0
				events.append({"type": "ricochet", "pos": res})
			else:
				landed = true
				break
		else:
			_record_bend(h, h.pins[h.pins.size() - 1] if not h.pins.is_empty() else p.pos, from, res, bent, moved)
	if landed or h.flown >= h.flight_dist - 0.00001:
		if not h.pins.is_empty() and h.pins[h.pins.size() - 1].distance_to(h.pos) < Mods.PIN_REACH:
			h.pins.resize(h.pins.size() - 1)  # a pin right at the head adds nothing
		if pass_level >= 1:
			_pierce_exit(h, r, pass_level)
		_land(p, h)


## The string lies on the path of a head that changes direction (Steered Throw): a pin at the corner where a bend begins
## (`from` = where the step began; not when it is within reach of the previous string point `anchor`), then one
## every PATH_PIN_SPACING metres flown while it keeps bending. Capped at MAX_PATH_PINS per head.
func _record_bend(h: SimHead, anchor: Vector2, from: Vector2, to: Vector2, bent: bool, moved: float) -> void:
	if not bent:
		h.turning = false
		return
	if h.pins.size() >= Mods.MAX_PATH_PINS:
		return
	if not h.turning:
		h.turning = true
		h.pin_acc = 0.0
		if from.distance_to(anchor) > Mods.PIN_REACH:
			h.pins.append(from)
	h.pin_acc += moved
	if h.pin_acc >= Mods.PATH_PIN_SPACING:
		h.pins.append(to)
		h.pin_acc = 0.0


## The aim stick as a steering order for the yo-yo (Steered Throw), or zero when it cannot be used right now: no
## modifier, dead or stumbling, a head in hand or a throw being charged (Twin with a head in hand: the stick
## charges the next throw instead), a pull running, or the stick not deflected.
func _steer_stick(p: SimPlayer, inp: SimInput) -> Vector2:
	if lv(p, "steer") <= 0 or not p.alive or p.stun_t > 0.0 or p.charging or p.pulling or p.hand_index() >= 0:
		return Vector2.ZERO
	if not inp.aim_held or inp.aim.length() < cfg.aim_deadzone:
		return Vector2.ZERO
	return inp.aim.limit_length(1.0)


## Telekinesis (Steered Throw III): a lying head follows the deflected stick at tk_speed (times the stick length). It is
## stopped by walls, blocks and the crate like a flying head (pierce lifts what it lifts for the flight), may not
## stretch the string beyond its limit, and is lethal on the way like any head that is out. The string follows its
## path (pins, see `_record_bend`); moving back onto the last pin winds that pin up again.
func _step_telekinesis(p: SimPlayer, h: SimHead, stick: Vector2, dt: float) -> void:
	var r := head_r(p)
	var pass_level := _flight_pass(p)
	var dist := mv(p, "steer", "tk_speed", 0.0) * stick.length() * dt
	var dir := stick.normalized()
	var n := maxi(1, ceili(dist / (r * Config.SUBSTEP_FACTOR)))
	var step := dist / float(n)
	h.limit = minf(h.limit, maxf(cfg.string_length, path_length(string_path(p, h))))
	var before_dir := h.throw_dir
	h.throw_dir = dir
	var bent := absf(before_dir.angle_to(dir)) > Mods.STEER_MIN_TURN
	for _i in n:
		var from := h.pos
		var res := _resolve_head(from + dir * step, r, true, pass_level)
		# Never more string than the limit: stay on the circle around the last pin (or the player).
		var anchor := h.pins[h.pins.size() - 1] if not h.pins.is_empty() else p.pos
		# Moving straight back along the last segment winds the string up: that is no bend.
		var winding := anchor.distance_to(from) > 0.0001 and dir.dot((anchor - from).normalized()) > 0.9995
		var rest := path_length(string_path(p, h)) - anchor.distance_to(h.pos)
		var room := maxf(h.limit - rest, 0.0)
		if anchor.distance_to(res) > room:
			res = _resolve_head(anchor + (res - anchor).normalized() * room, r, true, pass_level)
		var moved := res.distance_to(h.pos)
		h.pos = res
		if not h.pins.is_empty() and h.pins[h.pins.size() - 1].distance_to(res) <= Mods.PIN_REACH \
				and h.pins[h.pins.size() - 1].distance_to(res) < h.pins[h.pins.size() - 1].distance_to(from):
			h.pins.resize(h.pins.size() - 1)  # back onto the last pin: the string winds up
			h.turning = false
		else:
			_record_bend(h, anchor, from, res, bent and not winding, moved)


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


## `meet` (not INF): Crossfire, fly to that point first and return from there.
func _start_retract(p: SimPlayer, h: SimHead, meet := Vector2.INF) -> void:
	h.state = HS.RETRACT
	h.limit = 1e9
	h.meet_on = false
	h.turning = false
	# --- Tripwire ---
	if lv(p, "tripwire") > 0:
		_lay_wire(p, h)
	# --- Shards ---
	var l := lv(p, "shards")
	if l > 0:
		_spawn_shards(p, h, l)
	# --- Warhead: second explosion where the retract starts ---
	l = lv(p, "warhead")
	if l > 0 and Mods.n("warhead", "retract_blast", l) > 0.0:
		_explode(p, h.pos, blast_radius(p, Mods.n("warhead", "radius", l)))
		if not p.alive:
			return  # blew itself up: the yo-yo is reset, no retract to set up
	if meet != Vector2.INF:
		h.pins.clear()  # the way to the meeting point is a straight line
		h.meet_on = true
		h.meet = meet
		return


func _step_retract(p: SimPlayer, h: SimHead, dt: float) -> void:
	var r := head_r(p)
	var pass_level := _retract_pass(p)
	var step := cfg.retract_speed * mv(p, "twin", "retract_mult", 1.0) * dt
	if h.meet_on:
		_step_meet(p, h, r, pass_level, step)
		return
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


## Crossfire: fly to the meeting point; from there the head returns straight to the player.
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
			_head_hit = true
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
	events.append({"type": "box_break", "pos": MapDef.box_pos(map_id)})


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
		if _hittable(v) and pos.distance_to(v.pos) - cfg.player_radius < radius:
			if v == owner:
				if mode.own_blast_kills():
					_kill(v, null, "self")  # own explosions hurt the owner: a death, no kill for anybody
			else:
				_hit(v, owner)


## Lays the current string of head `h` on the ground as a wire (Tripwire).
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
				if v.id == w.owner_id or not _hittable(v) or not mode.harms(w.owner_id, v.id):
					continue
				if not w.lethal and v.stun_t > 0.0:
					continue
				var nearest := closest_on_path(v.pos, w.pts)
				if nearest.distance_to(v.pos) < reach:
					if w.lethal:
						_hit(v, players[w.owner_id])
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
				_explode(players[s.owner_id], s.pos, s.blast)  # Shards + Warhead
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
		if v == owner or not _hittable(v):
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(v.pos, s.prev_pos, res)
		if nearest.distance_to(v.pos) < s.radius + cfg.player_radius:
			_hit(v, owner)
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
			if not (b.enabled and b.alive and b.any_out()) or not (mode.harms(i, j) or mode.harms(j, i)):
				continue   # teammates' yo-yos pass through each other
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
				if v == a or not _hittable(v):
					continue
				# Swept check along this tick's head path, so a fast head cannot skip over a player.
				var nearest := Geometry2D.get_closest_point_to_segment(v.pos, h.prev_pos, h.pos)
				if nearest.distance_to(v.pos) < reach:
					_hit(v, a)
		var br := body_lethal_r(a)
		if br > 0.0 and a.alive:
			for v in players:
				if v == a or not _hittable(v):
					continue
				var nearest := Geometry2D.get_closest_point_to_segment(v.pos, a.prev_pos, a.pos)
				if nearest.distance_to(v.pos) < br + pr + Mods.BODY_LETHAL_MARGIN:
					_hit(v, a)


## Every harm done by an attacker (yo-yo head, body, blast, shard, wire, stomp) goes through here, so the mode can
## spare players (Teams: no friendly fire). Kills of the train, the zone, lava and an own blast do not.
func _hit(victim: SimPlayer, attacker: SimPlayer) -> void:
	if mode.on_hit(self, attacker.id, victim.id):
		_kill(victim, attacker)


## `killer` null = a death for the victim, a kill for nobody; `cause` then says why ("train", "self" or "zone").
func _kill(victim: SimPlayer, killer: SimPlayer, cause := "train") -> void:
	victim.alive = false
	victim.zone_t = 0.0
	victim.air_t = 0.0
	victim.deaths += 1
	if killer != null:
		killer.kills += 1
		if mode.phase == MatchMode.Phase.PLAY:
			mode.note_kill(victim.id, killer.id)
	victim.respawn_t = cfg.respawn_time
	_reset_yoyo(victim)
	var e := {"type": "kill", "pos": victim.pos, "victim": victim.id, "killer": -1 if killer == null else killer.id}
	if killer == null:
		e["cause"] = cause
	events.append(e)


## Pushes a circle out of every train car (the cars are solid for yo-yo heads, like the crate). Unchanged when
## the train is off. Identical centres are pushed along the car's travel direction.
func _push_train(pos: Vector2, r: float) -> Vector2:
	if not train_on():
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


## True while a shrinking zone exists: in a match (any phase but OFF). Free play has none.
func zone_active() -> bool:
	return mode.phase != MatchMode.Phase.OFF and mode.uses_zone()


## The safe rectangle now: the whole arena in free play and for the first ZONE_FULL_TIME seconds of a round, then
## every edge moves linearly to the round's final spot over ZONE_SHRINK_TIME seconds and stays there.
func zone_rect() -> Rect2:
	var full := Rect2(Vector2.ZERO, Config.ARENA_SIZE)
	if not zone_active():
		return full
	var k := clampf((mode.zone_t - MatchMode.ZONE_FULL_TIME) / MatchMode.ZONE_SHRINK_TIME, 0.0, 1.0)
	var spots := MapDef.zone_spots(map_id)
	var f: Rect2 = spots[clampi(mode.zone_spot, 0, spots.size() - 1)]
	if k >= 1.0:
		return f
	var a := full.position.lerp(f.position, k)
	var b := full.end.lerp(f.end, k)
	return Rect2(a, b - a)


func _outside_zone(pos: Vector2, z: Rect2) -> bool:
	return pos.x < z.position.x or pos.y < z.position.y or pos.x > z.end.x or pos.y > z.end.y


## PLAY only: advances the zone clock and every living player's personal timer; the timer filling up is a death
## for the victim and a kill for nobody (cause "zone").
func _step_zone(dt: float) -> void:
	mode.zone_t += dt
	var z := zone_rect()
	for p in players:
		if not (p.enabled and p.alive):
			continue
		if _outside_zone(p.pos, z):
			p.zone_t += dt
			if p.zone_t >= MatchMode.ZONE_DEATH_TIME:
				_kill(p, null, "zone")
		else:
			p.zone_t = maxf(0.0, p.zone_t - dt)


## Moves the train along its loop. The cars shove the crate aside, run living players over and are solid for
## yo-yo heads (a flying head stops or bounces, a retracting one lies down, a lying one is shoved aside; the
## shove can kill). Strings, wires and shards pass over them. Speed 0 = no train at all.
func _step_train(dt: float) -> void:
	if not train_on():
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
			if _hittable(v) and v.pos.distance_to(c) < reach:
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
	if not train_on():
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
		h.pins.clear()
		h.meet_on = false
		h.turning = false
	p.charging = false
	p.pulling = false
	p.charge_t = 0.0
	p.press_active = false
	p.press_t = 0.0
	p.dash_t = 0.0
	p.stun_t = 0.0
	p.fling_left = 0.0


func _respawn(p: SimPlayer) -> void:
	var spawns := MapDef.spawns(map_id)
	var best: Vector2 = spawns[0]
	var best_score := -1e9
	for s: Vector2 in spawns:
		var nearest := 1000.0
		for o in players:
			if o == p or not (o.enabled and o.alive):
				continue
			nearest = minf(nearest, s.distance_to(o.pos))
			for h in o.heads:
				if h.lethal():
					nearest = minf(nearest, s.distance_to(h.pos))
		var score := nearest + rng.randf() * Config.SPAWN_NOISE
		if spawn_unsafe(s):
			score -= 1000.0
		if score > best_score:
			best_score = score
			best = s
	p.alive = true
	p.zone_t = 0.0
	p.air_t = 0.0
	p.pos = best
	p.prev_pos = best
	_reset_yoyo(p)
	p.facing = (Config.ARENA_SIZE * 0.5 - best).normalized()
	p.aim_dir = p.facing
	p.dash_cd = 0.0
	p.dash_charges = dash_max(p)
	events.append({"type": "respawn", "pos": best, "player": p.id})


# ---------------------------------------------------------------- maps
# Layout data and all numbers: MapDef. Design: docs/maps.md. Map 0 is the train above.

## Outer walls first, then the obstacles of the current map.
func _build_statics() -> void:
	statics.clear()
	var a := Config.ARENA_SIZE
	var t := Config.WALL_THICKNESS
	statics.append(Rect2(-t, -t, a.x + 2.0 * t, t))
	statics.append(Rect2(-t, a.y, a.x + 2.0 * t, t))
	statics.append(Rect2(-t, 0.0, t, a.y))
	statics.append(Rect2(a.x, 0.0, t, a.y))
	wall_count = statics.size()
	for o: Rect2 in MapDef.obstacles(map_id):
		statics.append(o)
	_built_map = map_id


## Switches the running sim to another map: its layout, the chest and the present at their start, a fresh twist and
## every player on a spawn point with the yo-yo in hand. Scores and the match phase stay.
func set_map(id: int) -> void:
	map_id = MapDef.valid(id)
	_build_statics()
	wires.clear()
	shards.clear()
	crate_pos = MapDef.crate_start(map_id)
	prev_crate_pos = crate_pos
	box_active = true
	box_timer = 0.0
	train_s = 0.0
	prev_train_s = 0.0
	_reset_map_state()
	var spawns := MapDef.spawns(map_id)
	for i in players.size():
		var p := players[i]
		_reset_yoyo(p)
		p.pos = spawns[i % spawns.size()]
		p.prev_pos = p.pos
		for h in p.heads:
			h.pos = p.pos
			h.prev_pos = p.pos


## The next map of the rotation: every map once in a shuffled order (sim rng), then a new shuffle; the first map of a
## new shuffle is never the one just played.
func _next_rotation_map() -> int:
	var bag: Array = mode.map_bag
	if mode.map_bag_i >= bag.size():
		bag = []
		for m in Config.MAP_COUNT:
			bag.append(m)
		for k in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp: int = bag[k]
			bag[k] = bag[j]
			bag[j] = tmp
		if bag[0] == map_id and mode.round > 1:
			var t: int = bag[0]
			bag[0] = bag[1]
			bag[1] = t
		mode.map_bag = bag
		mode.map_bag_i = 0
	var id: int = bag[mode.map_bag_i]
	mode.map_bag_i += 1
	return id


func _reset_map_state() -> void:
	map_t = 0.0
	lava_cells = PackedInt32Array()
	lava_wave = 0
	pig_coins = 0
	pig_t = 0.0
	for p in players:
		p.air_t = 0.0


## The train only runs on its own map.
func train_on() -> bool:
	return map_id == MapDef.Id.TRAIN and cfg.train_speed > 0.0


## A player the world can touch right now: in the game, alive and not in the air (Bounce House).
func _hittable(v: SimPlayer) -> bool:
	return v.enabled and v.alive and v.air_t <= 0.0


## True when a player appearing at `pos` would die at once (the train) or stand on a marked mat.
func spawn_unsafe(pos: Vector2) -> bool:
	if train_unsafe(pos):
		return true
	return map_id == MapDef.Id.LAVA and lava_cells.has(MapDef.lava_cell(pos))


## The twist of the current map, once per played tick (never while the world is frozen).
func _step_map(dt: float) -> void:
	if map_id == MapDef.Id.TRAIN:
		return
	map_t += dt
	match map_id:
		MapDef.Id.BELTS:
			_step_belts(dt)
		MapDef.Id.LAVA:
			_step_lava(dt)
		MapDef.Id.BOUNCE:
			_step_pads()
		MapDef.Id.MAGNETS:
			_step_magnets(dt)
		MapDef.Id.PIGGY:
			_step_pig(dt)


## Assembly Line: the belt carries what stands or lies on it (players, lying yo-yos, the chest) at its speed.
## Walls, blocks and the others stop them as always; a carried yo-yo stays deadly.
func _step_belts(dt: float) -> void:
	if MapDef.belt_factor(map_t) == 0.0:
		return
	var r := cfg.player_radius
	for p in players:
		if not _hittable(p):
			continue
		var v := MapDef.belt_velocity(p.pos, map_t)
		if v != Vector2.ZERO:
			p.pos = _push_statics(p.pos + v * dt, r, wall_count) if _phasing(p) else _collide_player(p.pos + v * dt, r)
		var hr := head_r(p)
		for h in p.heads:
			if h.state != HS.OUT:
				continue
			var hv := MapDef.belt_velocity(h.pos, map_t)
			if hv != Vector2.ZERO:
				h.pos = _sweep_head(h.pos, hv * dt, hr, false)
	var cv := MapDef.belt_velocity(crate_pos, map_t)
	if cv != Vector2.ZERO:
		crate_pos = _resolve_crate(crate_pos + cv * dt)


## Lava Mats: when the blinking starts a new set of mats is drawn; while they burn, a player whose centre is on
## one dies (a death for the victim, a kill for nobody, cause "lava"); afterwards the floor is clear again.
func _step_lava(dt: float) -> void:
	var now := MapDef.lava_stage(map_t)
	if now == MapDef.Lava.CALM:
		if not lava_cells.is_empty():
			lava_cells = PackedInt32Array()
		return
	if now == MapDef.Lava.WARN:
		if MapDef.lava_stage(map_t - dt) == MapDef.Lava.CALM:
			_draw_lava()
		return
	if lava_cells.is_empty():
		return
	for p in players:
		if _hittable(p) and lava_cells.has(MapDef.lava_cell(p.pos)):
			_kill(p, null, "lava")


## Draws the mats of the next wave from the sim's rng: one mat each of that many different pairs (a pair = the two
## mats 2k and 2k + 1, left and right neighbours), so the other mat of every pair stays safe.
func _draw_lava() -> void:
	var pairs: Array[int] = []
	for k in MapDef.LAVA_COLS * MapDef.LAVA_ROWS / 2:
		pairs.append(k)
	var n := mini(MapDef.lava_count(lava_wave), pairs.size())
	lava_wave += 1
	var cells := PackedInt32Array()
	for i in n:
		var j := rng.randi_range(i, pairs.size() - 1)
		var tmp := pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = tmp
		cells.append(pairs[i] * 2 + rng.randi_range(0, 1))
	cells.sort()
	lava_cells = cells
	events.append({"type": "lava_warn", "count": n})


## Bounce House: a player whose centre is on a trampoline is flung to its landing spot.
func _step_pads() -> void:
	for p in players:
		if not _hittable(p):
			continue
		var k := MapDef.pad_at(p.pos)
		if k < 0:
			continue
		_reset_yoyo(p)   # the yo-yos snap back into the hand
		p.air_t = MapDef.AIR_TIME
		p.air_from = p.pos
		p.air_to = MapDef.PADS[k][1]
		p.facing = (p.air_to - p.air_from).normalized()
		p.aim_dir = p.facing
		events.append({"type": "launch", "pos": p.pos, "player": p.id, "pad": k})


## A player in the air: moves along the straight line to the landing spot (the arc is the view's business) and
## squashes whoever stands there on arrival (a kill with credit).
func _step_air(p: SimPlayer, dt: float) -> void:
	p.air_t = maxf(0.0, p.air_t - dt)
	if p.air_t > 0.0:
		p.pos = p.air_from.lerp(p.air_to, 1.0 - p.air_t / MapDef.AIR_TIME)
	else:
		p.pos = _collide_player(p.air_to, cfg.player_radius)
		events.append({"type": "land", "pos": p.pos, "player": p.id})
		for v in players:
			if v != p and _hittable(v) and v.pos.distance_to(p.pos) < MapDef.STOMP_RADIUS:
				_hit(v, p)
	for h in p.heads:
		h.pos = p.pos


## Magnet Lab: lying yo-yos creep towards the pulling magnet and away from the pushing one (deadly on the way,
## stopped by everything solid). The bend of a flying yo-yo is in `_step_flight`.
func _step_magnets(dt: float) -> void:
	for p in players:
		if not (p.enabled and p.alive):
			continue
		var hr := head_r(p)
		for h in p.heads:
			if h.state != HS.OUT:
				continue
			var v := MapDef.magnet_drift(h.pos, map_t)
			if v != Vector2.ZERO:
				h.pos = _sweep_head(h.pos, v * dt, hr, false)


## The aim line on the Magnet Lab: the flight an unsteered throw would take in the magnets' fields as they are
## now, with the same steps as `_step_flight`, up to the first thing that stops it.
func _magnet_aim_path(p: SimPlayer, pts: PackedVector2Array) -> void:
	var r := head_r(p)
	var pass_level := _flight_pass(p)
	var dt := 1.0 / Config.TICK_RATE
	var left := charge_range(p)
	var pos := p.pos
	var dir := p.aim_dir
	while left > 0.00001:
		var move := minf(cfg.flight_speed * dt, left)
		var n := maxi(1, ceili(move / (r * Config.SUBSTEP_FACTOR)))
		var step := move / float(n)
		for _i in n:
			dir = MapDef.magnet_bend(pos, dir, map_t, dt / float(n))
			var start := pos + dir * step
			pos = _resolve_head(start, r, false, pass_level)
			if (pos - start).length_squared() > 1e-10:
				pts.append(pos)
				return
		left -= move
		pts.append(pos)


## Piggy Bank: a coin appears on the pig every PIG_FILL seconds, up to PIG_MAX.
func _step_pig(dt: float) -> void:
	if pig_coins >= MapDef.PIG_MAX:
		pig_t = 0.0
		return
	pig_t += dt
	if pig_t >= MapDef.PIG_FILL:
		pig_t -= MapDef.PIG_FILL
		pig_coins += 1
		events.append({"type": "pig_coin", "pos": MapDef.PIG_RECT.get_center(), "coins": pig_coins})


## A thrown (flying) yo-yo of `p` touching the pig takes all its coins. In a match they are the thrower's bonus
## of this round (paid with the round's coins); in free play it only rattles.
func _pig_touch(p: SimPlayer, h: SimHead, r: float) -> void:
	if pig_coins <= 0 or Collide.push_out_rect(h.pos, r + MapDef.PIG_TOUCH, MapDef.PIG_RECT) == Vector2.ZERO:
		return
	var n := pig_coins
	pig_coins = 0
	pig_t = 0.0
	if mode.phase == MatchMode.Phase.PLAY:
		mode.bonus[p.id] += n
	events.append({"type": "pig", "pos": h.pos, "player": p.id, "coins": n})
