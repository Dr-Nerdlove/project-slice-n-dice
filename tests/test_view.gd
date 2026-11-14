extends SceneTree
## Headless checks of the toy figures (pose mapping, motion tracking, building) and of the playroom arena.

var fails := 0
const A := ToyPose.Act


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  [" + info + "]" if info != "" else ""))
	if not ok:
		fails += 1


func facts(act: int, kind := ToyPose.Kind.DINO) -> ToyPose.Facts:
	var f := ToyPose.Facts.new()
	f.kind = kind
	match act:
		A.DEAD: f.alive = false
		A.SPAWN: f.since_spawn = 0.0
		A.WALK: f.fwd_speed = 1.0; f.gait = 1.0
		A.CHARGE: f.charging = true; f.charge = 1.0
		A.THROW: f.since_throw = 0.0
		A.OUT: f.out = true
		A.CATCH: f.since_catch = 0.0
		A.DASH: f.dashing = true
		A.DASH_STOP: f.since_dash = 0.0
		A.PULL: f.pulling = true
		A.STUN: f.stunned = true
	return f


func pose_of(f: ToyPose.Facts) -> Array[float]:
	var out := ToyPose.new_pose()
	ToyPose.targets(f, out)
	return out


func dist(a: Array[float], b: Array[float]) -> float:
	var d := 0.0
	for c in ToyPose.CHANNELS:
		d = maxf(d, absf(a[c] - b[c]))
	return d


func _initialize() -> void:
	test_pose_mapping()
	test_springs()
	test_motion()
	await test_figures()
	test_arena_geometry()
	await test_view_sources()
	await test_main_scene()
	quit(fails)


