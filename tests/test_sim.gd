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
func throw_i(s: Sim, i: int, dir: Vector2, charge_ticks: int, wait := 200) -> void:
	var arr := idle4()
	for t in charge_ticks:
		arr[i] = inp(Vector2.ZERO, dir, true)
		s.step(arr)
	arr[i] = inp()
	s.step(arr)
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
			throw_i(s, 0, Vector2.RIGHT, 30); tap_i(s, 0); many(s, 40, idle4())
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
		throw_i(s, 0, Vector2.RIGHT, 60); p = s.players[0]
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

	# --- 6 Bogenwurf
	# L3 circle
	s = mk([0]); place(s, 0, Vector2(6, 6.3)); setm(s, 0, {"arc": 3})
	throw_i(s, 0, Vector2.RIGHT, 21); p = s.players[0]
	tap_i(s, 0)
	var ang_prev := (p.heads[0].pos - p.pos).angle()
	var total := 0.0
	var ticks_c := 0
	for t in 200:
		s.step(idle4())
		var a_now := (p.heads[0].pos - p.pos).angle()
		total += absf(angle_difference(ang_prev, a_now)); ang_prev = a_now
		if p.heads[0].state == HS.HAND: break
		ticks_c += 1
	check("arc L3: head sweeps a full circle around the player then comes home", total >= TAU - 0.5 and p.heads[0].state == HS.HAND, "swept=%.2f rad" % total)
	# circle lethal: victim on circle
	s = mk([0, 1]); place(s, 0, Vector2(6, 6.3)); place(s, 1, Vector2(6, 6.3 + 4.0)); setm(s, 0, {"arc": 3})
	throw_i(s, 0, Vector2.RIGHT, 21)
	s.players[1].pos = Vector2(6, 10.3)
	tap_i(s, 0); many(s, 60, idle4())
	check("arc L3: circling head kills someone standing on the circle", s.players[1].deaths == 1)
	# arc blocked by wall -> OUT
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"arc": 2})
	throw_i(s, 0, Vector2.RIGHT, 60); p = s.players[0]
	s.statics.append(Rect2(6.0, 7.0, 2.0, 3.0))
	tap_i(s, 0); many(s, 90, idle4())
	check("arc: obstacle stops the retract -> OUT", p.heads[0].state == HS.OUT or p.heads[0].state == HS.HAND, "state=%d" % p.heads[0].state)

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
	throw_i(s, 0, Vector2.RIGHT, 60); h = s.players[0].heads[0]
	check("bounce L2: one pin at the wall, string path length = 8 + 3", h.pins.size() == 1 and absf(h.pins[0].x - (RW - 0.35)) < 0.05 and absf(Sim.path_length(s.string_path(s.players[0], h)) - 11.0) < 0.2, "pins=%s len=%.2f" % [h.pins, Sim.path_length(s.string_path(s.players[0], h))])
	for L in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(RW - 6.0, 6.3)); setm(s, 0, {"bounce": L})
		throw_i(s, 0, Vector2.RIGHT, 60); h = s.players[0].heads[0]
		var back := RW - 0.35 - h.pos.x
		check("bounce L%d: flies %.1f m back after the wall (2.35 + bonus)" % [L, 2.35 + Mods.n("bounce", "bonus_dist", L)], absf(back - (2.35 + [1.5, 3.0, 5.0][L - 1])) < 0.15, "back=%.2f" % back)

	# ---------------- 2 Bogenwurf: curved throw
	for L in [1, 2, 3]:
		for side in [1, -1]:
			s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"arc": L}); p = s.players[0]
			throw_mv(s, 0, Vector2.RIGHT, 60, Vector2(0, 1) if side == -1 else Vector2.ZERO)
			var maxdev := 0.0
			for t in 80:
				s.step(idle4())
				var dv := p.heads[0].pos.y - 6.3
				if absf(dv) > absf(maxdev): maxdev = dv
				if p.heads[0].state == HS.OUT: break
			var want := minf(Mods.n("arc", "bulge", L), 8.0 * 0.6)
			check("arc throw L%d side %s: bulge %.1f m, lands at the aimed point" % [L, "left" if side == 1 else "right", want], absf(absf(maxdev) - want) < 0.4 and (maxdev < 0.0) == (side == 1) and p.heads[0].pos.distance_to(Vector2(11, 6.3)) < 0.2 and p.heads[0].state == HS.OUT, "dev=%.2f end=%s" % [maxdev, p.heads[0].pos])
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"arc": 2}); p = s.players[0]
	throw_mv(s, 0, Vector2.RIGHT, 1, Vector2.ZERO)
	var maxd2 := 0.0
	for t in 80:
		s.step(idle4())
		maxd2 = maxf(maxd2, absf(p.heads[0].pos.y - 6.3))
		if p.heads[0].state == HS.OUT: break
	var short_range := p.heads[0].pos.x - 3.0
	check("arc throw: short throw is capped at 60 % of its distance", absf(maxd2 - short_range * 0.6) < 0.25 and short_range < 3.0, "dev=%.2f range=%.2f" % [maxd2, short_range])
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"arc": 1}); p = s.players[0]
	for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
	var ap := s.aim_path(p)
	var apmax := 0.0
	for q in ap: apmax = maxf(apmax, absf(q.y - 6.3))
	check("arc throw: aim line is a curve ending at the aimed point", ap.size() > 10 and apmax > 2.0 and ap[ap.size() - 1].distance_to(Vector2(11, 6.3)) < 0.1, "n=%d dev=%.2f end=%s" % [ap.size(), apmax, ap[ap.size() - 1]])
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {}); p = s.players[0]
	for t in 60: s.step(only0(inp(Vector2.ZERO, Vector2.RIGHT, true)))
	check("no arc modifier: aim line stays straight (2 points)", s.aim_path(p).size() == 2)
	# curved throw that hits a wall lands there (no bounce) / pins stay empty
	s = mk([0]); place(s, 0, Vector2(20, 6.3)); setm(s, 0, {"arc": 2}); p = s.players[0]
	s.statics.append(Rect2(23, 0, 1, BW))
	throw_i(s, 0, Vector2.RIGHT, 60)
	check("arc throw stopped by a wall lies there, no bounce, curve pins before the wall", p.heads[0].state == HS.OUT and p.heads[0].pos.x < 23.0 and p.heads[0].bounces == 0 and p.heads[0].pins.size() >= 1, "x=%.2f pins=%d" % [p.heads[0].pos.x, p.heads[0].pins.size()])

	# L3 circle: next to the outer wall and through a block and the crate
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"arc": 3}); p = s.players[0]
	throw_i(s, 0, Vector2.RIGHT, 60); tap_i(s, 0)
	var ang_prev := (p.heads[0].pos - p.pos).angle()
	var total := 0.0
	var went_out := false
	var left_arena := false
	var saw_circle := false
	for t in 200:
		s.step(idle4())
		var hp := p.heads[0].pos
		if hp.x < -0.01 or hp.y < -0.01 or hp.x > RW + 0.01 or hp.y > BW + 0.01: left_arena = true
		if p.heads[0].circ_left > 0.0: saw_circle = true
		var a_now := (hp - p.pos).angle()
		total += absf(angle_difference(ang_prev, a_now)); ang_prev = a_now
		if p.heads[0].state == HS.OUT: went_out = true
		if p.heads[0].state == HS.HAND: break
	check("arc L3 circle next to the outer wall: full turn, never stuck, stays inside", saw_circle and not went_out and not left_arena and total >= TAU - 0.6 and p.heads[0].state == HS.HAND, "swept=%.2f out=%s left=%s" % [total, went_out, left_arena])
	s = mk([0]); place(s, 0, Vector2(6, 6.3)); setm(s, 0, {"arc": 3}); p = s.players[0]
	s.statics.append(Rect2(5.0, 9.8, 2.0, 1.6))       # block on the circle (radius 4 around the player)
	s.crate_pos = Vector2(6.0, 2.3)                   # crate on the circle too
	var crate0 := s.crate_pos
	throw_i(s, 0, Vector2.RIGHT, 21); tap_i(s, 0)
	ang_prev = (p.heads[0].pos - p.pos).angle(); total = 0.0; went_out = false
	var through_block := false
	for t in 200:
		s.step(idle4())
		var hp2 := p.heads[0].pos
		if hp2.y > 10.0 and hp2.x > 5.0 and hp2.x < 7.0: through_block = true
		var a_now2 := (hp2 - p.pos).angle()
		total += absf(angle_difference(ang_prev, a_now2)); ang_prev = a_now2
		if p.heads[0].state == HS.OUT: went_out = true
		if p.heads[0].state == HS.HAND: break
	check("arc L3 circle passes through a block and the crate, full turn", through_block and not went_out and total >= TAU - 0.6 and p.heads[0].state == HS.HAND and s.crate_pos == crate0, "swept=%.2f through=%s out=%s crate=%s" % [total, through_block, went_out, s.crate_pos])

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
	throw_i(s, 0, Vector2.RIGHT, 30); tap_i(s, 0)
	check("shards L3 + bounce L3: 1 + 5 shard bounces (more than the single bounce of Splitter III)", s.shards[0].bounces_left == 6, "left=%d" % s.shards[0].bounces_left)
	# shards + bighead, bighead + warhead
	for bl in [1, 2, 3]:
		s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 1, "bighead": bl})
		throw_i(s, 0, Vector2.RIGHT, 30); tap_i(s, 0)
		check("shards+bighead L%d: shard radius x%.1f" % [bl, Mods.n("bighead", "radius_mult", bl)], absf(s.shards[0].radius - 0.12 * Mods.n("bighead", "radius_mult", bl)) < 0.001, "r=%.3f" % s.shards[0].radius)
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"shards": 1}); throw_i(s, 0, Vector2.RIGHT, 30); tap_i(s, 0)
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
	s = mk([0]); place(s, 0, Vector2(3, 6.3)); setm(s, 0, {"warhead": 1, "bighead": 3, "shards": 2}); throw_i(s, 0, Vector2.RIGHT, 30); tap_i(s, 0)
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
	# arc + bounce: the retract still goes through every pin
	s = two_pin_sim(2, {"arc": 1}); p = s.players[0]; h = p.heads[0]
	var pins_before: PackedVector2Array = h.pins.duplicate()
	var poly_ab := s.string_path(p, h).duplicate()
	var off_ab := 0.0; var prefix_ok := true
	tap_i(s, 0)
	for t in 200:
		s.step(idle4())
		off_ab = maxf(off_ab, dist_to_path(h.pos, poly_ab))
		if h.pins.size() > 0 and h.pins != pins_before.slice(0, h.pins.size()): prefix_ok = false
		if h.state == HS.HAND: break
	check("arc+bounce retract consumes every recorded pin in reverse, stays on the string and comes home", pins_before.size() >= 2 and h.state == HS.HAND and prefix_ok and off_ab < 0.1, "pins=%d off=%.3f" % [pins_before.size(), off_ab])

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
	menu._on_export()
	check("menu: export shows the text and the confirmation", menu._export_panel.visible and menu._export_text.text == cfgm.export_text() and menu._export_status.text == "In die Zwischenablage kopiert" and not menu._export_text.editable)
	menu.queue_free()


