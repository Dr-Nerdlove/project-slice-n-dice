class_name ArenaView
extends Node3D
## 3D presentation. Only reads sim state; interpolates between the last two ticks.
## Sim (x, y) maps to 3D (x, 0, y).

const PLAYER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.3), Color(0.35, 0.85, 0.4), Color(1.0, 0.8, 0.25)]
const HEAD_Y := 0.35
const HAND_LIFT := 0.1            # a yo-yo in the hand sits this far above the hand
const FLIGHT_ARC := 0.3           # extra height in the middle of a throw
const CATCH_RISE_DIST := 2.5      # a returning yo-yo climbs to the hand over this distance
const STRING_WIDTH := 0.05
const STRING_Y := 0.6
const ELASTIC_STRING_WIDTH := 0.13
const ELASTIC_STRING_COLOR := Color(1.0, 0.65, 0.15)
const WIRE_WIDTH := 0.1
const WIRE_LETHAL_WIDTH := 0.2
const WIRE_LETHAL_COLOR := Color(1.0, 0.1, 0.08)
const WIRE_BLINK_TIME := 0.8
const SHARD_COLOR := Color(1.0, 0.95, 0.5)
const EXPLOSION_COLOR := Color(1.0, 0.55, 0.15)
const HAND_SPREAD := 0.6          # sideways spacing of several yo-yos in the hand (in head radii)
const MARK_BOUNCE := Color(1, 1, 1)
const MARK_PIERCE := Color(0.5, 0.95, 1.0)
const MARK_PIERCE_L3 := Color(1.0, 0.85, 0.2)
const MARK_ARC := Color(0.75, 0.4, 1.0)
const MARK_WARHEAD := Color(1.0, 0.3, 0.1)
const MARK_SHARDS := Color(1.0, 0.95, 0.3)

var sim: Sim
## Online: the interpolated state the OTHER players (their yo-yo, string, wires and shards) are drawn from, with
## the blend factor between its prev_* and current positions. null: everything is drawn from `sim`.
var others_sim: Sim
var others_alpha := 1.0
var _local_slot := 0
var cfg: Config
var camera: Camera3D

var _bodies: Array[CharacterRig] = []
var _hand_counts: Array[int] = []   # per player: yo-yos in the hand last frame (throw / catch flick)
var _heads: Array = []     # per player: Array[Node3D]
var _string_segs: Array[MeshInstance3D] = []   # pool: one box per string segment, reused every frame
var _aim_segs: Array[MeshInstance3D] = []      # pool: segments of the aim lines
var _seg_cursor := 0
var _aim_cursor := 0
var _lethal_discs: Array[MeshInstance3D] = []
var _wire_core: Array[MeshInstance3D] = []
var _wire_glow: Array[MeshInstance3D] = []
var _shard_nodes: Array[MeshInstance3D] = []
var _aim_marks: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _crate: MeshInstance3D
var _box: MeshInstance3D
var _spin := 0.0
var _time := 0.0
var _shake_t := 0.0
var _shake_total := 0.01
var _shake_strength := 0.0
var _rng := RandomNumberGenerator.new()


func setup(s: Sim) -> void:
	sim = s
	cfg = s.cfg
	_rng.randomize()
	_build_environment()
	_build_arena()
	_build_players()


## Shows another sim (the predicted one while playing online) and marks `local_slot` as the own player.
func use_sim(s: Sim, local_slot: int) -> void:
	sim = s
	cfg = s.cfg
	_local_slot = local_slot
	others_sim = null
	_ring.get_parent().remove_child(_ring)
	_bodies[local_slot].add_child(_ring)


