extends SceneTree

var fails := 0
const Y := SimPlayer.Yo
## The right and bottom outer walls: checks next to them are written relative to these.
const RW := Config.ARENA_SIZE.x
const BW := Config.ARENA_SIZE.y

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  [" + info + "]" if info != "" else ""))
	if not ok:
		fails += 1

func mk(only: Array, walls_only := true) -> Sim:
	var cfg := Config.new()
	cfg.train_speed = 0.0 # the train has its own checks; the other tests want an empty track
	# Most checks hard-code distances for the old 8 m throw range / 9 m string; the defaults are checked in _range_tests.
	cfg.max_range = 8.0
	cfg.string_length = 9.0
	var s := Sim.new(cfg, 1)
	for i in 4:
		s.set_player_enabled(i, i in only)
	if walls_only:
		s.statics.resize(s.wall_count)
	s.crate_pos = Vector2(-50, -50) # far away unless the test needs it
	s.box_active = false
	s.box_timer = 9999.0
	for i in only:
		s.players[i].alive = true
	return s

func inp(move := Vector2.ZERO, aim := Vector2.ZERO, held := false, dash := false) -> SimInput:
	var i := SimInput.new()
	i.move = move; i.aim = aim; i.aim_held = held; i.dash = dash
	return i

# run n ticks; per-player input array given as Callable(tick)->Array of inputs (len 4)
func run(s: Sim, n: int, f: Callable) -> void:
	for t in n:
		s.step(f.call(t))

func idle4() -> Array:
	return [inp(), inp(), inp(), inp()]

func only0(i: SimInput) -> Array:
	return [i, inp(), inp(), inp()]

func place(s: Sim, i: int, pos: Vector2) -> void:
	var p := s.players[i]
	p.pos = pos; p.prev_pos = pos; p.head = pos; p.prev_head = pos

func throw0(s: Sim, dir: Vector2, charge_ticks: int) -> void:
	for t in charge_ticks:
		s.step(only0(inp(Vector2.ZERO, dir, true)))
	s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, false)))
	for t in 200:
		if s.players[0].ystate == Y.OUT: break
		s.step(idle4())

func _initialize() -> void:
	# 1 throw distance
	var s := mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	var p := s.players[0]
	check("full charge throws ~max range", p.ystate == Y.OUT and absf(p.head.x - 3.0 - s.cfg.max_range) < 0.2, "dist=%.2f" % (p.head.x - 3.0))
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 21)
	p = s.players[0]
	var expect := 2.5 + 0.5 * (s.cfg.max_range - 2.5)
	check("half charge throws ~half range", p.ystate == Y.OUT and absf(p.head.x - 3.0 - expect) < 0.6, "dist=%.2f expect=%.2f" % [p.head.x - 3.0, expect])
	# no second throw while OUT
	var before := p.head
	for t in 5: s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
	check("no new throw while OUT", p.ystate == Y.OUT and p.head == before)

	# 2 wall stop
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	s.statics.append(Rect2(8, 5, 1, 3))
	throw0(s, Vector2.RIGHT, 60)
	p = s.players[0]
	check("flight stops at wall", p.ystate == Y.OUT and absf(p.head.x - (8.0 - 0.35)) < 0.05, "x=%.3f" % p.head.x)

	# 3 tap retract
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	p = s.players[0]
	for t in 6: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))
	check("tap -> RETRACT", p.ystate == Y.RETRACT)
	for t in 60:
		s.step(idle4())
	check("retract ends READY at player", p.ystate == Y.READY and p.head.distance_to(p.pos) < 0.01)

	# 4 hold pull
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	p = s.players[0]
	for t in 20: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	check("hold -> PULL and player moving", p.ystate == Y.PULL and p.pos.x > 3.5, "x=%.2f" % p.pos.x)
	for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	check("pull reaches head -> READY", p.ystate == Y.READY and p.pos.x > 10.0, "x=%.2f" % p.pos.x)
	# release mid pull
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	p = s.players[0]
	for t in 20: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))
	var px := p.pos.x
	for t in 10: s.step(idle4())
	check("release mid-pull keeps OUT, player stops", p.ystate == Y.OUT and absf(p.pos.x - px) < 0.01 and p.pos.x < 10.0)
	# pull blocked by wall (never tunnel)
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	s.statics.append(Rect2(7, 4, 1, 5))
	p = s.players[0]
	for t in 90: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	check("pull blocked by wall", p.pos.x < 7.0 - 0.4, "x=%.2f" % p.pos.x)

	# 5 variants
	for v in 3:
		s = mk([0]); place(s, 0, Vector2(14, 6.3))
		s.cfg.out_variant = v
		throw0(s, Vector2.RIGHT, 60)
		p = s.players[0]
		var h0 := p.head.x
		var off0 := p.head.x - p.pos.x
		for t in 180: s.step(only0(inp(Vector2.LEFT)))
		var dist := p.pos.distance_to(p.head)
		match v:
			0: check("variant A: head dragged behind, string taut", p.head.x < h0 - 1.0 and absf(dist - 9.0) < 0.3, "head %.2f->%.2f dist=%.2f" % [h0, p.head.x, dist])
			1: check("variant B: head stays, player leashed", absf(p.head.x - h0) < 0.01 and dist <= 9.05 and p.pos.x < h0 - 4, "player x=%.2f dist=%.2f" % [p.pos.x, dist])
			2: check("variant C: head keeps offset", absf((p.head.x - p.pos.x) - off0) < 0.1 and p.head.x < h0 - 3, "off=%.2f/%.2f" % [p.head.x - p.pos.x, off0])
	# C stopped by wall
	s = mk([0]); place(s, 0, Vector2(14, 6.3)); s.cfg.out_variant = 2
	throw0(s, Vector2.RIGHT, 60)
	p = s.players[0]
	s.statics.append(Rect2(23.5, 0, 1, BW))
	for t in 120: s.step(only0(inp(Vector2.RIGHT)))
	check("variant C: head stopped by wall", p.head.x < 23.5 - 0.3, "head x=%.2f player x=%.2f" % [p.head.x, p.pos.x])

	# 6 kill + respawn
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(8, 6.3))
	for t in 25: s.step([inp(Vector2.ZERO, Vector2.RIGHT, true), inp(), inp(), inp()])
	s.step([inp(), inp(), inp(), inp()])
	var killed := false
	for t in 20:
		s.step(idle4())
		for e in s.events: if e["type"] == "kill": killed = true
	check("lethal head kills other player", killed and not s.players[1].alive and s.players[0].kills == 1 and s.players[1].deaths == 1)
	check("killer stays alive (own head harmless)", s.players[0].alive)
	for t in 100: s.step(idle4())
	check("respawn after ~1.5s", s.players[1].alive and s.players[1].pos.distance_to(Vector2(8, 6.3)) > 0.5)
	# own head harmless: walk onto own OUT head
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); s.cfg.out_variant = 1
	throw0(s, Vector2.RIGHT, 21)
	for t in 120: s.step(only0(inp(Vector2.RIGHT)))
	check("own head does not hurt owner", s.players[0].alive and s.players[0].deaths == 0)
	# OUT head kills walker
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(11, 3.0))
	throw0(s, Vector2.RIGHT, 60)
	for t in 120: s.step([inp(), inp(Vector2(0, 1)), inp(), inp()])
	check("OUT head is lethal to walking player", not s.players[1].alive or s.players[1].deaths == 1)

	# 8 bounce
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(19, 6.3))
	for t in 60: s.step([inp(Vector2.ZERO, Vector2.RIGHT, true), inp(Vector2.ZERO, Vector2.LEFT, true), inp(), inp()])
	s.step([inp(), inp(), inp(), inp()])
	var bounced := false
	for t in 40:
		s.step(idle4())
		for e in s.events: if e["type"] == "bounce": bounced = true
	var a := s.players[0]; var b := s.players[1]
	check("two heads bounce, nobody dies", bounced and a.alive and b.alive and a.kills == 0 and b.kills == 0 and a.ystate == Y.OUT and b.ystate == Y.OUT and a.head.distance_to(b.head) >= 0.7 - 0.001,
		"gap=%.2f" % a.head.distance_to(b.head))

	# 9 crate drag
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	p = s.players[0]
	s.crate_pos = Vector2(8, 6.3)
	p.head = Vector2(11, 6.3)
	for t in 5: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))
	for t in 60: s.step(idle4())
	check("retract drags crate toward player", s.crate_pos.x < 8.0 - 1.5, "crate x=%.2f" % s.crate_pos.x)
	# crate pushed slowly by player
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); s.crate_pos = Vector2(5, 6.3)
	for t in 60: s.step(only0(inp(Vector2.RIGHT)))
	check("player pushes crate slowly", s.crate_pos.x > 5.5 and s.players[0].pos.x < 3.0 + 6.0 * 0.6, "p=%.2f crate=%.2f" % [s.players[0].pos.x, s.crate_pos.x])

	# 10 box
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	s.box_active = true
	var cfg_box := Config.BOX_POS
	place(s, 0, Vector2(cfg_box.x - 5, cfg_box.y))
	throw0(s, Vector2.RIGHT, 60)
	check("flying head breaks box", not s.box_active)
	for t in int(Config.BOX_RESPAWN_TIME * 60.0) + 120: s.step(only0(inp(Vector2(0, -1)) ))
	check("box reappears", s.box_active)
	s.box_active = true
	p = s.players[0]
	p.ystate = Y.OUT; p.head = cfg_box + Vector2(3, 0); place(s, 0, cfg_box + Vector2(-4, 0)); p.head = cfg_box + Vector2(3, 0)
	p.ystate = Y.RETRACT
	for t in 60: s.step(idle4())
	check("retracting head breaks box", not s.box_active)

	# 11 dash
	s = mk([0]); place(s, 0, Vector2(5, 6.3))
	s.step(only0(inp(Vector2.RIGHT, Vector2.ZERO, false, true)))
	for t in 20: s.step(only0(inp()))
	check("dash distance", absf(s.players[0].pos.x - 5.0 - 3.0) < 0.1, "d=%.2f" % (s.players[0].pos.x - 5.0))
	var x1 := s.players[0].pos.x
	s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, false, true)))
	for t in 20: s.step(only0(inp()))
	check("dash cooldown blocks second dash", absf(s.players[0].pos.x - x1) < 0.1)

	# 12 accidental touch
	s = mk([0]); place(s, 0, Vector2(5, 6.3))
	for t in 2: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))
	check("accidental tap does not throw", s.players[0].ystate == Y.READY)
	for t in 8: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))
	for t in 100: s.step(idle4())
	check("short deliberate hold throws min range", s.players[0].ystate == Y.OUT and absf(s.players[0].head.distance_to(s.players[0].pos) - 3.5) < 0.3)


	# 13 press during flight (buffered)
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
	s.step(only0(inp()))
	p = s.players[0]
	check("flight started", p.ystate == Y.FLIGHT)
	for t in 3: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))   # press during flight, keep holding
	var pulled := false
	for t in 80:
		s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
		if p.ystate == Y.PULL: pulled = true; break
	check("press held during flight -> PULL after landing", pulled and p.pos.x >= 3.0)
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
	s.step(only0(inp()))
	p = s.players[0]
	for t in 3: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))   # short tap released while still flying
	check("tap during flight still flying", p.ystate == Y.FLIGHT)
	var retr := false
	for t in 40:
		s.step(idle4())
		if p.ystate == Y.RETRACT: retr = true; break
	check("short tap during flight -> RETRACT after landing", retr)

	# 14 retract blocked by obstacle
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	p = s.players[0]
	s.statics.append(Rect2(6.0, 5.0, 1.0, 3.0))   # between head (x~11) and player (x=3)
	for t in 5: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))
	var ended_out := false
	for t in 120:
		s.step(idle4())
		if p.ystate == Y.OUT: ended_out = true; break
	check("retract blocked by obstacle ends OUT at obstacle", ended_out and absf(p.head.x - (7.0 + 0.35)) < 0.1 and p.head.x > 7.0, "head x=%.2f" % p.head.x)
	var hx := p.head
	for t in 30: s.step(idle4())
	check("blocked head stays (no jitter)", p.ystate == Y.OUT and p.head == hx)
	# and it can be tapped again / pulled
	for t in 20: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	check("pull possible after block", p.ystate == Y.PULL or p.ystate == Y.OUT)

	# 15 dash charges
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); s.cfg.dash_charges = 2
	s.players[0].dash_charges = 2
	var dashes := 0
	var last := s.players[0].pos.x
	for k in 3:
		s.step(only0(inp(Vector2.RIGHT, Vector2.ZERO, false, true)))
		for t in 12: s.step(only0(inp()))
		if s.players[0].pos.x - last > 2.0: dashes += 1
		last = s.players[0].pos.x
	check("2 charges: two dashes in a row, third blocked", dashes == 2, "dashes=%d" % dashes)
	for t in 60: s.step(only0(inp()))   # ~1.3s total since first dash -> one charge back
	check("one charge refilled after cooldown", s.players[0].dash_charges == 1, "c=%d" % s.players[0].dash_charges)
	for t in 80: s.step(only0(inp()))
	check("fully refilled after second cooldown", s.players[0].dash_charges == 2, "c=%d" % s.players[0].dash_charges)


	_mod_tests()
	_new_tests()
	_path_tests()
	_steer_tests()
	_train_tests()
	_pickup_tests()
	_self_damage_tests()
	_phase_dash_tests()
	_range_tests()
	_match_tests()
	_eight_tests()
	_color_tests()
	_coin_tests()
	_shop_tests()
	_zone_tests()
	_map_tests()
	_rotation_tests()

var _frames := 0
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_menu_tests()
	_touch_tests()
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	quit(fails)
	return true


# ================================================================ modifier tests
const HS := SimHead.S

func setm(s: Sim, i: int, m: Dictionary) -> void:
	s.players[i].mods = m

func many(s: Sim, n: int, ins: Array) -> void:
	for t in n:
		s.step(ins)

func ins2(a: SimInput, b: SimInput) -> Array:
	return [a, b, inp(), inp()]

# charge + release of player `i` (others idle)
# stunned: the thrower is stunned right after the release, so a head that lands at their feet is not picked up
func throw_i(s: Sim, i: int, dir: Vector2, charge_ticks: int, wait := 200, stunned := false) -> void:
	var arr := idle4()
	for t in charge_ticks:
		arr[i] = inp(Vector2.ZERO, dir, true)
		s.step(arr)
	arr[i] = inp()
	s.step(arr)
	if stunned:
		s.players[i].stun_t = 100.0
	for t in wait:
		var all_done := true
		for h in s.players[i].heads:
			if h.state == HS.FLIGHT: all_done = false
		if all_done: break
		s.step(idle4())

func tap_i(s: Sim, i: int, move := Vector2.ZERO) -> void:
	var arr := idle4()
	for t in 6:
		arr[i] = inp(move, Vector2.ZERO, true)
		s.step(arr)
	arr[i] = inp(move)
	s.step(arr)

func _mod_tests() -> void:
	var s: Sim
	var p: SimPlayer
	# --- Mods table basics
	check("copies -> level", Mods.level_for_copies(0) == 0 and Mods.level_for_copies(1) == 1 and Mods.level_for_copies(2) == 1 and Mods.level_for_copies(3) == 2 and Mods.level_for_copies(5) == 2 and Mods.level_for_copies(6) == 3)
	check("ten modifiers, all with 3 descriptions", Mods.ORDER.size() == 10 and Mods.ORDER.all(func(id): return (Mods.TABLE[id]["desc"] as Array).size() == 3 and Mods.describe(id, 2).find("{") == -1))
	var cfgx := Config.new()
	cfgx.mods_you["pierce"] = 2; cfgx.mods_bots["twin"] = 3
	var cfgy := Config.new()
	cfgy.from_dict(JSON.parse_string(JSON.stringify(cfgx.to_dict())))
	check("sandbox choice survives JSON round trip", cfgy.mods_you["pierce"] == 2 and cfgy.mods_bots["twin"] == 3 and cfgy.mods_you["twin"] == 0)

	# --- figure choice (presentation only)
	check("figure: skin count agrees in sim and view", Config.SKIN_COUNT == ToyFigure.NAMES.size())
	var cfgc := Config.new()
	check("figure: default is the first one", cfgc.character == 0 and cfgc.to_dict()["character"] == 0)
	cfgc.character = Config.SKIN_COUNT - 1
	var cfgd := Config.new()
	cfgd.from_dict(JSON.parse_string(JSON.stringify(cfgc.to_dict())))
	check("figure: choice survives JSON round trip", cfgd.character == Config.SKIN_COUNT - 1)
	cfgd.reset()
	check("figure: reset leaves the choice", cfgd.character == Config.SKIN_COUNT - 1)
	for garbage: Variant in ["x", null, [3], {"a": 1}, NAN, INF, true]:
		cfgd.character = 1
		cfgd.from_dict({"character": garbage})
		check("figure: garbage value %s gives 0" % str(garbage), cfgd.character == 0)
	cfgd.from_dict({"character": Config.SKIN_COUNT + 1})
	check("figure: too large value wraps into range", cfgd.character == 1)
	cfgd.from_dict({"character": -1})
	check("figure: negative value wraps into range", cfgd.character == Config.SKIN_COUNT - 1)
	cfgd.from_dict({"character": 2.0})
	check("figure: float value is accepted", cfgd.character == 2)
	cfgd.from_dict({})
	check("figure: old file without the key gives 0", cfgd.character == 0)
	var cfgt := Config.new()
	check("target score: default 10", cfgt.target_score == 10 and cfgt.to_dict()["target_score"] == 10)
	cfgt.target_score = 20
	var cfgu := Config.new()
	cfgu.from_dict(JSON.parse_string(JSON.stringify(cfgt.to_dict())))
	check("target score: survives the JSON round trip", cfgu.target_score == 20)
	cfgu.reset()
	check("target score: reset leaves it", cfgu.target_score == 20)
	for garbage in [7, -3, "x", null, 1e30]:
		cfgu.from_dict({"target_score": garbage})
		check("target score: garbage %s gives the default" % str(garbage), cfgu.target_score == 10)
	s = mk([0, 1])
	check("figure: new sim shows figure = slot (wrapped)", s.players[0].skin == 0 % Config.SKIN_COUNT and s.players[1].skin == 1 % Config.SKIN_COUNT)
	s.set_skin(1, Config.SKIN_COUNT - 1)
	check("figure: set_skin sets it", s.players[1].skin == Config.SKIN_COUNT - 1 and s.players[0].skin == 0)
	s.set_skin(1, Config.SKIN_COUNT + 2)
	check("figure: set_skin wraps too large", s.players[1].skin == 2 % Config.SKIN_COUNT)
	s.set_skin(1, -1)
	check("figure: set_skin wraps negative", s.players[1].skin == Config.SKIN_COUNT - 1)
	var sa := Sim.new(Config.new(), 7)
	var sb := Sim.new(Config.new(), 7)
	for k in Config.NUM_PLAYERS:
		sb.set_skin(k, Config.SKIN_COUNT - 1 - k)
	for tk in 120:
		var ia := idle4()
		ia[0] = inp(Vector2(1, 0.3), Vector2(1, 0), tk % 50 < 25, tk == 40)
		ia[1] = inp(Vector2(-1, 0.2), Vector2(-1, 0), tk % 70 < 30, tk == 70)
		sa.step(ia)
		sb.step(ia)
	var same := true
	for k in Config.NUM_PLAYERS:
		same = same and sa.players[k].pos == sb.players[k].pos and sa.players[k].heads[0].pos == sb.players[k].heads[0].pos
	check("figure: a different skin does not change the simulation", same and sa.players[0].pos != Config.SPAWNS[0] and sa.players[0].skin != sb.players[0].skin)

	# --- 1 Tripwire
	for L in [1, 2, 3]:
		s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(7, 9.0)); setm(s, 0, {"tripwire": L})
		throw_i(s, 0, Vector2.RIGHT, 60)
		tap_i(s, 0)
		var w0: SimWire = s.wires[0] if s.wires.size() > 0 else null
		check("tripwire L%d: retract leaves wire from player to head" % L, w0 != null and absf(w0.pts[0].x - 3.0) < 0.2 and absf(w0.pts[w0.pts.size() - 1].x - 11.0) < 0.2 and w0.lethal == (L == 3), "wires=%d" % s.wires.size())
		many(s, 60, idle4())
		check("tripwire L%d: head back home" % L, s.players[0].heads[0].state == HS.HAND)
		var killed_before := s.players[1].deaths
		for t in 80:
			s.step(ins2(inp(), inp(Vector2(0, -1))))
			if s.wires.size() == 0: break
		var v := s.players[1]
		if L < 3:
			check("tripwire L%d: touching stuns (alive), wire used up" % L, v.deaths == 0 and s.wires.size() == 0 and v.stun_t > 0.0, "stun=%.2f" % v.stun_t)
			var px := v.pos
			var stun_ticks := 0
			while v.stun_t > 0.0 and stun_ticks < 200:
				s.step(ins2(inp(), inp(Vector2(1, 0), Vector2.RIGHT, true))); stun_ticks += 1
			check("tripwire L%d: stun length ~%.1fs, no moving/throwing meanwhile" % [L, Mods.n("tripwire", "stun_time", L)], absf(stun_ticks / 60.0 - Mods.n("tripwire", "stun_time", L)) < 0.1 and v.pos.distance_to(px) < 0.2 and v.heads[0].state == HS.HAND, "ticks=%d" % stun_ticks)
		else:
			check("tripwire L3: wire is lethal", v.deaths == 1 and s.players[0].kills == 1 and s.wires.size() == 0)
	# no touch -> expires; max wires
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"tripwire": 1})
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0); many(s, 40, idle4())
	check("tripwire L1: wire present before expiry", s.wires.size() == 1)
	many(s, 130, idle4())
	check("tripwire L1: wire expires after 2.5s", s.wires.size() == 0)
	for L in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"tripwire": L})
		for k in 4:
			throw_i(s, 0, Vector2.RIGHT, 15); tap_i(s, 0); many(s, 40, idle4())
		check("tripwire L%d: at most %d wires" % [L, int(Mods.n("tripwire", "max_wires", L))], s.wires.size() == int(Mods.n("tripwire", "max_wires", L)), "n=%d" % s.wires.size())
	# own wire harmless
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"tripwire": 3})
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0); many(s, 50, idle4())
	for t in 60: s.step(only0(inp(Vector2(1, 0))))
	check("tripwire: own wire never hurts owner", s.players[0].alive and s.players[0].stun_t == 0.0)

	# --- 2 Big Chunk
	var offs := [[0, 1.0, false], [1, 1.0, true], [1, 1.1, false], [2, 1.1, true], [2, 1.4, false], [3, 1.4, true], [3, 1.6, false]]
	for c in offs:
		s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(8, 6.3 + c[1])); setm(s, 0, {"bighead": c[0]} if c[0] > 0 else {})
		throw_i(s, 0, Vector2.RIGHT, 60)
		check("bighead L%d: offset %.1f %s" % [c[0], c[1], "hits" if c[2] else "misses"], (s.players[1].deaths == 1) == c[2])
	s = mk([0]); setm(s, 0, {"bighead": 3})
	check("bighead L3 radius x2.8", absf(s.head_r(s.players[0]) - 0.35 * 2.8) < 0.001)

	# --- 3 Rubber Band
	var pull_ticks := {}
	for L in [0, 1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"elastic": L} if L > 0 else {})
		throw_i(s, 0, Vector2.RIGHT, 60); p = s.players[0]
		var hx := p.heads[0].pos.x
		var tcount := 0
		var caught_x := 0.0
		for t in 200:
			s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true))); tcount += 1
			if p.heads[0].state == HS.HAND:
				caught_x = p.pos.x; break
		pull_ticks[L] = tcount
		many(s, 40, only0(inp()))
		if L > 0:
			var fd := Mods.n("elastic", "fling_dist", L)
			check("elastic L%d: flung %.1fm past the catch" % [L, fd], absf((p.pos.x - caught_x) - fd) < 0.5, "flung=%.2f caught=%.2f" % [p.pos.x - caught_x, caught_x])
		else:
			check("no elastic: no fling", absf(p.pos.x - caught_x) < 0.05)
	check("elastic: pull faster (L3 << none)", (pull_ticks[3] - 12) * 1.8 < (pull_ticks[0] - 12) and pull_ticks[1] < pull_ticks[0], str(pull_ticks))
	s = mk([0]); place(s, 0, Vector2(RW - 10.0, 6.3)); setm(s, 0, {"elastic": 3})
	throw_i(s, 0, Vector2.RIGHT, 60)
	for t in 120: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	check("elastic L3: fling stopped by wall", s.players[0].pos.x <= RW - 0.5 + 0.01 and s.players[0].pos.x > RW - 2.0 and s.players[0].fling_left == 0.0, "x=%.2f" % s.players[0].pos.x)
	# control loss during fling
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"elastic": 3})
	throw_i(s, 0, Vector2.RIGHT, 60)
	var flung_moving := false
	for t in 60:
		s.step(only0(inp(Vector2(-1, 0), Vector2.ZERO, true)))
		if s.players[0].fling_left > 0.0:
			var x0 := s.players[0].pos.x
			s.step(only0(inp(Vector2(-1, 0), Vector2.ZERO, false)))
			flung_moving = s.players[0].pos.x > x0 + 0.3
			break
	check("elastic: fling ignores move input", flung_moving)
	for L in [1, 2, 3]:
		s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(13.6, 6.3)); setm(s, 0, {"elastic": L})
		throw_i(s, 0, Vector2.RIGHT, 60)
		for t in 100: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
		check("elastic L%d: body %s" % [L, "harmless" if L == 1 else "lethal"], (s.players[1].deaths == 1) == (L >= 2) and s.players[0].alive, "deaths=%d" % s.players[1].deaths)
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(6.0, 7.2)); setm(s, 0, {"elastic": 2})
	throw_i(s, 0, Vector2.RIGHT, 60)
	for t in 100: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	var l2_kill := s.players[1].deaths
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(6.0, 7.6)); setm(s, 0, {"elastic": 3})
	throw_i(s, 0, Vector2.RIGHT, 60)
	for t in 100: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	var l3_kill := s.players[1].deaths
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(6.0, 7.6)); setm(s, 0, {"elastic": 2})
	throw_i(s, 0, Vector2.RIGHT, 60)
	for t in 100: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	check("elastic L3 body radius x1.5 reaches further than L2", l2_kill == 1 and l3_kill == 1 and s.players[1].deaths == 0, "L2near=%d L3far=%d L2far=%d" % [l2_kill, l3_kill, s.players[1].deaths])

	# --- 4 Extra Dash
	var refill := {}
	var dist_d := {}
	for L in [0, 1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(2, 6.3)); setm(s, 0, {"extradash": L} if L > 0 else {})
		p = s.players[0]; p.dash_charges = s.dash_max(p)
		check("extradash L%d: max charges %d" % [L, 1 + L], s.dash_max(p) == 1 + L)
		var xs := p.pos.x
		s.step(only0(inp(Vector2.RIGHT, Vector2.ZERO, false, true)))
		for t in 12: s.step(only0(inp()))
		dist_d[L] = p.pos.x - xs
		var tc := 0
		while p.dash_charges < s.dash_max(p) and tc < 400:
			s.step(only0(inp())); tc += 1
		refill[L] = tc + 13
	check("extradash: the dash is the same length at every level", absf(dist_d[3] - 3.0) < 0.15 and absf(dist_d[0] - 3.0) < 0.15 and absf(dist_d[2] - 3.0) < 0.15, str(dist_d))
	check("extradash: cooldown x1 / x0.75 / x0.5", absf(refill[0] / 60.0 - 1.2) < 0.1 and absf(refill[2] / 60.0 - 0.9) < 0.1 and absf(refill[3] / 60.0 - 0.6) < 0.1, str(refill))
	s = mk([0]); place(s, 0, Vector2(2, 6.3)); setm(s, 0, {"extradash": 3}); s.players[0].dash_charges = 4
	var nd := 0
	var last_x := 2.0
	for k in 6:
		s.step(only0(inp(Vector2.UP, Vector2.ZERO, false, true)))
		many(s, 8, only0(inp()))
	check("extradash L3: four dashes in a row (charges drained)", s.players[0].dash_charges <= 1, "left=%d" % s.players[0].dash_charges)

	# --- 5 Ricochet
	var land_x := {}
	for L in [0, 1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"bounce": L} if L > 0 else {})
		throw_i(s, 0, Vector2.RIGHT, 60, 200, true); p = s.players[0]
		land_x[L] = p.heads[0].pos.x
	check("bounce: L0 stops at wall, L1 +1.5m, L2 +3m, L3 +5m per bounce", absf(land_x[0] - (RW - 0.35)) < 0.05 and absf(land_x[1] - (RW - 4.2)) < 0.15 and absf(land_x[2] - (RW - 5.7)) < 0.15 and absf(land_x[3] - (RW - 7.7)) < 0.15, str(land_x))
	var bcount := {}
	for L in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(RW - 2.0, 6.3)); setm(s, 0, {"bounce": L})
		s.statics.append(Rect2(RW - 4.0, 3, 1, 7))
		throw_i(s, 0, Vector2.RIGHT, 60)
		bcount[L] = s.players[0].heads[0].bounces
	check("bounce: max 1 / 3 / 5 bounces between two walls", bcount[1] == 1 and bcount[2] == 3 and bcount[3] == 5, str(bcount))
	s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"bounce": 3})
	var spd := 0.0
	for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
	s.step(only0(inp()))
	for t in 40:
		s.step(idle4())
		if s.players[0].heads[0].bounces == 1: spd = s.players[0].heads[0].speed_mult
	check("bounce L3: 25% faster after first bounce", absf(spd - 1.25) < 0.001, str(spd))
	# bounce + pierce: pierce wins for blocks, bounce for the outer wall
	s = mk([0]); place(s, 0, Vector2(RW - 7.0, 11.0)); setm(s, 0, {"bounce": 1, "pierce": 1})
	s.statics.append(Rect2(RW - 5.0, 9, 1, 3))
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("bounce+pierce: passes block, bounces off outer wall", s.players[0].heads[0].bounces == 1 and s.players[0].heads[0].pos.x > RW - 5.0 and s.players[0].heads[0].pos.x < RW - 1.0, "x=%.2f b=%d" % [s.players[0].heads[0].pos.x, s.players[0].heads[0].bounces])

	# --- 7 Piercing
	for L in [0, 1, 2]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"pierce": L} if L > 0 else {})
		s.statics.append(Rect2(6, 5, 1, 3))
		throw_i(s, 0, Vector2.RIGHT, 60); p = s.players[0]
		var expect_x := 3.0 + 8.0 * (1.2 if L == 2 else 1.0)
		if L == 0:
			check("pierce L0: block stops the head", absf(p.heads[0].pos.x - 5.65) < 0.05)
		else:
			check("pierce L%d: head passes the block (range%s)" % [L, " +20%" if L == 2 else ""], absf(p.heads[0].pos.x - expect_x) < 0.1, "x=%.2f expect=%.2f" % [p.heads[0].pos.x, expect_x])
		tap_i(s, 0)
		var was_out := false
		for _i in 90:
			many(s, 1, idle4())
			if p.heads[0].state == HS.OUT:
				was_out = true
		if L == 1:
			check("pierce L1: head never stops OUT on the way back", not was_out)
			check("pierce L1: head returns to the hand through the block", p.heads[0].state == HS.HAND)
		if L == 2:
			check("pierce L2: retract passes the block", p.heads[0].state == HS.HAND)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"pierce": 1})
	s.statics.append(Rect2(6, 5, 1, 3))
	throw_i(s, 0, Vector2.RIGHT, 8)
	check("pierce L1: landing inside a block continues to the far side", s.players[0].heads[0].state == HS.OUT and s.players[0].heads[0].pos.x >= 7.34 and s.players[0].heads[0].pos.x < 7.6, "x=%.2f" % s.players[0].heads[0].pos.x)
	s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"pierce": 3})
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("pierce L3: never through the outer wall", s.players[0].heads[0].pos.x <= RW - 0.35 + 0.01 and s.players[0].heads[0].state == HS.OUT)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"pierce": 1}); s.crate_pos = Vector2(8, 6.3)
	throw_i(s, 0, Vector2.RIGHT, 60)
	var cx1 := s.players[0].heads[0].pos.x
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"pierce": 2}); s.crate_pos = Vector2(8, 6.3)
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("pierce: crate stops L1 flight, L2 passes it", cx1 < 7.1 and s.players[0].heads[0].pos.x > 11.5 and absf(s.crate_pos.x - 8.0) < 0.01, "L1 x=%.2f L2 x=%.2f" % [cx1, s.players[0].heads[0].pos.x])
	# retract vs crate: L1 drags the crate along, L2 passes through it
	for L in [1, 2]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"pierce": L}); p = s.players[0]
		throw_i(s, 0, Vector2.RIGHT, 60)
		s.crate_pos = Vector2(7.0, 6.3)
		tap_i(s, 0); many(s, 90, idle4())
		if L == 1:
			check("pierce L1: retracting head still pushes the crate", absf(s.crate_pos.x - 7.0) > 0.3 or p.heads[0].state != HS.HAND, "crate x=%.2f" % s.crate_pos.x)
		else:
			check("pierce L2: retracting head passes the crate", p.heads[0].state == HS.HAND and absf(s.crate_pos.x - 7.0) < 0.01, "crate x=%.2f" % s.crate_pos.x)
	# L3 duel
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(19, 6.3)); setm(s, 0, {"pierce": 3})
	for t in 60: s.step([inp(Vector2.ZERO, Vector2.RIGHT, true), inp(Vector2.ZERO, Vector2.LEFT, true), inp(), inp()])
	s.step(idle4())
	many(s, 40, idle4())
	var a := s.players[0]; var b := s.players[1]
	check("pierce L3: enemy head knocked away and OUT, own head unaffected", a.heads[0].pos.x > 12.55 and b.heads[0].state == HS.OUT and b.heads[0].pos.x > 11.9 and a.alive and b.alive, "a=%.2f b=%.2f" % [a.heads[0].pos.x, b.heads[0].pos.x])
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(19, 6.3)); setm(s, 0, {"pierce": 3}); setm(s, 1, {"pierce": 3})
	for t in 60: s.step([inp(Vector2.ZERO, Vector2.RIGHT, true), inp(Vector2.ZERO, Vector2.LEFT, true), inp(), inp()])
	s.step(idle4())
	many(s, 40, idle4())
	a = s.players[0]; b = s.players[1]
	check("pierce L3 vs L3: bounce normally", a.heads[0].pos.distance_to(b.heads[0].pos) >= 0.69 and a.heads[0].pos.x < 11.0 and a.alive and b.alive)

	# --- 8 Shards
	for L in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": L})
		throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0)
		var cnt := s.shards.size()
		var d0 := s.shards[0].dir if cnt > 0 else Vector2.ZERO
		check("shards L%d: %d shards, one straight away from the player" % [L, int(Mods.n("shards", "count", L))], cnt == int(Mods.n("shards", "count", L)) and d0.distance_to(Vector2.RIGHT) < 0.01, "n=%d" % cnt)
		var maxd := 0.0
		var origin := s.shards[0].pos
		for t in 90:
			s.step(idle4())
			for sh in s.shards: maxd = maxf(maxd, sh.pos.distance_to(origin))
		check("shards L%d: gone after range, none flies further than %.0fm" % [L, Mods.n("shards", "range", L)], s.shards.size() == 0 and maxd <= Mods.n("shards", "range", L) + 0.3, "maxd=%.2f" % maxd)
		check("shards L%d: owner unharmed" % L, s.players[0].alive and s.players[0].deaths == 0)
	for c in [[1, 3.0, true], [1, 5.5, false], [2, 5.5, true], [2, 7.0, false], [3, 7.0, true]]:
		s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(11.0 + c[1], 6.3)); setm(s, 0, {"shards": c[0]})
		throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0); many(s, 60, idle4())
		check("shards L%d: victim %.1fm behind the head %s" % [c[0], c[1], "dies" if c[2] else "survives"], (s.players[1].deaths == 1) == c[2])
	var travel := {}
	for L in [1, 3]:
		s = mk([0]); place(s, 0, Vector2(RW - 8.25, 6.3)); setm(s, 0, {"shards": L})
		throw_i(s, 0, Vector2.RIGHT, 21); tap_i(s, 0)
		var sh0: SimShard = null
		for sh in s.shards:
			if sh.dir.x > 0.9: sh0 = sh
		var dist_t := 0.0
		for t in 120:
			if sh0 == null: break
			s.step(idle4())
			if not s.shards.has(sh0): break
			dist_t += sh0.pos.distance_to(sh0.prev_pos)
		travel[L] = dist_t
	check("shards L3 bounce once off the wall, L1 stop at it", travel[1] > 2.0 and travel[1] < 3.3 and travel[3] > 7.0 and travel[3] < 8.2, str(travel))
	s = mk([0]); place(s, 0, Vector2(Config.BOX_POS.x - 11.0, Config.BOX_POS.y)); setm(s, 0, {"shards": 1}); s.box_active = true
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0); many(s, 30, idle4())
	check("shards break the box", not s.box_active)
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(11.0, 2.0)); setm(s, 0, {"shards": 1}); s.statics.append(Rect2(10, 3.5, 3, 1.0))
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0); many(s, 60, idle4())
	check("shards are stopped by obstacles", s.players[1].deaths == 0)

	# --- 9 Warhead
	var rad := {1: 1.6, 2: 2.4, 3: 3.4}
	for L in [1, 2, 3]:
		for off in [rad[L] + 0.5 - 0.3, rad[L] + 0.5 + 0.3]:
			var inside: bool = off < rad[L] + 0.5
			s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(11.0, 6.3 + off)); setm(s, 0, {"warhead": L})
			throw_i(s, 0, Vector2.RIGHT, 60)
			check("warhead L%d: victim %.1fm from landing %s" % [L, off, "dies" if inside else "survives"], (s.players[1].deaths == 1) == inside)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": 3})
	throw_i(s, 0, Vector2.RIGHT, 8)
	check("warhead L3: owner inside own explosion dies (no kill credit)", not s.players[0].alive and s.players[0].deaths == 1 and s.players[0].kills == 0)
	for L in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": L})
		var ex := 0
		var rr := 0.0
		for t in 60: 
			s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
		s.step(only0(inp()))
		for t in 60:
			s.step(idle4()); for e in s.events: if e["type"] == "explosion": ex += 1; rr = e["radius"]
		tap_i(s, 0) 
		for e in s.events: if e["type"] == "explosion": ex += 1
		check("warhead L%d: %d explosion(s), radius %.1f in event" % [L, 1 if L == 1 else 2, rad[L]], ex == (1 if L == 1 else 2) and absf(rr - rad[L]) < 0.001, "ex=%d" % ex)
	s = mk([0]); place(s, 0, Vector2(Config.BOX_POS.x - 4.0, Config.BOX_POS.y)); setm(s, 0, {"warhead": 1}); s.box_active = true
	throw_i(s, 0, Vector2.RIGHT, 21)
	check("warhead breaks the box", not s.box_active)

	# --- 10 Twin
	for L in [1, 2, 3]:
		s = mk([0]); setm(s, 0, {"twin": L}); s.step(idle4())
		check("twin L%d: exactly 2 yo-yos" % L, s.players[0].heads.size() == 2)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 1}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("twin: first out, second in hand", p.heads[0].state == HS.OUT and p.heads[1].state == HS.HAND)
	throw_i(s, 0, Vector2.UP, 60)
	check("twin: second throw while the first is out", p.heads[1].state == HS.OUT and p.heads[0].state == HS.OUT and absf(p.heads[1].pos.x - 3.0) < 0.2 and p.heads[1].pos.y < 1.0, "h1=%s" % p.heads[1].pos)
	# tap with one in hand retracts the out one
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 1}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60)
	tap_i(s, 0)
	check("twin: tap retracts the out yo-yo even with one in hand", p.heads[0].state == HS.RETRACT and p.heads[1].state == HS.HAND and not p.charging)
	many(s, 60, idle4())
	check("twin: retracted yo-yo is home", p.heads[0].state == HS.HAND)
	# aimed flick throws instead
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 1}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60)
	for t in 6: s.step(only0(inp(Vector2.ZERO, Vector2.DOWN, true)))
	s.step(only0(inp()))
	check("twin: aimed quick flick still throws the next one", p.heads[1].state == HS.FLIGHT or p.heads[1].state == HS.OUT)
	# tap retracts all
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 1}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60); throw_i(s, 0, Vector2.UP, 60)
	tap_i(s, 0)
	check("twin: tap with all out retracts all", p.heads[0].state == HS.RETRACT and p.heads[1].state == HS.RETRACT)
	many(s, 80, idle4())
	check("twin: both home", p.heads[0].state == HS.HAND and p.heads[1].state == HS.HAND)
	# tap during flight of one: queued
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 1}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60, 0)
	tap_i(s, 0)
	check("twin: tap during flight queues the retract", p.heads[0].state == HS.FLIGHT or p.heads[0].state == HS.RETRACT)
	many(s, 60, idle4())
	check("twin: queued retract completes", p.heads[0].state == HS.HAND)
	# pull picks the head in move direction
	for c in [[Vector2.RIGHT, 0], [Vector2(0, -1), 1], [Vector2.ZERO, 1]]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 1}); p = s.players[0]
		throw_i(s, 0, Vector2.RIGHT, 60); throw_i(s, 0, Vector2.UP, 60)
		for t in 15: s.step(only0(inp(c[0], Vector2.ZERO, true)))
		check("twin: pull target for move %s is head %d" % [c[0], c[1]], p.pulling and p.pull_target == c[1], "target=%d pulling=%s" % [p.pull_target, p.pulling])
		for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
		check("twin: catching puts it in hand and ends the pull", not p.pulling and p.heads[c[1]].state == HS.HAND and p.heads[1 - c[1]].state == HS.OUT)
	# leash with two heads
	s = mk([0]); place(s, 0, Vector2(14, 6.3)); setm(s, 0, {"twin": 1}); s.cfg.out_variant = 1; p = s.players[0]
	throw_i(s, 0, Vector2.LEFT, 60); throw_i(s, 0, Vector2.RIGHT, 60)
	var worst := 0.0
	for t in 120:
		s.step(only0(inp(Vector2(0, -1))))
		worst = maxf(worst, maxf(p.pos.distance_to(p.heads[0].pos), p.pos.distance_to(p.heads[1].pos)))
	check("twin + leash: player stays within string length of both", worst <= 9.1, "worst=%.2f" % worst)
	# stunned cannot use yo-yo
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); s.players[0].stun_t = 0.5
	for t in 10: s.step(only0(inp(Vector2.RIGHT, Vector2.RIGHT, true)))
	s.step(only0(inp()))
	check("stunned: no throw, no move", s.players[0].heads[0].state == HS.HAND and s.players[0].pos.x < 3.01)

	# --- all together: no errors, determinism
	var snap := []
	for run in 2:
		s = Sim.new(Config.new(), 7)
		var all3 := {}
		for id in Mods.ORDER: all3[id] = 3
		for i in 4: s.players[i].mods = all3
		var bots: Array[Bot] = []
		for i in 4: bots.append(Bot.new(i, s.cfg, 50 + i))
		for t in 1800:
			var arr: Array = []
			for bt in bots: arr.append(bt.think(s, 1.0 / 60.0))
			s.step(arr)
		var key := []
		for pl in s.players: key.append([pl.pos, pl.kills, pl.deaths])
		snap.append(str(key))
	check("deterministic with all modifiers (same seed, same result)", snap[0] == snap[1])