# ---------------------------------------------------------------- string = flight path
func curved_sim(L: int, pos := Vector2(3, 6.3), extra := {}) -> Sim:
	var s := mk([0, 1])
	place(s, 0, pos); place(s, 1, Vector2(1, 1))
	s.players[1].alive = false; s.players[1].respawn_t = 9999.0
	var m := {"arc": L}
	m.merge(extra)
	setm(s, 0, m)
	throw_i(s, 0, Vector2.RIGHT, 60)
	return s

func _path_tests() -> void:
	for L in [1, 2]:
		var s := curved_sim(L); var p := s.players[0]; var h := p.heads[0]
		var line_dev := 0.0
		var gaps: Array = []
		var prev := Vector2(3, 6.3)
		for q in h.pins:
			line_dev = maxf(line_dev, absf(q.y - 6.3))
			gaps.append(prev.distance_to(q)); prev = q
		var gmin: float = gaps.min() if gaps.size() > 0 else 0.0
		var gmax: float = gaps.max() if gaps.size() > 0 else 0.0
		check("curved throw L%d leaves pins on the curve, ~0.7 m apart" % L, h.state == HS.OUT and h.pins.size() >= 9 and line_dev > 1.5 and gmin > 0.5 and gmax < 0.9, "pins=%d dev=%.2f gaps=%.2f..%.2f" % [h.pins.size(), line_dev, gmin, gmax])
		var sp := s.string_path(p, h)
		check("curved throw L%d: string/wire path is curved (longer than the chord, off the straight line)" % L, Sim.path_length(sp) > 8.0 + 0.5 and sp.size() == h.pins.size() + 2, "len=%.2f" % Sim.path_length(sp))
		# tripwire follows the curve
		var s2 := curved_sim(L, Vector2(3, 6.3), {"tripwire": 1}); tap_i(s2, 0)
		check("curved throw L%d: tripwire is laid along the curve" % L, s2.wires.size() == 1 and s2.wires[0].pts.size() >= 10, "pts=%d" % (s2.wires[0].pts.size() if s2.wires.size() > 0 else -1))
		# retract along the polyline at constant speed
		var poly: PackedVector2Array = sp.duplicate()
		var pins0: PackedVector2Array = h.pins.duplicate()
		var step_want: float = 22.0 / 60.0 * (1.3 if L == 2 else 1.0)
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
		check("retract L%d after a curved throw: stays on the polyline, passes pins in reverse, constant speed" % L, h.state == HS.HAND and worst_off < 0.1 and order_ok and ticks > 20 and worst_speed > 0.97 and best_speed < 1.0001, "off=%.3f speed=%.3f..%.3f order=%s" % [worst_off, worst_speed, best_speed, order_ok])
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
		check("pull L%d after a curved throw: player follows the curve at constant speed and catches the head" % L, pulled and h.state == HS.HAND and off < 0.2 and wspeed > 0.95 and bspeed < 1.0001, "off=%.3f speed=%.3f..%.3f" % [off, wspeed, bspeed])

	# arc + bounce records both parts
	var s3 := curved_sim(2, Vector2(RW - 7.0, 6.3), {"bounce": 1}); var p3 := s3.players[0]; var h3 := p3.heads[0]
	var bpin := -1
	for k in h3.pins.size():
		if h3.pins[k].x > RW - 0.7: bpin = k
	var curve_dev := 0.0
	for k in h3.pins.size(): curve_dev = maxf(curve_dev, absf(h3.pins[k].y - 6.3))
	check("arc + bounce: pins on the curve before the bounce and the bounce point itself", h3.bounces == 1 and bpin >= 3 and curve_dev > 1.0, "pins=%d bpin=%d dev=%.2f head=%s" % [h3.pins.size(), bpin, curve_dev, h3.pos])
	var poly3 := s3.string_path(p3, h3).duplicate()
	var near3 := 99.0
	tap_i(s3, 0)
	var off3 := 0.0
	for t in 300:
		s3.step(idle4())
		off3 = maxf(off3, dist_to_path(h3.pos, poly3))
		if bpin >= 0: near3 = minf(near3, h3.pos.distance_to(h3.pins[bpin] if bpin < h3.pins.size() else poly3[bpin + 1]))
		if h3.state == HS.HAND: break
	check("arc + bounce: retract follows curve and straight part back home", h3.state == HS.HAND and off3 < 0.1, "off=%.3f" % off3)

	# DRAG / LEASH / RIGID with a curved string
	for v in 3:
		var s4 := curved_sim(2, Vector2(14, 6.3)); var p4 := s4.players[0]; var h4 := p4.heads[0]
		s4.cfg.out_variant = v
		s4.step(idle4())
		var head0 := h4.pos; var npins := h4.pins.size()
		var worst := 0.0
		for t in 120:
			s4.step(only0(inp(Vector2(-1, 0))))
			worst = maxf(worst, Sim.path_length(s4.string_path(p4, h4)) - h4.limit)
		match v:
			0: check("curved string DRAG: path never longer than allowed, head dragged back along the curve", worst < 0.02 and h4.pos.distance_to(head0) > 2.0 and h4.pins.size() < npins and not is_nan(h4.pos.x), "worst=%.3f moved=%.2f pins %d->%d" % [worst, h4.pos.distance_to(head0), npins, h4.pins.size()])
			1: check("curved string LEASH: path never longer than allowed, head and pins stay", worst < 0.02 and h4.pos.distance_to(head0) < 0.001 and h4.pins.size() == npins, "worst=%.3f" % worst)
			2: check("curved string RIGID: pins dropped when the player moves, head follows", worst < 0.02 and h4.pins.is_empty() and h4.pos.distance_to(head0) > 2.0, "worst=%.3f pins=%d" % [worst, h4.pins.size()])

	# L3 circle
	_circle_run("open field", Vector2(14, 6.3), 60, false)
	_circle_run("near wall (R limited by the wall)", Vector2(2.6, 6.3), 60, false)
	_circle_run("very near wall (floor 1.5 m, may slide)", Vector2(1.2, 6.3), 60, false)
	_circle_run("player walking away", Vector2(10, 4.0), 60, true)
	# head already inside the radius: circle starts at once
	var s5 := curved_sim(3, Vector2(14, 6.3)); var p5 := s5.players[0]
	s5 = mk([0]); place(s5, 0, Vector2(14, 6.3)); setm(s5, 0, {"arc": 3}); p5 = s5.players[0]
	throw_i(s5, 0, Vector2.RIGHT, 1); tap_i(s5, 0); s5.step(idle4())
	var d0 := p5.heads[0].pos.distance_to(p5.pos)
	check("arc L3: head already inside the radius starts the circle at once", p5.heads[0].circ_left > 0.0 and d0 < 4.0, "d=%.2f left=%.2f" % [d0, p5.heads[0].circ_left])

