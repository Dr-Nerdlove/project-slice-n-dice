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
	test_looks()
	test_die_roll()
	test_winding()
	await test_figures()
	await test_figure_details()
	await test_held_yoyo()
	await test_dino_die_figures()
	test_arena_geometry()
	await test_view_sources()
	await test_arena_view_figures()
	await test_playroom_details()
	await test_map_views()
	await test_wall_rows()
	await test_overhead()
	await test_bomb_view()
	await test_preview_framing()
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
	var K := ToyPose.Kind
	for kind in range(ToyFigure.NAMES.size()):
		var lift := 0.0
		var roll := 0.0
		var lean := 0.0
		for k in 32:
			var f := facts(A.WALK, kind)
			f.gait = TAU * k / 32.0
			var o := pose_of(f)
			lift = maxf(lift, o[ToyPose.LIFT])
			roll = maxf(roll, absf(o[ToyPose.ROLL]))
			lean += o[ToyPose.LEAN] / 32.0
		amp[kind] = [lift, roll, lean]
	check("pose: eight kinds, and a walk cycle for each", K.size() == 8 and ToyPose.CYCLE.size() == 8 and ToyFigure.NAMES.size() == 8 and ToyFigure.ACCENTS.size() == 8)
	check("pose: the bunny hops (lift far above the walkers)", amp[K.BUNNY][0] > 4.0 * maxf(amp[K.DINO][0], maxf(amp[K.ROBOT][0], amp[K.DUCK][0])), str(amp))
	var walkers := [K.DINO, K.ROBOT, K.DUCK, K.DIE, K.DOLL, K.TOP]
	var low := 0.0
	for kind in walkers:
		low = maxf(low, amp[kind][0])
	check("pose: the imp bounces on its spring (lift far above the walkers and above the bunny)", amp[K.IMP][0] > 4.0 * low and amp[K.IMP][0] > 1.2 * amp[K.BUNNY][0], str(amp))
	check("pose: the duck waddles (more roll than the dino), the robot stays stiff (least)", amp[K.DUCK][1] > amp[K.DINO][1] and amp[K.ROBOT][1] < amp[K.DINO][1] * 0.6, str(amp))
	check("pose: the die neither leans, rolls nor hops through the pose (the cube really rolls: ToyMotion.tumble)", amp[K.DIE][0] == 0.0 and amp[K.DIE][1] == 0.0 and absf(amp[K.DIE][2]) < 0.001, str(amp[K.DIE]))
	var die_charge := facts(A.CHARGE, K.DIE)
	die_charge.charge = 1.0
	check("pose: the die does not twist (its face stays to the front), not even when charging", pose_of(facts(A.WALK, K.DIE))[ToyPose.TWIST] == 0.0 and pose_of(die_charge)[ToyPose.TWIST] == 0.0)
	check("pose: the die's walk cycle is two quarter turns of its cube", absf(ToyPose.CYCLE[K.DIE] - 2.0 * ToyMotion.DIE_SIDE) < 0.001)
	var most_lean := -1.0
	for kind in [K.DINO, K.ROBOT, K.BUNNY, K.DUCK, K.IMP, K.DIE, K.DOLL]:
		most_lean = maxf(most_lean, amp[kind][2])
	check("pose: the top leans far into its walk (the largest mean lean)", amp[K.TOP][2] > most_lean + 0.05, str(amp))
	# Standing still: the doll sways and the top wobbles, the dino does not.
	var sway := {}
	for kind in [K.DINO, K.DOLL, K.TOP]:
		var lo := INF
		var hi := -INF
		for k in 60:
			var f := facts(A.IDLE, kind)
			f.time = k * 0.1
			var r := pose_of(f)[ToyPose.ROLL]
			lo = minf(lo, r)
			hi = maxf(hi, r)
		sway[kind] = hi - lo
	check("pose: the doll sways at rest and the top wobbles, the dino stands still", sway[K.DOLL] > 0.08 and sway[K.TOP] > 0.06 and sway[K.DINO] < 0.001, str(sway))
	var both := facts(A.CHARGE)
	both.dashing = true
	check("pose: a dash while charging shows the dash (the faster tell wins)", ToyPose.act_of(both) == A.DASH)
	var still := facts(A.IDLE)
	check("pose: standing still does not walk", pose_of(still)[ToyPose.STEP] == 0.0 and ToyPose.act_of(still) == A.IDLE)


## Winding of a mesh's triangles: sign of dot(cross(b-a, c-a), vertex normal) and of dot(cross, centre). Godot's
## front faces are clockwise from outside; a correct solid has the same sign as the built-in BoxMesh.
func winding_signs(mesh: Mesh) -> Dictionary:
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx.resize(vs.size())
		for i in vs.size():
			idx[i] = i
	var r := {"n_pos": 0, "n_neg": 0, "c_pos": 0, "c_neg": 0}
	for t in range(0, idx.size() - 2, 3):
		var a := vs[idx[t]]
		var b := vs[idx[t + 1]]
		var c := vs[idx[t + 2]]
		var cr := (b - a).cross(c - a)
		if cr.length() < 1e-7:
			continue            # degenerate (the poles)
		var n := ns[idx[t]] + ns[idx[t + 1]] + ns[idx[t + 2]]
		r["n_pos" if cr.dot(n) > 0.0 else "n_neg"] += 1
		r["c_pos" if cr.dot((a + b + c) / 3.0) > 0.0 else "c_neg"] += 1
	return r


func test_winding() -> void:
	var box := winding_signs(BoxMesh.new())
	var s: String = "pos" if box["n_pos"] > 0 else "neg"
	var o: String = "neg" if s == "pos" else "pos"
	check("mesh winding: the built-in box is consistent (%s)" % str(box), box["n_" + o] == 0 and box["c_" + o] == 0)
	for r in [0.12, 0.22, 0.3, 0.35, 1.0]:
		var w := winding_signs(ToyKit.rounded_box(r))
		check("mesh winding: rounded_box(%.2f) is wound like Godot's box, outward (%s)" % [r, str(w)],
				w["n_" + s] > 0 and w["n_" + o] == 0 and w["c_" + s] > 0 and w["c_" + o] == 0)