# ================================================================ tests of the second round (points 1-7)

func throw_mv(s: Sim, i: int, dir: Vector2, ticks: int, move: Vector2) -> void:
	var arr := idle4()
	for t in ticks:
		arr[i] = inp(Vector2.ZERO, dir, true)
		s.step(arr)
	arr[i] = inp(move)
	s.step(arr)

# hold without deflection for n ticks
# like tap_i, but returns the events of the tap steps
func tap_ev(s: Sim, i: int) -> Array:
	var evs := []
	var arr := idle4()
	for t in 6:
		arr[i] = inp(Vector2.ZERO, Vector2.ZERO, true)
		s.step(arr)
		evs.append_array(s.events)
	arr[i] = inp()
	s.step(arr)
	evs.append_array(s.events)
	return evs

func hold_i(s: Sim, i: int, n: int, move := Vector2.ZERO) -> void:
	var arr := idle4()
	for t in n:
		arr[i] = inp(move, Vector2.ZERO, true)
		s.step(arr)

func release_i(s: Sim, i: int) -> void:
	s.step(idle4())

func dist_to_path(q: Vector2, pts: PackedVector2Array) -> float:
	return Sim.closest_on_path(q, pts).distance_to(q)

# two-pin setup: player (22,10) throws diagonally down-right with bounce level L
func two_pin_sim(L: int, extra := {}) -> Sim:
	var s := mk([0, 1])
	place(s, 0, Vector2(RW - 6.0, BW - 2.6)); place(s, 1, Vector2(2, 2))
	s.players[1].alive = false; s.players[1].respawn_t = 9999.0
	var m := {"bounce": L}
	m.merge(extra)
	setm(s, 0, m)
	throw_i(s, 0, Vector2(1, 1), 60)
	return s

func _new_tests() -> void:
	var s: Sim
	var p: SimPlayer
	var h: SimHead

	# ---------------- 1 Ricochet: pins recorded, distance per bounce already in the adapted check
	s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"bounce": 2})
	throw_i(s, 0, Vector2.RIGHT, 60, 200, true); h = s.players[0].heads[0]
	check("bounce L2: one pin at the wall, string path length = 8 + 3", h.pins.size() == 1 and absf(h.pins[0].x - (RW - 0.35)) < 0.05 and absf(Sim.path_length(s.string_path(s.players[0], h)) - 11.0) < 0.2, "pins=%s len=%.2f" % [h.pins, Sim.path_length(s.string_path(s.players[0], h))])
	for L in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"bounce": L})
		throw_i(s, 0, Vector2.RIGHT, 60, 200, true); h = s.players[0].heads[0]
		var back := RW - 0.35 - h.pos.x
		check("bounce L%d: flies %.1f m back after the wall (2.35 + bonus)" % [L, 2.35 + Mods.n("bounce", "bonus_dist", L)], absf(back - (2.35 + [1.5, 3.0, 5.0][L - 1])) < 0.15, "back=%.2f" % back)

	# ---------------- 3 Twin
	s = mk([0]); s.step(idle4())
	check("twin L0: one yo-yo", s.players[0].heads.size() == 1)
	# L2 Crossfire
	for L in [1, 2]:
		s = mk([0, 1]); place(s, 0, Vector2(5, 10)); place(s, 1, Vector2(11, 8)); setm(s, 0, {"twin": L}); p = s.players[0]
		throw_i(s, 0, Vector2.RIGHT, 60); throw_i(s, 0, Vector2.UP, 60)
		# heads at (13,10) and (5,2); meeting point (9,6)
		check("twin L%d: both out where expected" % L, p.heads[0].pos.distance_to(Vector2(13, 10)) < 0.2 and p.heads[1].pos.distance_to(Vector2(5, 2)) < 0.2, "%s %s" % [p.heads[0].pos, p.heads[1].pos])
		tap_i(s, 0)
		var met := false
		var near_player_before_meet := false
		var both_home := false
		for t in 150:
			s.step(idle4())
			var d0 := p.heads[0].pos.distance_to(Vector2(9, 6)); var d1 := p.heads[1].pos.distance_to(Vector2(9, 6))
			if d0 < 0.3 and d1 < 0.3: met = true
			if not met and (p.heads[0].pos.distance_to(p.pos) < 1.0 or p.heads[1].pos.distance_to(p.pos) < 1.0): near_player_before_meet = true
			if p.heads[0].state == HS.HAND and p.heads[1].state == HS.HAND:
				both_home = true
				break
		check("twin L%d: heads %s at the midpoint, then both come home" % [L, "meet" if L == 2 else "do NOT meet"], met == (L == 2) and both_home and (L == 1 or not near_player_before_meet), "met=%s home=%s" % [met, both_home])
		check("twin L%d: victim in the sweep between the heads %s" % [L, "dies" if L == 2 else "survives"], (s.players[1].deaths == 1) == (L == 2), "deaths=%d" % s.players[1].deaths)
	# Crossfire needs a free way: a block at the meeting point -> normal return
	s = mk([0]); place(s, 0, Vector2(5, 10)); setm(s, 0, {"twin": 2}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60); throw_i(s, 0, Vector2.UP, 60)
	s.statics.append(Rect2(8.4, 5.4, 1.2, 1.2))
	tap_i(s, 0)
	check("twin L2: blocked meeting point -> plain return, no meet", not p.heads[0].meet_on and not p.heads[1].meet_on)
	many(s, 100, idle4())
	check("twin L2: ... and both come home", p.heads[0].state == HS.HAND and p.heads[1].state == HS.HAND)
	# L3 retract speed x1.5
	var ticks_home := {}
	for L in [2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": L}); p = s.players[0]
		throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0)
		var tk := 0
		while p.heads[0].state != HS.HAND and tk < 200:
			s.step(idle4()); tk += 1
		ticks_home[L] = tk
	check("twin L3: retract 1.5x faster than L2", float(ticks_home[2]) / ticks_home[3] > 1.3 and float(ticks_home[2]) / ticks_home[3] < 1.7, str(ticks_home))
	# L3 pull with one in hand
	for L in [2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": L}); p = s.players[0]
		throw_i(s, 0, Vector2.RIGHT, 60)
		hold_i(s, 0, 25)
		if L == 3:
			check("twin L3: undeflected hold with one in hand pulls to the lying one", p.pulling and p.pull_target == 0 and p.pos.x > 4.0 and p.heads[1].state == HS.HAND, "pulling=%s x=%.2f" % [p.pulling, p.pos.x])
			hold_i(s, 0, 60)
			check("twin L3: ... and catches it", not p.pulling and p.heads[0].state == HS.HAND and p.pos.x > 10.0, "x=%.2f" % p.pos.x)
		else:
			check("twin L2: the same hold does not pull", not p.pulling)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 3}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0)
	check("twin L3: a short undeflected tap still retracts", p.heads[0].state == HS.RETRACT and not p.pulling)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 3}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60)
	for t in 30: s.step(only0(inp(Vector2.ZERO, Vector2.DOWN, true)))
	s.step(only0(inp()))
	check("twin L3: a deflected press charges and throws the second one", not p.pulling and p.heads[1].state != HS.HAND, "h1=%d" % p.heads[1].state)

	# ---------------- 4 Synergien
	# shards + warhead
	for wl in [0, 1, 3]:
		s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(15.0, 7.3)); setm(s, 0, {"shards": 1, "warhead": wl} if wl > 0 else {"shards": 1})
		throw_i(s, 0, Vector2.RIGHT, 60)
		s.players[1].pos = Vector2(15.0, 7.3 + (0.0 if wl < 3 else 0.0)); s.players[1].prev_pos = s.players[1].pos
		tap_i(s, 0)
		var blasts := 0
		var brad := 0.0
		for t in 90:
			s.step(idle4())
			for e in s.events:
				if e["type"] == "explosion" and (e["radius"] as float) < 1.5 and wl != 3: blasts += 1; brad = e["radius"]
				if e["type"] == "explosion" and wl == 3 and (e["radius"] as float) < 2.0: blasts += 1; brad = e["radius"]
		var want_r: float = [0.0, 0.8, 1.6][[0, 1, 3].find(wl)]
		check("shards+warhead L%d: %d shard explosions of radius %.1f" % [wl, 3 if wl > 0 else 0, want_r], (blasts == 3 and absf(brad - want_r) < 0.001) if wl > 0 else blasts == 0, "blasts=%d r=%.2f" % [blasts, brad])
		if wl == 1:
			check("shards+warhead: shard blast kills a victim beside the shard's end", s.players[1].deaths == 1)
		if wl == 0:
			check("shards alone: the same victim survives", s.players[1].deaths == 0)
	s = mk([0]); place(s, 0, Vector2(RW - 7.0, 6.3)); setm(s, 0, {"shards": 1, "warhead": 1}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 40); h = p.heads[0]
	var wall_blast := Vector2.ZERO
	var evs0 := tap_ev(s, 0)
	for t in 90:
		s.step(idle4())
		evs0.append_array(s.events)
	for e in evs0:
		if e["type"] == "explosion" and absf((e["radius"] as float) - 0.8) < 0.001 and (e["pos"] as Vector2).x > RW - 1.0: wall_blast = e["pos"]
	check("shards+warhead: a shard hitting the wall explodes at the wall", wall_blast.x > RW - 0.5 and wall_blast.x < RW, "pos=%s" % wall_blast)
	# shards + pierce
	for pl in [0, 1, 2]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 1, "pierce": pl} if pl > 0 else {"shards": 1}); p = s.players[0]
		s.statics.append(Rect2(13, 5, 1, 3))
		throw_i(s, 0, Vector2.RIGHT, 60)
		var hx := p.heads[0].pos.x
		tap_i(s, 0)
		var maxx := 0.0
		for t in 60:
			s.step(idle4())
			for sh in s.shards: if sh.dir.x > 0.9: maxx = maxf(maxx, sh.pos.x)
		check("shards+pierce L%d: shard %s the block" % [pl, "stops at" if pl == 0 else "passes"], (maxx < 13.0) if pl == 0 else (maxx > 14.0), "head=%.2f maxx=%.2f" % [hx, maxx])
	for pl in [1, 2]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 1, "pierce": pl}); p = s.players[0]
		s.crate_pos = Vector2(14.0, 6.3)
		throw_i(s, 0, Vector2.RIGHT, 60)
		tap_i(s, 0)
		var maxx2 := 0.0
		for t in 60:
			s.step(idle4())
			for sh in s.shards: if sh.dir.x > 0.9: maxx2 = maxf(maxx2, sh.pos.x)
		check("shards+pierce L%d: shard %s the crate" % [pl, "stops at" if pl == 1 else "passes"], (maxx2 < 13.4) if pl == 1 else (maxx2 > 14.8), "maxx=%.2f" % maxx2)
	# shards + bounce
	for bl in [0, 1, 3]:
		s = mk([0]); place(s, 0, Vector2(RW - 8.25, 6.3)); setm(s, 0, {"shards": 1, "bounce": bl} if bl > 0 else {"shards": 1}); p = s.players[0]
		throw_i(s, 0, Vector2.RIGHT, 21); tap_i(s, 0)
		var sh0: SimShard = null
		for sh in s.shards: if sh.dir.x > 0.9: sh0 = sh
		var bl_left := sh0.bounces_left
		var reversed := false
		for t in 150:
			if sh0 == null: break
			s.step(idle4())
			if not s.shards.has(sh0): break
			if sh0.dir.x < -0.9: reversed = true
		check("shards+bounce L%d: shard has %d bounce(s) and %s" % [bl, bl, "stops at the wall" if bl == 0 else "turns around at the wall"], bl_left == [0, 1, 3, 5][bl] and reversed == (bl > 0), "left=%d reversed=%s" % [bl_left, reversed])
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 3, "bounce": 3})
	throw_i(s, 0, Vector2.RIGHT, 15); tap_i(s, 0)
	check("shards L3 + bounce L3: 1 + 5 shard bounces (more than the single bounce of Shards III)", s.shards[0].bounces_left == 6, "left=%d" % s.shards[0].bounces_left)
	# shards + bighead, bighead + warhead
	for bl in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 1, "bighead": bl})
		throw_i(s, 0, Vector2.RIGHT, 15); tap_i(s, 0)
		check("shards+bighead L%d: shard radius x%.1f" % [bl, Mods.n("bighead", "radius_mult", bl)], absf(s.shards[0].radius - 0.12 * Mods.n("bighead", "radius_mult", bl)) < 0.001, "r=%.3f" % s.shards[0].radius)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 1}); throw_i(s, 0, Vector2.RIGHT, 15); tap_i(s, 0)
	check("shards alone: radius unchanged", absf(s.shards[0].radius - 0.12) < 0.001)
	for bl in [0, 1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); var lv_set := {"warhead": 2}
		if bl > 0: lv_set["bighead"] = bl
		setm(s, 0, lv_set)
		var rr := 0.0
		for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
		s.step(only0(inp()))
		for t in 30:
			s.step(idle4())
			for e in s.events: if e["type"] == "explosion": rr = e["radius"]
		var wantr: float = 2.4 * ([1.0, 1.15, 1.3, 1.5][bl])
		check("bighead L%d + warhead: explosion radius %.2f" % [bl, wantr], absf(rr - wantr) < 0.001, "r=%.3f" % rr)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": 1, "bighead": 3, "shards": 2}); throw_i(s, 0, Vector2.RIGHT, 15); tap_i(s, 0)
	var shard_r := 0.0
	for t in 120:
		s.step(idle4())
		for e in s.events: if e["type"] == "explosion" and (e["radius"] as float) < 2.5: shard_r = e["radius"]
	check("bighead + warhead also scales shard explosions (shards+warhead 0.8 x 1.5)", absf(shard_r - 1.2) < 0.001, "r=%.3f" % shard_r)
	# bighead + tripwire: wider trigger
	for syn_on in [false, true]:
		s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(2.0, 2.0)); setm(s, 0, {"tripwire": 1, "bighead": 2} if syn_on else {"tripwire": 1})
		throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0); many(s, 60, idle4())
		var w: SimWire = s.wires[0] if s.wires.size() > 0 else null
		s.players[1].pos = Vector2(7.0, 6.3 + 0.58); s.players[1].prev_pos = s.players[1].pos
		s.step(idle4())
		check("bighead + tripwire: victim 0.58 m beside the wire is %s" % ["stunned (wire 2x wider)" if syn_on else "not touched (tripwire alone)"], w != null and (s.players[1].stun_t > 0.0) == syn_on and (not syn_on or absf(w.half_width - 0.12) < 0.001), "stun=%.2f" % s.players[1].stun_t)
	# synergy table and list
	var lv := Mods.empty_levels(); lv["shards"] = 1; lv["warhead"] = 2; lv["bighead"] = 1
	var act := Mods.active_synergies(lv)
	check("active_synergies lists exactly the pairs where both are on", act == ["shards_warhead", "shards_bighead", "bighead_warhead"], str(act))
	check("synergy description carries its number", Mods.describe_synergy("shards_warhead", lv).contains("1.2") and Mods.describe_synergy("bighead_warhead", lv).contains("1.15"), Mods.describe_synergy("shards_warhead", lv))
	check("every synergy has a pair of known ids and a text", Mods.SYNERGY_ORDER.size() == Mods.SYNERGIES.size() and Mods.SYNERGIES.keys().all(func(k): return (Mods.SYNERGIES[k]["ids"] as Array).size() == 2 and (Mods.SYNERGIES[k]["ids"] as Array).all(func(id): return Mods.ORDER.has(id)) and (Mods.SYNERGIES[k]["desc"] as String).length() > 20))

	# ---------------- 5 String follows the bounce path
	s = two_pin_sim(2); p = s.players[0]; h = p.heads[0]
	var P0 := Vector2.ZERO; var P1 := Vector2.ZERO
	check("polyline: two pins recorded in order from the player outwards, path length 14", h.pins.size() == 2 and absf(h.pins[0].y - (BW - 0.35)) < 0.1 and absf(h.pins[1].x - (RW - 0.35)) < 0.1 and absf(Sim.path_length(s.string_path(p, h)) - 14.0) < 0.3, "pins=%s len=%.2f" % [h.pins, Sim.path_length(s.string_path(p, h))])
	if h.pins.size() == 2:
		P0 = h.pins[0]; P1 = h.pins[1]
	var path0 := s.string_path(p, h)
	# victim on the middle segment
	s.players[1].alive = true; s.players[1].pos = (P0 + P1) * 0.5; s.players[1].prev_pos = s.players[1].pos
	tap_i(s, 0)
	var order := []
	var off_path := 0.0
	var killed_on_way := false
	for t in 200:
		s.step(idle4())
		if h.state == HS.RETRACT:
			off_path = maxf(off_path, dist_to_path(h.pos, path0))
		if order.is_empty() or order[order.size() - 1] != h.pins.size(): order.append(h.pins.size())
		if h.state == HS.HAND: break
	check("polyline retract: passes the pins in reverse order (2 -> 1 -> 0), ends in hand", order == [2, 1, 0] and h.state == HS.HAND, str(order))
	check("polyline retract: head stays on the string path and is lethal on the way (victim on the path died)", off_path < 0.2 and s.players[1].deaths == 1, "off=%.2f deaths=%d" % [off_path, s.players[1].deaths])
	# pull follows the pins
	s = two_pin_sim(2); p = s.players[0]; h = p.heads[0]
	var near0 := 99.0; var near1 := 99.0
	var order2 := []
	var off2 := 0.0
	var path1 := s.string_path(p, h)
	var arr := idle4()
	for t in 200:
		arr[0] = inp(Vector2.ZERO, Vector2.ZERO, true)
		s.step(arr)
		near0 = minf(near0, p.pos.distance_to(P0)); near1 = minf(near1, p.pos.distance_to(P1))
		if p.pulling: off2 = maxf(off2, dist_to_path(p.pos, path1))
		if order2.is_empty() or order2[order2.size() - 1] != h.pins.size(): order2.append(h.pins.size())
		if h.state == HS.HAND: break
	check("polyline pull: player travels through both pins in order and catches the head", near0 < 0.35 and near1 < 0.35 and order2 == [2, 1, 0] and h.state == HS.HAND and off2 < 0.45, "n0=%.2f n1=%.2f order=%s state=%d off=%.2f" % [near0, near1, order2, h.state, off2])
	# path length respected: DRAG
	s = two_pin_sim(2); p = s.players[0]; h = p.heads[0]; s.cfg.out_variant = 0
	s.step(idle4())
	var lim := h.limit
	var worst := 0.0
	var head_start := h.pos
	for t in 100:
		s.step(only0(inp(Vector2(-1, 0))))
		worst = maxf(worst, Sim.path_length(s.string_path(p, h)) - h.limit)
	check("polyline DRAG: path never longer than allowed, head dragged along the path, pin consumed", worst < 0.02 and h.pos.distance_to(head_start) > 3.0 and h.pins.size() < 2 and absf(lim - 14.0) < 0.3, "worst=%.3f moved=%.2f pins=%d lim=%.2f" % [worst, h.pos.distance_to(head_start), h.pins.size(), lim])
	check("polyline DRAG: head moves along the segment towards its nearest pin (stays on the old path)", dist_to_path(h.pos, path0) < 0.3, "off=%.2f" % dist_to_path(h.pos, path0))
	# LEASH
	s = two_pin_sim(2); p = s.players[0]; h = p.heads[0]; s.cfg.out_variant = 1
	s.step(idle4())
	head_start = h.pos; worst = 0.0
	var pcount := h.pins.size()
	for t in 100:
		s.step(only0(inp(Vector2(-1, 0))))
		worst = maxf(worst, Sim.path_length(s.string_path(p, h)) - h.limit)
	check("polyline LEASH: path never longer than allowed, head and pins stay", worst < 0.02 and h.pos.distance_to(head_start) < 0.001 and h.pins.size() == pcount, "worst=%.3f pins=%d" % [worst, h.pins.size()])
	s = two_pin_sim(2); p = s.players[0]; h = p.heads[0]; s.cfg.out_variant = 1
	s.step(idle4())
	var mv_before := p.pos
	for t in 30: s.step(only0(inp(Vector2(1, 1).normalized())))
	check("polyline LEASH: player can still move towards the first pin", p.pos.distance_to(mv_before) > 0.5)
	# RIGID
	s = two_pin_sim(2); p = s.players[0]; h = p.heads[0]; s.cfg.out_variant = 2
	s.step(idle4())
	var pre := h.pos
	for t in 5: s.step(only0(inp(Vector2(-1, 0))))
	check("polyline RIGID: pins are dropped as soon as the player moves, head follows", h.pins.is_empty() and h.pos.distance_to(pre) > 0.3, "pins=%d" % h.pins.size())
	# pierce makes no pins
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"pierce": 2}); s.statics.append(Rect2(6, 5, 1, 3))
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("pierce creates no pins", s.players[0].heads[0].pins.is_empty())
	# steer (idle) + bounce: the retract still goes through every pin
	s = two_pin_sim(2, {"steer": 1}); p = s.players[0]; h = p.heads[0]
	var pins_before: PackedVector2Array = h.pins.duplicate()
	var poly_ab := s.string_path(p, h).duplicate()
	var off_ab := 0.0; var prefix_ok := true
	tap_i(s, 0)
	for t in 200:
		s.step(idle4())
		off_ab = maxf(off_ab, dist_to_path(h.pos, poly_ab))
		if h.pins.size() > 0 and h.pins != pins_before.slice(0, h.pins.size()): prefix_ok = false
		if h.state == HS.HAND: break
	check("steer+bounce retract consumes every recorded pin in reverse, stays on the string and comes home", pins_before.size() >= 2 and h.state == HS.HAND and prefix_ok and off_ab < 0.1, "pins=%d off=%.3f" % [pins_before.size(), off_ab])

	# ---------------- 6 Tripwire on pull and along the path
	s = two_pin_sim(2, {"tripwire": 1}); p = s.players[0]; h = p.heads[0]
	check("tripwire: no wire before a retract or pull", s.wires.is_empty())
	var pp0 := p.pos
	hold_i(s, 0, 15)
	var wpull: SimWire = s.wires[0] if s.wires.size() > 0 else null
	check("tripwire: laid when a pull starts, shaped like the string path (player, pin, pin, head)", p.pulling and wpull != null and wpull.pts.size() == 4 and wpull.pts[0].distance_to(pp0) < 0.3 and wpull.pts[1].distance_to(P0) < 0.1 and wpull.pts[2].distance_to(P1) < 0.1, "wires=%d pts=%s" % [s.wires.size(), wpull.pts if wpull else "-"])
	s.players[1].alive = true; s.players[1].pos = (P0 + P1) * 0.5 + Vector2(-0.3, 0.3).normalized() * 0.2; s.players[1].prev_pos = s.players[1].pos
	s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	check("tripwire: the middle segment of the polyline triggers", s.players[1].stun_t > 0.0 and s.wires.is_empty())
	s = two_pin_sim(2, {"tripwire": 1}); p = s.players[0]
	tap_i(s, 0)
	check("tripwire: retract wire is a polyline too", s.wires.size() == 1 and s.wires[0].pts.size() == 4, "pts=%d" % (s.wires[0].pts.size() if s.wires.size() > 0 else -1))
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"tripwire": 1}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60); hold_i(s, 0, 15)
	check("tripwire on pull without pins: straight two-point wire", s.wires.size() == 1 and s.wires[0].pts.size() == 2)

	# ---------------- 7 export of values
	var cfgx := Config.new()
	cfgx.player_speed = 7.5
	cfgx.out_variant = Config.OutVariant.LEASH
	cfgx.mods_you["bighead"] = 2
	cfgx.mods_bots["twin"] = 3
	var txt := cfgx.export_text()
	var missing := []
	for k in Config.DEFAULTS: if not txt.contains(k + "="): missing.append(k)
	for id in Mods.ORDER: if not txt.contains(id + "="): missing.append(id)
	check("export contains every config key and every modifier id", missing.is_empty(), str(missing))
	check("export marks changed values with * and leaves defaults alone", txt.contains("player_speed=7.5 *") and txt.contains("out_variant=LEASH *") and txt.contains("dash_cooldown=1.2\n") and txt.contains("bighead=2*") and txt.contains("twin=3*") and txt.contains("tripwire=0 "), txt)
	check("export is one block without blank lines", not txt.contains("\n\n") and txt.split("\n").size() == Config.DEFAULTS.size() + 3)

