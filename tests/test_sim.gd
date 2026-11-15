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
	check("full charge throws ~max range", p.ystate == Y.OUT and absf(p.head.x - 3.0 - 8.0) < 0.2, "dist=%.2f" % (p.head.x - 3.0))
	s = mk([0]); place(s, 0, Vector2(3, 6.3))
	throw0(s, Vector2.RIGHT, 21)
	p = s.players[0]
	var expect := 2.5 + 0.5 * (8.0 - 2.5)
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

var _frames := 0
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_menu_tests()
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

	# --- 1 Stolperdraht
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

	# --- 2 Dicker Brocken
	var offs := [[0, 1.0, false], [1, 1.0, true], [1, 1.1, false], [2, 1.1, true], [2, 1.4, false], [3, 1.4, true], [3, 1.6, false]]
	for c in offs:
		s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(8, 6.3 + c[1])); setm(s, 0, {"bighead": c[0]} if c[0] > 0 else {})
		throw_i(s, 0, Vector2.RIGHT, 60)
		check("bighead L%d: offset %.1f %s" % [c[0], c[1], "hits" if c[2] else "misses"], (s.players[1].deaths == 1) == c[2])
	s = mk([0]); setm(s, 0, {"bighead": 3})
	check("bighead L3 radius x2.8", absf(s.head_r(s.players[0]) - 0.35 * 2.8) < 0.001)

	# --- 3 Gummiband
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

	# --- 4 Extra-Dash
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
	check("extradash: L3 dash 1.3x longer", absf(dist_d[3] - 3.9) < 0.15 and absf(dist_d[0] - 3.0) < 0.15 and absf(dist_d[2] - 3.0) < 0.15, str(dist_d))
	check("extradash: cooldown x1 / x0.75 / x0.5", absf(refill[0] / 60.0 - 1.2) < 0.1 and absf(refill[2] / 60.0 - 0.9) < 0.1 and absf(refill[3] / 60.0 - 0.6) < 0.1, str(refill))
	s = mk([0]); place(s, 0, Vector2(2, 6.3)); setm(s, 0, {"extradash": 3}); s.players[0].dash_charges = 4
	var nd := 0
	var last_x := 2.0
	for k in 6:
		s.step(only0(inp(Vector2.UP, Vector2.ZERO, false, true)))
		many(s, 8, only0(inp()))
	check("extradash L3: four dashes in a row (charges drained)", s.players[0].dash_charges <= 1, "left=%d" % s.players[0].dash_charges)

	# --- 5 Abpraller
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

	# --- 7 Durchschlag
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

	# --- 8 Splitter
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

	# --- 9 Sprengkopf
	var rad := {1: 1.6, 2: 2.4, 3: 3.4}
	for L in [1, 2, 3]:
		for off in [rad[L] + 0.5 - 0.3, rad[L] + 0.5 + 0.3]:
			var inside: bool = off < rad[L] + 0.5
			s = mk([0, 1]); place(s, 0, Vector2(3, 6.3)); place(s, 1, Vector2(11.0, 6.3 + off)); setm(s, 0, {"warhead": L})
			throw_i(s, 0, Vector2.RIGHT, 60)
			check("warhead L%d: victim %.1fm from landing %s" % [L, off, "dies" if inside else "survives"], (s.players[1].deaths == 1) == inside)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": 3})
	throw_i(s, 0, Vector2.RIGHT, 8)
	check("warhead L3: owner inside own explosion survives", s.players[0].alive and s.players[0].deaths == 0)
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

	# --- 10 Zwilling
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

	# ---------------- 1 Abpraller: pins recorded, distance per bounce already in the adapted check
	s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"bounce": 2})
	throw_i(s, 0, Vector2.RIGHT, 60, 200, true); h = s.players[0].heads[0]
	check("bounce L2: one pin at the wall, string path length = 8 + 3", h.pins.size() == 1 and absf(h.pins[0].x - (RW - 0.35)) < 0.05 and absf(Sim.path_length(s.string_path(s.players[0], h)) - 11.0) < 0.2, "pins=%s len=%.2f" % [h.pins, Sim.path_length(s.string_path(s.players[0], h))])
	for L in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"bounce": L})
		throw_i(s, 0, Vector2.RIGHT, 60, 200, true); h = s.players[0].heads[0]
		var back := RW - 0.35 - h.pos.x
		check("bounce L%d: flies %.1f m back after the wall (2.35 + bonus)" % [L, 2.35 + Mods.n("bounce", "bonus_dist", L)], absf(back - (2.35 + [1.5, 3.0, 5.0][L - 1])) < 0.15, "back=%.2f" % back)

	# ---------------- 3 Zwilling
	s = mk([0]); s.step(idle4())
	check("twin L0: one yo-yo", s.players[0].heads.size() == 1)
	# L2 Kreuzfeuer
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
	# Kreuzfeuer needs a free way: a block at the meeting point -> normal return
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
	check("shards L3 + bounce L3: 1 + 5 shard bounces (more than the single bounce of Splitter III)", s.shards[0].bounces_left == 6, "left=%d" % s.shards[0].bounces_left)
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
	check("synergy description carries its number", Mods.describe_synergy("shards_warhead", lv).contains("1,2") and Mods.describe_synergy("bighead_warhead", lv).contains("1,15"), Mods.describe_synergy("shards_warhead", lv))
	check("every synergy has a pair of known ids and a German text", Mods.SYNERGY_ORDER.size() == Mods.SYNERGIES.size() and Mods.SYNERGIES.keys().all(func(k): return (Mods.SYNERGIES[k]["ids"] as Array).size() == 2 and (Mods.SYNERGIES[k]["ids"] as Array).all(func(id): return Mods.ORDER.has(id)) and (Mods.SYNERGIES[k]["desc"] as String).length() > 20))

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

	# ---------------- 6 Stolperdraht on pull and along the path
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
	check("menu: synergy list shows the active combination for Du", menu._syn_label.text.contains("Splitter + Sprengkopf"), menu._syn_label.text)
	menu._show_page(1)
	menu._on_reset()
	check("menu: reset on the modifier page clears the levels (both) but not the values", cfgm.mods_you["shards"] == 0 and cfgm.mods_bots["pierce"] == 0 and cfgm.player_speed == 9.0)
	check("menu: synergy list is empty again after reset", menu._syn_label.text.begins_with("Keine"))
	cfgm.mods_you["shards"] = 1
	menu._show_page(0)
	menu._on_reset()
	check("menu: reset on the values page resets the values but not the levels", cfgm.player_speed == Config.DEFAULTS["player_speed"] and cfgm.mods_you["shards"] == 1)
	menu._show_page(3)
	check("menu: figure tab shows only the figure page", menu._figure_page.visible and not menu._values_page.visible and not menu._mods_page.visible and not menu._online_page.visible and menu._tab_figure.button_pressed)
	check("menu: figure page has one button per figure named after it and a preview area first", menu._figure_buttons.size() == Config.SKIN_COUNT and menu._figure_buttons[Config.SKIN_COUNT - 1].text == ToyFigure.NAMES[Config.SKIN_COUNT - 1] and menu._figure_preview.get_index() == 0 and menu._figure_buttons[0].button_pressed and not menu._figure_buttons[1].button_pressed)
	check("menu: the preview shows the configured figure at the start", menu._figure_preview.figure != null and menu._figure_preview.figure.kind == 0)
	menu._figure_buttons[2].pressed.emit()
	check("menu: pressing a figure button sets the choice", cfgm.character == 2)
	check("menu: only the chosen figure shows pressed", menu._figure_buttons[2].button_pressed and menu._figure_buttons.filter(func(b: Button) -> bool: return b.button_pressed).size() == 1)
	check("menu: the preview shows the pressed figure", menu._figure_preview.figure != null and menu._figure_preview.figure.kind == 2)
	menu._figure_buttons[Config.SKIN_COUNT - 1].pressed.emit()
	check("menu: ... and changes with the next button", menu._figure_preview.figure.kind == Config.SKIN_COUNT - 1 and cfgm.character == Config.SKIN_COUNT - 1)
	menu._figure_buttons[2].pressed.emit()
	menu._on_reset()
	check("menu: reset on the figure page leaves the figure", cfgm.character == 2 and menu._figure_buttons[2].button_pressed)
	cfgm.character = 1
	menu.refresh()
	check("menu: refresh shows the choice from the config", menu._figure_buttons[1].button_pressed and not menu._figure_buttons[2].button_pressed)
	check("menu: refresh also moves the preview", menu._figure_preview.figure.kind == 1)
	menu._show_page(0)
	menu._on_export()
	check("menu: export shows the text and the confirmation", menu._export_panel.visible and menu._export_text.text == cfgm.export_text() and menu._export_status.text == "In die Zwischenablage kopiert" and not menu._export_text.editable)
	menu.queue_free()


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
	# --- Zwilling with a head in hand: the stick charges the next throw, the flying head is not steered
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
			if d[0] == "train_speed" and d[1] == "Eisenbahn-Tempo" and d[2] == 0.0 and d[3] == 10.0:
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

	# Zwilling: only the touched head is picked up.
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