## Roly-poly doll tilt, snapper jaw: pure pose and springs.
func test_looks() -> void:
	var dt := 1.0 / 60.0
	# The doll tips into its run, swings back past upright when it stops, and the swing dies away.
	var f := facts(A.IDLE, ToyPose.Kind.DOLL)
	var shown := ToyPose.new_pose()
	var vel: Array[float] = []
	vel.resize(ToyPose.CHANNELS)
	vel.fill(0.0)
	var tgt := ToyPose.new_pose()
	f.fwd_speed = 1.0
	var tilt_run := 0.0
	for _k in 90:
		f.time += dt
		ToyPose.targets(f, tgt)
		ToyPose.spring_step(shown, vel, tgt, dt)
		tilt_run = maxf(tilt_run, shown[ToyPose.TILT_F])
	f.fwd_speed = 0.0
	var first_swing := 0.0     # most it rocks back past upright
	var late_swing := 0.0      # ... and in the last second
	var steps := 240
	for k in steps:
		f.time += dt
		ToyPose.targets(f, tgt)
		ToyPose.spring_step(shown, vel, tgt, dt)
		if k < steps / 2:
			first_swing = maxf(first_swing, absf(shown[ToyPose.TILT_F]) if shown[ToyPose.TILT_F] < 0.0 else 0.0)
		elif k >= steps - 60:
			late_swing = maxf(late_swing, absf(shown[ToyPose.TILT_F]))
	check("pose: the roly-poly doll tips into its run (%.2f rad), rocks back past upright when it stops (%.2f) and the swing decays (%.3f)" % [tilt_run, first_swing, late_swing],
			tilt_run > 0.4 and first_swing > 0.08 and late_swing < 0.25 * first_swing)
	# The snapper dino opens its jaw wider the longer the throw is charged and shuts it on the throw.
	var c0 := facts(A.CHARGE, ToyPose.Kind.DINO)
	c0.charge = 0.0
	var c1 := facts(A.CHARGE, ToyPose.Kind.DINO)
	c1.charge = 1.0
	var th := facts(A.THROW, ToyPose.Kind.DINO)
	var j0 := pose_of(c0)[ToyPose.JAW]
	var j1 := pose_of(c1)[ToyPose.JAW]
	var jt := pose_of(th)[ToyPose.JAW]
	check("pose: the dino's jaw opens wider with the charge (%.2f -> %.2f) and snaps shut on the throw (%.2f)" % [j0, j1, jt], j1 > j0 + 0.3 and j1 > 0.9 and jt < 0.05)
	var w0 := facts(A.WALK, ToyPose.Kind.DINO)
	w0.gait = 0.4
	var w1 := facts(A.WALK, ToyPose.Kind.DINO)
	w1.gait = 0.4 + PI * 0.5
	check("pose: the dino's jaw snaps open and shut in step with its walk", absf(pose_of(w0)[ToyPose.JAW] - pose_of(w1)[ToyPose.JAW]) > 0.5)
	var dw0 := facts(A.WALK, ToyPose.Kind.DOLL)
	dw0.gait = 0.0
	var dw1 := facts(A.WALK, ToyPose.Kind.DOLL)
	dw1.gait = PI * 0.5
	check("pose: the walking doll rocks with the cosine of its gait (roll %.3f at 0, %.3f at a quarter cycle)" % [pose_of(dw0)[ToyPose.ROLL], pose_of(dw1)[ToyPose.ROLL]], pose_of(dw0)[ToyPose.ROLL] > 0.04 and absf(pose_of(dw1)[ToyPose.ROLL]) < 0.01)
	var jst := pose_of(facts(A.STUN, ToyPose.Kind.DINO))[ToyPose.JAW]
	var st_other := pose_of(facts(A.STUN, ToyPose.Kind.ROBOT))[ToyPose.JAW]
	check("pose: the dazed dino's jaw hangs a little open (%.2f)" % jst, jst > 0.15 and jst < 0.5 and st_other == 0.0)
	var catch_max := 0.0
	var catch_first := 1.0
	var catch_last := 1.0
	for k in 21:
		var fc := facts(A.CATCH, ToyPose.Kind.DINO)
		fc.since_catch = ToyPose.CATCH_TIME * k / 20.0 * 0.999
		var jc := pose_of(fc)[ToyPose.JAW]
		catch_max = maxf(catch_max, jc)
		if k == 0:
			catch_first = jc
		catch_last = jc
	check("pose: the dino snaps once on a catch: shut, wide open, shut again (%.2f / %.2f / %.2f)" % [catch_first, catch_max, catch_last], catch_first < 0.05 and catch_max > 0.6 and catch_last < 0.1)


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
	var extras := {ToyPose.Kind.DINO: ["Tail"], ToyPose.Kind.ROBOT: ["Key"], ToyPose.Kind.BUNNY: ["Head/EarL", "Head/EarR", "Tail"], ToyPose.Kind.DUCK: ["Tail"],
			ToyPose.Kind.IMP: [], ToyPose.Kind.DIE: [], ToyPose.Kind.DOLL: [], ToyPose.Kind.TOP: []}
	for kind in range(ToyFigure.NAMES.size()):
		var fig := ToyFigure.new(kind, Color("ff2e88"))
		holder.add_child(fig)
		var missing := []
		for n in ["Body", "Head", "ArmL", "ArmR", "FootL", "FootR"] + extras[kind]:
			if fig.pose_node.get_node_or_null(n) == null:
				missing.append(n)
		var meshes := fig.find_children("*", "MeshInstance3D", true, false).size()
		check("figure %s: builds with its parts (%d meshes)" % [ToyFigure.NAMES[kind], meshes], missing.is_empty() and meshes >= 15 and meshes <= 58, str(missing))
		if kind == ToyPose.Kind.IMP or kind == ToyPose.Kind.TOP or kind == ToyPose.Kind.DOLL or kind == ToyPose.Kind.DIE:
			var feet_meshes := 0
			for fn in ["FootL", "FootR"]:
				feet_meshes += fig.pose_node.get_node(fn).find_children("*", "MeshInstance3D", true, false).size()
			check("figure %s: has no visible feet (the pieces exist but carry no meshes)" % ToyFigure.NAMES[kind], feet_meshes == 0, str(feet_meshes))
		var fp := fig.body_footprint()
		check("figure %s: the body's footprint matches the hit circle (radius %.2f player radii)" % [ToyFigure.NAMES[kind], fp], fp >= 0.9 and fp < 1.15)
		var reach := fig.solid_reach()
		check("figure %s: body and head fill the hit circle and do not stick out of it far (reach %.2f player radii)" % [ToyFigure.NAMES[kind], reach], reach >= 0.9 and reach <= 1.3)
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