func _menu_tests() -> void:
	# menu: reset per page, export panel, synergy list
	var menu := TuningMenu.new()
	root.add_child(menu)
	var cfgm := Config.new()
	cfgm.player_speed = 9.0; cfgm.mods_you["shards"] = 2; cfgm.mods_you["warhead"] = 1; cfgm.mods_bots["pierce"] = 3
	menu.setup(cfgm)
	check("menu: synergy list shows the active combination for Du", menu._syn_label.text.contains("Shards + Warhead"), menu._syn_label.text)
	menu._show_page(1)
	menu._on_reset()
	check("menu: reset on the modifier page clears the levels (both) but not the values", cfgm.mods_you["shards"] == 0 and cfgm.mods_bots["pierce"] == 0 and cfgm.player_speed == 9.0)
	check("menu: synergy list is empty again after reset", menu._syn_label.text.begins_with("None"))
	cfgm.mods_you["shards"] = 1
	menu._show_page(0)
	menu._on_reset()
	check("menu: reset on the values page resets the values but not the levels", cfgm.player_speed == Config.DEFAULTS["player_speed"] and cfgm.mods_you["shards"] == 1)
	check("menu: the Training menu has no figure or Lokal page any more (they live in the Play lobby)", not ["_figure_page", "_local_page", "_tab_figure", "_tab_local"].any(func(n: String) -> bool: return menu.get_property_list().any(func(d: Dictionary) -> bool: return d["name"] == n)))
	var main_requests := [0]
	menu.main_menu_requested.connect(func() -> void: main_requests[0] += 1)
	var to_main: Button = menu.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Main menu").front()
	to_main.pressed.emit()
	check("menu: the Training menu has a Main menu button that reports it", main_requests[0] == 1)
	menu._show_page(0)
	menu._on_export()
	check("menu: export shows the text and the confirmation", menu._export_panel.visible and menu._export_text.text == cfgm.export_text() and menu._export_status.text == "Copied to the clipboard" and not menu._export_text.editable)
	menu.queue_free()
	_lobby_tests()


## The Play lobby: the mode card, and the figure choice (the preview, one button per figure, the saved choice).
func _lobby_tests() -> void:
	var lob := PlayLobby.new()
	root.add_child(lob)
	var saved := Config.new()
	saved.player_speed = 9.0   # a tuned value: the lobby must neither use nor change it
	var saves: Array = []
	var chosen: Array = []
	lob.save_fn = func(c: Config) -> void: saves.append(c.character)
	lob.figure_chosen.connect(func(i: int) -> void: chosen.append(i))
	lob.setup(saved)
	lob.open()
	check("lobby: shows the one mode card Last Standing, selected", lob.mode_card != null and lob.mode_card.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Last Standing"))
	check("lobby: the figure area has one button per figure named after it and a preview", lob.figure_buttons.size() == Config.SKIN_COUNT and lob.figure_buttons[Config.SKIN_COUNT - 1].text == ToyFigure.NAMES[Config.SKIN_COUNT - 1] and lob.figure_preview != null and lob.figure_buttons[0].button_pressed and not lob.figure_buttons[1].button_pressed)
	check("lobby: the preview shows the saved figure at the start", lob.figure_preview.figure != null and lob.figure_preview.figure.kind == 0)
	lob.figure_buttons[2].pressed.emit()
	check("lobby: pressing a figure button sets the choice, saves it and reports it", saved.character == 2 and saves == [2] and chosen == [2])
	check("lobby: only the chosen figure shows pressed", lob.figure_buttons[2].button_pressed and lob.figure_buttons.filter(func(b: Button) -> bool: return b.button_pressed).size() == 1)
	check("lobby: the preview shows the pressed figure", lob.figure_preview.figure.kind == 2)
	lob.figure_buttons[Config.SKIN_COUNT - 1].pressed.emit()
	check("lobby: ... and changes with the next button", lob.figure_preview.figure.kind == Config.SKIN_COUNT - 1 and saved.character == Config.SKIN_COUNT - 1)
	check("lobby: the figure choice leaves the tuned values alone", saved.player_speed == 9.0)
	saved.character = 1
	lob.open()
	check("lobby: opening again shows the choice of the config", lob.figure_buttons[1].button_pressed and not lob.figure_buttons[2].button_pressed and lob.figure_preview.figure.kind == 1)
	var solo: Array = []
	lob.solo_requested.connect(func() -> void: solo.append(true))
	lob.solo_btn.pressed.emit()
	check("lobby: Go starts a solo game", solo.size() == 1 and lob.solo_btn.text == "Go")
	var backs: Array = []
	lob.back_pressed.connect(func() -> void: backs.append(true))
	lob.back_btn.pressed.emit()
	check("lobby: Back reports", backs.size() == 1)
	lob.queue_free()


# ---------------------------------------------------------------- string = flight path
# charge + release of player `i`, then the aim stick `stick` is held for `hold` ticks while the head flies, then
# released. Returns where the head was when it landed.
func steer_i(s: Sim, i: int, dir: Vector2, charge_ticks: int, stick: Vector2, hold := 999) -> Vector2:
	var arr := idle4()
	for t in charge_ticks:
		arr[i] = inp(Vector2.ZERO, dir, true)
		s.step(arr)
	arr[i] = inp()
	s.step(arr)
	var n := 0
	var h: SimHead = s.players[i].heads[0]
	while n < 200 and h.state == HS.FLIGHT:
		arr[i] = inp(Vector2.ZERO, stick, n < hold)
		s.step(arr)
		n += 1
	var end := h.pos
	s.step(idle4())
	return end

# hold the aim stick (deflected) for n ticks
func aim_hold(s: Sim, i: int, stick: Vector2, n: int) -> void:
	var arr := idle4()
	for t in n:
		arr[i] = inp(Vector2.ZERO, stick, true)
		s.step(arr)

func steer_sim(L: int, extra := {}) -> Sim:
	var s := mk([0, 1])
	place(s, 0, Vector2(3, 3.0)); place(s, 1, Vector2(30, 13))
	setm(s, 0, {"steer": L} if L > 0 else {})
	s.players[0].mods.merge(extra)
	return s

func _steer_tests() -> void:
	var s: Sim
	var p: SimPlayer
	var h: SimHead
	var DOWN := Vector2(0, 1)
	var end0 := Vector2.ZERO
	# --- without the modifier the stick changes nothing in flight
	s = steer_sim(0); h = s.players[0].heads[0]
	var e := steer_i(s, 0, Vector2.RIGHT, 60, DOWN)
	check("steer L0: the stick during flight does not bend it (straight, lands at 8 m)", absf(e.y - 3.0) < 0.001 and absf(e.x - 11.0) < 0.05, "end=%s" % e)
	# --- L1
	s = steer_sim(1); h = s.players[0].heads[0]; p = s.players[0]
	end0 = steer_i(steer_sim(1), 0, Vector2.RIGHT, 60, Vector2.ZERO)
	e = steer_i(s, 0, Vector2.RIGHT, 60, DOWN)
	check("steer L1: no stick = straight throw to 8 m", absf(end0.y - 3.0) < 0.001 and absf(end0.x - 11.0) < 0.05, "end=%s" % end0)
	check("steer L1: the head ends off the straight line, towards the stick side", e.y > end0.y + 2.0 and e.x < end0.x - 1.0, "end=%s straight=%s" % [e, end0])
	check("steer L1: the head still flies the charged distance (8 m of path), string lies on the bend", absf(h.flown - 8.0) < 0.05 and absf(Sim.path_length(s.string_path(p, h)) - 8.0) < 0.4 and h.pins.size() >= 5, "flown=%.2f path=%.2f pins=%d" % [h.flown, Sim.path_length(s.string_path(p, h)), h.pins.size()])
	e = steer_i(steer_sim(1), 0, Vector2.RIGHT, 60, Vector2(0, -1))
	check("steer L1: the other stick side steers the other way", e.y < 3.0 - 2.0, "end=%s" % e)
	e = steer_i(steer_sim(1), 0, Vector2.RIGHT, 60, DOWN * 0.2)
	check("steer L1: a stick inside the dead zone does not steer", absf(e.y - 3.0) < 0.001, "end=%s" % e)
	s = steer_sim(1); p = s.players[0]; h = p.heads[0]
	steer_i(s, 0, Vector2.RIGHT, 60, DOWN)
	many(s, 60, idle4())
	check("steer L1: a deflected touch during flight does not retract or pull", h.state == HS.OUT and not h.queued_retract and not p.pulling)
	s = steer_sim(1); p = s.players[0]; h = p.heads[0]
	steer_i(s, 0, Vector2.RIGHT, 60, DOWN, 3)
	many(s, 60, idle4())
	check("steer L1: a short deflected touch (shorter than a tap) does not retract either", h.state == HS.OUT and not p.pulling)
	s = steer_sim(1); p = s.players[0]; h = p.heads[0]
	var arr := idle4()
	for t in 60: arr[0] = inp(Vector2.ZERO, Vector2.RIGHT, true); s.step(arr)
	s.step(idle4())
	for t in 3: arr[0] = inp(Vector2.ZERO, Vector2.ZERO, true); s.step(arr)
	s.step(idle4())
	many(s, 90, idle4())
	check("steer L1: a plain tap during flight still retracts the head", h.state == HS.HAND, "state=%d" % h.state)
	s = steer_sim(1); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0)
	check("steer L1: a tap on a lying head still retracts it", h.state == HS.RETRACT or h.state == HS.HAND)
	s = steer_sim(1); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60); hold_i(s, 0, 20)
	check("steer L1: holding without deflection still pulls to the lying head", p.pulling and p.pos.x > 3.5, "x=%.2f" % p.pos.x)
	# --- L2
	e = steer_i(steer_sim(1), 0, Vector2.RIGHT, 60, Vector2.ZERO)
	var e2 := steer_i(steer_sim(2), 0, Vector2.RIGHT, 60, Vector2.ZERO)
	check("steer L2: flies 25 % farther (10 m instead of 8 m)", absf(e.x - 11.0) < 0.05 and absf(e2.x - 13.0) < 0.05, "L1 x=%.2f L2 x=%.2f" % [e.x, e2.x])
	s = steer_sim(2, {"pierce": 2})
	e = steer_i(s, 0, Vector2.RIGHT, 60, Vector2.ZERO)
	check("steer L2 and pierce L2: the ranges multiply (8 * 1.25 * 1.2 = 12 m)", absf(e.x - 15.0) < 0.1, "x=%.2f" % e.x)
	var d1 := steer_sim(1); var d2 := steer_sim(2)
	steer_i(d1, 0, Vector2.RIGHT, 60, DOWN, 5); steer_i(d2, 0, Vector2.RIGHT, 60, DOWN, 5)
	var a1 := absf(d1.players[0].heads[0].throw_dir.angle()); var a2 := absf(d2.players[0].heads[0].throw_dir.angle())
	check("steer L2 turns harder than L1", a2 > a1 + 0.2 and a1 > 0.3, "L1 %.2f rad, L2 %.2f rad" % [a1, a2])
	# --- Twin with a head in hand: the stick charges the next throw, the flying head is not steered
	s = steer_sim(1, {"twin": 1}); p = s.players[0]
	arr = idle4()
	for t in 60: arr[0] = inp(Vector2.ZERO, Vector2.RIGHT, true); s.step(arr)
	s.step(idle4())
	for t in 4: arr[0] = inp(Vector2.ZERO, DOWN, true); s.step(arr)
	check("steer + twin with a head in hand: the stick charges the next throw, the flying head stays straight", p.charging and p.heads[0].state == HS.FLIGHT and absf(p.heads[0].pos.y - 3.0) < 0.001, "y=%.3f charging=%s" % [p.heads[0].pos.y, p.charging])
	# --- L3 telekinesis (a half charge leaves slack in the string: 9 m string, about 5.5 m thrown)
	var home := Vector2(11, 3.0)
	s = steer_sim(3); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 15)
	home = h.pos
	check("steer L3: a half charge lies OUT with slack in the string", h.state == HS.OUT and home.x - 3.0 > 4.0 and home.x - 3.0 < 6.5, "home=%s" % home)
	aim_hold(s, 0, DOWN, 6)
	check("steer L3: the stick moves a lying head at tk_speed (12 m/s, 6 ticks = 1.2 m)", h.state == HS.OUT and absf(h.pos.y - (home.y + 1.2)) < 0.05 and absf(h.pos.x - home.x) < 0.01, "pos=%s home=%s" % [h.pos, home])
	check("steer L3: the string gets a pin at the corner", h.pins.size() == 1 and h.pins[0].distance_to(home) < 0.01, "pins=%s" % [h.pins])
	aim_hold(s, 0, Vector2(0, -1), 6)
	check("steer L3: moving back onto the corner winds the pin up again", h.pins.is_empty() and h.pos.distance_to(home) < 0.2, "pins=%d pos=%s" % [h.pins.size(), h.pos])
	var y_before := h.pos.y
	aim_hold(s, 0, DOWN * 0.5, 6)
	check("steer L3: half stick = half speed", absf(h.pos.y - y_before - 0.6) < 0.05, "dy=%.2f" % (h.pos.y - y_before))
	for variant in 3:
		s = steer_sim(3); p = s.players[0]; h = p.heads[0]; s.cfg.out_variant = variant
		throw_i(s, 0, Vector2.RIGHT, 15); home = h.pos
		aim_hold(s, 0, Vector2(1, 1), 150)
		var plen := Sim.path_length(s.string_path(p, h))
		check("steer L3 (out variant %d): never more string than the limit (the player is not dragged), and the head did move" % variant, plen <= h.limit + 0.02 and plen > s.cfg.string_length - 0.3 and p.pos.distance_to(Vector2(3, 3.0)) < 0.001 and h.limit <= s.cfg.string_length + 0.001 and h.pos.distance_to(home) > 0.5 and h.pins.size() <= Mods.MAX_PATH_PINS and not p.pulling, "len=%.2f limit=%.2f pins=%d" % [plen, h.limit, h.pins.size()])
	check("steer L3: a deflected hold never starts a pull", not p.pulling and h.state == HS.OUT)
	s = steer_sim(3); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 15); home = h.pos
	s.statics.append(Rect2(home.x - 1.0, 4.5, 2.0, 2.0))
	aim_hold(s, 0, DOWN, 60)
	check("steer L3: a block stops the moved head", absf(h.pos.y - (4.5 - 0.35)) < 0.05 and h.state == HS.OUT, "pos=%s" % h.pos)
	s = steer_sim(3, {"pierce": 1}); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 15); home = h.pos
	s.statics.append(Rect2(home.x - 1.0, 3.8, 2.0, 0.6))
	aim_hold(s, 0, DOWN, 30)
	check("steer L3 with pierce: the moved head passes blocks", h.pos.y > 5.0, "pos=%s" % h.pos)
	s = steer_sim(3); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 15); home = h.pos
	place(s, 1, Vector2(home.x, 5.0))
	many(s, 30, idle4())
	var calm := s.players[1].deaths == 0
	aim_hold(s, 0, DOWN, 30)
	check("steer L3: a head moved into an enemy kills; the lying head did not", calm and s.players[1].deaths == 1 and p.kills == 1, "calm=%s deaths=%d" % [calm, s.players[1].deaths])
	s = steer_sim(3); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 15)
	aim_hold(s, 0, DOWN, 10)
	s.step(idle4())
	var rest := h.pos
	many(s, 40, idle4())
	check("steer L3: letting go leaves the head where it is (OUT, no retract, no throw)", h.state == HS.OUT and h.pos == rest and not p.pulling and not p.charging)
	s = steer_sim(3); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 60); hold_i(s, 0, 20)
	check("steer L3: holding without deflection still pulls to the head", p.pulling and p.pos.x > 3.5, "x=%.2f" % p.pos.x)
	s = steer_sim(3); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0)
	check("steer L3: a tap still retracts", h.state == HS.RETRACT or h.state == HS.HAND)
	s = steer_sim(2); p = s.players[0]; h = p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, 60); home = h.pos
	aim_hold(s, 0, DOWN, 20)
	check("steer L2: no telekinesis, the lying head stays", h.pos == home)
	e = steer_i(steer_sim(3), 0, Vector2.RIGHT, 60, DOWN)
	check("steer L3: in flight the head turns almost at once towards the stick", e.y > 9.0 and e.x < 5.5, "end=%s" % e)
	# the stick is the same press: TK after a steered flight
	s = steer_sim(3); p = s.players[0]; h = p.heads[0]
	arr = idle4()
	for t in 60: arr[0] = inp(Vector2.ZERO, Vector2.RIGHT, true); s.step(arr)
	s.step(idle4())
	for t in 80: arr[0] = inp(Vector2.ZERO, DOWN, true); s.step(arr)
	check("steer L3: one long touch steers the flight, then moves the landed head", h.state == HS.OUT and h.pos.y > 8.0 and not p.pulling, "pos=%s state=%d" % [h.pos, h.state])


func curved_sim(L: int, pos := Vector2(3, 3.0), extra := {}, stick := Vector2(0, 1)) -> Sim:
	var s := mk([0, 1])
	place(s, 0, pos); place(s, 1, Vector2(1, 1))
	s.players[1].alive = false; s.players[1].respawn_t = 9999.0
	var m := {"steer": L}
	m.merge(extra)
	setm(s, 0, m)
	steer_i(s, 0, Vector2.RIGHT, 60, stick)
	return s

func _path_tests() -> void:
	for L in [1, 2]:
		var s := curved_sim(L); var p := s.players[0]; var h := p.heads[0]
		var line_dev := 0.0
		var gaps: Array = []
		var prev := Vector2(3, 3.0)
		for q in h.pins:
			line_dev = maxf(line_dev, absf(q.y - 3.0))
			gaps.append(prev.distance_to(q)); prev = q
		var gmin: float = gaps.min() if gaps.size() > 0 else 0.0
		var gmax: float = gaps.max() if gaps.size() > 0 else 0.0
		check("steered throw L%d leaves pins on the bend, ~0.7 m apart" % L, h.state == HS.OUT and h.pins.size() >= 4 and line_dev > 1.5 and gmin > 0.5 and gmax < 0.95, "pins=%d dev=%.2f gaps=%.2f..%.2f" % [h.pins.size(), line_dev, gmin, gmax])
		var sp := s.string_path(p, h)
		check("steered throw L%d: string/wire path is curved (longer than the chord, off the straight line)" % L, Sim.path_length(sp) > 8.0 * (1.25 if L == 2 else 1.0) - 0.5 and Sim.path_length(sp) < 8.0 * (1.25 if L == 2 else 1.0) + 0.05 and sp.size() == h.pins.size() + 2, "len=%.2f" % Sim.path_length(sp))
		# tripwire follows the curve
		var s2 := curved_sim(L, Vector2(3, 3.0), {"tripwire": 1}); tap_i(s2, 0)
		check("steered throw L%d: tripwire is laid along the curve" % L, s2.wires.size() == 1 and s2.wires[0].pts.size() >= 6, "pts=%d" % (s2.wires[0].pts.size() if s2.wires.size() > 0 else -1))
		# retract along the polyline at constant speed
		var poly: PackedVector2Array = sp.duplicate()
		var pins0: PackedVector2Array = h.pins.duplicate()
		var step_want: float = 22.0 / 60.0
		var worst_off := 0.0; var worst_speed := 1.0; var best_speed := 0.0
		var order_ok := true; var ticks := 0
		tap_i(s, 0)
		var before := h.pos
		for t in 300:
			s.step(idle4())
			if h.state != HS.RETRACT: break
			ticks += 1
			worst_off = maxf(worst_off, dist_to_path(h.pos, poly))
			var mvd := h.pos.distance_to(before); before = h.pos
			if h.pins.size() > 0:
				worst_speed = minf(worst_speed, mvd / step_want); best_speed = maxf(best_speed, mvd / step_want)
			if h.pins.size() > 0 and h.pins != pins0.slice(0, h.pins.size()): order_ok = false
		check("retract L%d after a steered throw: stays on the polyline, passes pins in reverse, constant speed" % L, h.state == HS.HAND and worst_off < 0.1 and order_ok and ticks > 20 and worst_speed > 0.97 and best_speed < 1.0001, "off=%.3f speed=%.3f..%.3f order=%s" % [worst_off, worst_speed, best_speed, order_ok])
		# pull along the curve
		s = curved_sim(L); p = s.players[0]; h = p.heads[0]
		poly = s.string_path(p, h).duplicate()
		var pull_speed: float = s.cfg.pull_speed / 60.0
		var off := 0.0; var wspeed := 1.0; var bspeed := 0.0; var pb := p.pos; var pulled := false
		var arr := idle4(); var was_pull := false
		for t in 200:
			arr[0] = inp(Vector2.ZERO, Vector2.ZERO, true)
			s.step(arr)
			if p.pulling and was_pull:
				pulled = true
				off = maxf(off, dist_to_path(p.pos, poly))
				var mvd2 := p.pos.distance_to(pb)
				if h.pins.size() > 0:
					wspeed = minf(wspeed, mvd2 / pull_speed); bspeed = maxf(bspeed, mvd2 / pull_speed)
			pb = p.pos
			was_pull = p.pulling
			if h.state == HS.HAND: break
		check("pull L%d after a steered throw: player follows the curve at constant speed and catches the head" % L, pulled and h.state == HS.HAND and off < 0.2 and wspeed > 0.95 and bspeed < 1.0001, "off=%.3f speed=%.3f..%.3f" % [off, wspeed, bspeed])

	# steer + bounce records both parts
	var s3 := curved_sim(2, Vector2(RW - 7.0, 3.0), {"bounce": 1}, Vector2(1, 1)); var p3 := s3.players[0]; var h3 := p3.heads[0]
	var bend_pins := 0
	for k in h3.pins.size():
		if h3.pins[k].distance_to(Vector2(RW - 0.35, h3.pins[k].y)) > 0.3 and h3.pins[k].y < BW - 0.7: bend_pins += 1
	check("steer + bounce: pins on the bend before the bounce, and the bounce point itself", h3.bounces == 1 and bend_pins >= 2 and h3.pins.size() >= 3, "pins=%d bend=%d b=%d head=%s" % [h3.pins.size(), bend_pins, h3.bounces, h3.pos])
	var poly3 := s3.string_path(p3, h3).duplicate()
	tap_i(s3, 0)
	var off3 := 0.0
	for t in 300:
		s3.step(idle4())
		off3 = maxf(off3, dist_to_path(h3.pos, poly3))
		if h3.state == HS.HAND: break
	check("steer + bounce: retract follows the bend and the straight part back home", h3.state == HS.HAND and off3 < 0.1, "off=%.3f" % off3)

	# DRAG / LEASH / RIGID with a steered string
	for v in 3:
		var s4 := curved_sim(2, Vector2(14, 3.0)); var p4 := s4.players[0]; var h4 := p4.heads[0]
		s4.cfg.out_variant = v
		s4.step(idle4())
		var head0 := h4.pos; var npins := h4.pins.size()
		var worst := 0.0
		for t in 120:
			s4.step(only0(inp(Vector2(-1, 0))))
			worst = maxf(worst, Sim.path_length(s4.string_path(p4, h4)) - h4.limit)
		match v:
			0: check("steered string DRAG: path never longer than allowed, head dragged back along the curve", worst < 0.02 and h4.pos.distance_to(head0) > 2.0 and h4.pins.size() < npins and not is_nan(h4.pos.x), "worst=%.3f moved=%.2f pins %d->%d" % [worst, h4.pos.distance_to(head0), npins, h4.pins.size()])
			1: check("steered string LEASH: path never longer than allowed, head and pins stay", worst < 0.02 and h4.pos.distance_to(head0) < 0.001 and h4.pins.size() == npins, "worst=%.3f" % worst)
			2: check("steered string RIGID: pins dropped when the player moves, head follows", worst < 0.02 and h4.pins.is_empty() and h4.pos.distance_to(head0) > 2.0, "worst=%.3f pins=%d" % [worst, h4.pins.size()])


