class_name ArenaView
extends Node3D
## 3D presentation. Only reads sim state; interpolates between the last two ticks.
## Sim (x, y) maps to 3D (x, 0, y).

const PLAYER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.3), Color(0.35, 0.85, 0.4), Color(1.0, 0.8, 0.25)]
const BODY_HEIGHT := 1.8
const HEAD_Y := 0.35
const HAND_Y := 0.7
const STRING_WIDTH := 0.05
const STRING_Y := 0.6

var sim: Sim
var cfg: Config
var camera: Camera3D

var _bodies: Array[Node3D] = []
var _heads: Array[Node3D] = []
var _strings: Array[MeshInstance3D] = []
var _aim_lines: Array[MeshInstance3D] = []
var _aim_marks: Array[MeshInstance3D] = []
var _crate: MeshInstance3D
var _box: MeshInstance3D
var _spin := 0.0
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
		var body := Node3D.new()
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 1.0
		cm.height = BODY_HEIGHT
		cap.mesh = cm
		cap.material_override = _mat(col)
		body.add_child(cap)
		var nose := _box_mesh(Vector3(0.3, 0.3, 0.5), _mat(Color(1, 1, 1)))
		nose.name = "Nose"
		body.add_child(nose)
		add_child(body)
		_bodies.append(body)

		var head := Node3D.new()
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 0.5
		disc.mesh = cyl
		disc.material_override = _mat(col.lightened(0.3))
		head.add_child(disc)
		var bar := _box_mesh(Vector3(1.7, 0.6, 0.3), _mat(Color(0.1, 0.1, 0.12)))
		head.add_child(bar)
		add_child(head)
		_heads.append(head)

		var st := _box_mesh(Vector3(1, 1, 1), _mat(Color(0.9, 0.9, 0.9), true))
		add_child(st)
		_strings.append(st)

		var line := _box_mesh(Vector3(1, 1, 1), _mat(col.lightened(0.4), true, 0.8))
		add_child(line)
		_aim_lines.append(line)
		var mark := MeshInstance3D.new()
		var mc := CylinderMesh.new()
		mc.top_radius = 1.0
		mc.bottom_radius = 1.0
		mc.height = 0.04
		mark.mesh = mc
		mark.material_override = _mat(col.lightened(0.4), true, 0.6)
		add_child(mark)
		_aim_marks.append(mark)

	# Ring under the local player (index 0).
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 1.0
	rc.bottom_radius = 1.0
	rc.height = 0.02
	ring.mesh = rc
	ring.material_override = _mat(Color(1, 1, 1), true, 0.35)
	ring.name = "LocalRing"
	_bodies[0].add_child(ring)


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
		"box_break":
			burst(pos, Color(0.8, 0.3, 0.7), 20, 5.0)


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


func render(alpha: float, delta: float) -> void:
	_spin += delta * Config.HEAD_SPIN_SPEED
	var pr := cfg.player_radius
	var hr := cfg.head_radius
	for i in sim.players.size():
		var p := sim.players[i]
		var body := _bodies[i]
		var head := _heads[i]
		var vis := p.enabled and p.alive
		body.visible = vis
		head.visible = vis
		_strings[i].visible = false
		_aim_lines[i].visible = false
		_aim_marks[i].visible = false
		if not vis:
			continue
		var pos := p.prev_pos.lerp(p.pos, alpha)
		body.position = Vector3(pos.x, BODY_HEIGHT * 0.5, pos.y)
		var cap := body.get_child(0) as MeshInstance3D
		(cap.mesh as CapsuleMesh).radius = pr
		(cap.mesh as CapsuleMesh).height = BODY_HEIGHT
		var face := p.aim_dir if p.ystate == SimPlayer.Yo.CHARGING else p.facing
		body.rotation.y = atan2(face.x, face.y)
		(body.get_child(1) as Node3D).position = Vector3(0, 0.5, pr)
		var ring := body.get_node_or_null("LocalRing") as Node3D
		if ring != null:
			ring.scale = Vector3(pr * 1.5, 1.0, pr * 1.5)
			ring.position = Vector3(0, -BODY_HEIGHT * 0.5 + 0.03, 0)
			ring.rotation.y = -body.rotation.y

		var out_like := p.head_is_lethal()
		var hp := p.prev_head.lerp(p.head, alpha)
		var hy := HEAD_Y
		var hs := hr
		if not out_like:
			hp = pos + face * (pr + hr * 0.4)
			hy = HAND_Y
			hs = hr * 0.7
		head.position = Vector3(hp.x, hy, hp.y)
		head.scale = Vector3(hs, hs * 0.5, hs)
		head.rotation.y = _spin if out_like else _spin * 0.3
		if out_like:
			var from3 := Vector3(pos.x, STRING_Y, pos.y)
			var to3 := Vector3(hp.x, HEAD_Y + 0.1, hp.y)
			_place_line(_strings[i], from3, to3, STRING_WIDTH)
		if p.ystate == SimPlayer.Yo.CHARGING:
			var rng_len := sim.aim_range(p)
			var end := pos + p.aim_dir * rng_len
			_place_line(_aim_lines[i], Vector3(pos.x, 0.05, pos.y), Vector3(end.x, 0.05, end.y), Config.AIM_LINE_WIDTH)
			var mark := _aim_marks[i]
			mark.visible = true
			mark.position = Vector3(end.x, 0.05, end.y)
			mark.scale = Vector3(hr * 1.1, 1.0, hr * 1.1)

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