func world_xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Blink, spring coils, spinning top and the paw, on figures that stand in the tree.
func test_figure_details() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame
	var dt := 1.0 / 60.0
	var K := ToyPose.Kind
	var blink_ok := true
	var paw_ok := true
	var rest_ok := []
	var wound_ok := []
	var reach_ok := []
	for kind in range(ToyFigure.NAMES.size()):
		var fig := ToyFigure.new(kind, Color("2ec4ff"))
		holder.add_child(fig)
		var s := one_player()
		var p := s.players[0]
		for _k in 60:
			fig.sync(p, s, p.pos, dt)
		var pos: Vector2 = p.pos
		var face := Vector2.RIGHT
		# --- blink: closes for a moment and opens again (forced, then by itself over ten seconds)
		if fig._eyes.is_empty():
			blink_ok = false
		else:
			fig._blink = 0.005
			fig.sync(p, s, p.pos, dt)
			fig.sync(p, s, p.pos, dt)
			var closed := (fig._eyes[0] as Node3D).basis.get_scale().y
			fig._blink = -ToyFigure.BLINK_TIME - 0.001
			fig.sync(p, s, p.pos, dt)
			var opened := (fig._eyes[0] as Node3D).basis.get_scale().y
			blink_ok = blink_ok and closed < 0.3 and opened > 0.9 and fig._blink > 1.0
			var shut := 0
			for _k in 600:
				fig.sync(p, s, p.pos, dt)
				if (fig._eyes[0] as Node3D).basis.get_scale().y < 0.3:
					shut += 1
			blink_ok = blink_ok and shut >= 3 and shut < 120
		# --- the paw: hand_point is the paw (plus the documented offset)
		var hr := s.head_r(p)
		var hp := fig.hand_point(pos, face, hr, 0.5)
		paw_ok = paw_ok and fig._paw != null and hp.is_equal_approx(fig._paw.global_position + Vector3(0, hr * 0.3, 0))
		# at rest it is in front of the body
		var rel := world_xz(hp) - pos
		if rel.dot(face) <= 0.1:
			rest_ok.append(kind)
		# wound up for a throw: behind the body, above the shoulder
		p.charging = true
		p.aim_dir = face
		p.charge_t = s.cfg.charge_time
		for _k in 60:
			fig.sync(p, s, p.pos, dt)
		var wp := fig.hand_point(pos, face, hr, 0.5)
		if not ((world_xz(wp) - pos).dot(face) < 0.0 and wp.y > fig._arm_r.global_position.y):
			wound_ok.append(kind)
		p.charging = false
		for _k in 60:
			fig.sync(p, s, p.pos, dt)
		# a yo-yo out to the side: the hand lies on that side (and so does the arm)
		p.heads[0].state = SimHead.S.FLIGHT
		var lateral := {}
		for dirv in [Vector2.UP, Vector2.DOWN, Vector2.RIGHT]:
			fig.string_dir = dirv
			for _k in 40:
				fig.sync(p, s, p.pos, dt)
			lateral[dirv] = world_xz(fig.hand_point(pos, face, hr, 0.5)) - pos
		# The yo-yo arm is the figure's right one (towards UP here): that side is reached, the far side only
		# half way across the body, but the hand still moves towards it.
		if not (lateral[Vector2.UP].dot(Vector2.UP) > 0.3 and lateral[Vector2.DOWN].dot(Vector2.DOWN) > lateral[Vector2.UP].dot(Vector2.DOWN) + 0.3 and lateral[Vector2.RIGHT].dot(Vector2.RIGHT) > 0.2):
			reach_ok.append([kind, lateral])
		fig.string_dir = Vector2.ZERO
		p.heads[0].state = SimHead.S.HAND
		fig.queue_free()
		await process_frame
	check("figure: every kind has eyes that close for a moment and open again, by themselves too", blink_ok)
	check("figure: hand_point is the paw of the yo-yo arm (plus the documented offset)", paw_ok)
	check("figure: at rest the hand is in front of the body", rest_ok.is_empty(), str(rest_ok))
	check("figure: wound up for a throw the hand is behind the body and above the shoulder", wound_ok.is_empty(), str(wound_ok))
	check("figure: with the yo-yo out the hand follows the direction of the string", reach_ok.is_empty(), str(reach_ok))
	var fb := ToyFigure.new(K.DINO, Color.WHITE)       # not in the tree: the old formula
	var hpf := fb.hand_point(Vector2(10, 7), Vector2.RIGHT, 0.3, 0.5)
	check("figure: outside the tree hand_point falls back to the formula", hpf.x > 10.0 and absf(hpf.y - 0.5) < 0.01, str(hpf))
	fb.free()

	# --- the imp's spring stays on the floor while it hops
	var imp := ToyFigure.new(K.IMP, Color("2ec4ff"))
	holder.add_child(imp)
	var si := one_player()
	imp.sync(si.players[0], si, si.players[0].pos, dt)
	imp.motion.shown[ToyPose.LIFT] = 0.0
	imp._apply_pose()
	var floor_y := imp._coils[0].global_position.y
	imp.motion.shown[ToyPose.LIFT] = 0.8
	imp._apply_pose()
	var pr := si.cfg.player_radius
	var coil_low := imp._coils[0].global_position.y
	var coil_top := imp._coils[3].global_position.y
	check("figure Springteufel: the lowest coil stays near the floor at the top of a hop (%.2f, rest %.2f)" % [coil_low, floor_y],
			imp._coils.size() == 4 and absf(coil_low - floor_y) < 0.25 * pr and coil_top > coil_low + 0.5 * pr)
	imp.queue_free()

	# --- the top's spinning part turns while it moves, and much more slowly while it stands
	var top := ToyFigure.new(K.TOP, Color("2ec4ff"))
	holder.add_child(top)
	var st := one_player()
	var pt := st.players[0]
	for _k in 30:
		top.sync(pt, st, pt.pos, dt)
	var a0 := top._spin.rotation.y
	for _k in 30:
		top.sync(pt, st, pt.pos, dt)
	var idle_turn := absf(angle_difference(a0, top._spin.rotation.y))
	var pos2: Vector2 = pt.pos
	var moved_turn := 0.0
	for _k in 30:
		var before: float = top._spin.rotation.y
		pos2 += Vector2.RIGHT * st.cfg.player_speed * dt
		top.sync(pt, st, pos2, dt)
		moved_turn += absf(angle_difference(before, top._spin.rotation.y))
	check("figure Kreisel: its spinning part turns while it runs (%.2f rad, standing %.2f)" % [moved_turn, idle_turn], top._spin != null and moved_turn > 2.0 and moved_turn > 3.0 * idle_turn)
	# --- the duck's wheels turn with the distance travelled (and stand still when it stands)
	var duck := ToyFigure.new(K.DUCK, Color("ff2e88"))
	holder.add_child(duck)
	var sdk := one_player()
	var pdk := sdk.players[0]
	for _k in 20:
		duck.sync(pdk, sdk, pdk.pos, dt)
	var wa := duck._wheels[0].rotation.x
	for _k in 20:
		duck.sync(pdk, sdk, pdk.pos, dt)
	var still_turn := absf(angle_difference(wa, duck._wheels[0].rotation.x))
	var travelled := 0.0
	var posd: Vector2 = pdk.pos
	var angle_sum := 0.0
	for _k in 60:
		var before: float = duck._wheels[0].rotation.x
		posd += Vector2.RIGHT * sdk.cfg.player_speed * dt
		travelled += sdk.cfg.player_speed * dt
		duck.sync(pdk, sdk, posd, dt)
		angle_sum += absf(angle_difference(before, duck._wheels[0].rotation.x))
	var expect := travelled / (sdk.cfg.player_radius * 0.34)
	check("figure Ente: four wheels; they turn with the distance (%.1f rad for %.1f m, about %.1f expected), not when standing (%.3f)" % [angle_sum, travelled, expect, still_turn],
			duck._wheels.size() == 4 and still_turn < 0.01 and angle_sum > 0.6 * expect and angle_sum < 1.4 * expect)
	duck.queue_free()
	# The base turns at its own speed: slowly standing, clearly faster running, fastest in a dash.
	var applied := [true]
	var base_turn := func(speed_factor: float, dash: bool) -> float:
		var t2 := ToyFigure.new(K.TOP, Color("2ec4ff"))
		holder.add_child(t2)
		var s2 := one_player()
		var p2 := s2.players[0]
		var pos3: Vector2 = p2.pos
		for _k in 30:
			pos3 += Vector2.RIGHT * s2.cfg.player_speed * speed_factor * dt
			p2.dash_t = 0.3 if dash else 0.0
			t2.sync(p2, s2, pos3, dt)
		var m0: float = t2.motion.spin
		for _k in 30:
			pos3 += Vector2.RIGHT * s2.cfg.player_speed * speed_factor * dt
			p2.dash_t = 0.3 if dash else 0.0
			t2.sync(p2, s2, pos3, dt)
		var turn: float = t2.motion.spin - m0
		applied[0] = applied[0] and is_equal_approx(wrapf(t2._base.rotation.y, -PI, PI), wrapf(t2.motion.spin, -PI, PI))
		t2.queue_free()
		return turn
	var spin_idle: float = base_turn.call(0.0, false)
	var spin_run: float = base_turn.call(1.0, false)
	var spin_dash: float = base_turn.call(2.5, true)
	check("figure Kreisel: the base spins slowly standing (%.2f rad), faster running (%.2f), fastest in a dash (%.2f)" % [spin_idle, spin_run, spin_dash],
			spin_idle > 0.5 and spin_run > 2.0 * spin_idle and spin_dash > 1.5 * spin_run)
	check("figure Kreisel: the base node follows the spin angle", applied[0])
	top.queue_free()
	holder.queue_free()
	await process_frame


## Starts a die's ToyMotion on the sim's one player and lets the drop-in pass: [motion, sim, player, position].
func die_motion() -> Array:
	var s := one_player()
	var m := ToyMotion.new(ToyPose.Kind.DIE)
	var p := s.players[0]
	var pos: Vector2 = p.pos
	for _k in 40:
		m.update(p, s, pos, 1.0 / 60.0)
	return [m, s, p, pos]