# ---------------------------------------------------------------- toy train

func car_pos(s: Sim, k: int) -> Vector2:
	return TrainTrack.point(TrainTrack.car_s(s.train_s, k))

func train_sim(only: Array, speed := Config.DEFAULTS["train_speed"]) -> Sim:
	var s := mk(only)
	s.cfg.train_speed = speed
	return s

## Steps until player `i` is dead (at most n ticks); returns the kill events seen on the way.
func run_until_dead(s: Sim, i: int, n: int) -> Array:
	var kills := []
	for _t in n:
		s.step(idle4())
		for e: Dictionary in s.events:
			if e["type"] == "kill":
				kills.append(e)
		if not s.players[i].alive:
			break
	return kills

func rect_dist(q: Vector2, r: Rect2) -> float:
	return q.distance_to(Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y)))

func _train_tests() -> void:
	var dt := 1.0 / 60.0
	var spd: float = Config.DEFAULTS["train_speed"]
	var xm := TrainTrack.CENTER.x   # on the straight piece of the long sides
	var s := train_sim([0])
	place(s, 0, Vector2(2, 2))
	s.step(idle4())
	check("train: advances by speed * dt per tick and remembers the step before", is_equal_approx(s.train_s, spd * dt) and is_equal_approx(s.prev_train_s, 0.0), "s=%f prev=%f" % [s.train_s, s.prev_train_s])
	s.train_s = TrainTrack.LENGTH - 0.01
	s.prev_train_s = s.train_s - spd * dt
	s.step(idle4())
	check("train: wraps at the loop length and prev / current stay one step apart", s.train_s < 0.2 and is_equal_approx(s.train_s - s.prev_train_s, spd * dt) and is_equal_approx(s.train_s, spd * dt - 0.01), "s=%f prev=%f" % [s.train_s, s.prev_train_s])
	s.cfg.train_speed = 10.0
	s.step(idle4())
	check("train: the speed is read every tick (tuning slider)", is_equal_approx(s.train_s - s.prev_train_s, 10.0 * dt))
	check("train: default speed is 5.7 m/s and the tuning page has a slider for it", Config.DEFAULTS["train_speed"] == 5.7 and (func() -> bool:
		for d: Array in TuningMenu.SLIDERS:
			if d[0] == "train_speed" and d[1] == "Train speed" and d[2] == 0.0 and d[3] == 10.0:
				return true
		return false).call())

	# speed 0: nothing moves, nobody is run over (player right on a car)
	s = train_sim([0], 0.0)
	place(s, 0, TrainTrack.point(0.0))
	s.crate_pos = TrainTrack.point(12.0)
	var crate0 := s.crate_pos
	run(s, 120, func(_t: int) -> Array: return idle4())
	check("train: speed 0 freezes it, kills nobody and moves no crate", s.train_s == 0.0 and s.prev_train_s == 0.0 and s.players[0].alive and s.players[0].deaths == 0 and s.crate_pos == crate0)

	# a player standing on the rails
	s = train_sim([0, 1])
	place(s, 0, TrainTrack.point(3.0)); place(s, 1, Vector2(2, 10))
	var ev := run_until_dead(s, 0, 120)
	var e0: Dictionary = ev[0] if ev.size() == 1 else {}
	check("train: runs a player over (death +1, no kill for anybody)", not s.players[0].alive and s.players[0].deaths == 1 and s.players[0].kills == 0 and s.players[1].kills == 0 and s.players[1].deaths == 0 and s.players[1].alive)
	check("train: kill event has victim, killer -1 and cause train", e0.get("type") == "kill" and e0.get("victim") == 0 and e0.get("killer") == -1 and e0.get("cause") == "train" and e0.has("pos"), str(ev))
	check("train: the victim respawns later like after any kill", (func() -> bool:
		run(s, 120, func(_t: int) -> Array: return idle4())
		return s.players[0].alive).call())
	# the whole train is deadly, not only the locomotive
	s = train_sim([0, 1])
	s.train_s = 0.0
	place(s, 0, TrainTrack.point(-2.0 * TrainTrack.CAR_GAP + 0.1)); place(s, 1, Vector2(2, 10))
	ev = run_until_dead(s, 0, 120)
	check("train: the last car kills too (a player sitting on it, the others are farther away)", not s.players[0].alive and s.players[0].deaths == 1)

	# just outside / just inside the hit distance (straight piece: the train runs along the top side)
	var reach := TrainTrack.CAR_RADIUS + s.cfg.player_radius * Config.TRAIN_HIT_SHARE
	var line_y := TrainTrack.point(0.0).y
	s = train_sim([0])
	place(s, 0, Vector2(xm, line_y + reach + 0.05))
	run(s, 150, func(_t: int) -> Array: return idle4())
	check("train: a player just outside the hit distance survives the whole train", s.players[0].alive and s.players[0].deaths == 0 and s.train_s > 5.0)
	s = train_sim([0])
	place(s, 0, Vector2(xm, line_y + reach - 0.05))
	run_until_dead(s, 0, 150)
	check("train: a player just inside the hit distance is run over", not s.players[0].alive)
	s = train_sim([0])
	s.players[0].enabled = false
	place(s, 0, TrainTrack.point(2.0))
	run(s, 60, func(_t: int) -> Array: return idle4())
	check("train: a disabled player is not touched", s.players[0].deaths == 0)

	# the dash across the rails is judged on the positions of the same tick
	s = train_sim([0])
	place(s, 0, Vector2(xm, line_y + 2.5)); s.train_s = xm - TrainTrack.point(0.0).x - 0.3
	s.prev_train_s = s.train_s
	s.step(only0(inp(Vector2(0, -1), Vector2.ZERO, false, true)))
	for _t in 15:
		s.step(only0(inp(Vector2(0, -1))))
		if not s.players[0].alive: break
	check("train: a player dashing in front of the locomotive is run over", not s.players[0].alive or s.players[0].deaths == 1)

	# the crate
	s = train_sim([0])
	place(s, 0, Vector2(2, 2))
	s.crate_pos = Vector2(xm, line_y); s.prev_crate_pos = s.crate_pos
	var overlap := false
	var moved := false
	for _t in 450:
		s.step(idle4())
		if s.crate_pos.distance_to(Vector2(xm, line_y)) > 0.5: moved = true
		for k in TrainTrack.CARS:
			if Collide.push_out_rect(car_pos(s, k), TrainTrack.CAR_RADIUS, s.crate_rect()).length() > 0.02:
				overlap = true
	check("train: the crate is pushed off the track and never overlaps a car (a whole lap)", moved and not overlap, "moved=%s overlap=%s crate=%s" % [moved, overlap, s.crate_pos])

	# yo-yo heads: the cars are solid for them (like the crate)
	var cs0 := xm - TrainTrack.point(0.0).x      # train_s that puts the locomotive at x = xm on the top side
	var thrown := {}
	for variant in ["off", "on", "bounce", "pierce2"]:
		s = train_sim([0], 0.0 if variant == "off" else 0.001)
		s.train_s = cs0; s.prev_train_s = cs0
		place(s, 0, Vector2(xm, line_y + 5.0))
		if variant == "bounce": setm(s, 0, {"bounce": 1})
		if variant == "pierce2": setm(s, 0, {"pierce": 2})
		throw_i(s, 0, Vector2.UP, 60)
		thrown[variant] = [s.players[0].heads[0].pos.y, s.players[0].heads[0].bounces, s.players[0].heads[0].state]
	var hr0 := s.head_r(s.players[0])
	check("train: without the train a thrown head flies past the spot of the locomotive", thrown["off"][0] < line_y - 0.5, str(thrown))
	check("train: a head thrown at a car lands in front of it", thrown["on"][2] == HS.OUT and thrown["on"][0] > line_y + TrainTrack.CAR_RADIUS + hr0 - 0.05 and thrown["on"][0] < line_y + TrainTrack.CAR_RADIUS + hr0 + 0.3, str(thrown))
	check("train: with the bounce modifier the head ricochets off a car", thrown["bounce"][1] == 1 and thrown["bounce"][0] > line_y, str(thrown))
	check("train: a head with pierce level 2 passes the cars like the crate", thrown["pierce2"][0] < line_y - 0.5, str(thrown))

	# a head lying on the rails is shoved out of the way when a car arrives (and never overlaps a car afterwards)
	s = train_sim([0])
	place(s, 0, Vector2(2, line_y))
	var h := s.players[0].heads[0]
	h.state = HS.OUT; h.pos = Vector2(xm, line_y); h.prev_pos = h.pos
	s.train_s = cs0 - 2.0; s.prev_train_s = s.train_s
	var start_h := h.pos
	var overlap_h := false
	for _t in 40:
		s.step(idle4())
		for k in TrainTrack.CARS:
			if h.pos.distance_to(car_pos(s, k)) < TrainTrack.CAR_RADIUS + s.head_r(s.players[0]) - 0.01:
				overlap_h = true
	check("train: a head lying on the track is shoved aside by the cars and stays OUT", h.state == HS.OUT and h.pos.distance_to(start_h) > 0.5 and not overlap_h and s.players[0].alive, "pos=%s overlap=%s" % [h.pos, overlap_h])
	s = train_sim([0])
	place(s, 0, Vector2(2, line_y))
	h = s.players[0].heads[0]
	h.state = HS.OUT; h.pos = Vector2(xm, line_y); h.prev_pos = h.pos
	var shove_blk := Rect2(xm + 0.5, line_y - 1.0, 1.0, 2.0)
	s.statics.append(shove_blk)
	s.train_s = cs0 - 1.5; s.prev_train_s = s.train_s
	var in_block := false
	for _t in 40:
		s.step(idle4())
		if Collide.push_out_rect(h.pos, s.head_r(s.players[0]), shove_blk).length() > 0.02: in_block = true
	check("train: a head shoved by a car is stopped by a block (never pushed into it)", not in_block and h.state == HS.OUT, "pos=%s" % h.pos)
	s = train_sim([0], 0.0)
	place(s, 0, Vector2(2, line_y))
	h = s.players[0].heads[0]
	h.state = HS.OUT; h.pos = Vector2(xm, line_y); h.prev_pos = h.pos
	s.train_s = cs0; s.prev_train_s = cs0
	run(s, 30, func(_t: int) -> Array: return idle4())
	check("train: speed 0 leaves a lying head alone", h.state == HS.OUT and h.pos == Vector2(xm, line_y))

	# a retracting head with a car between it and the player lies down
	s = train_sim([0], 0.0)
	place(s, 0, Vector2(xm, line_y + 5.0))
	throw_i(s, 0, Vector2.UP, 60)
	var p := s.players[0]
	s.cfg.train_speed = 0.001
	s.train_s = cs0; s.prev_train_s = cs0
	for _t in 5: s.step(only0(inp(Vector2.ZERO, Vector2.ZERO, true)))
	s.step(only0(inp()))
	var out_again := false
	for _t in 120:
		s.step(idle4())
		if p.ystate == Y.OUT: out_again = true; break
	check("train: a retracting head blocked by a car ends OUT behind it", out_again and p.head.y < line_y, "state=%d head=%s" % [p.ystate, p.head])

	# respawn: never into a car. Big players make several spawn points unsafe for a car standing near them.
	var bad := 0
	var checked := 0
	var unsafe_spawns := 0
	for seed_i in 60:
		s = train_sim([0])
		s.cfg.player_radius = 4.0
		s.rng.seed = seed_i + 1
		s.players[0].alive = false; s.players[0].respawn_t = 0.0
		s.train_s = 0.0; s.prev_train_s = 0.0
		for sp in Config.SPAWNS:
			if s.train_unsafe(sp):
				unsafe_spawns += 1
		var cars: Array[Vector2] = []
		for k in TrainTrack.CARS: cars.append(car_pos(s, k))
		s.step(idle4())
		var rp := Vector2.INF
		for e: Dictionary in s.events:
			if e["type"] == "respawn": rp = e["pos"]
		var r_reach := TrainTrack.CAR_RADIUS + 4.0 * Config.TRAIN_HIT_SHARE
		checked += 1
		for c in cars:
			if rp == Vector2.INF or rp.distance_to(c) < r_reach: bad += 1
	check("train: no respawn inside a car's hit distance (60 seeds, a spawn point made unsafe)", checked == 60 and bad == 0 and unsafe_spawns > 0, "bad=%d unsafe=%d" % [bad, unsafe_spawns])

	# a bot standing on the rails ahead of the train gets out of the way
	var all_alive := true
	for bs in 6:
		s = train_sim([0])
		place(s, 0, TrainTrack.point(3.0 + bs * 0.4))
		var b := Bot.new(0, s.cfg, 40 + bs)
		var fell := false
		for _t in 900:
			s.step([b.think(s, dt), inp(), inp(), inp()])
			if not s.players[0].alive: fell = true; break
		if fell or s.players[0].deaths > 0: all_alive = false
	check("train: a bot on the rails ahead of the train steps aside and survives two laps (6 starts)", all_alive)

	# a bot never dashes while a car is within the avoidance distance plus its dash distance
	var near_ticks := 0
	var near_dashes := 0
	for bs in 12:
		s = train_sim([0], 0.001)
		place(s, 0, car_pos(s, 0) + Vector2(0, 3.0 + s.cfg.dash_distance * 0.5))
		var b2 := Bot.new(0, s.cfg, 90 + bs)
		for _t in 600:
			var near := false
			for k in TrainTrack.CARS:
				near = near or s.players[0].pos.distance_to(car_pos(s, k)) < Config.BOT_TRAIN_AVOID_DIST + s.cfg.dash_distance
			var bi := b2.think(s, dt)
			if near:
				near_ticks += 1
				if bi.dash:
					near_dashes += 1
			s.step([bi, inp(), inp(), inp()])
	check("train: a bot does not dash while a car is near enough for the dash to reach it", near_ticks > 1000 and near_dashes == 0, "near=%d dashes=%d" % [near_ticks, near_dashes])

	# snapshot round trip
	s = train_sim([0])
	s.train_s = 7.3; s.prev_train_s = 7.3 - spd * dt
	var s2 := train_sim([0])
	s2.load_state(s.save_state())
	check("train: save_state / load_state carry the position", s2.train_s == 7.3 and is_equal_approx(s2.prev_train_s, 7.3 - spd * dt))
	var back: Dictionary = bytes_to_var(var_to_bytes(s.save_state()))
	check("train: the state survives var_to_bytes", back["train_s"] == 7.3 and back.has("prev_train_s"))

	# geometry: the rails keep clear of obstacles and walls, the spawn points keep clear of the rails
	var min_obst := 1e9
	var min_wall := 1e9
	var min_spawn := 1e9
	var n := int(TrainTrack.LENGTH / 0.02)
	for i in n:
		var q := TrainTrack.point(i * 0.02)
		for o in Config.OBSTACLES:
			min_obst = minf(min_obst, rect_dist(q, o))
		min_wall = minf(min_wall, minf(minf(q.x, Config.ARENA_SIZE.x - q.x), minf(q.y, Config.ARENA_SIZE.y - q.y)))
		for sp in Config.SPAWNS:
			min_spawn = minf(min_spawn, q.distance_to(sp))
	check("train: every point of the track is at least a car radius from every obstacle", min_obst >= TrainTrack.CAR_RADIUS, "min=%.3f" % min_obst)
	check("train: every point of the track is at least a car radius from the outer walls", min_wall >= TrainTrack.CAR_RADIUS, "min=%.3f" % min_wall)
	check("train: all spawn points are farther from the track than the hit distance plus the spawn noise", min_spawn > reach + Config.SPAWN_NOISE, "min=%.3f need>%.3f" % [min_spawn, reach + Config.SPAWN_NOISE])
	check("train: a loop is closed (the point after one length is the start)", TrainTrack.point(TrainTrack.LENGTH).distance_to(TrainTrack.point(0.0)) < 1e-4)

	# a player of the default size fits between the centre block and the rails without being hit (all four sides)
	var rr: float = s.cfg.player_radius
	var blk: Rect2 = Config.OBSTACLES[0]
	var gaps := [
		Vector2(xm, ((TrainTrack.CENTER.y - TrainTrack.HALF.y) + reach + blk.position.y - rr) * 0.5),
		Vector2(xm, ((TrainTrack.CENTER.y + TrainTrack.HALF.y) - reach + blk.end.y + rr) * 0.5),
		Vector2(((TrainTrack.CENTER.x - TrainTrack.HALF.x) + reach + blk.position.x - rr) * 0.5, TrainTrack.CENTER.y),
		Vector2(((TrainTrack.CENTER.x + TrainTrack.HALF.x) - reach + blk.end.x + rr) * 0.5, TrainTrack.CENTER.y),
	]
	var gap_ok := true
	for g: Vector2 in gaps:
		var near := 1e9
		for i in n:
			near = minf(near, TrainTrack.point(i * 0.02).distance_to(g))
		gap_ok = gap_ok and near > reach and rect_dist(g, blk) >= rr
	check("train: a default-size player fits between the centre block and the rails on every side without being hit", gap_ok)
	s = train_sim([0], Config.DEFAULTS["train_speed"])
	s.statics.resize(s.wall_count)
	place(s, 0, gaps[0])
	run(s, int(TrainTrack.LENGTH / spd * 60.0) + 60, func(_t: int) -> Array: return idle4())
	check("train: a player standing in the gap above the centre block survives a whole lap", s.players[0].alive and s.players[0].deaths == 0 and s.train_s > 0.0)


# ================================================================ walking over your own lying yo-yo

func _count_events(evs: Array, type: String) -> int:
	var n := 0
	for e in evs:
		if e["type"] == type:
			n += 1
	return n

func _pickup_tests() -> void:
	# Throw, let it land, walk to it without pressing anything: back in hand, one event, can throw again.
	var s := mk([0]); place(s, 0, Vector2(3, 6.3))
	throw_i(s, 0, Vector2.RIGHT, 40)
	var p := s.players[0]
	var h := p.heads[0]
	check("pickup: head lies out after the throw", h.state == HS.OUT)
	var catch_d := s.cfg.player_radius + s.head_r(p) + Config.CATCH_MARGIN
	var evs := []
	var shards_seen := 0
	for t in 200:
		s.step(only0(inp(Vector2.RIGHT)))
		evs.append_array(s.events)
		if h.state != HS.OUT: break
	check("pickup: walking onto the lying head puts it back in hand", h.state == HS.HAND and p.hand_index() == 0)
	check("pickup: exactly one pickup event", _count_events(evs, "pickup") == 1, "n=%d" % _count_events(evs, "pickup"))
	check("pickup: no explosion, wire or shard from a pickup", _count_events(evs, "explosion") == 0 and s.wires.is_empty() and s.shards.is_empty())
	throw_i(s, 0, Vector2.LEFT, 30)
	check("pickup: can throw again afterwards", p.heads[0].state == HS.OUT or p.heads[0].state == HS.FLIGHT)

	# Farther than the catch distance: stays out.
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw_i(s, 0, Vector2.RIGHT, 40)
	p = s.players[0]
	var far := p.pos.distance_to(p.heads[0].pos)
	many(s, 30, idle4())
	check("pickup: head farther than the catch distance stays out", p.heads[0].state == HS.OUT and far > catch_d, "d=%.2f" % far)

	# Shards + warhead: a pickup is not a retract.
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 3, "warhead": 3})
	throw_i(s, 0, Vector2.RIGHT, 40)
	p = s.players[0]
	s.events.clear()
	var evs2 := []
	for t in 200:
		s.step(only0(inp(Vector2.RIGHT)))
		evs2.append_array(s.events)
		shards_seen += s.shards.size()
		if p.heads[0].state != HS.OUT: break
	check("pickup (shards+warhead): picked up", p.heads[0].state == HS.HAND)
	check("pickup (shards+warhead): no shards, wire or blast", shards_seen == 0 and s.wires.is_empty() and _count_events(evs2, "explosion") == 0)

	# A stunned player standing on the head does not pick it up.
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw_i(s, 0, Vector2.RIGHT, 40)
	p = s.players[0]
	place(s, 0, p.heads[0].pos)
	p.stun_t = 0.3
	s.step(idle4())
	check("pickup: stunned player does not pick up", p.heads[0].state == HS.OUT)
	many(s, 30, idle4())
	check("pickup: after the stun it is picked up", p.heads[0].state == HS.HAND)

	# Another player on the head does not take it.
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(12, 3))
	throw_i(s, 0, Vector2.RIGHT, 40)
	p = s.players[0]
	var hpos := p.heads[0].pos
	place(s, 1, hpos + Vector2(0.05, 0))
	s.step(idle4())
	check("pickup: another player on the head does not pick it up", p.heads[0].state == HS.OUT and p.heads[0].pos == hpos)

	# Twin: only the touched head is picked up.
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"twin": 1})
	throw_i(s, 0, Vector2.RIGHT, 20)
	throw_i(s, 0, Vector2.RIGHT, 50)
	p = s.players[0]
	check("pickup twin: both heads lie out", p.heads.size() == 2 and p.heads[0].state == HS.OUT and p.heads[1].state == HS.OUT)
	var near_i := 0 if p.pos.distance_to(p.heads[0].pos) < p.pos.distance_to(p.heads[1].pos) else 1
	var far_i := 1 - near_i
	for t in 300:
		s.step(only0(inp(Vector2.RIGHT)))
		if p.heads[near_i].state != HS.OUT: break
	check("pickup twin: touched head is in hand, the other still out", p.heads[near_i].state == HS.HAND and p.heads[far_i].state == HS.OUT)


func _step_events(s: Sim, n: int, ins: Array) -> Array:
	var evs: Array = []
	for t in n:
		s.step(ins)
		evs.append_array(s.events)
	return evs


func _self_damage_tests() -> void:
	# Own landing explosion near the owner: a short throw at warhead L3 (radius 3.4).
	var s := mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": 3})
	var arr := idle4()
	var evs: Array = []
	for t in 8:
		arr[0] = inp(Vector2.ZERO, Vector2.RIGHT, true); s.step(arr); evs.append_array(s.events)
	arr[0] = inp()
	evs.append_array(_step_events(s, 120, arr))
	var kills: Array = evs.filter(func(e): return e["type"] == "kill")
	var p := s.players[0]
	check("self blast: owner near own landing dies once, no kill credit", p.deaths == 1 and p.kills == 0, "deaths=%d kills=%d" % [p.deaths, p.kills])
	check("self blast: kill event has killer -1 and cause self", kills.size() == 1 and kills[0]["killer"] == -1 and kills[0]["cause"] == "self" and kills[0]["victim"] == 0, str(kills))
	# Owner far from the landing point survives (L1, radius 1.6, full throw).
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": 1})
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("self blast: owner outside the radius survives", s.players[0].alive and s.players[0].deaths == 0)
	# The other player is still credited to the owner.
	s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(11.0, 6.3)); setm(s, 0, {"warhead": 1})
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("self blast: a victim of the blast still gives the owner a kill", s.players[1].deaths == 1 and s.players[0].kills == 1 and s.players[0].alive)
	# Retract blast (warhead L2) next to the owner.
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": 2})
	throw_i(s, 0, Vector2.RIGHT, 60, 200, true)
	s.players[0].stun_t = 0.0
	s.players[0].pos = Vector2(10.0, 6.3)
	tap_i(s, 0); many(s, 120, idle4())
	check("self blast: the retract blast also hurts the owner", s.players[0].deaths >= 1 and s.players[0].kills == 0, "deaths=%d" % s.players[0].deaths)


func _phase_dash_tests() -> void:
	for L in [1, 2, 3]:
		var s := mk([0]); place(s, 0, Vector2(2, 6.3)); setm(s, 0, {"extradash": L})
		s.statics.append(Rect2(4.5, 5, 1, 3))
		var p := s.players[0]; p.dash_charges = s.dash_max(p)
		s.step(only0(inp(Vector2.RIGHT, Vector2.ZERO, false, true)))
		many(s, 20, only0(inp()))
		if L < 3:
			check("extradash L%d: the dash is stopped by a block" % L, p.pos.x < 4.5, "x=%.2f" % p.pos.x)
		else:
			check("extradash L3: the dash passes a block and ends outside it", p.pos.x > 5.5 + s.cfg.player_radius - 0.01 and p.pos.x < 7.0 and absf(p.pos.y - 6.3) < 0.01, "x=%.2f" % p.pos.x)
	# Ends inside a block: continues until free, never stuck inside.
	var s := mk([0]); place(s, 0, Vector2(2.5, 6.3)); setm(s, 0, {"extradash": 3})
	s.statics.append(Rect2(4.5, 5, 3, 3))  # the dash (3 m) would end in the middle of it
	var p := s.players[0]; p.dash_charges = s.dash_max(p)
	s.step(only0(inp(Vector2.RIGHT, Vector2.ZERO, false, true)))
	many(s, 20, only0(inp()))
	check("extradash L3: a dash ending inside a block continues out of it", p.pos.x > 7.5 + s.cfg.player_radius - 0.01 and p.pos.x < 8.3, "x=%.2f" % p.pos.x)
	# The crate is passed too (and not pushed away).
	s = mk([0]); place(s, 0, Vector2(2, 6.3)); setm(s, 0, {"extradash": 3}); s.crate_pos = Vector2(3.4, 6.3)
	p = s.players[0]; p.dash_charges = s.dash_max(p)
	s.step(only0(inp(Vector2.RIGHT, Vector2.ZERO, false, true)))
	many(s, 20, only0(inp()))
	check("extradash L3: passes the crate", p.pos.x > s.crate_pos.x + 0.7 and p.pos.x < 6.5 and absf(s.crate_pos.x - 3.4) < 0.01, "x=%.2f crate=%.2f" % [p.pos.x, s.crate_pos.x])
	# Outer wall still stops it, also when the block is next to the wall.
	s = mk([0]); place(s, 0, Vector2(RW - 1.5, 6.3)); setm(s, 0, {"extradash": 3})
	s.statics.append(Rect2(RW - 1.2, 5, 0.8, 3))
	p = s.players[0]; p.dash_charges = s.dash_max(p)
	s.step(only0(inp(Vector2.RIGHT, Vector2.ZERO, false, true)))
	many(s, 20, only0(inp()))
	check("extradash L3: never leaves the arena through an outer wall", p.pos.x <= RW - s.cfg.player_radius + 0.01 and p.pos.x > RW - 3.0, "x=%.2f" % p.pos.x)
	for d in [Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		s = mk([0]); place(s, 0, Vector2(RW * 0.5, 6.3)); setm(s, 0, {"extradash": 3}); p = s.players[0]
		var pp := Vector2(0.9, 0.9) if d != Vector2.DOWN else Vector2(RW - 1.0, Config.ARENA_SIZE.y - 0.9)
		place(s, 0, pp); p.dash_charges = s.dash_max(p)
		s.step(only0(inp(d, Vector2.ZERO, false, true)))
		many(s, 20, only0(inp()))
		check("extradash L3: stays inside towards %s wall" % d, p.pos.x >= s.cfg.player_radius - 0.01 and p.pos.y >= s.cfg.player_radius - 0.01 and p.pos.y <= Config.ARENA_SIZE.y - s.cfg.player_radius + 0.01, str(p.pos))


func _range_tests() -> void:
	var cfg := Config.new()
	cfg.train_speed = 0.0
	check("default max throw range is 10 m and the string allows it", cfg.max_range == 10.0 and cfg.effective_max_range() == 10.0, "max=%.1f eff=%.1f" % [cfg.max_range, cfg.effective_max_range()])
	var s := Sim.new(cfg, 1)
	for i in 4:
		s.set_player_enabled(i, i == 0)
	s.statics.resize(s.wall_count); s.crate_pos = Vector2(-50, -50); s.box_active = false; s.box_timer = 9999.0
	s.players[0].alive = true
	place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 60)
	var d: float = s.players[0].head.x - 3.0
	check("default config: full charge throws ~10 m", s.players[0].ystate == Y.OUT and absf(d - 10.0) < 0.2, "dist=%.2f" % d)


# ================================================================ shrinking zone
func rect_close(a: Rect2, b: Rect2) -> bool:
	return a.position.is_equal_approx(b.position) and a.end.is_equal_approx(b.end)