func test_pose_mapping() -> void:
	var acts := [A.IDLE, A.WALK, A.CHARGE, A.THROW, A.OUT, A.CATCH, A.DASH, A.DASH_STOP, A.PULL, A.STUN, A.DEAD, A.SPAWN]
	var poses := {}
	var wrong := []
	for act in acts:
		var f := facts(act)
		if ToyPose.act_of(f) != act:
			wrong.append(act)
		poses[act] = pose_of(f)
	check("pose: each situation is recognised as its action", wrong.is_empty(), str(wrong))
	var close := []
	for i in acts.size():
		for j in range(i + 1, acts.size()):
			if dist(poses[acts[i]], poses[acts[j]]) < 0.15:
				close.append([acts[i], acts[j]])
	check("pose: every action has its own pose (each pair differs by 0.15 or more in some channel)", close.is_empty(), str(close))
	var ch: Array[float] = poses[A.CHARGE]
	check("pose: full charge leans back, winds the yo-yo arm behind the shoulder, crouches and trembles",
			ch[ToyPose.LEAN] < -0.25 and ch[ToyPose.ARM] <= -0.99 and ch[ToyPose.SQUASH] < 0.9 and ch[ToyPose.TREMBLE] > 0.05 and ch[ToyPose.TWIST] < -0.3, str(ch))
	var th: Array[float] = poses[A.THROW]
	check("pose: throw lunges forward with the arm out", th[ToyPose.LEAN] > 0.5 and th[ToyPose.ARM] == 1.0 and th[ToyPose.STRETCH] > 1.2)
	var da: Array[float] = poses[A.DASH]
	check("pose: dash stretches along the dash and flattens", da[ToyPose.STRETCH] >= 1.4 and da[ToyPose.SQUASH] < 0.9 and da[ToyPose.LEAN] > 0.3)
	var ds: Array[float] = poses[A.DASH_STOP]
	check("pose: the end of a dash squashes the other way", ds[ToyPose.STRETCH] < 0.8 and ds[ToyPose.LEAN] < -0.2)
	var pu: Array[float] = poses[A.PULL]
	check("pose: pulled to the yo-yo: flying, stretched, leaning far forward, arm out", pu[ToyPose.LIFT] > 0.3 and pu[ToyPose.LEAN] > 0.6 and pu[ToyPose.STRETCH] > 1.3 and pu[ToyPose.ARM] == 1.0)
	var stun: Array[float] = poses[A.STUN]
	check("pose: stun is dizzy", stun[ToyPose.DIZZY] == 1.0)
	var ca: Array[float] = poses[A.CATCH]
	check("pose: catching squashes and recoils", ca[ToyPose.SQUASH] < 0.8 and ca[ToyPose.LEAN] < -0.2)
	var sp: Array[float] = poses[A.SPAWN]
	check("pose: respawn starts high above the floor", sp[ToyPose.LIFT] > 3.0)
	var land := facts(A.SPAWN)
	land.since_spawn = ToyPose.DROP_TIME + 0.01
	check("pose: respawn lands with a squash", pose_of(land)[ToyPose.LIFT] == 0.0 and pose_of(land)[ToyPose.SQUASH] < 0.7)
	check("pose: dead is the rest pose", dist(poses[A.DEAD], ToyPose.REST) < 0.0001)
	# Charge grows monotonically; the tremble only near full charge.
	var mono := true
	var prev := pose_of(facts(A.IDLE))
	var trem_early := 0.0
	for k in range(0, 21):
		var f := facts(A.CHARGE)
		f.charge = k / 20.0
		var o := pose_of(f)
		if k > 0 and (o[ToyPose.LEAN] > prev[ToyPose.LEAN] + 1e-6 or o[ToyPose.ARM] > prev[ToyPose.ARM] + 1e-6 or o[ToyPose.SQUASH] > prev[ToyPose.SQUASH] + 1e-6 or o[ToyPose.TWIST] > prev[ToyPose.TWIST] + 1e-6):
			mono = false
		if k / 20.0 < 0.85:
			trem_early = maxf(trem_early, o[ToyPose.TREMBLE])
		prev = o
	check("pose: the wind-up grows monotonically with the charge (lean, arm, crouch, twist)", mono)
	check("pose: no tremble below 85 % charge", trem_early == 0.0)
	# Walk flavours over one cycle.
	var amp := {}
	for kind in [ToyPose.Kind.DINO, ToyPose.Kind.ROBOT, ToyPose.Kind.BUNNY, ToyPose.Kind.DUCK]:
		var lift := 0.0
		var roll := 0.0
		for k in 32:
			var f := facts(A.WALK, kind)
			f.gait = TAU * k / 32.0
			var o := pose_of(f)
			lift = maxf(lift, o[ToyPose.LIFT])
			roll = maxf(roll, absf(o[ToyPose.ROLL]))
		amp[kind] = [lift, roll]
	check("pose: the bunny hops (lift far above the others)", amp[ToyPose.Kind.BUNNY][0] > 4.0 * maxf(amp[ToyPose.Kind.DINO][0], maxf(amp[ToyPose.Kind.ROBOT][0], amp[ToyPose.Kind.DUCK][0])), str(amp))
	check("pose: the duck waddles (most roll), the robot stays stiff (least)", amp[ToyPose.Kind.DUCK][1] > amp[ToyPose.Kind.DINO][1] and amp[ToyPose.Kind.ROBOT][1] < amp[ToyPose.Kind.DINO][1] * 0.6, str(amp))
	var both := facts(A.CHARGE)
	both.dashing = true
	check("pose: a dash while charging shows the dash (the faster tell wins)", ToyPose.act_of(both) == A.DASH)
	var still := facts(A.IDLE)
	check("pose: standing still does not walk", pose_of(still)[ToyPose.STEP] == 0.0 and ToyPose.act_of(still) == A.IDLE)