## The die really rolls: ToyMotion.tumble, die_height, die_hop.
func test_die_roll() -> void:
	var dt := 1.0 / 60.0
	var K := ToyPose.Kind
	var side_m := ToyMotion.DIE_SIDE * Config.new().player_radius       # one side length in metres
	# The player faces +x on the sim's plane: local +z (front) is world +x, local +x is world -y (the `side` vector).
	var fwd := Vector2.RIGHT
	var lat := Vector2(0, -1)
	var rolled := func(dir: Vector2, length: float, fps: int) -> Basis:
		var d: Array = die_motion()
		var m: ToyMotion = d[0]
		var pos: Vector2 = d[3]
		var before := m.tumble
		var n := roundi(10.0 * fps / 60.0)
		for _k in n:
			pos += dir * (length / n)
			m.update(d[2], d[1], pos, 1.0 / fps)
		return m.tumble * before.inverse()
	var q: Basis = rolled.call(fwd, side_m, 60)
	check("die: one side length forward is a quarter turn that tips the top to the front (up -> %s)" % str(q * Vector3.UP), (q * Vector3.UP).is_equal_approx(Vector3(0, 0, 1)) and (q * Vector3(0, 0, 1)).is_equal_approx(Vector3(0, -1, 0)))
	var qs: Basis = rolled.call(lat, side_m, 60)
	check("die: sideways movement rolls about the other axis, the top tips to the side (up -> %s)" % str(qs * Vector3.UP), (qs * Vector3.UP).is_equal_approx(Vector3(1, 0, 0)) and (qs * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, -1, 0)))
	var qb: Basis = rolled.call(-fwd, side_m, 60)
	check("die: backwards tips the top to the back", (qb * Vector3.UP).is_equal_approx(Vector3(0, 0, -1)))
	var q2: Basis = rolled.call(fwd, side_m * 2.0, 60)
	check("die: two side lengths are a half turn", (q2 * Vector3.UP).is_equal_approx(Vector3(0, -1, 0)))
	# Same result at 30, 60 and 120 fps (a path with a corner).
	var around := func(fps: int) -> Basis:
		var d: Array = die_motion()
		var m: ToyMotion = d[0]
		var pos: Vector2 = d[3]
		var n := roundi(12.0 * fps / 60.0)
		for k in 2 * n:
			pos += (fwd if k < n else lat) * (side_m * 1.3 / n)
			m.update(d[2], d[1], pos, 1.0 / fps)
		return m.tumble
	var a30: Basis = around.call(30)
	var a60: Basis = around.call(60)
	var a120: Basis = around.call(120)
	var dev := 0.0
	for ax in 3:
		dev = maxf(dev, maxf((a30[ax] - a120[ax]).length(), (a60[ax] - a120[ax]).length()))
	check("die: the roll is the same at 30, 60 and 120 fps (deviation %.3f)" % dev, dev < 0.06)
	# Height: lying flat is half a side, on an edge (45 degrees) half a side times sqrt(2), on a corner times sqrt(3).
	var mh := ToyMotion.new(K.DIE)
	var half := ToyMotion.DIE_SIDE * 0.5
	var h0 := mh.die_height()
	mh.tumble = Basis(Vector3.RIGHT, PI * 0.25)
	var h45 := mh.die_height()
	mh.tumble = Basis(Vector3(1, 0, -1).normalized(), atan(sqrt(2.0)))        # a corner straight down
	var hc := mh.die_height()
	mh.tumble = Basis(Vector3.UP, 0.9)
	var hy := mh.die_height()
	check("die: the cube always touches the floor (flat %.3f = %.3f, edge %.3f = %.3f, corner %.3f = %.3f, turned about up %.3f)" % [h0, half, h45, half * sqrt(2.0), hc, half * sqrt(3.0), hy],
			is_equal_approx(h0, half) and absf(h45 - half * sqrt(2.0)) < 1e-4 and absf(hc - half * sqrt(3.0)) < 1e-3 and absf(hy - half) < 1e-4)
	# Standing still: eases back to upright (the face to the front) within 0.6 s, with a small hop on the way.
	var d: Array = die_motion()
	var m: ToyMotion = d[0]
	var pos: Vector2 = d[3]
	for _k in 14:
		pos += fwd * (side_m * 0.12)
		m.update(d[2], d[1], pos, dt)
	var tilt0 := m.tumble.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)
	var hop_max := 0.0
	var hop_t := -1.0
	for k in 40:
		m.update(d[2], d[1], pos, dt)
		hop_max = maxf(hop_max, m.die_hop())
		if hop_t < 0.0 and m.tumble == Basis.IDENTITY:
			hop_t = (k + 1) * dt
	check("die: standing it eases back upright within 0.6 s (was %.2f rad off, upright after %.2f s) with a hop of up to %.2f, none at rest" % [tilt0, hop_t, hop_max],
			tilt0 > 0.5 and hop_t > 0.0 and hop_t < 0.6 and hop_max > 0.05 and m.die_hop() == 0.0 and m.die_height() == half)
	# A big angle gives the full hop height: a half turn still to go is 0.35.
	m.tumble = Basis(Vector3.RIGHT, PI * 0.999)
	m.settling = true
	check("die: the settling hop grows with the angle still to go (%.2f at a half turn)" % m.die_hop(), absf(m.die_hop() - ToyMotion.SETTLE_HOP) < 0.01)
	# A teleport does not roll it; a stun sets it upright even while it slides; a respawn too.
	var d2: Array = die_motion()
	var m2: ToyMotion = d2[0]
	var pos2: Vector2 = d2[3]
	for _k in 12:
		pos2 += fwd * (side_m * 0.12)
		m2.update(d2[2], d2[1], pos2, dt)
	var before: Basis = m2.tumble
	pos2 += Vector2(8, 0)
	m2.update(d2[2], d2[1], pos2, dt)
	check("die: a teleport (respawn, correction) does not roll it", m2.tumble.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) <= before.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) + 1e-4)
	d2[2].stun_t = 1.0
	for _k in 60:
		pos2 += fwd * 0.02
		m2.update(d2[2], d2[1], pos2, dt)
	check("die: stunned it eases upright even while it slides", m2.tumble == Basis.IDENTITY)
	d2[2].stun_t = 0.0
	for _k in 12:
		pos2 += fwd * (side_m * 0.12)
		m2.update(d2[2], d2[1], pos2, dt)
	check("die: and it rolls again after the stun", m2.tumble != Basis.IDENTITY)
	d2[2].alive = false
	m2.update(d2[2], d2[1], pos2, dt)
	d2[2].alive = true
	m2.update(d2[2], d2[1], pos2, dt)
	check("die: on a respawn it is upright", m2.spawned and m2.tumble == Basis.IDENTITY)
	# A long random walk: the basis stays a clean rotation. Other figures never roll.
	var d3: Array = die_motion()
	var m3: ToyMotion = d3[0]
	var pos3: Vector2 = d3[3]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dir3 := Vector2.RIGHT
	var worst := 0.0
	for k in 4000:
		if k % 25 == 0:
			dir3 = Vector2.from_angle(rng.randf() * TAU)
		pos3 += dir3 * rng.randf_range(0.0, 0.12)
		m3.update(d3[2], d3[1], pos3, dt)
		var b := m3.tumble
		var err := absf(b.x.length() - 1.0) + absf(b.y.length() - 1.0) + absf(b.z.length() - 1.0)
		err += absf(b.determinant() - 1.0) + absf(b.x.dot(b.y)) + absf(b.y.dot(b.z)) + absf(b.x.dot(b.z))
		worst = maxf(worst, err)
	check("die: after a long random walk the cube's basis is still orthonormal (worst error %.5f)" % worst, worst < 1e-4)
	var dd: Array = die_motion()
	var duck := ToyMotion.new(K.DUCK)
	var posd: Vector2 = dd[3]
	for _k in 60:
		posd += fwd * 0.1
		duck.update(dd[2], dd[1], posd, dt)
	check("die: only the die rolls", duck.tumble == Basis.IDENTITY)


## The snapper's hinged upper jaw and the die's cube on real figures.
func test_dino_die_figures() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame
	var dt := 1.0 / 60.0
	var K := ToyPose.Kind
	# --- dino: the lower jaw stays, the upper part (with the eyes) swings UP and back when the mouth opens
	var dino := ToyFigure.new(K.DINO, Color("2ec4ff"))
	holder.add_child(dino)
	var sd := one_player()
	dino.sync(sd.players[0], sd, sd.players[0].pos, dt)
	var pr := sd.cfg.player_radius
	var tip := Vector3(0, 0.2, 0.9)                  # the front of the snout, in the hinged part's frame
	dino.motion.shown[ToyPose.JAW] = 0.0
	dino._apply_pose()
	var tip_shut := dino._jaw.to_global(tip)
	var eye_shut := (dino._eyes[0] as Node3D).global_position
	var lower_shut := (dino._head.get_child(0) as Node3D).global_position
	dino.motion.shown[ToyPose.JAW] = 1.0
	dino._apply_pose()
	var tip_open := dino._jaw.to_global(tip)
	var eye_open := (dino._eyes[0] as Node3D).global_position
	var lower_open := (dino._head.get_child(0) as Node3D).global_position
	var rise := (tip_open.y - tip_shut.y) / pr
	check("dino: opening the mouth swings the snout up by %.2f player radii, the lower jaw stays" % rise, rise > 0.35 and lower_open.is_equal_approx(lower_shut))
	check("dino: the eyes sit on the hinged part and tip back with it", dino._eyes.size() == 2 and (dino._eyes[0] as Node3D).get_parent() == dino._jaw and dino.to_local(eye_open).z < dino.to_local(eye_shut).z - 0.1)
	check("dino: a tail, a hinged Jaw node, a yo-yo paw on the right arm", dino.pose_node.get_node_or_null("Tail") == dino._tail and dino._head.get_node_or_null("Jaw") == dino._jaw and dino._paw != null and dino._paw.get_parent() == dino._arm_r)
	dino.queue_free()
	# --- die: the cube node follows the motion, always touches the floor, and the face looks to the front when upright
	var die := ToyFigure.new(K.DIE, Color("ff2e88"))
	holder.add_child(die)
	var si := one_player()
	for _k in 60:
		die.sync(si.players[0], si, si.players[0].pos, dt)
	var floor_err := 0.0
	var tilts := [Basis.IDENTITY, Basis(Vector3.RIGHT, 0.6), Basis(Vector3(1, 0.4, -0.7).normalized(), 2.2), Basis(Vector3.BACK, PI * 0.25)]
	for tb: Basis in tilts:
		die.motion.tumble = tb
		die.motion.settling = false
		die._apply_pose()
		var shell := die._cube.get_child(0) as MeshInstance3D
		var lowest := INF
		for i in 8:
			lowest = minf(lowest, (shell.global_transform * shell.mesh.get_aabb().get_endpoint(i)).y)
		floor_err = maxf(floor_err, absf(lowest))
	check("die: whatever its orientation the lowest corner of the cube is on the floor (error %.4f)" % floor_err, floor_err < 0.002 and die._cube.basis.is_equal_approx(tilts[3]))
	die.motion.tumble = Basis.IDENTITY
	die._apply_pose()
	var eye := die._eyes[0] as Node3D
	var face_dir := eye.global_basis.z.normalized()
	check("die: upright, the face (eyes, smile) looks to the front and up", die._eyes.size() == 2 and face_dir.dot(die.global_basis.z.normalized()) > 0.9 and face_dir.y > 0.1 and eye.get_parent() == die._cube)
	var pips := 0
	for node in die._cube.get_children():
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh == ToyKit.cylinder():
			pips += 1
	check("die: 3 + 4 + 2 + 5 + 6 pips on the five other sides (%d)" % pips, pips == 20)
	# Rolling shows on the figure: walking forward tips the top of the cube to the front.
	var pd := si.players[0]
	var posd: Vector2 = pd.pos
	for _k in 12:
		posd += Vector2.RIGHT * si.cfg.player_speed * dt
		die.sync(pd, si, posd, dt)
	var top_dir := die._cube.basis.y
	check("die: walking forward tips the cube's top towards the front of the figure (%s)" % str(top_dir), top_dir.z > 0.2 and absf(top_dir.x) < 0.05)
	# It stops: upright again; the burst of a death resets the cube.
	for _k in 60:
		die.sync(pd, si, posd, dt)
	check("die: stopped, the cube is upright again", die._cube.basis.is_equal_approx(Basis.IDENTITY) and absf(die._cube.position.y) < 0.001)
	die.motion.tumble = Basis(Vector3.RIGHT, 0.5)
	die._apply_pose()
	pd.alive = false
	die.sync(pd, si, posd, dt)
	check("die: a popped die's cube is reset (it flies as one piece)", die._cube.transform == Transform3D.IDENTITY)
	die.queue_free()
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
	check("view: every slot has its own toy", view._figures.size() == Config.NUM_PLAYERS and kinds.size() == Config.NUM_PLAYERS)
	view.queue_free()
	await process_frame