func _zone_tests() -> void:
	var M := MatchMode.Phase
	var dt := 1.0 / 60.0
	var full := Rect2(Vector2.ZERO, Config.ARENA_SIZE)
	var spot: Rect2 = Config.ZONE_SPOTS[0]
	# a stand-in for players who stay put (the zone clock runs in PLAY only)
	var hold := func(s: Sim, n: int, at0: Vector2, at1: Vector2) -> void:
		for _t in n:
			place(s, 0, at0); place(s, 1, at1)
			s.step(idle4())

	var s := mk([0, 1])
	hold.call(s, 25 * 60, Vector2(5, 7), Vector2(25, 7))
	check("zone: none in phase OFF (free play): full rect, no clock, no timers", not s.zone_active() and s.zone_rect() == full and s.mode.zone_t == 0.0 and s.players[0].zone_t == 0.0 and s.players[0].alive)

	s = mk([0, 1]); s.start_match(10); s.mode.zone_spot = 0
	check("zone: a match has one (full while the countdown runs)", s.zone_active() and s.zone_rect() == full)
	to_play(s)
	check("zone: the clock starts with PLAY", s.mode.phase == M.PLAY and s.mode.zone_t < 0.1)
	hold.call(s, int(MatchMode.ZONE_FULL_TIME * 60.0) - 130, Vector2(5, 7), Vector2(25, 7))
	check("zone: the whole arena for the first 20 s", s.zone_rect() == full and s.mode.zone_t < MatchMode.ZONE_FULL_TIME)
	hold.call(s, 240, Vector2(5, 7), Vector2(25, 7))
	check("zone: shrinks once the 20 s are over", s.mode.zone_t > MatchMode.ZONE_FULL_TIME and s.zone_rect() != full and s.mode.phase == M.PLAY)

	# every edge moves linearly from the arena edge to the final spot
	s.mode.zone_t = 20.0 + 15.0
	var mid := s.zone_rect()
	check("zone: halfway through the shrink every edge is halfway", mid.position.is_equal_approx(spot.position * 0.5) and mid.end.is_equal_approx((Config.ARENA_SIZE + spot.end) * 0.5), str(mid))
	s.mode.zone_t = 20.0 + 7.5
	var q := s.zone_rect()
	check("zone: a quarter of the way every edge is a quarter of the way", q.position.is_equal_approx(spot.position * 0.25) and q.end.is_equal_approx(Config.ARENA_SIZE * 0.75 + spot.end * 0.25), str(q))
	s.mode.zone_t = 20.0
	check("zone: exactly the full arena when the shrink begins", s.zone_rect() == full)

	# the final rect after 50 s, and it stays
	s.mode.zone_t = 49.9
	var c0 := spot.get_center()
	for p in s.players: p.zone_t = 0.0
	hold.call(s, 60, c0, c0 + Vector2(1, 0))
	check("zone: the final spot is reached after 50 s", rect_close(s.zone_rect(), spot), str(s.zone_rect()))
	hold.call(s, 600, c0, c0 + Vector2(1, 0))
	check("zone: and stays there", rect_close(s.zone_rect(), spot) and s.mode.phase == M.PLAY and s.players[0].alive and s.players[1].alive)

	# which spot: one of the four, varies over rounds
	var seen := {}
	s = mk([0, 1])
	for _r in 60:
		s.start_match(10)
		seen[s.mode.zone_spot] = true
	var in_range := true
	for k: int in seen.keys():
		in_range = in_range and k >= 0 and k < Config.ZONE_SPOTS.size()
	check("zone: the final spot varies over rounds and is always one of the four", seen.size() == Config.ZONE_SPOTS.size() and in_range and Config.ZONE_SPOTS.size() == 4, str(seen.keys()))
	var sa := mk([0, 1]); sa.start_match(10)
	var sb := mk([0, 1]); sb.start_match(10)
	check("zone: the same seed gives the same spot", sa.mode.zone_spot == sb.mode.zone_spot)

	# a death after 3 s outside, cause zone, without a kill credit
	s = mk([0, 1, 2]); s.start_match(10); s.mode.zone_spot = 0; to_play(s)
	s.mode.zone_t = 60.0
	var inside := spot.get_center()
	var outside := Vector2(20, 7.2)
	var seen_zone: Dictionary = {}
	var t_dead := -1.0
	var before := 0.0
	for t in 300:
		place(s, 0, outside); place(s, 1, inside); place(s, 2, inside + Vector2(1, 0))
		s.step(idle4())
		for e: Dictionary in s.events:
			if e["type"] == "kill": seen_zone = e
		if t_dead < 0.0 and not s.players[0].alive:
			t_dead = (t + 1) * dt
		elif t_dead < 0.0:
			before = s.players[0].zone_t
	check("zone: a player outside dies after 3 s", absf(t_dead - 3.0) < 0.05, "t=%f" % t_dead)
	check("zone: the timer was just below 3 s the tick before", before > 2.9 and before < 3.0, str(before))
	check("zone: the kill event has cause zone, the victim and no killer", seen_zone.get("cause") == "zone" and seen_zone.get("victim") == 0 and seen_zone.get("killer") == -1, str(seen_zone))
	check("zone: no kill credit, one death, the timer is reset", s.players[0].deaths == 1 and s.players[0].kills == 0 and s.players[1].kills == 0 and s.players[2].kills == 0 and s.players[0].zone_t == 0.0)
	check("zone: the others inside are untouched", s.players[1].alive and s.players[2].alive and s.players[1].zone_t == 0.0)

	# simultaneous deaths keep the rule: nobody scores
	s = mk([0, 1]); s.start_match(10); s.mode.zone_spot = 0; to_play(s)
	s.mode.zone_t = 60.0
	hold.call(s, 200, Vector2(20, 7.2), Vector2(24, 7.2))
	check("zone: both outside die in the same tick: no point, round over", not s.players[0].alive and not s.players[1].alive and s.mode.points == [0, 0, 0, 0, 0, 0, 0, 0] and s.mode.phase == M.RESULT and s.mode.last_scorer == -1)

	# draining inside at the same rate, floor at zero
	s = mk([0, 1]); s.start_match(10); s.mode.zone_spot = 0; to_play(s)
	s.mode.zone_t = 60.0
	hold.call(s, 120, Vector2(20, 7.2), inside)
	var filled: float = s.players[0].zone_t
	check("zone: the timer fills at one second per second", absf(filled - 2.0) < 0.05, str(filled))
	hold.call(s, 60, inside, inside + Vector2(1, 0))
	check("zone: back inside it drains at the same rate", absf(s.players[0].zone_t - (filled - 1.0)) < 0.05 and s.players[0].alive, str(s.players[0].zone_t))
	hold.call(s, 120, inside, inside + Vector2(1, 0))
	check("zone: and stops at zero", s.players[0].zone_t == 0.0 and s.players[0].alive)

	# the edge counts by the centre
	s = mk([0, 1]); s.start_match(10); s.mode.zone_spot = 0; to_play(s)
	s.mode.zone_t = 60.0
	hold.call(s, 30, Vector2(spot.end.x - 0.01, spot.get_center().y), inside)
	check("zone: a centre just inside the edge is safe", s.players[0].zone_t == 0.0)
	hold.call(s, 30, Vector2(spot.end.x + 0.01, spot.get_center().y), inside)
	check("zone: a centre just outside the edge fills the timer", s.players[0].zone_t > 0.4)

	# a new round resets clock and timers
	s = mk([0, 1, 2]); s.start_match(10); to_play(s)
	s.mode.zone_t = 40.0
	s.players[1].zone_t = 2.0
	s._start_round()
	check("zone: a new round resets the clock and every timer", s.mode.zone_t == 0.0 and s.players[1].zone_t == 0.0 and s.zone_rect() == full)
	s = mk([0, 1]); s.start_match(10); to_play(s)
	s.mode.zone_t = 40.0
	s.players[0].zone_t = 2.0
	kill_i(s, 1)
	s.step(idle4())
	next_round(s)
	for _t in 200:
		s.step(idle4())
	check("zone: the round after a finished one starts clean", s.mode.round == 2 and s.mode.zone_t < 1.0 and s.players[0].zone_t == 0.0)

	# the snapshot carries zone clock, spot and timers
	s = mk([0, 1]); s.start_match(10); s.mode.zone_spot = 2; to_play(s)
	hold.call(s, 40, Vector2(5, 7), Vector2(25, 7))
	s.mode.zone_t = 20.0 + 17.0
	s.players[0].zone_t = 1.5
	var twin := mk([0, 1])
	twin.load_state(s.save_state())
	check("zone: save / load carry clock, spot, timers and the rect", twin.mode.zone_t == s.mode.zone_t and twin.mode.zone_spot == 2 and twin.players[0].zone_t == 1.5 and twin.zone_rect() == s.zone_rect())
	hold.call(s, 30, Vector2(5, 7), Vector2(25, 7)); hold.call(twin, 30, Vector2(5, 7), Vector2(25, 7))
	check("zone: a restored sim continues identically", var_to_bytes(s.save_state()) == var_to_bytes(twin.save_state()))

	# bots steer back in and survive a long round
	var bs := mk([0, 1]); bs.start_match(10); bs.mode.zone_spot = 0; to_play(bs)
	bs.mode.zone_t = 60.0
	var steers := true
	for sd in 12:
		var bot := Bot.new(0, bs.cfg, 5 + sd)
		place(bs, 0, Vector2(20, 7.2)); place(bs, 1, inside)
		var bi := bot.think(bs, dt)
		steers = steers and bi.move.x < -0.3
	check("zone: a bot outside the zone steers towards it (12 random wander targets)", steers)
	bs = mk([0, 1]); bs.start_match(10); bs.mode.zone_spot = 3; to_play(bs)
	var bots := [Bot.new(0, bs.cfg, 5), Bot.new(1, bs.cfg, 6)]
	var worst := 0.0
	for _t in 60 * 58:
		for p in bs.players:
			if p.alive: worst = maxf(worst, p.zone_t)
		bs.step([bots[0].think(bs, dt), bots[1].think(bs, dt), inp(), inp()])
		if bs.mode.phase != M.PLAY: break
	check("zone: bots follow the shrinking zone (their timers stay low)", worst < 1.0, "worst=%f" % worst)

	# geometry of the spots: free areas
	var rr: float = Config.DEFAULTS["player_radius"]
	var crate := Rect2(Config.CRATE_START - Vector2.ONE * Config.CRATE_HALF, Vector2.ONE * Config.CRATE_HALF * 2.0)
	var box := Rect2(Config.BOX_POS - Vector2.ONE * Config.BOX_HALF, Vector2.ONE * Config.BOX_HALF * 2.0)
	var track_n := int(TrainTrack.LENGTH / 0.02)
	for k in Config.ZONE_SPOTS.size():
		var z: Rect2 = Config.ZONE_SPOTS[k]
		var nm := "zone spot %d: " % k
		check(nm + "inside the arena", full.encloses(z))
		check(nm + "a quarter of the arena", is_equal_approx(z.size.x, Config.ARENA_SIZE.x * 0.25) and is_equal_approx(z.size.y, Config.ARENA_SIZE.y * 0.25))
		var hit := false
		for o in Config.OBSTACLES:
			hit = hit or z.intersects(o)
		check(nm + "no obstacle in it", not hit)
		check(nm + "no crate start and no box in it", not z.intersects(crate) and not z.intersects(box))
		var near := 1e9
		for i in track_n:
			near = minf(near, rect_dist(TrainTrack.point(i * 0.02), z))
		check(nm + "at least car radius plus player radius from the train track", near >= TrainTrack.CAR_RADIUS + rr, "near=%.3f need>=%.3f" % [near, TrainTrack.CAR_RADIUS + rr])


# ================================================================ rounds and match (Last Standing)
func kill_i(s: Sim, i: int) -> void:
	s._kill(s.players[i], null)

func to_play(s: Sim) -> void:
	for _t in int(MatchMode.COUNTDOWN_TIME * 60.0) + 2:
		s.step(idle4())

## From RESULT through the shop (everybody done at once) to the next round's countdown.
func next_round(s: Sim) -> void:
	for _t in int((MatchMode.RESULT_TIME + Economy.SHOP_TIME) * 60.0) + 10:
		if s.mode.phase == MatchMode.Phase.COUNTDOWN: return
		if s.mode.phase == MatchMode.Phase.SHOP:
			for i in s.players.size():
				s.shop_done(i)
		s.step(idle4())


func _match_tests() -> void:
	var M := MatchMode.Phase
	var s := mk([0])
	check("match: needs two players", not s.start_match(10) and s.mode.phase == M.OFF)
	s = mk([0, 1, 2])
	check("match: starts with three players", s.start_match(15) and s.mode.phase == M.COUNTDOWN and s.mode.round == 1 and s.mode.target == 15)
	check("match: roster is the enabled players", s.mode.roster == [true, true, true, false, false, false, false, false])
	var spawned := {}
	var all_alive := true
	for i in 3:
		all_alive = all_alive and s.players[i].alive
		spawned[s.players[i].pos] = true
	check("match: roster alive on distinct spawn points", all_alive and spawned.size() == 3 and not s.players[3].alive)
	check("match: round_start event", s.events.any(func(e: Dictionary) -> bool: return e["type"] == "round_start"))
	var s2 := mk([0, 1, 2]); s2.rng.seed = 1
	s2.start_match(15)
	check("match: spawn shuffle is deterministic", s2.players[0].pos == s.players[0].pos)
	var s3 := mk([0, 1])
	s3.start_match(7)
	check("match: invalid target becomes 10", s3.mode.target == 10)

	# countdown freezes inputs, play does not
	s = mk([0, 1]); s.start_match(10)
	var p0 := s.players[0].pos
	for _t in 30:
		s.step([inp(Vector2.RIGHT), inp(), inp(), inp()])
	check("match: countdown freezes movement", s.players[0].pos == p0 and s.mode.phase == M.COUNTDOWN)
	for _t in 200:
		if s.mode.phase == M.PLAY: break
		s.step(idle4())
	check("match: countdown ends after COUNTDOWN_TIME", s.mode.phase == M.PLAY and absf(float(s.tick) - MatchMode.COUNTDOWN_TIME * 60.0) <= 31.0)
	p0 = s.players[0].pos
	for _t in 20:
		s.step([inp(Vector2.RIGHT), inp(), inp(), inp()])
	check("match: movement works in play", s.players[0].pos != p0)

	# no respawn in play; last alive scores, result follows
	s = mk([0, 1, 2]); s.start_match(10); to_play(s)
	kill_i(s, 2)
	for _t in 600:
		s.step(idle4())
	check("match: no respawn during play", not s.players[2].alive and s.mode.phase == M.PLAY)
	kill_i(s, 1)
	s.step(idle4())
	check("match: last one alive scores 1 and RESULT follows", s.mode.points[0] == 1 and s.mode.last_scorer == 0 and s.mode.phase == M.RESULT and s.events.any(func(e: Dictionary) -> bool: return e["type"] == "round_end" and e["scorer"] == 0))

	# result -> next round
	s.wires.append(SimWire.new()); s.shards.append(SimShard.new())
	var pos_frozen := s.players[0].pos
	for _t in 30:
		s.step([inp(Vector2.RIGHT), inp(), inp(), inp()])
	check("match: world frozen in RESULT", s.players[0].pos == pos_frozen and s.mode.phase == M.RESULT)
	next_round(s)
	var everyone := s.players[0].alive and s.players[1].alive and s.players[2].alive
	check("match: next round after the result and the shop with all alive and a clean arena", s.mode.phase == M.COUNTDOWN and s.mode.round == 2 and everyone and s.wires.is_empty() and s.shards.is_empty() and s.mode.points[0] == 1)

	# simultaneous deaths: nobody scores
	s = mk([0, 1]); s.start_match(10); to_play(s)
	kill_i(s, 0); kill_i(s, 1)
	s.step(idle4())
	check("match: both last players dying together scores nobody", s.mode.points == [0, 0, 0, 0, 0, 0, 0, 0] and s.mode.last_scorer == -1 and s.mode.phase == M.RESULT)

	# target reached -> match over, stays
	s = mk([0, 1]); s.start_match(10)
	s.mode.points[0] = 9
	to_play(s)
	kill_i(s, 1)
	s.step(idle4())
	check("match: reaching the target ends the match", s.mode.phase == M.MATCH_OVER and s.mode.winner == 0 and s.mode.points[0] == 10 and s.events.any(func(e: Dictionary) -> bool: return e["type"] == "match_over" and e["winner"] == 0))
	for _t in 600:
		s.step(idle4())
	check("match: MATCH_OVER stays", s.mode.phase == M.MATCH_OVER and s.mode.round == 1)
	check("match: rematch resets points and starts again", s.start_match(20) and s.mode.points == [0, 0, 0, 0, 0, 0, 0, 0] and s.mode.round == 1 and s.mode.winner == -1 and s.mode.target == 20 and s.mode.phase == M.COUNTDOWN)

	# leaving player counts dead and keeps points
	s = mk([0, 1, 2]); s.start_match(10); to_play(s)
	s.mode.points[2] = 4
	s.set_player_enabled(2, false)
	s.step(idle4())
	check("match: a leaver keeps points and the round goes on", s.mode.points[2] == 4 and s.mode.phase == M.PLAY)
	s.set_player_enabled(1, false)
	s.step(idle4())
	check("match: leaving counts as dead", s.mode.phase == M.RESULT and s.mode.points[0] == 1)
	s = mk([0, 1, 2]); s.start_match(10); to_play(s)
	s.set_player_enabled(2, false)
	s.set_player_enabled(2, true)
	for _t in 300:
		s.step(idle4())
	check("match: a slot enabled mid-round stays dead", not s.players[2].alive)

	# free play unchanged
	s = mk([0, 1])
	kill_i(s, 1)
	for _t in 400:
		s.step(idle4())
	check("match: OFF still respawns (Training unchanged)", s.players[1].alive and s.mode.phase == M.OFF)

	# snapshot round trip mid-round
	s = mk([0, 1, 2]); s.start_match(15); to_play(s)
	for _t in 50:
		s.step([inp(Vector2.RIGHT), inp(Vector2.UP), inp(), inp()])
	kill_i(s, 2)
	s.step(idle4())
	var snap := s.save_state()
	var twin := mk([0, 1, 2])
	twin.load_state(snap)
	check("match: snapshot carries the mode", twin.mode.phase == M.PLAY and twin.mode.target == 15 and twin.mode.roster == s.mode.roster and twin.mode.round == 1)
	var ins := [inp(Vector2.LEFT), inp(Vector2.DOWN), inp(), inp()]
	for _t in 120:
		s.step(ins); twin.step(ins)
	kill_i(s, 1); kill_i(twin, 1)
	s.step(idle4()); twin.step(idle4())
	check("match: restored state continues identically", var_to_bytes(s.save_state()) == var_to_bytes(twin.save_state()) and twin.mode.phase == M.RESULT)


## Up to eight players: the count setting, the slots, the spawn points, a whole 8-player match with bots.
func _eight_tests() -> void:
	var M := MatchMode.Phase
	var c := Config.new()
	check("players: default 4, saved, slots hold 8", c.player_count == 4 and c.to_dict()["player_count"] == 4 and Config.NUM_PLAYERS == 8 and Config.SPAWNS.size() >= Config.NUM_PLAYERS and Config.SKIN_COUNT >= Config.NUM_PLAYERS)
	c.player_count = 7
	var c2 := Config.new()
	c2.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check("players: survives the JSON round trip", c2.player_count == 7)
	c2.reset()
	check("players: reset leaves it", c2.player_count == 7)
	c2.from_dict({"player_count": 99})
	check("players: too large is clamped to 8", c2.player_count == 8)
	c2.from_dict({"player_count": -5})
	check("players: too small is clamped to 2", c2.player_count == 2)
	for garbage in ["x", null, 1e30]:
		c2.from_dict({"player_count": garbage})
		check("players: garbage %s gives 4 or a clamp" % str(garbage), c2.player_count == (8 if garbage is float else 4))
	c2.from_dict({})
	check("players: an old file without the key gives 4", c2.player_count == 4)

	# a new sim switches on only the first `player_count` slots
	var s := Sim.new(Config.new(), 3)
	var on := 0
	for p in s.players:
		on += 1 if p.enabled else 0
	check("players: a new sim enables player_count slots", s.players.size() == 8 and on == 4 and s.players[3].enabled and not s.players[4].enabled)

	# spawn points: clear of blocks, crate, box and each other
	var rr := 0.5
	var clear := true
	for i in Config.SPAWNS.size():
		for o in Config.OBSTACLES:
			clear = clear and rect_dist(Config.SPAWNS[i], o) > rr + Config.SPAWN_NOISE
		clear = clear and Config.SPAWNS[i].distance_to(Config.CRATE_START) > 1.0 + rr and Config.SPAWNS[i].distance_to(Config.BOX_POS) > 1.0 + rr
		for j in range(i + 1, Config.SPAWNS.size()):
			clear = clear and Config.SPAWNS[i].distance_to(Config.SPAWNS[j]) > 4.0 * rr
	check("players: all 8 spawn points are clear of the blocks, the crate, the box and each other", clear)

	# an 8-player match with bots runs and scores
	var cfg := Config.new()
	cfg.player_count = 8
	s = Sim.new(cfg, 11)
	var bots: Array[Bot] = []
	for i in 8:
		s.set_player_enabled(i, true)
		bots.append(Bot.new(i, cfg, 100 + i))
	check("players 8: a match starts with all eight in the roster", s.start_match(10) and s.mode.roster == [true, true, true, true, true, true, true, true])
	var alive_start := 0
	var spots := {}
	for _t in int(MatchMode.COUNTDOWN_TIME * 60.0) + 2:
		var ins0: Array = []
		for i in 8:
			ins0.append(SimInput.new())
		s.step(ins0)
	for p in s.players:
		alive_start += 1 if p.alive else 0
		spots[p.pos.snappedf(0.01)] = true
	check("players 8: all eight stand alive on eight different spots", alive_start == 8 and spots.size() == 8 and s.mode.phase == M.PLAY)
	var scored := false
	for _t in 60 * 90:
		var ins: Array = []
		for i in 8:
			ins.append(bots[i].think(s, 1.0 / 60.0))
		if s.mode.phase == M.SHOP:
			for i in 8:
				s.shop_done(i)
		s.step(ins)
		var total := 0
		for pt in s.mode.points:
			total += pt
		if total > 0 and s.mode.round >= 2:
			scored = true
			break
	check("players 8: bots play rounds and points are scored", scored, "round=%d points=%s" % [s.mode.round, str(s.mode.points)])
	var bytes: PackedByteArray = var_to_bytes(s.save_state())
	var twin := Sim.new(cfg, 1)
	twin.load_state(bytes_to_var(bytes))
	check("players 8: the state with eight players survives var_to_bytes", var_to_bytes(twin.save_state()) == bytes)


func _coin_tests() -> void:
	var E := Economy
	check("coins: the numbers decided in docs/PLAN.md", [E.COINS_BASE, E.COINS_KILL, E.COINS_SURVIVOR, E.COINS_UNDERDOG, E.COINS_LEADER_KILL] == [3, 1, 2, 2, 1])
	# everybody gets the base, the killer per kill, the survivor its bonus
	var s := mk([0, 1, 2]); s.start_match(10); to_play(s)
	s._kill(s.players[1], s.players[0])
	s._kill(s.players[2], s.players[0])
	s.step(idle4())
	check("coins: base + kills + survivor", s.mode.coins[0] == E.COINS_BASE + 2 * E.COINS_KILL + E.COINS_SURVIVOR and s.mode.earned[0] == s.mode.coins[0], str(s.mode.coins))
	check("coins: losers get the base", s.mode.coins[1] == E.COINS_BASE and s.mode.coins[2] == E.COINS_BASE and s.mode.coins[3] == 0)
	check("coins: nobody is underdog or leader while level", not s.mode.underdog.has(true) and not s.mode.leader.has(true))
	# coins are kept into the next round, kill counts are not
	next_round(s)
	check("coins: kept over rounds, round kills reset", s.mode.round == 2 and s.mode.coins[1] == E.COINS_BASE and s.mode.round_kills == [0, 0, 0, 0, 0, 0, 0, 0])
	check("coins: leader and underdog from the points at round start", s.mode.leader == [true, false, false, false, false, false, false, false] and s.mode.underdog == [false, true, true, false, false, false, false, false])
	to_play(s)
	s._kill(s.players[0], s.players[1])   # underdog 1 kills the leader
	s._kill(s.players[2], null, "zone")   # no credit
	s.step(idle4())
	var want1 := E.COINS_BASE * 2 + E.COINS_KILL + E.COINS_SURVIVOR + E.COINS_UNDERDOG + E.COINS_LEADER_KILL
	check("coins: underdog bonus and leader kill", s.mode.coins[1] == want1 and s.mode.earned[1] == want1 - E.COINS_BASE, str(s.mode.coins))
	check("coins: a death without a killer pays nobody", s.mode.earned[2] == E.COINS_BASE + E.COINS_UNDERDOG and s.mode.earned[0] == E.COINS_BASE)
	var parts := s.mode.coin_parts(1, s.mode.last_scorer)
	check("coins: parts add up to earned", parts["kills"] + parts["base"] + parts["survivor"] + parts["underdog"] + parts["leader"] == s.mode.earned[1] and parts["leader"] == E.COINS_LEADER_KILL)
	check("coins: coin text names the parts", MatchOverlay.coin_text(s.mode, 1).begins_with("+%d coins" % s.mode.earned[1]) and MatchOverlay.coin_text(s.mode, 1).contains("leader kill") and MatchOverlay.coin_text(s.mode, 3) == "")
	check("pips: filled count is the points, clamped to 0..target", ScorePips.filled_count(3, 10) == 3 and ScorePips.filled_count(-2, 10) == 0 and ScorePips.filled_count(25, 20) == 20 and ScorePips.filled_count(20, 20) == 20)
	check("pips: groups of five with a wider gap between groups", is_equal_approx(ScorePips.pip_x(1) - ScorePips.pip_x(0), ScorePips.D + ScorePips.GAP) and is_equal_approx(ScorePips.pip_x(5) - ScorePips.pip_x(4), ScorePips.D + ScorePips.GROUP_GAP) and is_equal_approx(ScorePips.pip_x(10) - ScorePips.pip_x(9), ScorePips.D + ScorePips.GROUP_GAP) and is_equal_approx(ScorePips.pip_x(6) - ScorePips.pip_x(5), ScorePips.D + ScorePips.GAP))
	check("pips: the row width covers every pip", is_equal_approx(ScorePips.total_width(10), ScorePips.pip_x(9) + ScorePips.D) and ScorePips.total_width(0) == 0.0 and ScorePips.total_width(20) > ScorePips.total_width(15))
	# no coins outside a match, a rematch zeroes them, snapshot carries them
	var snap := s.save_state()
	var twin := mk([0, 1, 2]); twin.load_state(snap)
	check("coins: in the snapshot", twin.mode.coins == s.mode.coins and twin.mode.leader == s.mode.leader)
	s.start_match(10)
	check("coins: rematch zeroes coins", s.mode.coins == [0, 0, 0, 0, 0, 0, 0, 0] and s.mode.earned == [0, 0, 0, 0, 0, 0, 0, 0])
	s = mk([0, 1])
	s._kill(s.players[1], s.players[0])
	check("coins: free play counts no round kills", s.mode.round_kills == [0, 0, 0, 0, 0, 0, 0, 0])
	s = mk([0, 1, 2]); s.start_match(10); to_play(s)
	s._kill(s.players[0], s.players[0])
	check("coins: a self-kill counts nothing", s.mode.round_kills[0] == 0)


## A two- or three-player match in its first shop, with `coins` coins for everybody.
func shop_sim(only: Array, coins: int) -> Sim:
	var s := mk(only); s.start_match(10); to_play(s)
	for i in range(1, only.size()):
		kill_i(s, only[i])
	s.step(idle4())
	for _t in int(MatchMode.RESULT_TIME * 60.0) + 2:
		if s.mode.phase == MatchMode.Phase.SHOP: break
		s.step(idle4())
	for i in s.players.size():
		s.mode.coins[i] = coins
	return s