func _mat(c: Color, unshaded := false, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box_mesh(size3: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size3
	mi.mesh = bm
	mi.material_override = m
	return mi


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	sun.light_energy = 0.9
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = Config.CAMERA_FOV
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.5
	camera.far = 200.0
	var pitch := deg_to_rad(Config.CAMERA_PITCH_DEG)
	var half_w := Config.ARENA_SIZE.x * 0.5 + Config.CAMERA_MARGIN
	var half_h := Config.ARENA_SIZE.y * 0.5 + Config.CAMERA_MARGIN
	# The near edge of the arena is closer to the camera and therefore limits the distance.
	var dist := half_w / tan(deg_to_rad(Config.CAMERA_FOV) * 0.5) + half_h * cos(pitch)
	var center := Vector3(Config.ARENA_SIZE.x * 0.5, 0.0, Config.ARENA_SIZE.y * 0.5)
	camera.position = center + Vector3(0.0, dist * sin(pitch), dist * cos(pitch))
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	add_child(camera)


func _build_arena() -> void:
	var a := Config.ARENA_SIZE
	var floor_mi := _box_mesh(Vector3(a.x, 0.2, a.y), _mat(Color(0.2, 0.22, 0.26)))
	floor_mi.position = Vector3(a.x * 0.5, -0.1, a.y * 0.5)
	add_child(floor_mi)
	for i in sim.statics.size():
		var r := sim.statics[i]
		var h := 1.2 if i < sim.wall_count else 1.5
		var col := Color(0.38, 0.4, 0.46) if i < sim.wall_count else Color(0.5, 0.45, 0.4)
		var mi := _box_mesh(Vector3(r.size.x, h, r.size.y), _mat(col))
		mi.position = Vector3(r.get_center().x, h * 0.5, r.get_center().y)
		add_child(mi)
	var ch := Config.CRATE_HALF * 2.0
	_crate = _box_mesh(Vector3(ch, ch, ch), _mat(Color(0.65, 0.45, 0.2)))
	add_child(_crate)
	var bh := Config.BOX_HALF * 2.0
	_box = _box_mesh(Vector3(bh, bh, bh), _mat(Color(0.8, 0.3, 0.7)))
	_box.position = Vector3(Config.BOX_POS.x, Config.BOX_HALF, Config.BOX_POS.y)
	add_child(_box)


func _build_players() -> void:
	for i in sim.players.size():
		var col := PLAYER_COLORS[i]
		var body := CharacterRig.new()
		body.setup(sim.players[i].skin, col)
		add_child(body)
		_bodies.append(body)
		_hand_counts.append(-1)

		var disc_l := MeshInstance3D.new()
		var dl := CylinderMesh.new()
		dl.top_radius = 1.0
		dl.bottom_radius = 1.0
		dl.height = 0.03
		disc_l.mesh = dl
		disc_l.material_override = _mat(EXPLOSION_COLOR, true, 0.45)
		disc_l.name = "LethalDisc"
		disc_l.visible = false
		add_child(disc_l)
		_lethal_discs.append(disc_l)

		var heads: Array[Node3D] = []
		for _k in Mods.max_heads():
			var head := _make_head(col)
			add_child(head)
			heads.append(head)
		_heads.append(heads)

		var mark := MeshInstance3D.new()
		var mc := CylinderMesh.new()
		mc.top_radius = 1.0
		mc.bottom_radius = 1.0
		mc.height = 0.04
		mark.mesh = mc
		mark.material_override = _mat(col.lightened(0.4), true, 0.6)
		add_child(mark)
		_aim_marks.append(mark)

	# Ring under the local player (index 0 until use_sim moves it).
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 1.0
	rc.bottom_radius = 1.0
	rc.height = 0.02
	ring.mesh = rc
	ring.material_override = _mat(Color(1, 1, 1), true, 0.35)
	ring.name = "LocalRing"
	_ring = ring
	_bodies[0].add_child(ring)


## A head in unit size (radius 1) with one cheap marker per modifier, shown or hidden each frame.
func _make_head(col: Color) -> Node3D:
	var head := Node3D.new()
	# Two shells with a groove for the string, and a stripe and cap on top that show the spin.
	var shell := _mat(col.lightened(0.3))
	for side: float in [-1.0, 1.0]:
		var half := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0 if side < 0.0 else 0.78
		cyl.bottom_radius = 0.78 if side < 0.0 else 1.0
		cyl.height = 0.2
		half.mesh = cyl
		half.material_override = shell
		half.position = Vector3(0.0, 0.15 * side, 0.0)
		head.add_child(half)
	var axle := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.45
	am.bottom_radius = 0.45
	am.height = 0.12
	axle.mesh = am
	axle.material_override = _mat(Color(0.1, 0.1, 0.12))
	head.add_child(axle)
	var bar := _box_mesh(Vector3(1.5, 0.08, 0.26), _mat(col.darkened(0.45)))
	bar.position = Vector3(0.0, 0.26, 0.0)
	head.add_child(bar)
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.36
	cm.height = 0.14
	cap.mesh = cm
	cap.material_override = _mat(Color(1, 1, 1))
	cap.position = Vector3(0.0, 0.3, 0.0)
	head.add_child(cap)
	# Abpraller: white ring around the rim.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.05
	tm.outer_radius = 1.4
	ring.mesh = tm
	ring.material_override = _mat(MARK_BOUNCE, true)
	ring.name = "MarkBounce"
	ring.visible = false
	head.add_child(ring)
	# Durchschlag: spikes pointing outwards (4, at level 3 eight in gold).
	var spikes := Node3D.new()
	spikes.name = "MarkPierce"
	spikes.visible = false
	for k in 8:
		var pivot := Node3D.new()
		pivot.rotation.y = TAU * k / 8.0
		var sp := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.3
		cone.height = 1.1
		sp.mesh = cone
		sp.material_override = _mat(MARK_PIERCE, true)
		sp.rotation.z = -PI * 0.5
		sp.position = Vector3(1.55, 0.0, 0.0)
		sp.name = "Spike"
		pivot.add_child(sp)
		spikes.add_child(pivot)
	head.add_child(spikes)
	# Bogenwurf: purple band on top.
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.12
	bm.bottom_radius = 1.12
	bm.height = 0.3
	band.mesh = bm
	band.material_override = _mat(MARK_ARC, true)
	band.position = Vector3(0.0, 0.2, 0.0)
	band.name = "MarkArc"
	band.visible = false
	head.add_child(band)
	# Sprengkopf: glowing red core.
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	core.mesh = sm
	core.material_override = _mat(MARK_WARHEAD, true)
	core.position = Vector3(0.0, 0.5, 0.0)
	core.scale = Vector3(1.0, 2.0, 1.0)
	core.name = "MarkWarhead"
	core.visible = false
	head.add_child(core)
	# Splitter: three yellow chips on the rim.
	var chips := Node3D.new()
	chips.name = "MarkShards"
	chips.visible = false
	for k in 3:
		var chip := _box_mesh(Vector3(0.45, 0.7, 0.45), _mat(MARK_SHARDS, true))
		var a := TAU * k / 3.0
		chip.position = Vector3(cos(a) * 0.95, 0.35, sin(a) * 0.95)
		chip.rotation.y = a + PI * 0.25
		chips.add_child(chip)
	head.add_child(chips)
	return head


func _set_head_marks(src: Sim, head: Node3D, p: SimPlayer) -> void:
	head.get_node("MarkBounce").visible = src.lv(p, "bounce") > 0
	var pierce := src.lv(p, "pierce")
	var spikes := head.get_node("MarkPierce") as Node3D
	spikes.visible = pierce > 0
	if pierce > 0:
		var gold := pierce >= Mods.MAX_LEVEL
		for k in spikes.get_child_count():
			var pivot := spikes.get_child(k) as Node3D
			pivot.visible = gold or k % 2 == 0
			((pivot.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = \
					MARK_PIERCE_L3 if gold else MARK_PIERCE
	head.get_node("MarkArc").visible = src.lv(p, "arc") > 0
	var wh := src.lv(p, "warhead")
	var core := head.get_node("MarkWarhead") as Node3D
	core.visible = wh > 0
	core.scale = Vector3(1.0, 2.0, 1.0) * (0.8 + 0.25 * wh)
	head.get_node("MarkShards").visible = src.lv(p, "shards") > 0


func shake(strength: float, time: float) -> void:
	_shake_strength = strength
	_shake_t = time
	_shake_total = maxf(time, 0.01)


func handle_event(e: Dictionary) -> void:
	var pos: Vector2 = e["pos"]
	match e["type"]:
		"kill":
			burst(pos, PLAYER_COLORS[e["victim"] as int], 32, 6.0)
			shake(Config.SHAKE_STRENGTH, Config.SHAKE_TIME)
		"bounce":
			burst(pos, Color(1, 1, 1), 10, 4.0)
		"ricochet":
			burst(pos, MARK_BOUNCE, 6, 3.0)
		"box_break":
			burst(pos, Color(0.8, 0.3, 0.7), 20, 5.0)
		"explosion":
			_explosion(pos, e["radius"] as float)
			shake(Config.SHAKE_STRENGTH * 0.5, Config.SHAKE_TIME * 0.6)
		"wire":
			burst(pos, PLAYER_COLORS[e["owner"] as int], 12, 4.0)
		"stun":
			burst(pos, Color(1, 0.95, 0.3), 10, 3.5)


## Quick expanding ring and flash of the real radius.
func _explosion(pos: Vector2, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.0
	rm.bottom_radius = 1.0
	rm.height = 0.06
	ring.mesh = rm
	var rmat := _mat(EXPLOSION_COLOR, true, 0.55)
	ring.material_override = rmat
	ring.position = Vector3(pos.x, 0.08, pos.y)
	ring.scale = Vector3(0.2, 1.0, 0.2)
	add_child(ring)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	edge.mesh = tm
	edge.material_override = _mat(Color(1, 1, 0.8), true)
	edge.position = ring.position
	edge.scale = Vector3(0.2, 1.0, 0.2)
	add_child(edge)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), Mods.EXPLOSION_VIEW_TIME)
	tw.tween_property(edge, "scale", Vector3(radius, 1.0, radius), Mods.EXPLOSION_VIEW_TIME)
	tw.tween_property(rmat, "albedo_color:a", 0.0, Mods.EXPLOSION_VIEW_TIME)
	tw.chain().tween_callback(ring.queue_free)
	tw.tween_callback(edge.queue_free)
	burst(pos, EXPLOSION_COLOR, 24, radius * 2.0)


func burst(pos: Vector2, col: Color, amount: int, speed: float) -> void:
	var ps := CPUParticles3D.new()
	ps.amount = amount
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.lifetime = 0.6
	ps.direction = Vector3.UP
	ps.spread = 180.0
	ps.initial_velocity_min = speed * 0.4
	ps.initial_velocity_max = speed
	ps.gravity = Vector3(0, -12, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	ps.mesh = sm
	var m := _mat(col.lightened(0.2), true)
	ps.material_override = m
	ps.position = Vector3(pos.x, 0.6, pos.y)
	add_child(ps)
	ps.emitting = true
	ps.finished.connect(ps.queue_free)
	# Flash: a quickly growing and fading sphere.
	var fl := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.5
	fm.height = 1.0
	fl.mesh = fm
	var fmat := _mat(Color(1, 1, 1), true, 0.8)
	fl.material_override = fmat
	fl.position = ps.position
	add_child(fl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fl, "scale", Vector3.ONE * 3.0, 0.22)
	tw.tween_property(fmat, "albedo_color:a", 0.0, 0.22)
	tw.chain().tween_callback(fl.queue_free)


## Screen position (viewport coordinates) -> sim position on the ground plane, or Vector2.INF.
func screen_to_ground(screen_pos: Vector2) -> Vector2:
	if camera == null:
		return Vector2.INF
	var o := camera.project_ray_origin(screen_pos)
	var n := camera.project_ray_normal(screen_pos)
	if absf(n.y) < 0.0001:
		return Vector2.INF
	var t := -o.y / n.y
	if t < 0.0:
		return Vector2.INF
	var hit := o + n * t
	return Vector2(hit.x, hit.z)


func _pool_node(pool: Array[MeshInstance3D], idx: int, make: Callable) -> MeshInstance3D:
	while pool.size() <= idx:
		var n: MeshInstance3D = make.call()
		add_child(n)
		pool.append(n)
	return pool[idx]


func _make_line_node() -> MeshInstance3D:
	return _box_mesh(Vector3(1, 1, 1), _mat(Color(1, 1, 1), true, 0.9))


func _make_string_node() -> MeshInstance3D:
	return _box_mesh(Vector3(1, 1, 1), _mat(Color(0.9, 0.9, 0.9), true))


## One segment of a polyline string / aim line; reuses pooled boxes (cursor reset every frame).
func _string_segment(a: Vector3, b: Vector3, width: float, col: Color) -> void:
	var mi := _pool_node(_string_segs, _seg_cursor, _make_string_node)
	_seg_cursor += 1
	(mi.material_override as StandardMaterial3D).albedo_color = col
	_place_line(mi, a, b, width)


func _aim_segment(a: Vector3, b: Vector3, width: float, col: Color) -> void:
	var mi := _pool_node(_aim_segs, _aim_cursor, _make_line_node)
	_aim_cursor += 1
	(mi.material_override as StandardMaterial3D).albedo_color = col
	_place_line(mi, a, b, width)


func _make_shard_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = _mat(SHARD_COLOR, true)
	return mi


## Draws the other players from `s` (the interpolated display state) instead of the predicted sim; null = off.
func set_others(s: Sim, a: float) -> void:
	others_sim = s
	others_alpha = a


func render(alpha: float, delta: float) -> void:
	_spin += delta * Config.HEAD_SPIN_SPEED
	_time += delta
	var pr := cfg.player_radius
	_seg_cursor = 0
	_aim_cursor = 0
	for i in sim.players.size():
		# The own player is drawn from the predicted sim, the others from the interpolated one (when given).
		var src: Sim = sim
		var a := alpha
		if others_sim != null and i != _local_slot:
			src = others_sim
			a = others_alpha
		var p := src.players[i]
		var body := _bodies[i]
		var vis := p.enabled and p.alive
		var appeared := vis and not body.visible
		body.visible = vis
		_aim_marks[i].visible = false
		_lethal_discs[i].visible = false
		var heads: Array = _heads[i]
		for k in heads.size():
			(heads[k] as Node3D).visible = false
		if not vis:
			continue
		if body.kind != posmod(p.skin, CharacterRig.KIND_COUNT):
			body.setup(p.skin, PLAYER_COLORS[i])
		var hr := src.head_r(p)
		var pos := p.prev_pos.lerp(p.pos, a)
		body.position = Vector3(pos.x, 0.0, pos.y)
		var face := p.aim_dir if p.charging else p.facing
		body.rotation.y = atan2(face.x, face.y)
		var ring := body.get_node_or_null("LocalRing") as Node3D
		if ring != null:
			ring.scale = Vector3(pr * 1.5, 1.0, pr * 1.5)
			ring.position = Vector3(0, 0.03, 0)
		# The figure: walk cycle from the real movement, wind-up from the charge, the hand follows the string.
		var hand_n := p.count_state(SimHead.S.HAND)
		if appeared:
			body.pop()
		elif _hand_counts[i] >= 0 and hand_n != _hand_counts[i]:
			body.throw_flick(hand_n < _hand_counts[i])
		_hand_counts[i] = hand_n
		var string_dir := Vector2.ZERO
		if hand_n == 0:
			for h in p.heads:
				var to: Vector2 = (h.pins[0] if h.pins.size() > 0 else h.prev_pos.lerp(h.pos, a)) - pos
				if to.length() > 0.05:
					string_dir = to.normalized()
					break
		var vel := (p.pos - p.prev_pos) * Config.TICK_RATE
		var charge := clampf(p.charge_t / maxf(cfg.charge_time, 0.01), 0.0, 1.0) if p.charging else 0.0
		body.animate(delta, pr, vel, cfg.player_speed, p.dash_t > 0.0 or p.body_is_moving_weapon(), charge,
				p.stun_t > 0.0, string_dir)
		var hand3 := body.hand_world()
		# Lethal body (Gummiband).
		var br := src.body_lethal_r(p)
		if br > 0.0:
			var ld := _lethal_discs[i]
			ld.visible = true
			ld.position = Vector3(pos.x, 0.05, pos.y)
			ld.scale = Vector3(br + Mods.BODY_LETHAL_MARGIN, 1.0, br + Mods.BODY_LETHAL_MARGIN)

		var elastic := src.lv(p, "elastic") > 0
		var hand_k := 0
		for k in p.heads.size():
			var h := p.heads[k]
			var node := heads[k] as Node3D
			node.visible = true
			_set_head_marks(src, node, p)
			var out_like := h.lethal()
			var hp := h.prev_pos.lerp(h.pos, a)
			var hy := HEAD_Y
			var hs := hr
			if not out_like:
				var side := Vector2(face.y, -face.x)
				hp = Vector2(hand3.x, hand3.z) + side * (hand_k - (hand_n - 1) * 0.5) * hr * HAND_SPREAD * 2.0
				hand_k += 1
				hy = hand3.y + HAND_LIFT
				hs = hr * 0.7
			else:
				hy = _head_height(h, hp.distance_to(pos), hand3.y)
			node.position = Vector3(hp.x, hy, hp.y)
			node.scale = Vector3(hs, hs * 0.5, hs)
			node.rotation.y = _spin if out_like else _spin * 0.3
			if out_like:
				var width := STRING_WIDTH
				var scol := Color(0.9, 0.9, 0.9)
				if elastic:
					width = ELASTIC_STRING_WIDTH * (1.0 + 0.3 * src.lv(p, "elastic") / Mods.MAX_LEVEL)
					scol = ELASTIC_STRING_COLOR
				# The string is a polyline: player -> bounce points (pins) -> head.
				var prev3 := hand3
				for pin in h.pins:
					var pin3 := Vector3(pin.x, STRING_Y, pin.y)
					_string_segment(prev3, pin3, width, scol)
					prev3 = pin3
				_string_segment(prev3, Vector3(hp.x, hy, hp.y), width, scol)
		if p.charging:
			var path := src.aim_path(p)
			var acol := PLAYER_COLORS[i].lightened(0.4)
			acol.a = 0.8
			for k in range(1, path.size()):
				_aim_segment(Vector3(path[k - 1].x, 0.05, path[k - 1].y), Vector3(path[k].x, 0.05, path[k].y), Config.AIM_LINE_WIDTH, acol)
			var end := path[path.size() - 1]
			var mark := _aim_marks[i]
			mark.visible = true
			mark.position = Vector3(end.x, 0.05, end.y)
			mark.scale = Vector3(hr * 1.1, 1.0, hr * 1.1)

	for k in range(_seg_cursor, _string_segs.size()):
		_string_segs[k].visible = false
	for k in range(_aim_cursor, _aim_segs.size()):
		_aim_segs[k].visible = false
	_render_wires()
	_render_shards(alpha)

	var cp := sim.prev_crate_pos.lerp(sim.crate_pos, alpha)
	_crate.position = Vector3(cp.x, Config.CRATE_HALF, cp.y)
	_box.visible = sim.box_active

	if _shake_t > 0.0:
		_shake_t -= delta
		var k := clampf(_shake_t / _shake_total, 0.0, 1.0) * _shake_strength
		camera.h_offset = _rng.randf_range(-k, k)
		camera.v_offset = _rng.randf_range(-k, k)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## Height of a yo-yo that is out: it leaves the hand in a flat arc, lies low while it is out and climbs back
## to the hand on its way home. Presentation only (hits are decided on the ground plane).
func _head_height(h: SimHead, dist: float, hand_y: float) -> float:
	match h.state:
		SimHead.S.FLIGHT:
			var t := clampf(h.flown / maxf(h.flight_dist, 0.01), 0.0, 1.0)
			return lerpf(hand_y, HEAD_Y, minf(t * 2.5, 1.0)) + sin(t * PI) * FLIGHT_ARC
		SimHead.S.RETRACT:
			var t := clampf(1.0 - dist / CATCH_RISE_DIST, 0.0, 1.0)
			return lerpf(HEAD_Y, hand_y, t * t)
	return HEAD_Y


## Tripwires on the ground in the owner's colour (polylines along the string); lethal ones glow red and pulse.
func _render_wires() -> void:
	var cursor := 0
	for w in _owned_by(sim.wires, true) + (_owned_by(others_sim.wires, false) if others_sim != null else []):
		var blink := 1.0
		if w.ttl < WIRE_BLINK_TIME:
			blink = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 30.0))
		var pulse := 0.6 + 0.4 * sin(_time * 12.0)
		var core_w := maxf(WIRE_WIDTH, w.half_width * 2.0)
		var glow_w := maxf(WIRE_LETHAL_WIDTH, w.half_width * 3.0) * (1.0 + 0.4 * pulse)
		for k in range(1, w.pts.size()):
			var a3 := Vector3(w.pts[k - 1].x, 0.05, w.pts[k - 1].y)
			var b3 := Vector3(w.pts[k].x, 0.05, w.pts[k].y)
			var core := _pool_node(_wire_core, cursor, _make_line_node)
			var glow := _pool_node(_wire_glow, cursor, _make_line_node)
			cursor += 1
			var cmat := core.material_override as StandardMaterial3D
			var gmat := glow.material_override as StandardMaterial3D
			if w.lethal:
				cmat.albedo_color = Color(1.0, 0.85, 0.8, blink)
				gmat.albedo_color = Color(WIRE_LETHAL_COLOR.r, WIRE_LETHAL_COLOR.g, WIRE_LETHAL_COLOR.b, 0.55 * pulse * blink)
				_place_line(core, a3, b3, core_w)
				_place_line(glow, a3 + Vector3(0, -0.01, 0), b3 + Vector3(0, -0.01, 0), glow_w)
			else:
				var c := PLAYER_COLORS[w.owner_id]
				cmat.albedo_color = Color(c.r, c.g, c.b, blink)
				_place_line(core, a3, b3, core_w)
				glow.visible = false
	for k in range(cursor, _wire_core.size()):
		_wire_core[k].visible = false
		_wire_glow[k].visible = false


func _render_shards(alpha: float) -> void:
	# Own shards from the predicted sim, the others' from the interpolated one (all from `sim` when it is off).
	var list: Array = []
	for s in _owned_by(sim.shards, true):
		list.append([s, alpha])
	if others_sim != null:
		for s in _owned_by(others_sim.shards, false):
			list.append([s, others_alpha])
	var n := list.size()
	for k in n:
		var s: SimShard = list[k][0]
		var node := _pool_node(_shard_nodes, k, _make_shard_node)
		var sp := s.prev_pos.lerp(s.pos, list[k][1])
		node.visible = true
		node.position = Vector3(sp.x, HEAD_Y + 0.15, sp.y)
		var r := s.radius * 1.4
		node.scale = Vector3(r, r, r)
	for k in range(n, _shard_nodes.size()):
		_shard_nodes[k].visible = false


## The wires or shards (anything with an `owner_id`) of the own player (`mine`) or of all the others. Without an
## interpolated sim every owner counts as "mine": everything comes from the predicted sim.
func _owned_by(list: Array, mine: bool) -> Array:
	if others_sim == null:
		return list if mine else []
	var out: Array = []
	for o in list:
		if (o.owner_id == _local_slot) == mine:
			out.append(o)
	return out


func _place_line(mi: MeshInstance3D, a: Vector3, b: Vector3, width: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var up := Vector3.RIGHT if absf(d.y / len) > 0.98 else Vector3.UP
	var basis := Basis.looking_at(d / len, up).scaled_local(Vector3(width, width, len))
	mi.transform = Transform3D(basis, (a + b) * 0.5)