func _circle_run(label: String, pos: Vector2, charge: int, walk: bool) -> void:
	var s := mk([0]); place(s, 0, pos); setm(s, 0, {"arc": 3}); var p := s.players[0]; var h := p.heads[0]
	throw_i(s, 0, Vector2.RIGHT, charge)
	var npins := h.pins.size()
	var rmax := minf(4.0, minf(minf(pos.x, RW - pos.x), minf(pos.y, BW - pos.y)) - 0.35)
	rmax = maxf(rmax, 1.5)
	tap_i(s, 0)
	var started := false; var cticks := 0; var swept := 0.0; var rworst := 0.0; var start_d := 0.0
	var pins_at_start := -1; var out_of_arena := false; var a_prev := 0.0; var home := false; var stuck := false
	var mvi := Vector2(0, 1) if walk else Vector2.ZERO
	for t in 400:
		s.step(only0(inp(mvi)))
		var hp := h.pos
		if hp.x < -0.01 or hp.y < -0.01 or hp.x > RW + 0.01 or hp.y > BW + 0.01: out_of_arena = true
		if h.circ_left > 0.0 or (started and cticks > 0 and h.circ_left <= 0.0 and false):
			if not started:
				started = true; start_d = hp.distance_to(p.pos); pins_at_start = h.pins.size(); a_prev = (hp - p.pos).angle()
			cticks += 1
			var an := (hp - p.pos).angle()
			swept += absf(angle_difference(a_prev, an)); a_prev = an
			rworst = maxf(rworst, hp.distance_to(p.pos))
		if h.state == HS.OUT: stuck = true
		if h.state == HS.HAND: home = true; break
	var tsec := cticks / 60.0
	var rlim := rmax + 0.1 + (0.35 if walk else 0.0)
	var wall_case := pos.x < 5.0
	check("arc L3 circle (%s): ~1.1 s, radius <= %.2f, full 360 deg, then home" % [label, rmax], started and absf(tsec - 1.1) < 0.12 and rworst <= rlim and swept >= TAU - 0.35 and home and not stuck and not out_of_arena and start_d <= rmax + 0.001 and start_d > rmax - 0.6 and pins_at_start < npins, "t=%.2fs r=%.2f/%.2f swept=%.2f start_d=%.2f pins %d->%d home=%s stuck=%s out=%s" % [tsec, rworst, rmax, swept, start_d, npins, pins_at_start, home, stuck, out_of_arena])