func _shop_tests() -> void:
	var M := MatchMode.Phase
	check("shop: the numbers decided in docs/PLAN.md", Economy.SHOP_TIME == 20.0 and Economy.REROLL_PRICE == 1 and Economy.OFFERS == 3 and Economy.SLOTS == 5)
	var s := shop_sim([0, 1, 2], 20)
	check("shop: opens after the result", s.mode.phase == M.SHOP and s.mode.round == 1 and s.mode.running() and s.mode.frozen())
	var o0: Array = s.mode.offers[0]
	var distinct := {}
	for id: String in o0:
		distinct[id] = true
	check("shop: three different offers per roster player, none outside", o0.size() == 3 and distinct.size() == 3 and s.mode.offers[1].size() == 3 and s.mode.offers[3].is_empty(), str(s.mode.offers))
	var pos0 := s.players[0].pos
	s.step([inp(Vector2.RIGHT), inp(), inp(), inp()])
	check("shop: the world stands still", s.players[0].pos == pos0)
	# buying
	var id: String = o0[0]
	var seq: int = s.mode.shop_seq[0]
	check("shop: a buy with an old counter is refused", not s.shop_buy(0, 0, seq + 1) and s.mode.coins[0] == 20)
	check("shop: buying costs the price and gives level 1", s.shop_buy(0, 0, seq) and s.mode.coins[0] == 20 - Mods.price(id) and s.mode.owned[0] == {id: 1} and s.lv(s.players[0], id) == 1 and s.mode.offers[0][0] == "")
	check("shop: the same request again is refused", not s.shop_buy(0, 0, seq) and not s.shop_buy(0, 0, s.mode.shop_seq[0]) and s.mode.owned[0] == {id: 1})
	s.mode.coins[0] = 0
	check("shop: too expensive is refused", not s.shop_buy(0, 1, s.mode.shop_seq[0]) and s.mode.owned[0].size() == 1)
	check("shop: no reroll without coins", not s.shop_reroll(0, s.mode.shop_seq[0]))
	s.mode.coins[0] = 5
	var before: Array = s.mode.offers[0].duplicate()
	var all_distinct := true
	var probe := shop_sim([0, 1], 99)
	for _r in 40:
		probe.shop_reroll(0, probe.mode.shop_seq[0])
		var seen := {}
		for x: String in probe.mode.offers[0]:
			seen[x] = true
		all_distinct = all_distinct and seen.size() == Economy.OFFERS
	check("shop: offers are always different from each other", all_distinct)
	var probe_seq: int = probe.mode.shop_seq[0]
	probe.shop_buy(0, 0, probe_seq)
	check("shop: a buy moves the counter, so a request sent before it is refused", not probe.shop_reroll(0, probe_seq) and probe.mode.coins[0] == 99 - 40 - Mods.price(probe.mode.owned[0].keys()[0]))
	check("shop: a reroll costs 1 and draws a full new set", s.shop_reroll(0, s.mode.shop_seq[0]) and s.mode.coins[0] == 4 and s.mode.offers[0].size() == 3 and not s.mode.offers[0].has(""), str(before) + str(s.mode.offers[0]))
	# levels by copies
	s.mode.owned[0][id] = 2
	s.mode.offers[0][0] = id
	s.mode.coins[0] = 20
	check("shop: the third copy makes level 2", s.shop_buy(0, 0, s.mode.shop_seq[0]) and s.lv(s.players[0], id) == 2 and s.mode.levels_of(0)[id] == 2)
	s.mode.owned[0][id] = 6
	check("shop: a modifier at level 3 is not offered or bought", not s.mode.can_take(0, id))
	s.shop_reroll(0, s.mode.shop_seq[0])
	check("shop: ... not offered after a reroll", not s.mode.offers[0].has(id))
	# slots
	var five := {}
	for k in Economy.SLOTS:
		five[Mods.ORDER[k]] = 1
	s.mode.owned[1] = five
	s.mode.coins[1] = 50
	s.shop_reroll(1, s.mode.shop_seq[1])
	var only_owned := true
	for x: String in s.mode.offers[1]:
		only_owned = only_owned and five.has(x)
	check("shop: with all slots full only owned modifiers are offered", only_owned and not s.mode.can_take(1, Mods.ORDER[Economy.SLOTS]) and s.mode.can_take(1, Mods.ORDER[0]))
	# done and the end of the shop
	check("shop: done blocks buying", s.shop_done(0) and s.mode.shop_ready[0] and not s.shop_buy(0, 1, s.mode.shop_seq[0]) and not s.shop_done(0))
	s.step(idle4())
	check("shop: stays open while someone shops", s.mode.phase == M.SHOP)
	s.set_player_enabled(2, false)
	s.shop_done(1)
	s.step(idle4())
	check("shop: closes when everybody still there is done; the next round starts", s.mode.phase == M.COUNTDOWN and s.mode.round == 2)
	check("shop: bought modifiers stay for the next round", s.lv(s.players[0], id) == 2 and s.mode.owned[0][id] == 6)
	s = shop_sim([0, 1], 0)
	for _t in int(Economy.SHOP_TIME * 60.0) + 2:
		if s.mode.phase != M.SHOP: break
		s.step(idle4())
	check("shop: closes after the time limit", s.mode.phase == M.COUNTDOWN and s.mode.round == 2 and s.mode.phase_t < 0.1)
	# the deciding round has no shop; a rematch clears the build
	s = shop_sim([0, 1], 10)
	s.shop_buy(0, 0, s.mode.shop_seq[0])
	var bought: String = s.mode.owned[0].keys()[0]
	next_round(s); to_play(s)
	s.mode.points[0] = 9
	kill_i(s, 1)
	s.step(idle4())
	for _t in 600:
		s.step(idle4())
	check("shop: none after the deciding round", s.mode.phase == M.MATCH_OVER)
	var snap := s.save_state()
	var twin := mk([0, 1]); twin.load_state(snap)
	check("shop: the build is in the snapshot", twin.mode.owned == s.mode.owned and twin.lv(twin.players[0], bought) == 1)
	s.start_match(10)
	check("shop: a rematch clears the build and the modifiers", s.mode.owned[0].is_empty() and s.lv(s.players[0], bought) == 0)
	# deterministic offers
	var a := shop_sim([0, 1, 2], 9)
	var b := shop_sim([0, 1, 2], 9)
	a.shop_reroll(1, a.mode.shop_seq[1]); b.shop_reroll(1, b.mode.shop_seq[1])
	check("shop: offers and rerolls are deterministic", a.mode.offers == b.mode.offers)
	# bots
	s = shop_sim([0, 1, 2], 8)
	Bot.shop(s, 1)
	check("bot shop: waits a moment first", not s.mode.shop_ready[1] and s.mode.coins[1] == 8)
	s.mode.phase_t = Economy.BOT_SHOP_DELAY
	var o1: Array = s.mode.offers[1].duplicate()
	Bot.shop(s, 1)
	var spent: int = 8 - int(s.mode.coins[1])
	check("bot shop: buys, then is done", s.mode.shop_ready[1] and spent > 0 and not s.mode.owned[1].is_empty(), "%s %s" % [str(o1), str(s.mode.owned[1])])
	check("bot shop: never goes below zero", s.mode.coins[1] >= 0)
	s.mode.owned[2] = {o1[0]: 1}
	s.mode.offers[2] = [Mods.ORDER[9] if o1[0] != Mods.ORDER[9] else Mods.ORDER[8], o1[0], ""]
	s.mode.coins[2] = 8
	Bot.shop(s, 2)
	check("bot shop: a copy of an owned modifier first", int(s.mode.owned[2][o1[0]]) == 2, str(s.mode.owned[2]))
	s = shop_sim([0, 1], 1)
	s.mode.phase_t = 5.0
	s.mode.offers[1] = ["warhead", "twin", "steer"]
	Bot.shop(s, 1)
	check("bot shop: does not waste its coins on rerolls it cannot use", s.mode.coins[1] == 1 and s.mode.shop_ready[1])
	_shop_rework_tests()


func _shop_rework_tests() -> void:
	var M := MatchMode.Phase
	# sell
	var s := shop_sim([0, 1, 2], 0)
	var m := s.mode
	m.owned[0] = {"bounce": 3, "tripwire": 1}
	s.apply_mods(0, m.levels_of(0))
	var seq: int = m.shop_seq[0]
	var bp: int = Mods.price("bounce")
	check("sell: the refund is half the price of every copy, rounded down", m.sell_refund(0, "bounce") == 3 * bp / 2 and m.sell_refund(0, "tripwire") == Mods.price("tripwire") / 2 and m.sell_refund(0, "twin") == 0)
	check("sell: a stale counter is refused", not s.shop_sell(0, "bounce", seq + 1) and m.owned[0].size() == 2 and m.coins[0] == 0)
	check("sell: not owned is refused", not s.shop_sell(0, "twin", seq) and not s.shop_sell(0, "nonsense", seq) and m.coins[0] == 0 and m.shop_seq[0] == seq)
	check("sell: removes the modifier with all copies, pays, frees the slot, drops the level", s.shop_sell(0, "bounce", seq) and m.coins[0] == 3 * bp / 2 and m.owned[0] == {"tripwire": 1} and s.lv(s.players[0], "bounce") == 0 and s.lv(s.players[0], "tripwire") == 1)
	check("sell: the same request again is refused", not s.shop_sell(0, "tripwire", seq) and m.owned[0].has("tripwire"))
	check("sell: the freed slot can take a new modifier", m.can_take(0, "bounce"))
	m.shop_ready[1] = true
	check("sell: not after done, not for a slot outside the roster", not s.shop_sell(1, "bounce", m.shop_seq[1]) and not s.shop_sell(3, "bounce", 0))
	var sold_all := shop_sim([0, 1], 0)
	sold_all.mode.owned[0] = {"twin": 6}
	sold_all.shop_sell(0, "twin", sold_all.mode.shop_seq[0])
	check("sell: a top-level modifier gives the half price of six copies", sold_all.mode.coins[0] == 6 * Mods.price("twin") / 2)
	# lock
	s = shop_sim([0, 1, 2], 30)
	m = s.mode
	var o: Array = m.offers[0].duplicate()
	check("lock: nothing is locked at the start", not m.is_locked(0, 0) and not m.is_locked(0, 1))
	check("lock: a stale counter, an empty or out-of-range offer are refused", not s.shop_lock(0, 1, m.shop_seq[0] + 1) and not s.shop_lock(0, 3, m.shop_seq[0]) and not s.shop_lock(0, -1, m.shop_seq[0]) and not m.is_locked(0, 1))
	var lseq: int = m.shop_seq[0]
	check("lock: toggles on", s.shop_lock(0, 1, lseq) and m.is_locked(0, 1) and not m.is_locked(0, 0) and m.coins[0] == 30)
	check("lock: the same request again is refused", not s.shop_lock(0, 1, lseq) and m.is_locked(0, 1))
	var survived := true
	for _r in 12:
		s.shop_reroll(0, m.shop_seq[0])
		survived = survived and m.offers[0][1] == o[1] and m.offers[0].count(o[1]) == 1 and m.offers[0].size() == 3
	check("lock: a locked offer survives rerolls and nothing repeats it", survived, str(o) + str(m.offers[0]))
	var changed := false
	var o2: Array = m.offers[0].duplicate()
	for _r in 6:
		s.shop_reroll(0, m.shop_seq[0])
		changed = changed or m.offers[0][0] != o2[0] or m.offers[0][2] != o2[2]
	check("lock: the others are redrawn", changed)
	check("lock: unlock is the same toggle", s.shop_lock(0, 1, m.shop_seq[0]) and not m.is_locked(0, 1))
	# stays for the next shop
	s.shop_lock(0, 2, m.shop_seq[0])
	var keep: String = m.offers[0][2]
	s.shop_done(0)
	next_round(s)
	to_play(s)
	kill_i(s, 1); kill_i(s, 2)
	s.step(idle4())
	for _t in int(MatchMode.RESULT_TIME * 60.0) + 2:
		if m.phase == M.SHOP: break
		s.step(idle4())
	check("lock: a locked offer is still there in the next shop, the others are new", m.phase == M.SHOP and m.offers[0][2] == keep and m.is_locked(0, 2) and not m.is_locked(0, 0) and m.offers[0].size() == 3, str(m.offers[0]))
	# buying clears the lock
	s.mode.coins[0] = 30
	check("lock: buying a locked offer clears the lock", s.shop_buy(0, 2, m.shop_seq[0]) and not m.is_locked(0, 2) and m.offers[0][2] == "")
	check("lock: a bought (empty) offer cannot be locked", not s.shop_lock(0, 2, m.shop_seq[0]) and not m.is_locked(0, 2))
	s.shop_reroll(0, m.shop_seq[0])
	check("lock: after the buy the slot is redrawn", m.offers[0][2] != "")
	# a locked offer that cannot be taken any more is redrawn
	s = shop_sim([0, 1], 30)
	m = s.mode
	var lid: String = m.offers[0][0]
	s.shop_lock(0, 0, m.shop_seq[0])
	m.owned[0][lid] = 6
	s.shop_reroll(0, m.shop_seq[0])
	check("lock: a locked offer that can no longer be taken is dropped", m.offers[0][0] != lid and not m.is_locked(0, 0))
	# the lock is in the snapshot, a new match clears it
	s = shop_sim([0, 1], 30)
	s.shop_lock(0, 1, s.mode.shop_seq[0])
	var twin := mk([0, 1]); twin.load_state(s.save_state())
	check("lock: the lock is in the snapshot", twin.mode.is_locked(0, 1) and twin.mode.locked == s.mode.locked)
	s.mode.phase = M.MATCH_OVER
	s.start_match(10)
	check("lock: a new match clears the locks", not s.mode.is_locked(0, 1) and not s.mode.is_locked(0, 0) and not s.mode.is_locked(0, 1))
	# bots never sell
	s = shop_sim([0, 1, 2], 20)
	s.mode.owned[1] = {"bounce": 1}
	s.mode.phase_t = Economy.BOT_SHOP_DELAY
	Bot.shop(s, 1)
	check("bot shop: never sells", s.mode.owned[1].has("bounce"))
	# texts and panel
	var short_ok := true
	for id in Mods.ORDER:
		var texts := {}
		for lv in range(1, Mods.MAX_LEVEL + 1):
			short_ok = short_ok and Mods.short(id, lv) != "" and Mods.short(id, lv).split(" ").size() <= 9
			texts[Mods.short(id, lv)] = true
		short_ok = short_ok and texts.size() == Mods.MAX_LEVEL and Mods.short(id, 0) == Mods.short(id, 1) and Mods.short(id, 9) == Mods.short(id, 3) and Mods.short(id) == Mods.short(id, 1)
		short_ok = short_ok and ModIcon.COLORS.has(id)
	check("shop text: every modifier has three distinct short texts (at most 9 words) and an icon colour", short_ok)
	check("shop text: pips towards the next level", ShopPanel.pips(1) == Vector2i(0, 2) and ShopPanel.pips(2) == Vector2i(1, 2) and ShopPanel.pips(3) == Vector2i(0, 3) and ShopPanel.pips(5) == Vector2i(2, 3) and ShopPanel.pips(6) == Vector2i(3, 3) and ShopPanel.pips(9) == Vector2i(3, 3), str(ShopPanel.pips(2)) + str(ShopPanel.pips(5)))
	check("shop text: what a buy gives", ShopPanel.gain_text(0) == "New · I" and ShopPanel.gain_text(1) == "Pip 1/2" and ShopPanel.gain_text(2) == "→ II" and ShopPanel.gain_text(3) == "Pip 1/3" and ShopPanel.gain_text(5) == "→ III")
	s = shop_sim([0, 1], 50)
	for k in Economy.SLOTS:
		s.mode.owned[0][Mods.ORDER[k]] = 1 + k
	var panel := ShopPanel.new()
	panel.theme = UiKit.theme()
	panel.refresh(s, 0)
	var ms := panel.get_combined_minimum_size()
	check("shop panel: five slots and three offers fit the 1280x576 base screen without scrolling", ms.x <= 1240.0 and ms.y <= 540.0 and Economy.SLOTS == 5 and Economy.OFFERS == 3, str(ms))
	var shown := 0
	for sl in panel.slots:
		if sl["id"] != "":
			shown += 1
	check("shop panel: the slots show the build in order", shown == 5 and panel.slots[0]["id"] == Mods.ORDER[0] and panel.slots[4]["level"].text == "II")
	panel.free()