func test_springs() -> void:
	var results := []
	for fps in [30.0, 60.0, 120.0]:
		var shown := ToyPose.new_pose()
		var vel: Array[float] = []
		vel.resize(ToyPose.CHANNELS)
		vel.fill(0.0)
		var tgt := pose_of(facts(A.CHARGE))
		var t := 0.0
		var mid := ToyPose.new_pose()
		while t < 0.6 - 1e-6:
			ToyPose.spring_step(shown, vel, tgt, 1.0 / fps)
			t += 1.0 / fps
			if absf(t - 0.1) < 0.5 / fps:
				mid = shown.duplicate()
		results.append([shown.duplicate(), mid])
	var worst := 0.0
	for r in results:
		worst = maxf(worst, maxf(dist(r[0], results[1][0]), dist(r[1], results[1][1])))
	check("springs: the same pose at 30, 60 and 120 fps, on the way (0.1 s) and at the end (worst %.4f)" % worst, worst < 0.01)
	var tgt := pose_of(facts(A.CHARGE))
	var end: Array[float] = results[1][0]
	check("springs: the pose arrives within 0.6 s", dist(end, tgt) < 0.03, "%.3f" % dist(end, tgt))
	var mid: Array[float] = results[1][1]
	check("springs: after 0.1 s it is on its way (eased, not popped)", mid[ToyPose.ARM] < 0.0 and mid[ToyPose.ARM] > tgt[ToyPose.ARM] - 0.001 and dist(mid, tgt) > 0.01)


## A sim with one player standing at (10, 7).
func one_player() -> Sim:
	var s := Sim.new(Config.new(), 1)
	for i in 4:
		s.set_player_enabled(i, i == 0)
	var p := s.players[0]
	p.alive = true
	p.pos = Vector2(10, 7)
	p.prev_pos = p.pos
	p.facing = Vector2.RIGHT
	return s


func test_motion() -> void:
	var s := one_player()
	var p := s.players[0]
	var m := ToyMotion.new(ToyPose.Kind.DUCK)
	var dt := 1.0 / 60.0
	m.update(p, s, p.pos, dt)
	check("motion: a figure that appears drops in", m.spawned and m.act == A.SPAWN and m.shown[ToyPose.LIFT] > 3.0)
	for _k in 60:
		m.update(p, s, p.pos, dt)
	check("motion: then stands (idle) on the floor", m.act == A.IDLE and absf(m.shown[ToyPose.LIFT]) < 0.02)
	# Walking at full speed along the facing: walk pose, the facing turns eased.
	var pos := p.pos
	var lean_jump := 0.0
	var last_lean := m.shown[ToyPose.LEAN]
	for _k in 60:
		pos += Vector2.RIGHT * s.cfg.player_speed * dt
		m.update(p, s, pos, dt)
		lean_jump = maxf(lean_jump, absf(m.shown[ToyPose.LEAN] - last_lean))
		last_lean = m.shown[ToyPose.LEAN]
	check("motion: walking is recognised from the drawn movement", m.act == A.WALK and m.facts.fwd_speed > 0.9, "act=%d fwd=%.2f" % [m.act, m.facts.fwd_speed])
	check("motion: the walk leans in smoothly (no frame changes the lean by more than 0.03 rad)", lean_jump < 0.03, "%.3f" % lean_jump)
	p.facing = Vector2.UP
	m.update(p, s, pos, dt)
	var yaw1 := m.yaw
	check("motion: a turn is eased, not snapped", absf(angle_difference(yaw1, atan2(0.0, -1.0))) > 0.5 and absf(angle_difference(yaw1, atan2(1.0, 0.0))) > 0.05)
	for _k in 30:
		m.update(p, s, pos, dt)
	check("motion: ... and arrives", absf(angle_difference(m.yaw, atan2(0.0, -1.0))) < 0.02)
	# Throw and catch from the heads leaving and entering the hand.
	p.heads[0].state = SimHead.S.FLIGHT
	m.update(p, s, pos, dt)
	check("motion: a throw is noticed (lunge)", m.act == A.THROW)
	for _k in 30:
		m.update(p, s, pos, dt)
	check("motion: while the yo-yo is out the arm reaches forward", m.act == A.OUT and m.target[ToyPose.ARM] > 0.8)
	p.heads[0].state = SimHead.S.HAND
	m.update(p, s, pos, dt)
	check("motion: a catch is noticed (recoil)", m.act == A.CATCH)
	# A dash seen only in the drawn movement (online the dash_t of the others can fall between snapshots).
	for _k in 30:
		m.update(p, s, pos, dt)
	for _k in 6:
		pos += Vector2.UP * 25.0 * dt
		m.update(p, s, pos, dt)
	check("motion: a dash is recognised from the speed alone", m.act == A.DASH, "act=%d" % m.act)
	for _k in 3:
		m.update(p, s, pos, dt)
	check("motion: the end of the dash squashes", m.act == A.DASH_STOP)
	# A teleport (respawn far away) is no dash.
	for _k in 30:
		m.update(p, s, pos, dt)
	pos = Vector2(25, 3)
	m.update(p, s, pos, dt)
	check("motion: a jump across the arena is no dash", m.act != A.DASH and m.velocity.length() < 1.0)
	# Death and respawn.
	p.alive = false
	m.update(p, s, pos, dt)
	check("motion: death pops the figure (once)", m.popped and m.act == A.DEAD)
	m.update(p, s, pos, dt)
	check("motion: ... only on the frame of the death", not m.popped)
	p.alive = true
	m.update(p, s, pos, dt)
	check("motion: respawn drops in again", m.spawned and m.act == A.SPAWN)
	var hit_floor := INF
	for k in 60:
		m.update(p, s, pos, dt)
		if m.shown[ToyPose.LIFT] <= 0.05 and hit_floor == INF:
			hit_floor = (k + 1) * dt
	check("motion: the drop reaches the floor after the drop time (%.2f s)" % hit_floor, absf(hit_floor - ToyPose.DROP_TIME) < 0.04)
	# Charging winds the hand up behind the shoulder.
	p.charging = true
	p.charge_t = s.cfg.charge_time
	for _k in 40:
		m.update(p, s, pos, dt)
	check("motion: full charge winds the hand up", m.act == A.CHARGE and m.wind_up() > 0.9)
	p.charging = false
	p.stun_t = 0.5
	m.update(p, s, pos, dt)
	check("motion: stun", m.act == A.STUN)