## The arena view: figure kind from the skin, the string from the hand, the height of a yo-yo that is out.
func test_arena_view_figures() -> void:
	var cfg := Config.new()
	var sm := Sim.new(cfg, 1)
	for k in Config.NUM_PLAYERS:
		sm.set_player_enabled(k, k < 2)
		sm.players[k].alive = true
		sm.players[k].prev_pos = sm.players[k].pos
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(sm)
	view.use_sim(sm, 0)
	for _k in 5:
		view.render(1.0, 1.0 / 60.0)
	var old_kind: int = view._figures[1].kind
	sm.players[1].skin = 5
	view.render(1.0, 1.0 / 60.0)
	check("view: a changed skin swaps the figure of that player", old_kind != 5 and view._figures[1].kind == 5 and view._figures[1].get_parent() == view and view._bodies[1] == view._figures[1])
	var toys := 0
	for c in view.get_children():
		if c is ToyFigure:
			toys += 1
	check("view: ... and no figure is left over", toys == Config.NUM_PLAYERS)
	var ring := view.find_child("LocalRing", true, false)
	check("view: the ring is on the local player's figure", ring != null and ring.get_parent() == view._figures[0])
	sm.players[0].skin = 6
	view.render(1.0, 1.0 / 60.0)
	ring = view.find_child("LocalRing", true, false)
	check("view: ... and stays there when that figure is swapped", view._figures[0].kind == 6 and ring != null and ring.get_parent() == view._figures[0] and view.find_children("LocalRing", "MeshInstance3D", true, false).size() == 1)
	sm.players[0].skin = 9
	view.render(1.0, 1.0 / 60.0)
	check("view: a skin out of range wraps", view._figures[0].kind == 1)
	# Player colour: the body keeps the toy's own colour, the ring on the floor carries the player colour.
	var f1: ToyFigure = view._figures[1]
	var ring1: MeshInstance3D = f1.get_node("ColorRing")
	var ring_col: Color = (ring1.material_override as StandardMaterial3D).albedo_color
	var want: Color = ArenaView.PLAYER_COLORS[sm.players[1].color]
	check("view colour: the body uses the toy's body colour, not the player colour", f1.body_mat.albedo_color == ToyFigure.BODY_COLORS[f1.kind] and f1.body_mat.albedo_color != want)
	check("view colour: the ring uses the player colour", is_equal_approx(ring_col.r, want.r) and is_equal_approx(ring_col.g, want.g) and is_equal_approx(ring_col.b, want.b))
	check("view colour: the ring lies flat around the feet (1.1 to 1.4 radii)", ring1.scale.x >= 2.2 and ring1.scale.x <= 2.8 and ring1.scale.y < ring1.scale.x * 0.5)
	var new_k := (sm.players[1].color + 1) % Config.COLOR_COUNT
	sm.players[1].color = new_k
	view.render(1.0, 1.0 / 60.0)
	var f1b: ToyFigure = view._figures[1]
	var ring_col2: Color = ((f1b.get_node("ColorRing") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	var want2: Color = ArenaView.PLAYER_COLORS[new_k]
	check("view colour: a colour change rebuilds the figure with the new ring", f1b != f1 and is_equal_approx(ring_col2.r, want2.r) and is_equal_approx(ring_col2.g, want2.g) and is_equal_approx(ring_col2.b, want2.b))
	var aim_col: Color = (view._aim_marks[1].material_override as StandardMaterial3D).albedo_color
	check("view colour: ... and the aim mark follows", is_equal_approx(aim_col.r, want2.lightened(0.4).r) and is_equal_approx(aim_col.b, want2.lightened(0.4).b))
	var head_node: Node3D = view._heads[1][0]
	var head_mats := head_node.find_children("*", "MeshInstance3D", true, false).map(func(m: MeshInstance3D) -> Color: return (m.material_override as StandardMaterial3D).albedo_color if m.material_override is StandardMaterial3D else Color.BLACK)
	var want_half := want2.lightened(0.15)
	check("view colour: ... and the yo-yo halves", head_mats.any(func(c: Color) -> bool: return is_equal_approx(c.r, want_half.r) and is_equal_approx(c.g, want_half.g) and is_equal_approx(c.b, want_half.b)))
	check("view colour: ArenaView.color_of reads the player's colour", ArenaView.color_of(sm.players[1]) == want2)
	check("view colour: every toy has a body colour", ToyFigure.BODY_COLORS.size() == ToyFigure.NAMES.size())
	# The yo-yo in the hand and out.
	var p := sm.players[0]
	p.pos = Vector2(10, 7)
	p.prev_pos = p.pos
	p.facing = Vector2.RIGHT
	for _k in 90:
		view.render(1.0, 1.0 / 60.0)
	var fig: ToyFigure = view._figures[0]
	var hr := sm.head_r(p)
	var h := p.heads[0]
	h.state = SimHead.S.FLIGHT
	h.throw_dir = Vector2.RIGHT
	h.flight_dist = 6.0
	h.flown = 3.0
	h.pos = Vector2(13, 7)
	h.prev_pos = h.pos
	view.render(1.0, 1.0 / 60.0)
	var node: Node3D = view._heads[0][0]
	var mid_y := node.position.y
	check("view: the figure's arm points along the string while a yo-yo is out", fig.string_dir.is_equal_approx(Vector2.RIGHT))
	var seg: MeshInstance3D = view._string_segs[0]
	var hand3 := fig.hand_point(p.pos, p.facing, hr, ArenaView.HAND_Y)
	# The string is a box from the hand to the yo-yo: its centre is half way, its length is the distance.
	var a3: Vector3 = seg.position - seg.basis.z * 0.5
	var b3: Vector3 = seg.position + seg.basis.z * 0.5
	var start: Vector3 = a3 if a3.distance_to(hand3) < b3.distance_to(hand3) else b3
	check("view: the string's first segment starts at the hand point", seg.visible and start.distance_to(hand3) < 0.05, "%s %s" % [start, hand3])
	h.state = SimHead.S.OUT
	h.flown = 6.0
	view.render(1.0, 1.0 / 60.0)
	var out_y := node.position.y
	check("view: a yo-yo in mid-flight is drawn higher than one lying out (%.2f > %.2f)" % [mid_y, out_y], mid_y > out_y + 0.2)
	h.state = SimHead.S.RETRACT
	h.pos = p.pos + Vector2(0.4, 0)
	h.prev_pos = h.pos
	view.render(1.0, 1.0 / 60.0)
	hand3 = fig.hand_point(p.pos, p.facing, hr, ArenaView.HAND_Y)
	var far_y := out_y
	var near_y := node.position.y
	check("view: a retracting yo-yo next to the player is near hand height (%.2f, hand %.2f, lying %.2f)" % [near_y, hand3.y, far_y],
			absf(near_y - hand3.y) < 0.5 * absf(hand3.y - far_y) + 0.05)
	view.queue_free()
	await process_frame


## The playroom: track, train, present.
func test_playroom_details() -> void:
	var sm := Sim.new(Config.new(), 1)
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(sm)
	var pr: Playroom = view.playroom
	var track := pr.get_node_or_null("Track")
	var multis := track.find_children("*", "MultiMeshInstance3D", false, false).size() if track != null else 0
	check("playroom: a track of two multimeshes (sleepers and rails) and one car per TrainTrack.CARS", multis == 2 and pr.cars.size() == TrainTrack.CARS and pr.get_node_or_null("Car%d" % (TrainTrack.CARS - 1)) != null)
	var off := []
	for s_train in [3.0, 17.5, TrainTrack.LENGTH - 0.5]:
		sm.train_s = s_train
		sm.prev_train_s = s_train
		pr.update(sm, 1.0, 0.016)
		for k in pr.cars.size():
			var want := TrainTrack.point(TrainTrack.car_s(s_train, k))
			if world_xz(pr.cars[k].position).distance_to(want) > 0.01:
				off.append([s_train, k])
	check("playroom: the cars sit where the sim has the train (every car, three places on the loop)", off.is_empty(), str(off))
	sm.prev_train_s = 3.0
	sm.train_s = 5.0
	pr.update(sm, 0.5, 0.016)
	check("playroom: ... between two ticks they are interpolated", world_xz(pr.cars[0].position).distance_to(TrainTrack.point(4.0)) < 0.01)
	var moved := world_xz(pr.cars[1].position)
	sm.prev_train_s = 8.0
	sm.train_s = 8.0
	pr.update(sm, 1.0, 0.016)
	check("playroom: ... and follow the sim when it moves the train", world_xz(pr.cars[1].position).distance_to(moved) > 1.0 and pr.cars[0].visible)
	sm.cfg.train_speed = 0.0
	pr.update(sm, 1.0, 0.016)
	var hidden := true
	for c in pr.cars:
		hidden = hidden and not c.visible
	check("playroom: the cars are hidden when the train is switched off", hidden)
	sm.cfg.train_speed = 5.7
	pr.update(sm, 1.0, 0.016)
	check("playroom: ... and back when it is switched on", pr.cars[0].visible and pr.cars[2].visible)
	# The present bursts and the debris goes away again.
	var dbg := pr.get_node("BoxDebris") as Node3D
	check("playroom: the burst pieces are hidden until the present breaks", not dbg.visible and pr._debris.size() >= 5)
	pr.box_break()
	check("playroom: the present bursts into pieces", dbg.visible)
	for _k in 12:
		pr.update(sm, 1.0, 0.016)
	var scattered := 0
	for pt in pr._debris:
		if pt.position.distance_to((pt.get_meta("home") as Transform3D).origin) > 0.3:
			scattered += 1
	check("playroom: ... they fly apart", scattered >= pr._debris.size() / 2 and dbg.visible, str(scattered))
	var t := 12 * 0.016
	while t < Playroom.BOX_DEBRIS_TIME - 0.1:
		pr.update(sm, 1.0, 0.05)
		t += 0.05
	var still_shown := dbg.visible
	for _k in 6:
		pr.update(sm, 1.0, 0.05)
	check("playroom: ... and are hidden again after BOX_DEBRIS_TIME", still_shown and not dbg.visible)
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
	check("main: offline the playroom and the toy figures are there and drawn", main.view.playroom != null and shown >= 1 and main.view._figures.size() == Config.NUM_PLAYERS, "visible=%d" % shown)
	main.queue_free()
	await process_frame


func test_map_views() -> void:
	var sm := Sim.new(Config.new(), 1)
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(sm)
	var ok := true
	var info := ""
	for id in Config.MAP_COUNT:
		sm.set_map(id)
		view.render(1.0, 0.016)   # another map: the playroom is rebuilt
		ok = ok and view.playroom.map_id == id
		for _t in 120:
			sm.step([SimInput.new(), SimInput.new(), SimInput.new(), SimInput.new()])
			view.render(1.0, 0.016)
		# Lava Mats: draw the three phases
		sm.map_t = MapDef.LAVA_CALM + 0.2
		view.render(1.0, 0.016)
		sm.map_t = MapDef.LAVA_CALM + MapDef.LAVA_WARN + 0.2
		view.render(1.0, 0.016)
		if not ok:
			info += " " + str(id)
	check("maps view: the playroom is built and updated for every map and follows a change of map", ok, info)
	view.queue_free()


## A long obstacle is drawn as a row of equal near-square blocks that covers exactly its rectangle.
func test_wall_rows() -> void:
	var near := Playroom.block_pieces(Rect2(10, 5, 2.4, 2.0))
	check("wall rows: a near-square obstacle stays one block", near.size() == 1 and near[0] == Rect2(10, 5, 2.4, 2.0))
	var edge := Playroom.block_pieces(Rect2(10, 5, 3.0, 2.0))
	check("wall rows: exactly 1.5 times as long is still one block", edge.size() == 1)
	var ok := true
	var info := ""
	for r: Rect2 in [Rect2(15.4, 3.2, 1.2, 8.0), Rect2(0, 0, 0.8, 2.8), Rect2(5, 5, 6.0, 0.8), Rect2(5, 5, 3.2, 2.0), Rect2(2, 2, 0.8, 4.4)]:
		var pieces := Playroom.block_pieces(r)
		var area := 0.0
		var union := pieces[0]
		var square := true
		for pc in pieces:
			area += pc.get_area()
			union = union.merge(pc)
			square = square and maxf(pc.size.x, pc.size.y) <= 1.5 * minf(pc.size.x, pc.size.y)
		var same := true
		for pc in pieces:
			same = same and pc.size.is_equal_approx(pieces[0].size)
		var touching := true
		for i in range(1, pieces.size()):
			touching = touching and pieces[i].intersects(pieces[i - 1].grow(0.001))
		var good := pieces.size() >= 2 and absf(area - r.get_area()) < 0.0001 and union.is_equal_approx(r) and square and same and touching
		ok = ok and good
		if not good:
			info += " %s" % str(r)
	check("wall rows: a long obstacle becomes equal near-square pieces that cover exactly its rectangle", ok, info)
	var sm := Sim.new(Config.new(), 1)
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(sm)
	var built := true
	var binfo := ""
	for id in Config.MAP_COUNT:
		sm.set_map(id)
		view.render(1.0, 0.016)
		var pr: Playroom = view.playroom
		var special: int = MapDef.SPECIAL_OBSTACLES[id]
		for i in range(sm.wall_count + special, sm.statics.size()):
			var r := sm.statics[i]
			var node := pr.get_node_or_null("Block%d" % (i - sm.wall_count))
			if node == null:
				built = false
				binfo += " missing %d/%d" % [id, i]
				continue
			var pieces := Playroom.block_pieces(r)
			if pieces.size() == 1:
				built = built and node.position.is_equal_approx(Vector3(r.get_center().x, 0, r.get_center().y))
			else:
				built = built and node.get_child_count() == pieces.size()
				for k in pieces.size():
					var pn := node.get_node_or_null("Piece%d" % k) as Node3D
					built = built and pn != null and pn.position.is_equal_approx(Vector3(pieces[k].get_center().x, 0, pieces[k].get_center().y))
	check("wall rows: the playroom of every map draws each obstacle as its block or row of blocks in the right place", built, binfo)
	view.queue_free()


## The yo-yo in the hand: drawn at normal size while held, real size when thrown (eased); with two yo-yos one in each
## hand of every figure, both visible from above.
func test_held_yoyo() -> void:
	var base := 0.35
	var big := base * 2.8
	check("yoyo: a held head is drawn at normal size even with Big Chunk", is_equal_approx(ArenaView.drawn_head_r(base, big, 0.0), base * ArenaView.HELD_SCALE))
	check("yoyo: a thrown head is drawn at its real size", is_equal_approx(ArenaView.drawn_head_r(base, big, 1.0), big))
	var mid := ArenaView.drawn_head_r(base, big, 0.5)
	check("yoyo: in between it eases", mid > base * ArenaView.HELD_SCALE + 0.05 and mid < big - 0.05)
	var g := 0.0
	for _k in 6:
		g = ArenaView.grow_step(g, true, 1.0 / 60.0)
	check("yoyo: it is not full size after 0.1 s out", g > 0.3 and g < 1.0, str(g))
	for _k in 10:
		g = ArenaView.grow_step(g, true, 1.0 / 60.0)
	check("yoyo: it is full size after 0.17 s out", is_equal_approx(g, 1.0), str(g))
	for _k in 12:
		g = ArenaView.grow_step(g, false, 1.0 / 60.0)
	check("yoyo: caught again it shrinks back to the held size", is_equal_approx(g, 0.0), str(g))
	check("yoyo: one yo-yo stays in the right hand, twin: right and left", ToyFigure.hand_side(0, 1) == 1 and ToyFigure.hand_side(0, 2) == 1 and ToyFigure.hand_side(1, 2) == -1)

	# In the real view: a held big head is small, a thrown one is big.
	var cfg := Config.new()
	var sm := Sim.new(cfg, 1)
	for k in Config.NUM_PLAYERS:
		sm.set_player_enabled(k, k < 1)
	var pl := sm.players[0]
	pl.alive = true
	pl.prev_pos = pl.pos
	pl.mods = {"bighead": 3, "twin": 3}
	var idle: Array = []
	for _k in Config.NUM_PLAYERS:
		idle.append(SimInput.new())
	sm.step(idle)
	sm.step(idle)
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(sm)
	view.use_sim(sm, 0)
	for _k in 30:
		view.render(1.0, 1.0 / 60.0)
	var hr := sm.head_r(pl)
	var head0: Node3D = view._heads[0][0]
	check("yoyo: Big Chunk is really big in the sim", hr > cfg.head_radius * 2.0 and pl.heads.size() >= 2, str(hr))
	check("yoyo: view: a held big head is drawn at normal size", head0.visible and is_equal_approx(head0.scale.x, cfg.head_radius * ArenaView.HELD_SCALE), str(head0.scale))
	pl.heads[0].state = SimHead.S.FLIGHT
	for _k in 30:
		view.render(1.0, 1.0 / 60.0)
	check("yoyo: view: a thrown big head is drawn at its real size", is_equal_approx(head0.scale.x, hr), str(head0.scale))
	pl.heads[0].state = SimHead.S.HAND
	view.render(1.0, 1.0 / 60.0)
	check("yoyo: view: a caught head is not at once small (eased)", head0.scale.x > cfg.head_radius * 1.5, str(head0.scale))
	for _k in 30:
		view.render(1.0, 1.0 / 60.0)
	check("yoyo: view: ... but small a moment later", is_equal_approx(head0.scale.x, cfg.head_radius * ArenaView.HELD_SCALE), str(head0.scale))
	var h1: Node3D = view._heads[0][1]
	var d := Vector2(head0.position.x - h1.position.x, head0.position.z - h1.position.z).length()
	check("yoyo: view: twin yo-yos are apart", d > cfg.head_radius * 1.4, str(d))
	view.queue_free()

	# Every figure: two distinct hands, left and right of the body, outside the body from above.
	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame
	var bad := []
	for kind in range(ToyFigure.NAMES.size()):
		var fig := ToyFigure.new(kind, Color("2ec4ff"))
		holder.add_child(fig)
		var s := one_player()
		var p := s.players[0]
		fig.left_hold = true
		for _k in 60:
			fig.sync(p, s, p.pos, 1.0 / 60.0)
		var pos: Vector2 = p.pos
		var face := Vector2.RIGHT
		var side := Vector2(face.y, -face.x)
		var l := world_xz(fig.hand_point(pos, face, base, 0.5, -1)) - pos
		var r := world_xz(fig.hand_point(pos, face, base, 0.5, 1)) - pos
		var pr := s.cfg.player_radius
		var yoyo_r := base * ArenaView.HELD_SCALE
		var sep := absf((l - r).dot(side))
		var opposite := l.dot(side) * r.dot(side) < 0.0
		# Outside the body shell seen from above: the yo-yo (radius yoyo_r) must not lie inside the body's footprint circle.
		var foot := fig.body_footprint() * pr
		var outside := minf(l.length(), r.length()) + yoyo_r > foot * 0.9
		if sep < 2.0 * yoyo_r or not opposite or not outside:
			bad.append([ToyFigure.NAMES[kind], snappedf(sep, 0.01), opposite, snappedf(l.length(), 0.01), snappedf(r.length(), 0.01), snappedf(foot, 0.01)])
		fig.queue_free()
		await process_frame
	check("yoyo: every figure has a left and a right hand, apart and outside the body seen from above", bad.is_empty(), str(bad))
	holder.queue_free()

## Markers above the heads: the pure decisions (OverheadView statics) and the real labels of an ArenaView.
func test_overhead() -> void:
	var cfg := Config.new()
	var sim := Sim.new(cfg, 3)
	for k in 4:
		sim.set_player_enabled(k, k < 2)
	# Free play (phase OFF): nothing, even with modifiers owned.
	sim.mode.owned[0] = {"twin": 1, "bounce": 2}
	check("overhead: no icons and no YOU in free play", OverheadView.icons_for(sim, 0).is_empty()
			and OverheadView.you_alpha(sim, 0, 0) == 0.0)
	sim.start_match(10)
	sim.mode.owned[0] = {"twin": 1, "bounce": 2}
	sim.mode.owned[1] = {}
	var ic := OverheadView.icons_for(sim, 0)
	check("overhead: countdown shows the owned modifiers in key order with their levels",
			sim.mode.phase == MatchMode.Phase.COUNTDOWN and ic.size() == 2 and ic[0][0] == "twin" and ic[1][0] == "bounce"
			and ic[0][1] == 1 and ic[1][1] == Mods.level_for_copies(2), str(ic))
	check("overhead: a player with nothing owned shows no icons", OverheadView.icons_for(sim, 1).is_empty())
	check("overhead: a slot that does not play shows nothing", OverheadView.icons_for(sim, 3).is_empty())
	check("overhead: YOU only for the local slot", OverheadView.you_alpha(sim, 0, 0) == 1.0
			and OverheadView.you_alpha(sim, 1, 0) == 0.0 and OverheadView.you_alpha(sim, 1, 1) == 1.0)
	sim.mode.phase = MatchMode.Phase.PLAY
	sim.mode.phase_t = 0.5
	check("overhead: early in PLAY icons and YOU are still there",
			not OverheadView.icons_for(sim, 0).is_empty() and OverheadView.you_alpha(sim, 0, 0) == 1.0)
	sim.mode.phase_t = 1.0
	var mid := OverheadView.icon_alpha(sim)
	check("overhead: icons fade during PLAY (%.2f)" % mid, mid > 0.0 and mid < 1.0)
	sim.mode.phase_t = 1.8
	var ya := OverheadView.you_alpha(sim, 0, 0)
	check("overhead: icons gone and YOU fading at 1.8 s (%.2f)" % ya, OverheadView.icons_for(sim, 0).is_empty() and ya > 0.0 and ya < 1.0)
	sim.mode.phase_t = 2.5
	check("overhead: YOU gone after 2 s of PLAY", OverheadView.you_alpha(sim, 0, 0) == 0.0)
	sim.mode.phase = MatchMode.Phase.RESULT
	check("overhead: nothing in the result phase", OverheadView.you_alpha(sim, 0, 0) == 0.0 and OverheadView.icons_for(sim, 0).is_empty())
	# Zone countdown.
	sim.mode.phase = MatchMode.Phase.PLAY
	sim.mode.phase_t = 10.0
	sim.mode.zone_t = MatchMode.ZONE_FULL_TIME + 5.0
	var p := sim.players[0]
	p.alive = true
	p.zone_t = 0.0
	check("overhead: no zone number while the timer is 0", OverheadView.zone_number(sim, 0) == 0)
	var got := []
	for t in [0.01, 0.9, 1.1, 1.99, 2.01, 2.9]:
		p.zone_t = t
		got.append(OverheadView.zone_number(sim, 0))
	check("overhead: zone number counts 3, 3, 2, 2, 1, 1 (%s)" % str(got), got == [3, 3, 2, 2, 1, 1])
	p.zone_t = 0.02
	var fresh := OverheadView.zone_pulse(sim, 0)
	p.zone_t = 0.5
	check("overhead: the number pulses right after it changes (%.2f, later %.2f)" % [fresh, OverheadView.zone_pulse(sim, 0)],
			fresh > 0.5 and OverheadView.zone_pulse(sim, 0) == 0.0)
	p.zone_t = 1.0
	p.alive = false
	check("overhead: no zone number for a dead player", OverheadView.zone_number(sim, 0) == 0)
	p.alive = true
	# The real view: label texts and the old ring is gone.
	sim.mode.zone_t = MatchMode.ZONE_FULL_TIME + 5.0
	p.zone_t = 1.2
	sim.players[1].zone_t = 0.0
	sim.players[1].alive = true
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(sim)
	view.use_sim(sim, 0)
	view.render(1.0, 1.0 / 60.0)
	var ov: OverheadView = view._overhead
	check("overhead view: the zone number is on screen for the player outside the zone only",
			ov._zone[0].visible and ov._zone[0].text == "2" and not ov._boxes[1].visible, "%s %s" % [ov._zone[0].text, ov._boxes[1].visible])
	sim.mode.phase = MatchMode.Phase.COUNTDOWN
	p.zone_t = 0.0
	view.render(1.0, 1.0 / 60.0)
	check("overhead view: YOU and the icons show on the own figure in the countdown",
			ov._boxes[0].visible and ov._you[0].visible and ov._you_label[0].text == "YOU" and ov._icons[0][0].visible
			and ov._icons[0][0].id == "twin" and not ov._you[1].visible)
	sim.mode.phase = MatchMode.Phase.OFF
	view.render(1.0, 1.0 / 60.0)
	check("overhead view: nothing in free play", not ov._boxes[0].visible and not ov._boxes[1].visible)
	check("overhead view: the red ring of the zone is gone", not view._zone.has_method("show_ring"))
	view.queue_free()
	await process_frame
## True when every visible mesh of the preview's figure lies inside the preview's bounds.
func preview_inside(pv: FigurePreview) -> bool:
	var box := pv.bounds
	for m in pv.figure.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.is_visible_in_tree() or mi == pv.figure._shadow:
			continue
		var t := pv.figure.global_transform.affine_inverse() * mi.global_transform
		for i in 8:
			var q := t * mi.get_aabb().get_endpoint(i)
			if Vector2(q.x, q.z).length() > box.size.x * 0.5 + 0.001 or q.y < box.position.y - 0.001 or q.y > box.end.y + 0.001:
				return false
	return true


## The lobby's figure picture frames every figure completely, whatever the shape of the picture (the camera is
## placed from the figure's real bounds, measured over its whole walk-and-stand cycle).
func test_preview_framing() -> void:   # async
	var cfg := Config.new()
	var pv := FigurePreview.new()
	root.add_child(pv)
	for shape in [Vector2(300, 120), Vector2(140, 120), Vector2(120, 400), Vector2(600, 90)]:
		pv.size = shape
		for kind in Config.SKIN_COUNT:
			pv.show_figure(kind, Color.RED, cfg)
			var long: bool = shape == Vector2(300, 120)
			var inside := true
			for _i in (330 if long else 2):   # (5.5 s: past a whole walk-and-stand cycle)
				await process_frame
				if long and _i % 10 == 0 and not preview_inside(pv):
					inside = false
			var nm: String = "%s at %s" % [ToyFigure.NAMES[kind], str(shape)]
			check("preview framing: %s: bounds are a real box" % nm, pv.bounds.size.y > 0.5 and pv.bounds.size.x > 0.5)
			check("preview framing: %s: all 8 corners of the bounds are in the picture" % nm, pv.fits())
			check("preview framing: %s: the figure stays inside its bounds while it walks" % nm, inside and preview_inside(pv))
	pv.queue_free()

# ---------------------------------------------------------------- Hot Potato bomb

func potato_view_sim(kind := Config.GameMode.POTATO) -> Sim:
	var cfg := Config.new()
	cfg.game_mode = kind
	cfg.train_speed = 0.0
	var s := Sim.new(cfg, 5)
	for k in Config.NUM_PLAYERS:
		s.set_player_enabled(k, k < 4)
		s.players[k].alive = k < 4
		s.players[k].prev_pos = s.players[k].pos
	s.start_match(10)
	for _t in 200:
		s.step([SimInput.new(), SimInput.new(), SimInput.new(), SimInput.new(), SimInput.new(), SimInput.new(), SimInput.new(), SimInput.new()])
	return s

func blink_edges(from_t: float, to_t: float) -> int:
	var edges := 0
	var last: bool = BombView.blink_red(from_t)
	var t := from_t
	while t > to_t:
		t -= 0.001
		var now: bool = BombView.blink_red(t)
		if now and not last:
			edges += 1
		last = now
	return edges

func test_bomb_view() -> void:
	var s := potato_view_sim()
	var m: HotPotato = s.mode
	check("bomb view: the sim is in a Hot Potato round with a bomb", m.phase == MatchMode.Phase.PLAY and m.bomb_holder >= 0)
	m.bomb_holder = 1
	m.bomb_fuse = 16.0
	m.bomb_t = 16.0
	check("bomb view: the holder is the carrier, a full fuse is 1", BombView.holder(s) == 1 and is_equal_approx(BombView.fuse_fraction(s), 1.0))
	m.bomb_t = 4.0
	check("bomb view: the fuse fraction follows bomb_t", is_equal_approx(BombView.fuse_fraction(s), 0.25))
	check("bomb view: a shorter fuse draws a shorter stick", BombView.fuse_length(1.0) > BombView.fuse_length(0.5) and BombView.fuse_length(0.5) > BombView.fuse_length(0.1) and BombView.fuse_length(0.0) > 0.0)
	check("bomb view: no blinking above 3 s, blinking below", not BombView.blink_red(16.0) and not BombView.blink_red(3.01) and BombView.blink_red(2.99) and not BombView.blink_red(-1.0))
	var early := blink_edges(3.0, 2.0)
	var late := blink_edges(1.0, 0.0)
	check("bomb view: the blinking gets faster towards the end", early >= 1 and late > early + 1, "%d vs %d" % [early, late])
	m.bomb_holder = -1
	check("bomb view: nobody carries it when there is no bomb", BombView.holder(s) == -1)
	m.bomb_holder = 2
	s.players[2].alive = false
	check("bomb view: a dead player shows no bomb", BombView.holder(s) == -1)
	s.players[2].alive = true
	m.phase = MatchMode.Phase.RESULT
	check("bomb view: no bomb outside a round", BombView.holder(s) == -1)
	m.phase = MatchMode.Phase.PLAY
	check("bomb view: no bomb in free for all", BombView.holder(potato_view_sim(Config.GameMode.FFA)) == -1 and BombView.fuse_fraction(potato_view_sim(Config.GameMode.FFA)) == 0.0)

	# on the real arena view
	var view := ArenaView.new()
	root.add_child(view)
	await process_frame
	view.setup(s)
	view.use_sim(s, 0)
	m.bomb_holder = 1
	m.bomb_fuse = 16.0
	m.bomb_t = 16.0
	view.render(1.0, 1.0 / 60.0)
	var bombs: BombView = view.find_child("Bombs", true, false)
	var shown: Array = []
	for i in Config.NUM_PLAYERS:
		if bombs._nodes[i].visible:
			shown.append(i)
	var node: Node3D = bombs._nodes[1]
	var fig_pos: Vector2 = s.players[1].pos
	check("bomb view: the bomb shows over the carrier only", shown == [1], str(shown))
	check("bomb view: ... above his head", is_equal_approx(node.position.x, fig_pos.x) and is_equal_approx(node.position.z, fig_pos.y) and node.position.y > 3.0 * s.cfg.player_radius)
	var full_len: float = bombs._fuses[1].scale.y
	m.bomb_t = 4.0
	view.render(1.0, 1.0 / 60.0)
	check("bomb view: the fuse stick is shorter after the fuse has burnt down", bombs._fuses[1].scale.y < full_len * 0.6 and bombs._fuses[1].scale.y > 0.0, "%f %f" % [full_len, bombs._fuses[1].scale.y])
	var calm: Material = bombs._bodies[1].material_override
	m.bomb_t = 2.99
	view.render(1.0, 1.0 / 60.0)
	var red: Material = bombs._bodies[1].material_override
	check("bomb view: the body turns red when it blinks", red != calm and (red as StandardMaterial3D).albedo_color == BombView.RED and (calm as StandardMaterial3D).albedo_color == BombView.BODY_COLOR)
	m.bomb_holder = 3
	view.render(1.0, 1.0 / 60.0)
	check("bomb view: a pass moves the bomb to the new carrier", bombs._nodes[3].visible and not bombs._nodes[1].visible)
	# the other players come from the display sim: the bomb follows THAT sim's carrier
	var other := potato_view_sim()
	other.mode.bomb_holder = 2
	other.mode.bomb_fuse = 16.0
	other.mode.bomb_t = 10.0
	view.set_others(other, 1.0)
	view.render(1.0, 1.0 / 60.0)
	check("bomb view: a figure drawn from the display sim shows that sim's bomb", bombs._nodes[2].visible and not bombs._nodes[3].visible)
	view.queue_free()