func _rm(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A router in the tree with a fresh TouchSettings of `mode`/`swap`; touches are fed straight to its handlers.
func _touch_router(mode: TouchSettings.Mode, swap := false) -> InputRouter:
	var r := InputRouter.new()
	root.add_child(r)
	r.touch.mode = mode
	r.touch.swap = swap
	return r


func _touch_tests() -> void:
	var old_path := TouchSettings.path
	TouchSettings.path = "user://test_touch_sim.json"
	_rm(TouchSettings.path)

	# store: defaults, round trip, damaged files
	var d := TouchSettings.load_saved()
	check("touch: no file gives the defaults (floating, size 1, opacity 1, no swap, no custom places)", d.mode == TouchSettings.Mode.FLOATING and d.scale == 1.0 and d.opacity == 1.0 and not d.swap and d.custom.is_empty())
	var t := TouchSettings.new()
	t.mode = TouchSettings.Mode.FIXED
	t.scale = 1.25
	t.opacity = 0.5
	t.swap = true
	t.custom = {"dash": Vector2(0.25, 0.5), "move": Vector2(0.5, 0.75)}
	t.save()
	var u := TouchSettings.load_saved()
	check("touch: mode, size, opacity and swap survive a save and load", u.mode == TouchSettings.Mode.FIXED and is_equal_approx(u.scale, 1.25) and is_equal_approx(u.opacity, 0.5) and u.swap)
	check("touch: placed controls survive, the others stay default", u.custom.size() == 2 and u.rel("dash").is_equal_approx(Vector2(0.25, 0.5)) and u.rel("move").is_equal_approx(Vector2(0.5, 0.75)) and u.rel("aim").is_equal_approx(u.default_rel("aim")))
	for junk in ["", "not json", "[1, 2]", "42", "{\"mode\": 7, \"scale\": \"big\", \"opacity\": null, \"swap\": \"yes\", \"pos\": 5}"]:
		_write_text(TouchSettings.path, junk)
		var j := TouchSettings.load_saved()
		check("touch: damaged file '%s' gives the defaults" % junk.left(12), j.mode == TouchSettings.Mode.FLOATING and j.scale == 1.0 and j.opacity == 1.0 and not j.swap and j.custom.is_empty())
	_write_text(TouchSettings.path, "{\"scale\": 99, \"opacity\": -3, \"pos\": {\"dash\": [5, -2], \"aim\": [\"a\", 1], \"move\": [0.5]}}")
	var w := TouchSettings.load_saved()
	check("touch: out-of-range numbers are clamped, malformed places dropped", w.scale == TouchSettings.SCALE_MAX and w.opacity == TouchSettings.OPACITY_MIN and w.custom.size() == 1 and w.rel("dash") == Vector2(1.0, 0.0))
	_rm(TouchSettings.path)

	# not part of the sim config
	check("touch: the settings are not in the simulation Config", not Config.new().to_dict().has("scale") and not Config.new().to_dict().has("swap") and not Config.new().to_dict().has("mode"))

	# geometry: defaults equal today's places, swap mirrors, clamping
	var g := TouchSettings.new()
	var ref := TouchSettings.REFERENCE
	check("touch: default places are today's places on the reference screen", g.center("dash", ref).is_equal_approx(ref - Config.DASH_BUTTON_OFFSET) and g.center("move", ref).is_equal_approx(Vector2(Config.STICK_REST_OFFSET_LEFT.x, ref.y - Config.STICK_REST_OFFSET_LEFT.y)) and g.center("aim", ref).is_equal_approx(ref - Config.STICK_REST_OFFSET_RIGHT))
	var sw := TouchSettings.new()
	sw.swap = true
	check("touch: swapped defaults are mirrored (move right, aim and dash left)", is_equal_approx(sw.default_rel("move").x, 1.0 - g.default_rel("move").x) and sw.default_rel("move").x > 0.5 and sw.default_rel("aim").x < 0.5 and sw.default_rel("dash").x < 0.5 and sw.default_rel("dash").y == g.default_rel("dash").y)
	var m := TouchSettings.new()
	m.custom = {"dash": Vector2(0.2, 0.3)}
	m.set_swap(true)
	check("touch: turning swap on mirrors a placed control", m.custom["dash"].is_equal_approx(Vector2(0.8, 0.3)))
	m.set_swap(false)
	check("touch: ... and off puts it back", m.custom["dash"].is_equal_approx(Vector2(0.2, 0.3)))
	var small := Vector2(800, 400)
	var edge := TouchSettings.new()
	edge.custom = {"dash": Vector2(1.0, 1.0), "move": Vector2(0.0, 0.0)}
	var dc := edge.center("dash", small)
	var mc := edge.center("move", small)
	check("touch: places are clamped so the whole control stays on the screen", dc.is_equal_approx(small - Vector2.ONE * edge.dash_radius()) and mc.is_equal_approx(Vector2.ONE * edge.stick_radius()))
	edge.scale = 1.6
	check("touch: a bigger size grows the controls and the clamp margin", edge.stick_radius() > g.stick_radius() and edge.center("move", small).x == edge.stick_radius())
	check("touch: a place maps to other screen sizes by its share", g.center("aim", Vector2(2560, 1152)).is_equal_approx(g.center("aim", ref) * 2.0))

	# set_positions / reset
	var e := TouchSettings.new()
	e.set_positions({"move": e.default_rel("move"), "dash": Vector2(0.4, 0.4)})
	check("touch: set_positions keeps only places that differ from the default", e.custom.size() == 1 and e.custom.has("dash"))
	e.reset_positions()
	check("touch: reset forgets the places", e.custom.is_empty())

	# router: floating default
	var r := _touch_router(TouchSettings.Mode.FLOATING)
	var sz := r._screen_size()
	r._touch_down(0, Vector2(sz.x * 0.25, sz.y * 0.2))
	var cm: Vector2 = r._move_c
	check("touch: floating default - a touch in the left half starts the move stick right where it landed", r._move_idx == 0 and cm == Vector2(sz.x * 0.25, sz.y * 0.2))
	r._touch_move(0, cm + Vector2(300, 0))
	check("touch: ... and the floating base follows a long drag, the stick reads full", not r._move_c.is_equal_approx(cm) and r._stick(r._move_c, r._move_p).is_equal_approx(Vector2.RIGHT))
	r._touch_down(1, Vector2(sz.x * 0.75, sz.y * 0.2))
	check("touch: floating - a touch in the right half is the aim stick", r._aim_idx == 1 and r._aim_c == Vector2(sz.x * 0.75, sz.y * 0.2))
	r._release_all()
	r._touch_down(2, r._dash_center())
	check("touch: the dash button takes a touch on it", r._dash_idx == 2)
	r.free()

	# router: swap sides (floating)
	r = _touch_router(TouchSettings.Mode.FLOATING, true)
	r._touch_down(0, Vector2(sz.x * 0.25, sz.y * 0.2))
	check("touch: swapped - the left half is the aim stick", r._aim_idx == 0 and r._move_idx == -1)
	r._touch_down(1, Vector2(sz.x * 0.75, sz.y * 0.2))
	check("touch: swapped - the right half is the move stick", r._move_idx == 1)
	r._release_all()
	r._touch_down(0, Vector2(sz.x * 0.42, sz.y * 0.2))
	r._touch_down(1, Vector2(sz.x * 0.4, sz.y * 0.3))
	check("touch: swapped - a second thumb near the middle takes the free stick", r._aim_idx == 0 and r._move_idx == 1)
	r.free()

	# router: fixed places
	r = _touch_router(TouchSettings.Mode.FIXED)
	r.touch.custom = {"move": Vector2(0.5, 0.5), "aim": Vector2(0.8, 0.4)}
	var mrest := r._move_rest()
	check("touch: fixed - the rest place is the placed one", mrest.is_equal_approx(Vector2(sz.x * 0.5, sz.y * 0.5)))
	r._touch_down(0, Vector2(sz.x * 0.1, sz.y * 0.1))
	check("touch: fixed - a touch far from every stick does nothing", r._move_idx == -1 and r._aim_idx == -1)
	r._touch_down(0, mrest + Vector2(30, 0))
	check("touch: fixed - a touch on the stick takes it, the centre stays put", r._move_idx == 0 and r._move_c.is_equal_approx(mrest))
	r._touch_move(0, mrest + Vector2(500, 0))
	check("touch: fixed - dragging far does not move the centre, the stick reads full", r._move_c.is_equal_approx(mrest) and r._stick(r._move_c, r._move_p).is_equal_approx(Vector2.RIGHT))
	r._touch_down(1, r._aim_rest())
	check("touch: fixed - the aim stick takes its own place", r._aim_idx == 1)
	r._release_all()
	r.touch.custom["dash"] = Vector2(0.3, 0.3)
	r._touch_down(3, Vector2(sz.x * 0.3, sz.y * 0.3))
	check("touch: a placed dash button is where it was put", r._dash_idx == 3)
	r.free()

	# router: size scales the controls
	r = _touch_router(TouchSettings.Mode.FIXED)
	r.touch.scale = 1.5
	var rest := r._move_rest()
	r._touch_down(0, rest + Vector2(Config.STICK_RADIUS * 1.4 * 1.5, 0))
	check("touch: a bigger size also widens the touch area of a fixed stick", r._move_idx == 0)
	check("touch: a stick reads full at its scaled radius", r._stick(rest, rest + Vector2(Config.STICK_RADIUS * 1.5, 0)).is_equal_approx(Vector2.RIGHT) and r._stick(rest, rest + Vector2(Config.STICK_RADIUS * 0.75, 0)).is_equal_approx(Vector2(0.5, 0)))
	r.free()
	TouchSettings.path = old_path


## Player colours: the palette, the sim's uniqueness rule, the saved choice, the lobby swatches.
func _color_tests() -> void:
	check("colour: the palette has COLOR_COUNT (8) entries", Config.COLOR_COUNT == ArenaView.PLAYER_COLORS.size() and Config.COLOR_COUNT == 8)
	var distinct := {}
	for c in ArenaView.PLAYER_COLORS:
		distinct[c.to_html()] = true
	check("colour: the eight palette colours are distinct", distinct.size() == 8)
	var cfg := Config.new()
	cfg.player_count = 8
	var s := Sim.new(cfg, 1)
	var uniq := func(sm: Sim) -> bool:
		var seen := {}
		for p in sm.players:
			if p.enabled:
				if seen.has(p.color):
					return false
				seen[p.color] = true
		return true
	check("colour: by default every slot has its own colour (slot index)", s.players.all(func(p: SimPlayer) -> bool: return p.color == p.id) and uniq.call(s))
	s.set_color(0, 8 + 6)
	check("colour: set_color wraps into range (14 -> 6, taken -> next free)", s.players[0].color >= 0 and s.players[0].color < 8 and uniq.call(s))
	var s4 := Sim.new(Config.new(), 1)   # four players: slots 4..7 are disabled
	s4.set_color(0, 8 + 6)
	check("colour: wrapped value 6 is free when only 4 play", s4.players[0].color == 6)
	s4.set_color(0, 1)
	check("colour: a taken colour gives the next free one (1, 2, 3 taken -> 4)", s4.players[0].color == 4 and uniq.call(s4))
	s4.set_color(0, 0)
	check("colour: the player's own colour is not a collision with itself", s4.players[0].color == 0)
	s4.set_color(1, -1)
	check("colour: negative wraps (-1 -> 7)", s4.players[1].color == 7)
	s4.players[5].color = 0
	s4.set_player_enabled(5, true)
	check("colour: a player who gets enabled with a taken colour is moved to a free one", s4.players[5].color != 0 and uniq.call(s4))
	for i in 8:
		s4.set_player_enabled(i, true)
		s4.set_color(i, 3)
	check("colour: with all eight in, all colours stay unique", uniq.call(s4) and s4.players.size() == 8)
	var s8 := Sim.new(cfg, 1)
	s8.assign_colors(5)
	check("colour: assign_colors gives player 0 its choice and the others the rest in order", s8.players[0].color == 5 and uniq.call(s8) and s8.players[1].color == 0 and s8.players[5].color == 4 and s8.players[7].color == 7)
	var before := s8.players.map(func(p: SimPlayer) -> int: return p.color)
	s8.assign_colors(5)
	check("colour: assign_colors is idempotent", s8.players.map(func(p: SimPlayer) -> int: return p.color) == before)
	var st := s8.save_state()
	var s9 := Sim.new(cfg, 2)
	s9.load_state(st)
	check("colour: the colour is part of the snapshot state", s9.players[0].color == 5 and s9.players[3].color == s8.players[3].color)
	# presentation only: another colour never changes the simulation
	var a := Sim.new(Config.new(), 7)
	var b := Sim.new(Config.new(), 7)
	b.set_color(0, 5)
	b.set_color(1, 7)
	var same := true
	for t in 240:
		var ins := [inp(Vector2(1, 0.3), Vector2(1, 0), t % 90 < 40, t == 50), inp(Vector2(-1, 0.1), Vector2(-1, 0), t % 70 < 30, t == 80), inp(), inp()]
		a.step(ins)
		b.step(ins)
		for i in 4:
			same = same and a.players[i].pos == b.players[i].pos and a.players[i].kills == b.players[i].kills
	check("colour: the colour does not change the simulation", same and a.players[0].pos != Config.SPAWNS[0])
	# the saved choice
	var c := Config.new()
	check("colour: default choice 0, saved in the dict", c.player_color == 0 and c.to_dict()["player_color"] == 0)
	c.player_color = 6
	var c2 := Config.new()
	c2.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check("colour: the choice survives the JSON round trip", c2.player_color == 6)
	c2.reset()
	check("colour: reset leaves the choice", c2.player_color == 6)
	c2.from_dict({"player_color": 9})
	check("colour: too large wraps into range", c2.player_color == 1)
	c2.from_dict({"player_color": -1})
	check("colour: negative wraps into range", c2.player_color == 7)
	for garbage in ["x", null, [1]]:
		c2.from_dict({"player_color": garbage})
		check("colour: garbage %s gives 0" % str(garbage), c2.player_color == 0)
	# the lobby swatches
	var lob := PlayLobby.new()
	root.add_child(lob)
	var saved := Config.new()
	var saves: Array = []
	var chosen: Array = []
	lob.save_fn = func(cc: Config) -> void: saves.append(cc.player_color)
	lob.color_chosen.connect(func(k: int) -> void: chosen.append(k))
	lob.setup(saved)
	lob.open()
	check("lobby colour: eight swatches, the first is chosen", lob.color_buttons.size() == 8 and lob.color_buttons[0].button_pressed and lob.color_buttons.filter(func(x: Button) -> bool: return x.button_pressed).size() == 1)
	lob.color_buttons[3].pressed.emit()
	check("lobby colour: a swatch sets the choice, saves it, reports it and is the only one pressed", saved.player_color == 3 and saves == [3] and chosen == [3] and lob.color_buttons[3].button_pressed and not lob.color_buttons[0].button_pressed)
	check("lobby colour: the preview shows the chosen colour", lob.figure_preview.figure.player_color == ArenaView.PLAYER_COLORS[3])
	saved.player_color = 5
	lob.open()
	check("lobby colour: opening again shows the colour of the config", lob.color_buttons[5].button_pressed and not lob.color_buttons[3].button_pressed and lob.figure_preview.figure.player_color == ArenaView.PLAYER_COLORS[5])
	lob.queue_free()



# ================================================================ maps

func map_sim(id: int, only := [0, 1, 2, 3], seed_value := 7, far_crate := false) -> Sim:
	var cfg := Config.new()
	cfg.map = id
	var s := Sim.new(cfg, seed_value)
	for i in Config.NUM_PLAYERS:
		s.set_player_enabled(i, i in only)
	for i in only:
		s.players[i].alive = true
	if far_crate:
		s.crate_pos = Vector2(-50, -50)
		s.prev_crate_pos = s.crate_pos
	return s

## Steps `n` ticks with idle input and returns every event seen.
func step_collect(s: Sim, n: int, ins: Array = []) -> Array:
	var out := []
	for _t in n:
		s.step(ins if not ins.is_empty() else idle4())
		out.append_array(s.events)
	return out

func has_event(evs: Array, type: String) -> bool:
	return evs.any(func(e: Dictionary) -> bool: return e["type"] == type)

func _map_geometry(id: int) -> void:
	var arena := Rect2(Vector2.ZERO, Config.ARENA_SIZE)
	var rr := Config.new().player_radius
	var obs: Array = MapDef.obstacles(id)
	var crate := MapDef.crate_start(id) if id != 0 else Config.CRATE_START
	var box := MapDef.box_pos(id)
	var crate_r := Rect2(crate - Vector2(Config.CRATE_HALF, Config.CRATE_HALF), Vector2(Config.CRATE_HALF, Config.CRATE_HALF) * 2.0)
	var box_r := Rect2(box - Vector2(Config.BOX_HALF, Config.BOX_HALF), Vector2(Config.BOX_HALF, Config.BOX_HALF) * 2.0)
	var nm: String = MapDef.NAMES[id]
	var ok := true
	for i in obs.size():
		ok = ok and arena.encloses(obs[i]) and not (obs[i] as Rect2).intersects(crate_r) and not (obs[i] as Rect2).intersects(box_r)
		for j in range(i + 1, obs.size()):
			ok = ok and not (obs[i] as Rect2).intersects(obs[j])
	check("map %s: blocks lie inside the arena and overlap neither each other, the chest nor the present" % nm, ok)
	var spawns: Array = MapDef.spawns(id)
	var clear := spawns.size() == 8
	for i in spawns.size():
		var sp: Vector2 = spawns[i]
		for o: Rect2 in obs:
			clear = clear and rect_dist(sp, o) > rr + Config.SPAWN_NOISE
		clear = clear and sp.distance_to(crate) > 1.0 + rr and sp.distance_to(box) > 1.0 + rr
		clear = clear and MapDef.belt_at(sp) < 0 if id == MapDef.Id.BELTS else clear
		if id == MapDef.Id.BOUNCE:
			for pd: Array in MapDef.PADS:
				clear = clear and sp.distance_to(pd[0]) > MapDef.PAD_RADIUS + rr and sp.distance_to(pd[1]) > MapDef.STOMP_RADIUS + rr
		for j in range(i + 1, spawns.size()):
			clear = clear and sp.distance_to(spawns[j]) > 4.0 * rr
	check("map %s: eight clear spawn points" % nm, clear)
	var zones: Array = MapDef.zone_spots(id)
	var zok := zones.size() == 4
	for z: Rect2 in zones:
		zok = zok and z.size.is_equal_approx(Config.ARENA_SIZE / 4.0) and arena.encloses(z) and not z.intersects(crate_r) and not z.intersects(box_r)
		for o: Rect2 in obs:
			zok = zok and not z.intersects(o)
		if id == MapDef.Id.BELTS:
			for b: Array in MapDef.BELTS:
				zok = zok and not z.intersects(b[0])
		if id == MapDef.Id.BOUNCE:
			for pd: Array in MapDef.PADS:
				zok = zok and rect_dist(pd[0], z) > MapDef.PAD_RADIUS
		if id == MapDef.Id.LAVA:
			var cells := 0
			for c in MapDef.LAVA_COLS * MapDef.LAVA_ROWS:
				var cr := MapDef.lava_rect(c)
				if z.encloses(cr.grow(-0.01)):
					cells += 1
			zok = zok and cells == 2
	check("map %s: four free zone areas" % nm, zok)
	var s := map_sim(id)
	check("map %s: the sim has the statics of the map" % nm, s.map_id == id and s.statics.size() == s.wall_count + obs.size())
	# Floor-plan rules (docs/map-rework.md, step F). Walking connectivity holds for every map; the stricter rules
	# only for the maps whose plan has been rebuilt (MapDef.REWORKED).
	var grid := NavGrid.for_sim(s)
	var points: Array = []
	points.append_array(spawns)
	for z: Rect2 in zones:
		points.append(z.get_center())
	points.append(crate)
	points.append(box)
	var linked := true
	for q: Vector2 in points:
		linked = linked and grid.reachable(points[0], q)
	check("map %s: spawn points, zone areas, chest and present can all be reached from each other" % nm, linked)
	if id in MapDef.REWORKED:
		var fails := _passage_failures(obs)
		check("map %s: every passage is at least %.1f m wide" % [nm, PASSAGE_MIN], fails.is_empty(), str(fails))
		fails = _plan_failures(obs, spawns, s.statics)
		check("map %s: floor-plan rules (obstacle count, spawn spacing, hidden starts, free floor)" % nm, fails.is_empty(), str(fails))

const PASSAGE_MIN := 2.0

## Distance between two rectangles (0 when they touch or overlap).
func rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()

## Pairs (and obstacle/outer wall) that leave a gap narrower than PASSAGE_MIN without closing it. Touching is fine.
func _passage_failures(obs: Array) -> Array:
	var out := []
	var arena := Rect2(Vector2.ZERO, Config.ARENA_SIZE)
	for i in obs.size():
		var o: Rect2 = obs[i]
		for edge in [o.position.x, o.position.y, arena.end.x - o.end.x, arena.end.y - o.end.y]:
			if edge > 0.0 and edge < PASSAGE_MIN - 1e-6:
				out.append(["wall", o])
		for j in range(i + 1, obs.size()):
			var g := rect_gap(o, obs[j])
			if g > 0.0 and g < PASSAGE_MIN - 1e-6:
				out.append([o, obs[j], g])
	return out

## The rules of a rebuilt floor plan: 10..18 obstacles, spawn points 6 m apart, none closer than 14 m in sight of
## another, 1.5 m of free floor around each. Returns what is broken.
func _plan_failures(obs: Array, spawns: Array, statics: Array[Rect2]) -> Array:
	var out := []
	if obs.size() < 10 or obs.size() > 18:
		out.append("obstacle count %d" % obs.size())
	var grid := NavGrid.new()
	grid.build(statics, Config.new().player_radius)
	for i in spawns.size():
		var a: Vector2 = spawns[i]
		for o: Rect2 in obs:
			if rect_dist(a, o) < 1.5:
				out.append(["floor around spawn", i])
		for j in range(i + 1, spawns.size()):
			var d := a.distance_to(spawns[j])
			if d < 6.0:
				out.append(["spawns too close", i, j])
			elif d < 14.0 and grid.line_clear(a, spawns[j], 0.0):
				out.append(["spawns see each other", i, j])
	return out

func _floor_plan_rule_tests() -> void:
	# a synthetic layout that follows the rules, and variants that each break one
	var good: Array = []
	for k in 10:
		good.append(Rect2(4.0 + 2.8 * k, 5.0 + (k % 2) * 2.0, 0.8, 2.4))
	var spawns: Array = [Vector2(2.0, 2.0), Vector2(30.0, 12.0)]
	var st: Array[Rect2] = [Rect2(-2, -2, 36, 2), Rect2(-2, 14.4, 36, 2), Rect2(-2, 0, 2, 14.4), Rect2(32, 0, 2, 14.4)]
	var all: Array[Rect2] = st.duplicate()
	for o: Rect2 in good:
		all.append(o)
	check("floor-plan rules: a good layout passes both", _passage_failures(good).is_empty() and _plan_failures(good, spawns, all).is_empty(), str(_plan_failures(good, spawns, all)))
	check("floor-plan rules: a gap of 1.0 m between two obstacles fails", not _passage_failures([Rect2(5, 5, 1, 3), Rect2(7, 5, 1, 3)]).is_empty())
	check("floor-plan rules: touching obstacles (an L) pass", _passage_failures([Rect2(5, 5, 1, 3), Rect2(6, 5, 3, 1)]).is_empty())
	check("floor-plan rules: an obstacle 1.0 m from the outer wall fails", not _passage_failures([Rect2(5, 1, 1, 3)]).is_empty())
	check("floor-plan rules: an obstacle against the outer wall passes", _passage_failures([Rect2(5, 0, 1, 3)]).is_empty())
	check("floor-plan rules: too few obstacles fail", not _plan_failures(good.slice(0, 5), spawns, st).is_empty())
	check("floor-plan rules: spawn points 4 m apart fail", not _plan_failures(good, [Vector2(2, 2), Vector2(6, 2)], all).is_empty())
	check("floor-plan rules: two starts in sight of each other 10 m apart fail", not _plan_failures(good, [Vector2(2, 1), Vector2(12, 1)], st).is_empty())
	check("floor-plan rules: a start with no free floor around it fails", not _plan_failures(good, [Vector2(4.4, 4.0), Vector2(30, 13)], all).is_empty())
	var seen := _plan_failures(good, [Vector2(1.0, 1.0), Vector2(31.0, 13.4)], all)
	check("floor-plan rules: far apart starts need no wall between them", not seen.any(func(f: Variant) -> bool: return f is Array and f[0] == "spawns see each other"))

## Map 0 (Train Set) is rebuilt, point-symmetric about the arena centre, so that no start is better than another.
func _train_set_plan_tests() -> void:
	check("map Train Set: it is marked as reworked, so the strict floor-plan rules run on it", 0 in MapDef.REWORKED)
	var c := Config.ARENA_SIZE * 0.5
	var mirrored := true
	for o: Rect2 in Config.OBSTACLES:
		var m := Rect2(Config.ARENA_SIZE - o.end, o.size)
		var found := false
		for q: Rect2 in Config.OBSTACLES:
			found = found or (q.position.distance_to(m.position) < 1e-4 and q.size.distance_to(m.size) < 1e-4)
		mirrored = mirrored and found
	for sp: Vector2 in Config.SPAWNS:
		var found := false
		for q: Vector2 in Config.SPAWNS:
			found = found or q.distance_to(2.0 * c - sp) < 1e-4
		mirrored = mirrored and found
	check("map Train Set: obstacles and spawn points are point-symmetric about the centre", mirrored)

## Map 1 (Assembly Line) is rebuilt: point-symmetric, the belt runs through openings in two dividing walls.
func _assembly_plan_tests() -> void:
	check("map Assembly Line: it is marked as reworked, so the strict floor-plan rules run on it", 1 in MapDef.REWORKED)
	var size := Config.ARENA_SIZE
	var obs: Array = MapDef.obstacles(1)
	var mirrored := true
	for o: Rect2 in obs:
		var m := Rect2(size - o.end, o.size)
		var found := false
		for q: Rect2 in obs:
			found = found or (q.position.distance_to(m.position) < 1e-4 and q.size.distance_to(m.size) < 1e-4)
		mirrored = mirrored and found
	for sp: Vector2 in MapDef.spawns(1):
		var found := false
		for q: Vector2 in MapDef.spawns(1):
			found = found or q.distance_to(size - sp) < 1e-4
		mirrored = mirrored and found
	for z: Rect2 in MapDef.zone_spots(1):
		var found := false
		for q: Rect2 in MapDef.zone_spots(1):
			found = found or q.position.distance_to(size - z.end) < 1e-4
		mirrored = mirrored and found
	check("map Assembly Line: obstacles, spawn points and zone areas are point-symmetric about the centre", mirrored)
	# no wall stands on the belt, and a wall that crosses the belt leaves its whole width open
	var on_belt := false
	for o: Rect2 in obs:
		for b: Array in MapDef.BELTS:
			on_belt = on_belt or o.grow(-0.001).intersects(b[0])
	check("map Assembly Line: no wall stands on the belt", not on_belt)
	var crossings := 0
	var open_ok := true
	for b: Array in MapDef.BELTS:
		var br: Rect2 = b[0]
		for x in [9.5, 22.5]:
			if br.position.x < x and br.end.x > x:
				crossings += 1
				var lo := 0.0
				var hi := size.y
				for o: Rect2 in obs:
					if o.position.x < x and o.end.x > x:
						if o.end.y <= br.position.y:
							lo = maxf(lo, o.end.y)
						elif o.position.y >= br.end.y:
							hi = minf(hi, o.position.y)
				open_ok = open_ok and hi - lo >= br.size.y
	check("map Assembly Line: the belt crosses both dividing walls through an opening as wide as the belt", crossings == 2 and open_ok)

## Map 4 (Magnet Lab) is rebuilt: point-symmetric, every magnet stands in a broken square (walls on three sides, open
## corners, the long middle wall on the fourth) that blocks a straight throw from outside but not a bent one.
func _magnet_plan_tests() -> void:
	check("map Magnet Lab: it is marked as reworked, so the strict floor-plan rules run on it", 4 in MapDef.REWORKED)
	var size := Config.ARENA_SIZE
	var obs: Array = MapDef.obstacles(4)
	var mirrored := true
	for o: Rect2 in obs:
		var m := Rect2(size - o.end, o.size)
		var found := false
		for q: Rect2 in obs:
			found = found or (q.position.distance_to(m.position) < 1e-3 and q.size.distance_to(m.size) < 1e-3)
		mirrored = mirrored and found
	for sp: Vector2 in MapDef.spawns(4):
		var found := false
		for q: Vector2 in MapDef.spawns(4):
			found = found or q.distance_to(size - sp) < 1e-4
		mirrored = mirrored and found
	for z: Rect2 in MapDef.zone_spots(4):
		var found := false
		for q: Rect2 in MapDef.zone_spots(4):
			found = found or q.position.distance_to(size - z.end) < 1e-3
		mirrored = mirrored and found
	check("map Magnet Lab: obstacles, spawn points and zone areas are point-symmetric about the centre", mirrored)
	# the magnets are the first two obstacles and stand where MAGNETS says
	var at_magnets := obs.size() >= 2
	for k in MapDef.MAGNETS.size():
		at_magnets = at_magnets and (obs[k] as Rect2).get_center().distance_to(MapDef.MAGNETS[k]) < 1e-3
	check("map Magnet Lab: the first two obstacles are the magnets", at_magnets)
	# a straight throw from outside a square cannot reach its magnet (left or right of it, above and below); the
	# inner side towards the middle wall is open
	var s := map_sim(4)
	var grid := NavGrid.for_sim(s)
	var blocked := true
	var open_inner := true
	for k in MapDef.MAGNETS.size():
		var m: Vector2 = MapDef.MAGNETS[k]
		var outward := -1.0 if k == 0 else 1.0
		for from: Vector2 in [m + Vector2(4.0 * outward, 0.0), m + Vector2(0.0, -5.0), m + Vector2(0.0, 5.0)]:
			blocked = blocked and not grid.line_clear(from, m + (from - m).normalized() * 0.9, 0.0)
		open_inner = open_inner and grid.line_clear(m + Vector2(-3.4 * outward, 0.0), m - Vector2(0.9 * outward, 0.0), 0.0)
	check("map Magnet Lab: a straight throw from the outside, above or below never reaches a magnet", blocked)
	check("map Magnet Lab: the inner side of each square is open", open_inner)
	# three wall pieces stand within 5 m of each magnet (centre of the piece) and not near the other one
	var near := 0
	for k in MapDef.MAGNETS.size():
		for i in range(2, obs.size()):
			var c: Vector2 = (obs[i] as Rect2).get_center()
			if c.distance_to(MapDef.MAGNETS[k]) < 5.0 and c.distance_to(MapDef.MAGNETS[1 - k]) > 5.0:
				near += 1
	check("map Magnet Lab: three wall pieces (outer, above, below) close in each magnet from its own side", near == 6, str(near))
	# the middle wall has a door on each side of its centre piece, 2.0 m wide
	var mid_ok := false
	var tops := 0.0
	var bottoms := 0.0
	for o: Rect2 in obs:
		if absf(o.get_center().x - size.x * 0.5) < 0.01 and o.position.y < 0.01:
			tops = o.end.y
		if absf(o.get_center().x - size.x * 0.5) < 0.01 and absf(o.end.y - size.y) < 0.01:
			bottoms = o.position.y
	var centre: Rect2 = obs[2]
	mid_ok = tops > 0.0 and bottoms > 0.0 and centre.position.y - tops >= 2.0 - 1e-3 and bottoms - centre.end.y >= 2.0 - 1e-3
	check("map Magnet Lab: the middle wall reaches both outer walls and leaves a door of at least 2 m on each side of its centre piece", mid_ok)

## Map 3 (Bounce House) is rebuilt: mirror-symmetric about x = 16 (three long walls with one door each, a pad and a
## landing spot in every strip), landing spots in the open, and a bot that takes a trampoline when the walk is long.
func _bounce_plan_tests() -> void:
	check("map Bounce House: it is marked as reworked, so the strict floor-plan rules run on it", 3 in MapDef.REWORKED)
	var size := Config.ARENA_SIZE
	var obs: Array = MapDef.obstacles(3)
	var mirrored := true
	for o: Rect2 in obs:
		var m := Rect2(size.x - o.end.x, o.position.y, o.size.x, o.size.y)
		var found := false
		for q: Rect2 in obs:
			found = found or (q.position.distance_to(m.position) < 1e-4 and q.size.distance_to(m.size) < 1e-4)
		mirrored = mirrored and found
	for sp: Vector2 in MapDef.spawns(3):
		var found := false
		for q: Vector2 in MapDef.spawns(3):
			found = found or q.distance_to(Vector2(size.x - sp.x, sp.y)) < 1e-4
		mirrored = mirrored and found
	for z: Rect2 in MapDef.zone_spots(3):
		var found := false
		for q: Rect2 in MapDef.zone_spots(3):
			found = found or q.position.distance_to(Vector2(size.x - z.end.x, z.position.y)) < 1e-4
		mirrored = mirrored and found
	for pd: Array in MapDef.PADS:
		var found := false
		for q: Array in MapDef.PADS:
			found = found or (q[0] as Vector2).distance_to(Vector2(size.x - pd[0].x, pd[0].y)) < 1e-4 and (q[1] as Vector2).distance_to(Vector2(size.x - pd[1].x, pd[1].y)) < 1e-4
		mirrored = mirrored and found
	check("map Bounce House: obstacles, spawn points, zone areas and trampolines are mirror-symmetric about x = 16", mirrored)
	# the long walls divide the room into four strips; every strip has one pad and one landing spot
	var long_walls: Array[Rect2] = []
	for o: Rect2 in obs:
		if o.size.y > 8.0:
			long_walls.append(o)
	var strip := func(x: float) -> int:
		var n := 0
		for w in long_walls:
			if x > w.end.x:
				n += 1
		return n
	var pads_in := [0, 0, 0, 0]
	var lands_in := [0, 0, 0, 0]
	var reach_ok := long_walls.size() == 3
	for pd: Array in MapDef.PADS:
		var a: int = strip.call(pd[0].x)
		var b: int = strip.call(pd[1].x)
		pads_in[a] += 1
		lands_in[b] += 1
		reach_ok = reach_ok and b != a and absi(b - a) <= 2
	check("map Bounce House: every strip has one trampoline and one landing spot, and a jump goes to another strip at most two away", pads_in == [1, 1, 1, 1] and lands_in == [1, 1, 1, 1] and reach_ok, "%s %s" % [pads_in, lands_in])
	# a landing spot has room for the stomp circle and a player around it, and is not in a doorway of a long wall
	var rr := Config.new().player_radius
	var room := MapDef.STOMP_RADIUS + rr
	var open_ok := true
	var near_pad := true
	for pd: Array in MapDef.PADS:
		var land: Vector2 = pd[1]
		for o: Rect2 in obs:
			open_ok = open_ok and rect_dist(land, o) >= room
		for w in long_walls:
			open_ok = open_ok and absf(land.x - w.get_center().x) >= room + 0.5 * w.size.x
		open_ok = open_ok and land.x >= room and land.x <= size.x - room and land.y >= room and land.y <= size.y - room
		for sp: Vector2 in MapDef.spawns(3):
			near_pad = near_pad and sp.distance_to(pd[0]) >= 2.0
	check("map Bounce House: every landing spot has the stomp radius and a player of free floor around it, outside the doorways", open_ok)
	check("map Bounce House: no trampoline lies within 2 m of a spawn point", near_pad)
	# bots: a long walk and a trampoline close by and landing much nearer to the goal: take the trampoline
	var s := map_sim(MapDef.Id.BOUNCE, [0], 7, true)
	place(s, 0, MapDef.spawns(3)[0])
	var b := Bot.new(0, s.cfg, 11)
	b.wander_target = Vector2(28.0, 9.0)
	b.wander_t = 1000.0
	var launched := false
	for _t in 60 * 4:
		s.step([b.think(s, 1.0 / 60.0), inp(), inp(), inp()])
		launched = launched or has_event(s.events, "launch")
	check("bot: far from its goal behind a wall it takes the trampoline of its strip", launched and s.players[0].pos.x > MapDef.PADS[0][1].x - 1.0, str(s.players[0].pos))
	# ... but not when the landing spot is outside the zone
	s = map_sim(MapDef.Id.BOUNCE, [0], 7, true)
	place(s, 0, MapDef.spawns(3)[0])
	b = Bot.new(0, s.cfg, 11)
	var goal := Vector2(28.0, 9.0)
	var zone_in := Rect2(0.0, 0.0, 14.0, 14.4)
	var zone_out := Rect2(0.0, 0.0, 9.0, 14.4)
	check("bot: it takes the trampoline when the landing spot is inside the zone", b._pad_goal(s, s.players[0], goal, zone_in, 1.0) == MapDef.PADS[0][0])
	b = Bot.new(0, s.cfg, 11)
	check("bot: it does not take a trampoline whose landing spot is outside the zone", b._pad_goal(s, s.players[0], goal, zone_out, 1.0) == goal)
	b = Bot.new(0, s.cfg, 11)
	check("bot: it walks when the goal is close", b._pad_goal(s, s.players[0], s.players[0].pos + Vector2(1.5, 0.0), Rect2(), 1.0) != MapDef.PADS[0][0])

## Map 2 (Lava Mats) is rebuilt: point-symmetric, and no wall closes the seam inside a mat pair.
func _lava_plan_tests() -> void:
	check("map Lava Mats: it is marked as reworked, so the strict floor-plan rules run on it", 2 in MapDef.REWORKED)
	var size := Config.ARENA_SIZE
	var obs: Array = MapDef.obstacles(2)
	var mirrored := true
	for o: Rect2 in obs:
		var m := Rect2(size - o.end, o.size)
		var found := false
		for q: Rect2 in obs:
			found = found or (q.position.distance_to(m.position) < 1e-4 and q.size.distance_to(m.size) < 1e-4)
		mirrored = mirrored and found
	for sp: Vector2 in MapDef.spawns(2):
		var found := false
		for q: Vector2 in MapDef.spawns(2):
			found = found or q.distance_to(size - sp) < 1e-4
		mirrored = mirrored and found
	for z: Rect2 in MapDef.zone_spots(2):
		var found := false
		for q: Rect2 in MapDef.zone_spots(2):
			found = found or q.position.distance_to(size - z.end) < 1e-4
		mirrored = mirrored and found
	check("map Lava Mats: obstacles, spawn points and zone areas are point-symmetric about the centre", mirrored)
	# the seam inside a mat pair (x = 4, 12, 20, 28) stays open for at least half of every mat's edge
	var worst := 0.0
	for pair in MapDef.LAVA_COLS / 2:
		var x := (pair * 2 + 1) * MapDef.LAVA_TILE.x
		for row in MapDef.LAVA_ROWS:
			var y0 := row * MapDef.LAVA_TILE.y
			var covered := 0.0
			for o: Rect2 in obs:
				if o.position.x < x - 1e-4 and o.end.x > x + 1e-4:
					covered += maxf(0.0, minf(o.end.y, y0 + MapDef.LAVA_TILE.y) - maxf(o.position.y, y0))
			worst = maxf(worst, covered / MapDef.LAVA_TILE.y)
	# no sealed pocket: every free spot of the floor can be walked to from the first spawn point
	var t := map_sim(2, [0])
	var grid := NavGrid.for_sim(t)
	var sealed := 0
	for row in NavGrid.ROWS:
		for col in NavGrid.COLS:
			if grid.is_free(col, row) and not grid.reachable(MapDef.spawns(2)[0], NavGrid.center(col, row)):
				sealed += 1
	check("map Lava Mats: no part of the floor is sealed off", sealed == 0, "sealed=%d" % sealed)
	check("map Lava Mats: no wall closes more than half of the seam inside a mat pair", worst <= 0.5 + 1e-4, "worst=%.2f" % worst)

func _map_tests() -> void:
	for id in Config.MAP_COUNT:
		_map_geometry(id)
	_floor_plan_rule_tests()
	_train_set_plan_tests()
	_assembly_plan_tests()
	_lava_plan_tests()
	_bounce_plan_tests()
	_magnet_plan_tests()
	_nav_tests()
	_bot_path_tests()
	_spawn_spread_tests()
	check("maps: the counts agree", Config.MAP_COUNT == MapDef.NAMES.size() and MapDef.HINTS.size() == Config.MAP_COUNT and MapDef.OBSTACLES.size() == Config.MAP_COUNT and MapDef.SPAWNS.size() == Config.MAP_COUNT and MapDef.ZONE_SPOTS.size() == Config.MAP_COUNT)
	# the config value
	var c := Config.new()
	c.map = 3
	var c2 := Config.new()
	c2.from_dict(c.to_dict())
	check("map config: survives to_dict and from_dict", c2.map == 3)
	var bad_ok := true
	for bad in ["x", 99, -5, NAN, null, 2.5e30]:
		var d := c.to_dict()
		d["map"] = bad
		c2.from_dict(d)
		bad_ok = bad_ok and c2.map == 0
	check("map config: garbage becomes map 0", bad_ok)
	var dr := c.to_dict()
	dr["map"] = -1
	c2.from_dict(dr)
	check("map config: the rotation value -1 is kept", c2.map == Config.MAP_ROTATE)
	c.reset()
	check("map config: reset leaves the map", c.map == 3)
	# set_map and load_state rebuild the layout
	var s := map_sim(0)
	s.set_map(MapDef.Id.LAVA)
	check("map: set_map builds the layout of the new map", s.map_id == MapDef.Id.LAVA and s.statics.size() == s.wall_count + MapDef.obstacles(MapDef.Id.LAVA).size())
	var snap := map_sim(MapDef.Id.MAGNETS).save_state()
	s.load_state(snap)
	check("map: loading a snapshot of another map rebuilds the layout", s.map_id == MapDef.Id.MAGNETS and s.statics.size() == s.wall_count + MapDef.obstacles(MapDef.Id.MAGNETS).size())
	_belt_tests()
	_lava_tests()
	_bounce_tests()
	_magnet_tests()
	_pig_tests()
	_map_determinism_tests()

func _belt_tests() -> void:
	var s := map_sim(MapDef.Id.BELTS, [0], 7, true)
	place(s, 0, Vector2(5.0, 3.7))
	var x0 := 5.0
	step_collect(s, 60)
	check("belts: a standing player rides the belt at its speed", absf(s.players[0].pos.x - (x0 + MapDef.BELT_SPEED)) < 0.2 and absf(s.players[0].pos.y - 3.7) < 0.1, str(s.players[0].pos))
	s = map_sim(MapDef.Id.BELTS, [0], 7, true)
	place(s, 0, Vector2(5.0, 8.0))
	step_collect(s, 60)
	check("belts: off the belt nothing moves", s.players[0].pos.is_equal_approx(Vector2(5.0, 8.0)), str(s.players[0].pos))
	s = map_sim(MapDef.Id.BELTS, [0], 7, true)
	place(s, 0, Vector2(5.0, 3.7))
	s.map_t = MapDef.BELT_RUN + 0.1
	step_collect(s, 40)
	check("belts: standing still while the belt turns", s.players[0].pos.is_equal_approx(Vector2(5.0, 3.7)), str(s.players[0].pos))
	step_collect(s, 100)
	check("belts: after the stop the belt runs the other way", s.players[0].pos.x < 5.0 - 0.5, str(s.players[0].pos))
	s = map_sim(MapDef.Id.BELTS, [0], 7, true)
	place(s, 0, Vector2(3.5, 3.7))
	step_collect(s, int(MapDef.BELT_RUN * 60.0) - 5)
	check("belts: the corner pieces carry a player along the whole S", s.players[0].pos.x > 29.0 and s.players[0].pos.y > 9.5, str(s.players[0].pos))
	s = map_sim(MapDef.Id.BELTS, [0], 7, true)
	s.statics.append(Rect2(6.5, 2.6, 1.0, 2.2))
	place(s, 0, Vector2(4.0, 3.7))
	step_collect(s, 120)
	check("belts: a block stops a carried player", s.players[0].pos.x < 6.5 - Config.new().player_radius + 0.05 and s.players[0].pos.x > 5.5, str(s.players[0].pos))
	s = map_sim(MapDef.Id.BELTS, [0, 1])
	s.crate_pos = Vector2(5.0, 3.7)
	var cx := s.crate_pos.x
	step_collect(s, 30)
	check("belts: the chest rides the belt too", s.crate_pos.x > cx + 1.0, str(s.crate_pos))
	# a carried lying yo-yo kills
	s = map_sim(MapDef.Id.BELTS, [0, 1], 7, true)
	s.statics.append(Rect2(9.6, 2.6, 1.0, 2.2))
	place(s, 1, Vector2(8.7, 3.7))
	place(s, 0, Vector2(3.0, 7.0))
	var h := s.players[0].heads[0]
	h.state = HS.OUT
	h.pos = Vector2(4.0, 3.7)
	h.prev_pos = h.pos
	h.limit = 1e9
	var evs := step_collect(s, 120)
	check("belts: a yo-yo lying on the belt is carried and kills", not s.players[1].alive and evs.any(func(e: Dictionary) -> bool: return e["type"] == "kill" and e["victim"] == 1 and e["killer"] == 0), str(h.pos))

func _lava_tests() -> void:
	var s := map_sim(MapDef.Id.LAVA, [0])
	place(s, 0, Vector2(16.0, 14.0))
	step_collect(s, int(MapDef.LAVA_CALM * 60.0) - 5)
	check("lava: no marked mats during the calm", s.lava_cells.is_empty())
	step_collect(s, 10)
	check("lava: the first warning marks the first wave", s.lava_cells.size() == MapDef.LAVA_FIRST)
	var pairs_ok := true
	var sizes := []
	for seed_value in 12:
		var t := map_sim(MapDef.Id.LAVA, [0], seed_value)
		for w in 8:
			t._draw_lava()
			sizes.append(t.lava_cells.size())
			var seen := {}
			for cell in t.lava_cells:
				pairs_ok = pairs_ok and not seen.has(cell / 2)
				seen[cell / 2] = true
	check("lava: never both mats of a pair", pairs_ok)
	check("lava: waves grow by LAVA_STEP and stop at LAVA_MAX", sizes.slice(0, 8) == [6, 8, 10, 12, 14, 16, 16, 16] and sizes.max() == MapDef.LAVA_MAX, str(sizes.slice(0, 8)))
	# a burning mat kills, a blinking one and a safe one do not
	var cell := 10
	var centre := MapDef.lava_rect(cell).get_center()
	var safe := MapDef.lava_rect(cell + 1).get_center() - Vector2(1.0, 0.0)   # clear of the wall of the new floor plan
	s = map_sim(MapDef.Id.LAVA, [0, 1])
	place(s, 0, centre)
	place(s, 1, safe)
	s.map_t = MapDef.LAVA_CALM + 0.3
	s.lava_cells = PackedInt32Array([cell])
	step_collect(s, 20)
	check("lava: a player on a blinking mat lives", s.players[0].alive)
	s.map_t = MapDef.LAVA_CALM + MapDef.LAVA_WARN + 0.01
	var evs := step_collect(s, 3)
	check("lava: on a burning mat dies without kill credit", not s.players[0].alive and evs.any(func(e: Dictionary) -> bool: return e["type"] == "kill" and e["victim"] == 0 and e["killer"] == -1 and e.get("cause", "") == "lava"))
	check("lava: a player on the safe mat of the pair lives", s.players[1].alive)
	s.map_t = MapDef.LAVA_CALM + MapDef.LAVA_WARN + MapDef.LAVA_HOT + 0.01
	step_collect(s, 3)
	check("lava: the mats are cleared after the wave", s.lava_cells.is_empty())
	s.lava_cells = PackedInt32Array([cell])
	check("lava: a respawn avoids marked mats", s.spawn_unsafe(centre) and not s.spawn_unsafe(safe))
	s = map_sim(MapDef.Id.LAVA, [0, 1])
	s.map_t = 20.0
	s.lava_wave = 3
	s.lava_cells = PackedInt32Array([1, 4])
	s.start_match(10)
	check("lava: a new round resets the clock, the waves and the mats", s.map_t == 0.0 and s.lava_wave == 0 and s.lava_cells.is_empty())
	_lava_escape_tests()
	_lava_bot_wall_test()

## A bot on a marked mat whose nearest safe mat lies behind a wall walks around the wall instead of pushing at it.
func _lava_bot_wall_test() -> void:
	var s := map_sim(MapDef.Id.LAVA, [0], 7, true)
	s.players[0].pos = Vector2(15.4, 5.4)   # right of the short bar at x 14..15; the nearest safe mat (x 8..12) is behind it
	s.map_t = MapDef.LAVA_CALM + 0.1
	s.lava_cells = PackedInt32Array([3, 4, 11, 12])
	var bot := Bot.new(0, s.cfg, 300)
	for _t in 75:
		s.step([bot.think(s, 1.0 / 60.0)])
	check("lava: a bot flees around a wall to the safe mat behind it", not s.lava_cells.has(MapDef.lava_cell(s.players[0].pos)), str(s.players[0].pos))

## Walking distance (metres, 8 neighbours on the NavGrid, no corner cutting) from every free cell to the nearest free
## cell of a mat that is not marked. -1.0 where there is no way.
func _escape_distances(grid: NavGrid, marked: PackedInt32Array) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(NavGrid.COLS * NavGrid.ROWS)
	dist.fill(1e9)
	for row in NavGrid.ROWS:
		for col in NavGrid.COLS:
			if grid.is_free(col, row) and not marked.has(MapDef.lava_cell(NavGrid.center(col, row))):
				dist[row * NavGrid.COLS + col] = 0.0
	var changed := true
	while changed:
		changed = false
		for row in NavGrid.ROWS:
			for col in NavGrid.COLS:
				if not grid.is_free(col, row):
					continue
				var here := row * NavGrid.COLS + col
				for k in 8:
					var dx: int = NavGrid.NEIGHBOURS[k].x
					var dy: int = NavGrid.NEIGHBOURS[k].y
					if not grid.is_free(col + dx, row + dy):
						continue
					if dx != 0 and dy != 0 and not (grid.is_free(col + dx, row) and grid.is_free(col, row + dy)):
						continue
					var d: float = dist[(row + dy) * NavGrid.COLS + col + dx] + NavGrid.CELL * (1.41421 if dx != 0 and dy != 0 else 1.0)
					if d < dist[here] - 1e-4:
						dist[here] = d
						changed = true
	return dist

## Whoever stands on a marked mat can walk to a safe one within the warning time, for every wave of many seeds. During
## the warning nothing burns yet, so only the length of the way counts (walls make it longer than the straight line).
func _lava_escape_tests() -> void:
	var limit := Config.new().player_speed * MapDef.LAVA_WARN
	var worst := 0.0
	var cells := 0
	var stuck := false
	var grid: NavGrid = null
	for seed_value in 12:
		var t := map_sim(MapDef.Id.LAVA, [0], seed_value)
		grid = NavGrid.for_sim(t)
		for w in 8:
			t._draw_lava()
			var dist := _escape_distances(grid, t.lava_cells)
			for row in NavGrid.ROWS:
				for col in NavGrid.COLS:
					if grid.is_free(col, row) and t.lava_cells.has(MapDef.lava_cell(NavGrid.center(col, row))):
						var d: float = dist[row * NavGrid.COLS + col]
						cells += 1
						worst = maxf(worst, d)
						stuck = stuck or d >= 1e8
	check("lava: every free spot of a marked mat has a safe mat within reach in the warning time (worst way %.1f m, limit %.1f m)" % [worst, limit], cells > 100 and not stuck and worst <= limit, "worst=%.2f cells=%d" % [worst, cells])

func _bounce_tests() -> void:
	var pad: Array = MapDef.PADS[0]
	var s := map_sim(MapDef.Id.BOUNCE, [0, 1, 2])
	place(s, 0, pad[0])
	place(s, 1, pad[1] + Vector2(1.0, 0.0))
	place(s, 2, pad[1] + Vector2(0.0, 2.2))
	var evs := step_collect(s, 2)
	check("bounce: a player on a trampoline is launched", s.players[0].air_t > 0.0 and has_event(evs, "launch"))
	var mid := s.players[0].pos
	var arr := idle4()
	arr[0] = inp(Vector2(0, 1), Vector2.ZERO, true)
	evs = step_collect(s, 10, arr)
	check("bounce: in the air input does nothing, the player flies towards the landing spot", s.players[0].pos.x > mid.x + 0.5 and s.players[0].pos.y > mid.y + 0.5 and s.players[0].pos.y < pad[1].y and s.players[0].air_t > 0.0, str(s.players[0].pos))
	check("bounce: nobody is hurt while the jumper flies", s.players[1].alive and s.players[2].alive)
	evs = step_collect(s, int(MapDef.AIR_TIME * 60.0))
	check("bounce: the jumper lands", has_event(evs, "land") and s.players[0].air_t == 0.0)
	check("bounce: the landing squashes a player next to the spot with credit for the jumper", not s.players[1].alive and evs.any(func(e: Dictionary) -> bool: return e["type"] == "kill" and e["victim"] == 1 and e["killer"] == 0))
	check("bounce: a player just outside the stomp radius lives", s.players[2].alive)
	s = map_sim(MapDef.Id.BOUNCE, [0, 1])
	place(s, 0, pad[0])
	place(s, 1, Vector2(2.0, 2.0))
	step_collect(s, 5)
	s._kill(s.players[0], null, "zone")
	check("bounce: a death in the air clears the flight", s.players[0].air_t == 0.0)

func _magnet_tests() -> void:
	var ends := []
	for t0 in [0.0, MapDef.MAGNET_PERIOD, MapDef.MAGNET_PERIOD - MapDef.MAGNET_OFF]:
		var s := map_sim(MapDef.Id.MAGNETS, [0])
		s.statics.resize(s.wall_count)    # the bending is tested on open floor, the walls of the plan would stop the throw
		place(s, 0, Vector2(6.0, 4.0))
		s.map_t = t0
		var path0 := s.aim_path(s.players[0])
		throw_i(s, 0, Vector2.RIGHT, 40)
		var h := s.players[0].heads[0]
		ends.append(h.pos)
	check("magnets: a pulling magnet bends the throw towards it", ends[0].y > 4.4, str(ends[0]))
	check("magnets: a pushing magnet bends it away", ends[1].y < 3.6, str(ends[1]))
	check("magnets: both off, the throw flies straight", absf(ends[2].y - 4.0) < 0.05, str(ends[2]))
	# the aim line is the real flight
	var s := map_sim(MapDef.Id.MAGNETS, [0])
	s.statics.resize(s.wall_count)
	place(s, 0, Vector2(6.0, 4.0))
	s.players[0].aim_dir = Vector2.RIGHT
	for _t in 40:
		s.step([inp(Vector2.ZERO, Vector2.RIGHT, true), inp(), inp(), inp()])
	var path := s.aim_path(s.players[0])
	var t_end := path[path.size() - 1]
	s.step([inp(), inp(), inp(), inp()])
	for _t in 100:
		if s.players[0].heads[0].state == HS.OUT:
			break
		s.step(idle4())
	check("magnets: the aim line ends where the throw lands", path.size() >= 2 and t_end.distance_to(s.players[0].heads[0].pos) < 0.5, "%s vs %s" % [t_end, s.players[0].heads[0].pos])
	var s0 := map_sim(MapDef.Id.TRAIN, [0])
	check("magnets: other maps keep the two-point aim line", s0.aim_path(s0.players[0]).size() == 2)
	# a lying yo-yo creeps towards the pulling magnet and away from the pushing one
	s = map_sim(MapDef.Id.MAGNETS, [0])
	place(s, 0, Vector2(6.0, 11.0))
	var h2 := s.players[0].heads[0]
	h2.state = HS.OUT
	h2.pos = Vector2(11.0, 4.5)
	h2.prev_pos = h2.pos
	step_collect(s, 60)
	var pulled := h2.pos.y
	s = map_sim(MapDef.Id.MAGNETS, [0])
	s.map_t = MapDef.MAGNET_PERIOD
	place(s, 0, Vector2(6.0, 11.0))
	h2 = s.players[0].heads[0]
	h2.state = HS.OUT
	h2.pos = Vector2(11.0, 4.5)
	h2.prev_pos = h2.pos
	step_collect(s, 60)
	check("magnets: a lying yo-yo creeps towards a pulling and away from a pushing magnet", pulled > 4.5 + 0.3 and h2.pos.y < 4.5 - 0.3, "%.2f %.2f" % [pulled, h2.pos.y])
	# the pulling and pushing magnets swap
	check("magnets: after one period the magnets have swapped", MapDef.magnet_sign(0, 0.0) == 1.0 and MapDef.magnet_sign(1, 0.0) == -1.0 and MapDef.magnet_sign(0, MapDef.MAGNET_PERIOD) == -1.0 and MapDef.magnet_sign(1, MapDef.MAGNET_PERIOD) == 1.0)

func _pig_tests() -> void:
	var s := map_sim(MapDef.Id.PIGGY, [0, 1])
	step_collect(s, int(MapDef.PIG_FILL * 60.0) + 2)
	check("pig: a coin appears every PIG_FILL seconds", s.pig_coins == 1)
	step_collect(s, int(MapDef.PIG_FILL * 60.0 * 5))
	check("pig: it holds at most PIG_MAX", s.pig_coins == MapDef.PIG_MAX)
	# hit the pig in a match
	s = map_sim(MapDef.Id.PIGGY, [0, 1])
	s.start_match(10)
	to_play(s)
	place(s, 0, Vector2(8.5, 7.2))
	place(s, 1, Vector2(2.0, 13.0))
	s.pig_coins = 2
	var evs := []
	for _t in 30:
		s.step([inp(Vector2.ZERO, Vector2.RIGHT, true), inp(), inp(), inp()])
	s.step(idle4())
	for _t in 60:
		s.step(idle4())
		evs.append_array(s.events)
	check("pig: a thrown yo-yo touching the pig empties it", s.pig_coins == 0 and evs.any(func(e: Dictionary) -> bool: return e["type"] == "pig" and e["coins"] == 2 and e["player"] == 0), "coins=%d" % s.pig_coins)
	check("pig: in a match the coins become the thrower's bonus", s.mode.bonus[0] == 2 and s.mode.bonus[1] == 0, str(s.mode.bonus))
	kill_i(s, 1)
	for _t in 10:
		s.step(idle4())
	check("pig: the bonus is paid with the round's coins and named in the coin text", s.mode.earned[0] >= 2 and MatchOverlay.coin_text(s.mode, 0).contains("piggy bank 2"), MatchOverlay.coin_text(s.mode, 0))
	check("pig: a new round empties the pig and the bonus", (func() -> bool:
		next_round(s)
		return s.pig_coins == 0 and s.mode.bonus[0] == 0).call())
	# a hit on an empty pig gives nothing; free play pays nothing
	s = map_sim(MapDef.Id.PIGGY, [0, 1])
	place(s, 0, Vector2(8.5, 7.2))
	s.pig_coins = 3
	for _t in 30:
		s.step([inp(Vector2.ZERO, Vector2.RIGHT, true), inp(), inp(), inp()])
	for _t in 80:
		s.step(idle4())
	check("pig: in free play the pig empties but nothing is paid", s.pig_coins == 0 and s.mode.bonus[0] == 0)
	s.pig_coins = 0
	s.players[0].heads[0].state = HS.OUT
	s.players[0].heads[0].pos = MapDef.PIG_RECT.get_center() + Vector2(0, -1.5)
	var before := s.pig_coins
	step_collect(s, 5)
	check("pig: a lying yo-yo does not collect", s.pig_coins == before)

func _map_determinism_tests() -> void:
	for id in Config.MAP_COUNT:
		var nm: String = MapDef.NAMES[id]
		var a := map_sim(id, [0, 1, 2, 3], 21)
		var b := map_sim(id, [0, 1, 2, 3], 21)
		var bots_a: Array[Bot] = []
		var bots_b: Array[Bot] = []
		for i in 4:
			bots_a.append(Bot.new(i, a.cfg, 300 + i))
			bots_b.append(Bot.new(i, b.cfg, 300 + i))
		var snap := PackedByteArray()
		var snap_ticks := 0
		var lava_deaths := 0
		var yo_kills := 0
		for t in 60 * 40:
			var ia: Array = []
			var ib: Array = []
			for i in 4:
				ia.append(bots_a[i].think(a, 1.0 / 60.0))
				ib.append(bots_b[i].think(b, 1.0 / 60.0))
			a.step(ia)
			b.step(ib)
			for e: Dictionary in a.events:
				if e["type"] == "kill":
					if e.get("cause", "") == "lava":
						lava_deaths += 1
					elif e["killer"] >= 0:
						yo_kills += 1
			if t == 60 * 12:
				snap = var_to_bytes(a.save_state())
				snap_ticks = t
		check("map %s: two sims with the same seed and bots stay identical for 40 s" % nm, var_to_bytes(a.save_state()) == var_to_bytes(b.save_state()))
		check("map %s: bots make kills with the yo-yo and rarely die of the map" % nm, yo_kills >= 3 and lava_deaths <= 6, "yo=%d lava=%d" % [yo_kills, lava_deaths])
		# save at 12 s, load into a fresh sim of the same config, step both without bots
		var c := map_sim(id, [0, 1, 2, 3], 5)
		c.load_state(bytes_to_var(snap))
		var d := map_sim(id, [0, 1, 2, 3], 21)
		var d_bots: Array[Bot] = []
		for i in 4:
			d_bots.append(Bot.new(i, d.cfg, 300 + i))
		for t in snap_ticks + 1:
			var idn: Array = []
			for i in 4:
				idn.append(d_bots[i].think(d, 1.0 / 60.0))
			d.step(idn)
		for _t in 240:
			c.step(idle4())
			d.step(idle4())
		check("map %s: a saved state loaded into a fresh sim continues identically" % nm, var_to_bytes(c.save_state()) == var_to_bytes(d.save_state()))

func _rotation_tests() -> void:
	var cfg := Config.new()
	cfg.map = Config.MAP_ROTATE
	var s := Sim.new(cfg, 3)
	check("rotation: free play before a match uses map 0", s.map_id == 0)
	for i in Config.NUM_PLAYERS:
		s.set_player_enabled(i, i < 2)
	s.start_match(20)
	var seen: Array[int] = [s.map_id]
	var rounds := Config.MAP_COUNT * 2 + 1
	for _r in rounds - 1:
		to_play(s)
		kill_i(s, 1)
		next_round(s)
		seen.append(s.map_id)
	var first := seen.slice(0, Config.MAP_COUNT)
	var second := seen.slice(Config.MAP_COUNT, Config.MAP_COUNT * 2)
	first.sort()
	second.sort()
	var want := []
	for m in Config.MAP_COUNT:
		want.append(m)
	check("rotation: every map comes once before any repeat", first == want and second == want, str(seen))
	var no_repeat := true
	for i in range(1, seen.size()):
		no_repeat = no_repeat and seen[i] != seen[i - 1]
	check("rotation: the map changes between rounds, also across a reshuffle", no_repeat and s.mode.map_bag.size() == Config.MAP_COUNT, str(seen))
	check("rotation: the layout follows the map", s.statics.size() == s.wall_count + MapDef.obstacles(s.map_id).size() and s.players[0].alive)
	# part of the state: save mid-match, a fresh sim continues with the same maps
	var twin := Sim.new(cfg, 99)
	twin.load_state(bytes_to_var(var_to_bytes(s.save_state())))
	var sa: Array[int] = []
	var sb: Array[int] = []
	for _r in 6:
		to_play(s)
		kill_i(s, 1)
		next_round(s)
		sa.append(s.map_id)
		to_play(twin)
		kill_i(twin, 1)
		next_round(twin)
		sb.append(twin.map_id)
	check("rotation: the bag is state, a loaded sim continues with the same maps", sa == sb and var_to_bytes(s.save_state()) == var_to_bytes(twin.save_state()), "%s vs %s" % [sa, sb])
	# the same seed gives the same order
	var s2 := Sim.new(cfg, 3)
	for i in Config.NUM_PLAYERS:
		s2.set_player_enabled(i, i < 2)
	s2.start_match(20)
	check("rotation: the order comes from the sim's seed", s2.map_id == seen[0])
	s.start_match(20)
	check("rotation: a rematch starts a fresh shuffle with every map still to come", s.mode.map_bag.size() == Config.MAP_COUNT and s.mode.map_bag_i == 1 and s.map_id == s.mode.map_bag[0], "i=%d" % s.mode.map_bag_i)
	# Training: a chosen map never rotates
	var tc := Config.new()
	tc.map = MapDef.Id.LAVA
	var t := Sim.new(tc, 3)
	for i in Config.NUM_PLAYERS:
		t.set_player_enabled(i, i < 2)
	t.start_match(20)
	var all_lava := t.map_id == MapDef.Id.LAVA
	for _r in 4:
		to_play(t)
		kill_i(t, 1)
		next_round(t)
		all_lava = all_lava and t.map_id == MapDef.Id.LAVA
	check("rotation: a fixed map (Training, --server) is never changed", all_lava and t.mode.map_bag.is_empty())


# ---------------------------------------------------------------- NavGrid, bots around walls, spread-out starts

func _nav_walls() -> Array[Rect2]:
	var st: Array[Rect2] = [Rect2(-2, -2, 36, 2), Rect2(-2, 14.4, 36, 2), Rect2(-2, 0, 2, 14.4), Rect2(32, 0, 2, 14.4)]
	return st

func _nav_tests() -> void:
	var rr := Config.new().player_radius
	var st := _nav_walls()
	st.append(Rect2(15.5, 2.0, 1.0, 10.4))   # a long wall with a 2 m gap above and below
	var g := NavGrid.new()
	g.build(st, rr)
	var a := Vector2(3.0, 7.2)
	var b := Vector2(29.0, 7.2)
	var path := g.find_path(a, b)
	check("nav: a path around the wall exists and ends at the goal", not path.is_empty() and path[path.size() - 1] == b)
	var free := true
	var dir_ok := true
	var corner_ok := true
	var through_gap := false
	var prev_cell := NavGrid.cell_of(a)
	for i in path.size():
		var c := NavGrid.cell_of(path[i])
		free = free and g.is_free(c.x, c.y)
		for r in st:
			free = free and rect_dist(path[i], r) >= rr - 1e-6
		if i > 0 or c != prev_cell:
			var dlt := c - prev_cell
			dir_ok = dir_ok and absi(dlt.x) <= 1 and absi(dlt.y) <= 1
			if dlt.x != 0 and dlt.y != 0:
				corner_ok = corner_ok and g.is_free(prev_cell.x + dlt.x, prev_cell.y) and g.is_free(prev_cell.x, prev_cell.y + dlt.y)
		prev_cell = c
		if absf(path[i].x - 16.0) < 0.5 and (path[i].y < 2.0 or path[i].y > 12.4):
			through_gap = true
	check("nav: every waypoint is free floor, steps are single cells, no corner is cut", free and dir_ok and corner_ok)
	check("nav: the path goes through a gap, not through the wall", through_gap)
	check("nav: the way around is longer than the straight line", _path_len(a, path) > a.distance_to(b) + 3.0)
	check("nav: a walking line through the wall is not clear, one above it is", not g.line_clear(a, b) and g.line_clear(Vector2(3, 1.0), Vector2(29, 1.0)) and g.line_clear(Vector2(3, 13.4), Vector2(29, 13.4)))
	check("nav: a line grazing the wall closer than the player radius is not clear", not g.line_clear(Vector2(10, 1.7), Vector2(20, 1.7)) and g.line_clear(Vector2(10, 1.2), Vector2(20, 1.2)))
	check("nav: segment test sees a hit and a miss", NavGrid.segment_hits_rect(Vector2(0, 0), Vector2(10, 10), Rect2(4, 4, 2, 2)) and not NavGrid.segment_hits_rect(Vector2(0, 0), Vector2(10, 0), Rect2(4, 4, 2, 2)))
	check("nav: next_point is the goal on a clear line and a corner of the way otherwise", g.next_point(Vector2(3, 1), Vector2(29, 1)) == Vector2(29, 1) and g.next_point(a, b).y < a.y - 1.0)
	var sealed := st.duplicate()
	sealed.append(Rect2(15.5, 0.0, 1.0, 2.0))
	sealed.append(Rect2(15.5, 12.4, 1.0, 2.0))
	var gs := NavGrid.new()
	gs.build(sealed, rr)
	check("nav: a sealed wall leaves no path", gs.find_path(a, b).is_empty() and not gs.reachable(a, b) and g.reachable(a, b))
	check("nav: a start inside a wall is snapped to free floor", g.reachable(Vector2(16.0, 7.0), a) and g.snap(Vector2(16.0, 7.0)) != Vector2(16.0, 7.0))
	var g2 := NavGrid.new()
	g2.build(st, rr)
	check("nav: same grid, same path (deterministic)", g2.find_path(a, b) == path)
	var s := map_sim(MapDef.Id.MAGNETS, [0, 1])
	var c1 := NavGrid.for_sim(s)
	var cached := NavGrid.for_sim(s) == c1
	s.statics.append(Rect2(8.0, 2.0, 1.0, 10.4))
	check("nav: the cache holds a grid per map and rebuilds it when the statics change", cached and NavGrid.for_sim(s) != c1 and not NavGrid.for_sim(s).line_clear(Vector2(3, 7.2), Vector2(13, 7.2)))
	var chest := map_sim(MapDef.Id.BELTS, [0, 1])
	var cg := NavGrid.for_sim(chest)
	var cc := NavGrid.cell_of(MapDef.crate_start(MapDef.Id.BELTS))
	check("nav: the chest is not a wall (its cell is free)", cg.is_free(cc.x, cc.y))

func _path_len(from: Vector2, path: PackedVector2Array) -> float:
	var d := 0.0
	var at := from
	for q in path:
		d += at.distance_to(q)
		at = q
	return d

func _bot_path_tests() -> void:
	var dt := 1.0 / 60.0
	# a bot behind a long wall reaches a goal on the other side
	var s := map_sim(MapDef.Id.MAGNETS, [0])
	s.statics.resize(s.wall_count)
	s.statics.append(Rect2(8.0, 2.0, 1.0, 10.4))
	place(s, 0, Vector2(3.0, 7.2))
	var bot := Bot.new(0, s.cfg, 11)
	var goal := Vector2(13.5, 3.0)
	bot.wander_target = goal
	bot.wander_t = 1e9
	var best := 1e9
	var t := 0
	while t < 60 * 15 and best > 1.0:
		var ins := idle4()
		ins[0] = bot.think(s, dt)
		s.step(ins)
		bot.wander_t = 1e9
		best = minf(best, s.players[0].pos.distance_to(goal))
		t += 1
	check("bot: placed behind a long wall it walks around it to a goal on the other side", best <= 1.0, "closest %.2f after %d ticks" % [best, t])
	# the same on every map's own layout: from each spawn to the opposite zone area, no sticking
	var stuck := []
	for id in Config.MAP_COUNT:
		var ms := map_sim(id, [0], 7, true)
		ms.cfg.train_speed = 0.0
		var sp: Array = MapDef.spawns(id)
		var zc: Vector2 = MapDef.zone_spots(id)[2].get_center()
		place(ms, 0, sp[0])
		var mb := Bot.new(0, ms.cfg, 5)
		mb.wander_target = zc
		var bestd := 1e9
		for _t in 60 * 25:
			var ins := idle4()
			ins[0] = mb.think(ms, dt)
			ms.step(ins)
			mb.wander_t = 1e9
			mb.wander_target = zc
			bestd = minf(bestd, ms.players[0].pos.distance_to(zc))
			if not ms.players[0].alive:
				break
		if bestd > 1.5:
			stuck.append([MapDef.NAMES[id], snappedf(bestd, 0.1)])
	check("bot: walks from a spawn point to a zone area on every map", stuck.is_empty(), str(stuck))
	# a throw needs a clear line
	var ts := map_sim(MapDef.Id.MAGNETS, [0, 1])
	ts.statics.append(Rect2(8.0, 2.0, 1.0, 10.4))
	place(ts, 0, Vector2(6.0, 4.0))
	place(ts, 1, Vector2(11.0, 4.0))
	var tb := Bot.new(0, ts.cfg, 3)
	var charged := false
	for _t in 60 * 12:
		tb.wander_target = Vector2(6.0, 4.0)
		tb.wander_t = 1e9
		tb.think(ts, dt)
		charged = charged or tb.phase != Bot.Phase.IDLE
	check("bot: does not throw at an enemy behind a wall", not charged)
	ts.statics.pop_back()
	var charged2 := false
	for _t in 60 * 12:
		tb.wander_target = Vector2(6.0, 4.0)
		tb.wander_t = 1e9
		tb.think(ts, dt)
		charged2 = charged2 or tb.phase != Bot.Phase.IDLE
	check("bot: throws at the same enemy once the wall is gone", charged2)

func _spawn_spread_tests() -> void:
	var bad := []
	var spread_ok := true
	var firsts := {}
	for id in Config.MAP_COUNT:
		var spawns: Array = MapDef.spawns(id)
		for n in [2, 3, 4, 8]:
			for sd in 25:
				var cfg := Config.new()
				cfg.map = id
				cfg.train_speed = 0.0
				var s := Sim.new(cfg, sd)
				for i in Config.NUM_PLAYERS:
					s.set_player_enabled(i, i < n)
				s.start_match(10)
				var used: Array[int] = []
				var ok := true
				for i in n:
					var idx := spawns.find(s.players[i].pos)
					if idx < 0:
						ok = false
						break
					if i == 0:
						firsts[id * 100 + idx] = true
					else:
						# independent greedy: the free point whose nearest given point is farthest, ties lowest index
						var want := -1
						var want_d := -1.0
						for k in spawns.size():
							if used.has(k):
								continue
							var d := 1e9
							for u in used:
								d = minf(d, (spawns[k] as Vector2).distance_to(spawns[u]))
							if d > want_d + 1e-9:
								want_d = d
								want = k
						ok = ok and idx == want
					used.append(idx)
				if not ok:
					bad.append([MapDef.NAMES[id], n, sd])
				if n == 2:
					var far := 0.0
					for k in spawns.size():
						far = maxf(far, (spawns[k] as Vector2).distance_to(s.players[0].pos))
					spread_ok = spread_ok and is_equal_approx(s.players[0].pos.distance_to(s.players[1].pos), far)
	check("spawns: after the first (drawn) point every player gets the free point farthest from all given ones", bad.is_empty(), str(bad.slice(0, 3)))
	check("spawns: two players start as far apart as the map allows, from any first point", spread_ok)
	check("spawns: the first point is drawn at random (many different first points over the seeds)", firsts.size() >= 3 * Config.MAP_COUNT, str(firsts.size()))
	# the same seed gives the same starts
	var starts := []
	for _r in 2:
		var cfg2 := Config.new()
		cfg2.map = 1
		var s2 := Sim.new(cfg2, 42)
		s2.start_match(10)
		starts.append([s2.players[0].pos, s2.players[1].pos, s2.players[2].pos, s2.players[3].pos])
	check("spawns: same seed, same starts", starts[0] == starts[1])