func test_figures() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame
	var extras := {ToyPose.Kind.DINO: ["Tail"], ToyPose.Kind.ROBOT: ["Key"], ToyPose.Kind.BUNNY: ["Head/EarL", "Head/EarR", "Tail"], ToyPose.Kind.DUCK: ["Tail"]}
	for kind in [ToyPose.Kind.DINO, ToyPose.Kind.ROBOT, ToyPose.Kind.BUNNY, ToyPose.Kind.DUCK]:
		var fig := ToyFigure.new(kind, Color("ff2e88"))
		holder.add_child(fig)
		var missing := []
		for n in ["Body", "Head", "ArmL", "ArmR", "FootL", "FootR"] + extras[kind]:
			if fig.pose_node.get_node_or_null(n) == null:
				missing.append(n)
		var meshes := fig.find_children("*", "MeshInstance3D", true, false).size()
		check("figure %s: builds with its parts (%d meshes)" % [ToyFigure.NAMES[kind], meshes], missing.is_empty() and meshes >= 15 and meshes <= 45, str(missing))
		var fp := fig.body_footprint()
		check("figure %s: the body's footprint matches the hit circle (radius %.2f player radii)" % [ToyFigure.NAMES[kind], fp], fp > 0.85 and fp < 1.15)
		# It follows a player and pops when the player dies.
		var s := one_player()
		var p := s.players[0]
		for _k in 40:
			fig.sync(p, s, p.pos, 1.0 / 60.0)
		var ok_pos := fig.position.is_equal_approx(Vector3(10, 0, 7)) and is_equal_approx(fig.scale.x, s.cfg.player_radius)
		p.alive = false
		fig.sync(p, s, p.pos, 1.0 / 60.0)
		for _k in 10:
			fig.sync(p, s, p.pos, 1.0 / 60.0)
		var head := fig.pose_node.get_node("Head") as Node3D
		var flew := head.position.y > 2.5 and fig.visible
		for _k in 90:
			fig.sync(p, s, p.pos, 1.0 / 60.0)
		check("figure %s: stands at the player, scaled to the radius; pops into flying pieces and vanishes" % ToyFigure.NAMES[kind], ok_pos and flew and not fig.visible)
	holder.queue_free()
	await process_frame


func circle_rect(c: Vector2, r: float, rect: Rect2) -> bool:
	var q := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return q.distance_to(c) < r


func test_arena_geometry() -> void:
	var a := Config.ARENA_SIZE
	var r := Config.new().player_radius
	check("arena: 20:9 and bigger than the first one (28 x 12.6)", absf(a.x / a.y - 20.0 / 9.0) < 0.001 and a.x > 28.0, str(a))
	var s := Sim.new(Config.new(), 1)
	var inside := Rect2(Vector2.ZERO, a)
	var crate := s.crate_rect()
	var box := s.box_rect()
	var bad := []
	for sp in Config.SPAWNS:
		if sp.x < r or sp.y < r or sp.x > a.x - r or sp.y > a.y - r:
			bad.append(["outside", sp])
		for o in Config.OBSTACLES:
			if circle_rect(sp, r + 0.2, o):
				bad.append(["block", sp])
		if circle_rect(sp, r + 0.2, crate) or circle_rect(sp, r + 0.2, box):
			bad.append(["crate/box", sp])
	check("arena: every spawn inside, clear of blocks, crate and box", bad.is_empty(), str(bad))
	var clash := []
	for o in Config.OBSTACLES:
		if not inside.encloses(o):
			clash.append(["outside", o])
		if o.grow(0.5).intersects(crate) or o.grow(0.5).intersects(box):
			clash.append(["crate/box", o])
	if crate.grow(1.0).intersects(box) or not inside.encloses(crate) or not inside.encloses(box):
		clash.append("crate/box")
	check("arena: blocks inside, crate and box free and apart", clash.is_empty(), str(clash))
	var view := ArenaView.new()
	view.setup(s)
	var blocks := 0
	for c in view.playroom.get_children():
		if c.name.begins_with("Block"):
			blocks += 1
	check("arena: the playroom has one wooden block per obstacle, a crate and a box", blocks == Config.OBSTACLES.size() and view.playroom.crate != null and view.playroom.box != null)
	view.free()


## Online, every figure reads the same sim as the rest of its player: the own one the predicted sim, the others
## the interpolated display sim.
func test_view_sources() -> void:
	var cfg := Config.new()
	var pred := Sim.new(cfg, 1)
	var disp := Sim.new(cfg, 1)
	for sm in [pred, disp]:
		for k in 4:
			sm.set_player_enabled(k, k < 2)
			sm.players[k].alive = true
	disp.players[1].charging = true
	disp.players[1].charge_t = cfg.charge_time
	pred.players[0].charging = true
	pred.players[0].charge_t = cfg.charge_time
	disp.players[0].stun_t = 1.0     # must not reach the own figure
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(pred)
	view.use_sim(pred, 0)
	view.set_others(disp, 1.0)
	for _k in 40:
		view.render(1.0, 1.0 / 60.0)
	check("view: the other player's figure poses from the display sim (charging there)", view._figures[1].motion.act == A.CHARGE)
	check("view: the own figure poses from the predicted sim", view._figures[0].motion.act == A.CHARGE)
	var kinds := {}
	for f in view._figures:
		kinds[f.kind] = true
	check("view: four players, four different toys", view._figures.size() == 4 and kinds.size() == 4)
	view.queue_free()
	await process_frame


func test_main_scene() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for _i in 90:
		await process_frame
	var shown := 0
	for f: ToyFigure in main.view._figures:
		if f.visible:
			shown += 1
	check("main: offline the playroom and the toy figures are there and drawn", main.view.playroom != null and shown >= 1 and main.view._figures.size() == 4, "visible=%d" % shown)
	main.queue_free()
	await process_frame
