class_name Playroom
extends Node3D
## The arena dressed as a children's room seen from above: wooden floorboards, a chequered play carpet framed by
## wooden beams with crayons, marbles and ring towers left lying on them (the outer walls), building blocks with
## letters (the obstacles), a toy chest on wheels (the movable crate), a wrapped present (the breakable box) that
## bursts apart when it breaks, and the toy train on its loop. View only: reads the sim.
## The carpet is darker and calmer than every player colour so the figures and their yo-yos stay the loudest
## things on screen.

const CARPET_A := Color("544a6e")
const CARPET_B := Color("61557b")
const CARPET_SEAM := Color("8478a0")
const CARPET_TILE := 1.6
const FLOOR_WOOD := Color("b88a5c")
const BEAM_WOOD := Color("dbb075")
const BEAM_TRIM := Color("9e7345")
const BEAM_WIDTH := 1.0
const BEAM_HEIGHT := 0.7
const BLOCK_WOOD := Color("f0dcb4")
const BLOCK_COLORS: Array[Color] = [Color("ff9e4d"), Color("4dcccc"), Color("b88fff"), Color("ff8cc7")]
const BLOCK_LETTERS := "JOYO"
const BLOCK_HEIGHT := 1.2
const CHEST_WOOD := Color("b8803f")
const CHEST_BAND := Color("4dbfd9")
const PRESENT := Color("cc4db3")
const RIBBON := Color("ffd94d")
const RAIL := Color("c2c7d1")
const SLEEPER := Color("805c3d")
const RAIL_GAUGE := 0.3
const TRAIN_RED := Color("d92924")
const TRAIN_DARK := Color("292933")
const TRAIN_YELLOW := Color("ffd133")
const WAGON_COLORS: Array[Color] = [Color("40b3b8"), Color("9973e6")]
const BOX_DEBRIS_TIME := 0.9

var crate: Node3D
var box: Node3D
var cars: Array[Node3D] = []
var _wheels: Array[Node3D] = []
var _debris: Array[Node3D] = []
var _debris_v: Array[Vector3] = []
var _debris_w: Array[Vector3] = []
var _debris_t := -1.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func build(sim: Sim) -> void:
	_rng.seed = 7
	var a := Config.ARENA_SIZE
	_build_floor(a)
	_build_beams(a)
	for i in range(sim.wall_count, sim.statics.size()):
		_build_block(sim.statics[i], i - sim.wall_count)
	_build_track()
	_build_train()
	_build_crate()
	_build_box()


func _shader_plane(size: Vector2, center: Vector3, code: String, params: Dictionary) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("size", size)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_floor(a: Vector2) -> void:
	var room := _shader_plane(Vector2(a.x + 30.0, a.y + 24.0), Vector3(a.x * 0.5, -0.01, a.y * 0.5), FLOOR_SHADER,
			{"wood": FLOOR_WOOD})
	room.name = "Floorboards"
	var carpet := _shader_plane(a, Vector3(a.x * 0.5, 0.0, a.y * 0.5), CARPET_SHADER,
			{"col_a": CARPET_A, "col_b": CARPET_B, "seam": CARPET_SEAM, "tile": CARPET_TILE})
	carpet.name = "Carpet"


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return ToyKit.part(parent, mesh, mat, pos, size, rot)


## Wooden beams just outside the arena edge (on the sim's outer walls), with things left lying on them. The node
## keeps the name "Fence": it is what fences the carpet in.
func _build_beams(a: Vector2) -> void:
	var fence := Node3D.new()
	fence.name = "Fence"
	add_child(fence)
	var wood := ToyKit.matte(BEAM_WOOD)
	var trim := ToyKit.matte(BEAM_TRIM)
	var rbox := ToyKit.rounded_box(0.12)
	var w := BEAM_WIDTH
	var h := BEAM_HEIGHT
	_part(fence, rbox, wood, Vector3(a.x * 0.5, h * 0.5, -w * 0.5), Vector3(a.x + 2.0 * w, h, w))
	_part(fence, rbox, wood, Vector3(a.x * 0.5, h * 0.5, a.y + w * 0.5), Vector3(a.x + 2.0 * w, h, w))
	_part(fence, rbox, wood, Vector3(-w * 0.5, h * 0.5, a.y * 0.5), Vector3(w, h, a.y))
	_part(fence, rbox, wood, Vector3(a.x + w * 0.5, h * 0.5, a.y * 0.5), Vector3(w, h, a.y))
	var e := 0.1
	_part(fence, rbox, trim, Vector3(a.x * 0.5, h, -e * 0.5), Vector3(a.x + e * 2.0, 0.05, e))
	_part(fence, rbox, trim, Vector3(a.x * 0.5, h, a.y + e * 0.5), Vector3(a.x + e * 2.0, 0.05, e))
	_part(fence, rbox, trim, Vector3(-e * 0.5, h, a.y * 0.5), Vector3(e, 0.05, a.y))
	_part(fence, rbox, trim, Vector3(a.x + e * 0.5, h, a.y * 0.5), Vector3(e, 0.05, a.y))
	# Crayons: [position along x or z as a share of the arena, on which beam (0 top, 1 bottom, 2 left, 3 right),
	# angle, colour].
	var mid := w * 0.5
	var crayons: Array = [
		[0.14, 0, 1.45, Color("ff7333")], [0.19, 0, 1.75, Color("4dbff2")], [0.8, 0, 1.3, Color("bf80ff")],
		[0.75, 2, 0.2, Color("66d980")], [0.25, 3, -0.25, Color("ffcc4d")], [0.62, 1, 1.5, Color("ff6f91")]]
	for c: Array in crayons:
		var cr := Node3D.new()
		cr.position = _on_beam(a, c[0], c[1], mid) + Vector3(0, h + 0.11, 0)
		cr.rotation.y = c[2]
		fence.add_child(cr)
		var cm := ToyKit.plastic(c[3])
		_part(cr, ToyKit.cylinder(), cm, Vector3.ZERO, Vector3(0.22, 1.1, 0.22), Vector3(PI * 0.5, 0, 0))
		_part(cr, ToyKit.cone(), cm, Vector3(0, 0, 0.67), Vector3(0.22, 0.25, 0.22), Vector3(PI * 0.5, 0, 0))
		_part(cr, ToyKit.cylinder(), ToyKit.matte(Color("fbfbf7")), Vector3(0, 0, -0.1), Vector3(0.235, 0.5, 0.235), Vector3(PI * 0.5, 0, 0))
	var marbles: Array = [
		[0.37, 0, 0.4, Color("4de6cc")], [0.4, 0, 0.3, Color("ff80b3")], [0.6, 0, 0.34, Color("ffd94d")],
		[0.25, 2, 0.4, Color("9980ff")], [0.68, 3, 0.36, Color("66e680")], [0.72, 3, 0.26, Color("ff8c4d")],
		[0.27, 1, 0.36, Color("ff80b3")], [0.7, 1, 0.4, Color("4dbff2")], [0.45, 1, 0.3, Color("ffd94d")]]
	for mb: Array in marbles:
		var d: float = mb[2]
		_part(fence, ToyKit.sphere(), ToyKit.plastic(mb[3]), _on_beam(a, mb[0], mb[1], mid + (d - 0.35)) + Vector3(0, h + d * 0.5, 0), Vector3.ONE * d)
	# A stacking ring tower in the two far corners.
	var ring_cols: Array[Color] = [Color("ff7366"), Color("ffcc4d"), Color("66cc80"), Color("59a6ff")]
	for x: float in [-mid, a.x + mid]:
		for k in 4:
			var dia := 0.95 - 0.16 * k
			_part(fence, ToyKit.torus(), ToyKit.plastic(ring_cols[k]), Vector3(x, h + 0.12 + 0.2 * k, -mid), Vector3(dia, 1.3, dia))
		_part(fence, ToyKit.cylinder(), ToyKit.matte(BEAM_TRIM), Vector3(x, h + 0.45, -mid), Vector3(0.14, 0.95, 0.14))


## A point on top of one of the four beams: `t` along it (0..1), `off` outwards from the arena edge.
func _on_beam(a: Vector2, t: float, beam: int, off: float) -> Vector3:
	match beam:
		0:
			return Vector3(a.x * t, 0, -off)
		1:
			return Vector3(a.x * t, 0, a.y + off)
		2:
			return Vector3(-off, 0, a.y * t)
	return Vector3(a.x + off, 0, a.y * t)


## A wooden building block filling the obstacle exactly: coloured faces and a letter on top.
func _build_block(r: Rect2, idx: int) -> void:
	var n := Node3D.new()
	n.name = "Block%d" % idx
	n.position = Vector3(r.get_center().x, 0, r.get_center().y)
	add_child(n)
	var col := BLOCK_COLORS[idx % BLOCK_COLORS.size()]
	var h := BLOCK_HEIGHT + (0.3 if idx == 0 else 0.0)
	var shadow := ToyKit.shadow(maxf(r.size.x, r.size.y) * 1.55)
	shadow.position = Vector3(0.25, 0.02, 0.2)
	n.add_child(shadow)
	var rbox := ToyKit.rounded_box(0.12)
	_part(n, rbox, ToyKit.matte(BLOCK_WOOD), Vector3(0, h * 0.5, 0), Vector3(r.size.x, h, r.size.y))
	var inset := 0.18
	_part(n, rbox, ToyKit.matte(col), Vector3(0, h, 0), Vector3(r.size.x - inset * 2.0, 0.06, r.size.y - inset * 2.0))
	_part(n, rbox, ToyKit.matte(col), Vector3(0, h * 0.5, r.size.y * 0.5), Vector3(r.size.x - inset * 2.0, h - inset * 2.0, 0.06))
	var label := Label3D.new()
	label.text = BLOCK_LETTERS[idx % BLOCK_LETTERS.length()]
	label.font_size = 160
	label.pixel_size = minf(r.size.x, r.size.y) * 0.0045
	label.outline_size = 0
	label.shaded = false
	label.rotation.x = -PI * 0.5
	label.position = Vector3(0, h + 0.05, 0)
	n.add_child(label)


## Sleepers and rails along the loop of the toy train, as two multimeshes (two draw calls).
func _build_track() -> void:
	var track := Node3D.new()
	track.name = "Track"
	add_child(track)
	var n_sleepers := int(TrainTrack.LENGTH / 0.42)
	var sleepers := _multi(track, Vector3(0.95, 0.04, 0.16), ToyKit.matte(SLEEPER), n_sleepers)
	for k in n_sleepers:
		var s := TrainTrack.LENGTH * k / n_sleepers
		var p := TrainTrack.point(s)
		var d := TrainTrack.dir(s)
		sleepers.multimesh.set_instance_transform(k, Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(p.x, 0.025, p.y)))
	var n_rail := int(TrainTrack.LENGTH / 0.2)
	var seg := TrainTrack.LENGTH / n_rail
	var rails := _multi(track, Vector3(0.07, 0.07, seg * 1.3), ToyKit.plastic(RAIL), n_rail * 2)
	for k in n_rail:
		var s := seg * k
		var p := TrainTrack.point(s)
		var d := TrainTrack.dir(s)
		var side := Vector2(d.y, -d.x) * RAIL_GAUGE
		var basis := Basis(Vector3.UP, atan2(d.x, d.y))
		rails.multimesh.set_instance_transform(k * 2, Transform3D(basis, Vector3(p.x + side.x, 0.07, p.y + side.y)))
		rails.multimesh.set_instance_transform(k * 2 + 1, Transform3D(basis, Vector3(p.x - side.x, 0.07, p.y - side.y)))


func _multi(parent: Node3D, size: Vector3, m: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = size
	mm.mesh = bm
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Locomotive and wagons, modelled facing +z around the centre of their hit circle.
func _build_train() -> void:
	var dark := ToyKit.plastic(TRAIN_DARK)
	var red := ToyKit.plastic(TRAIN_RED)
	var yellow := ToyKit.plastic(TRAIN_YELLOW)
	var rbox := ToyKit.rounded_box(0.25)
	for k in TrainTrack.CARS:
		var car := Node3D.new()
		car.name = "Car%d" % k
		add_child(car)
		cars.append(car)
		var sh := ToyKit.shadow(1.9)
		sh.position.y = 0.09
		car.add_child(sh)
		_part(car, rbox, red if k == 0 else dark, Vector3(0, 0.3, 0), Vector3(0.82, 0.18, 1.14))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var pivot := Node3D.new()
				pivot.position = Vector3(0.42 * sx, 0.19, 0.32 * sz)
				car.add_child(pivot)
				_part(pivot, ToyKit.cylinder(), dark, Vector3.ZERO, Vector3(0.38, 0.1, 0.38), Vector3(0, 0, PI * 0.5))
				_part(pivot, rbox, yellow, Vector3.ZERO, Vector3(0.12, 0.3, 0.08))
				_wheels.append(pivot)
		if k == 0:
			_part(car, ToyKit.cylinder(), dark, Vector3(0, 0.68, 0.18), Vector3(0.66, 0.72, 0.66), Vector3(PI * 0.5, 0, 0))
			_part(car, ToyKit.cylinder(), yellow, Vector3(0, 0.68, 0.5), Vector3(0.68, 0.08, 0.68), Vector3(PI * 0.5, 0, 0))
			_part(car, ToyKit.sphere(), ToyKit.unshaded(Color("fff29a")), Vector3(0, 0.68, 0.56), Vector3.ONE * 0.24)
			_part(car, ToyKit.cylinder(), dark, Vector3(0, 1.12, 0.3), Vector3(0.26, 0.36, 0.26))
			_part(car, ToyKit.cylinder(), red, Vector3(0, 1.32, 0.3), Vector3(0.38, 0.1, 0.38))
			_part(car, ToyKit.sphere(), yellow, Vector3(0, 1.04, 0.02), Vector3.ONE * 0.22)
			_part(car, rbox, red, Vector3(0, 0.7, -0.33), Vector3(0.8, 0.68, 0.44))
			_part(car, rbox, yellow, Vector3(0, 1.07, -0.33), Vector3(0.92, 0.1, 0.58))
			_part(car, rbox, yellow, Vector3(0, 0.22, 0.66), Vector3(0.8, 0.12, 0.3), Vector3(-0.5, 0, 0))
			var smoke := CPUParticles3D.new()
			smoke.name = "Smoke"
			smoke.amount = 10
			smoke.lifetime = 0.9
			smoke.direction = Vector3.UP
			smoke.spread = 15.0
			smoke.initial_velocity_min = 1.2
			smoke.initial_velocity_max = 1.8
			smoke.gravity = Vector3.ZERO
			smoke.scale_amount_min = 0.6
			smoke.scale_amount_max = 1.4
			var puff := SphereMesh.new()
			puff.radius = 0.13
			puff.height = 0.26
			puff.radial_segments = 8
			puff.rings = 4
			smoke.mesh = puff
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.albedo_color = Color(1, 1, 1, 0.7)
			smoke.material_override = sm
			smoke.position = Vector3(0, 1.4, 0.3)
			car.add_child(smoke)
		else:
			var wm := ToyKit.plastic(WAGON_COLORS[(k - 1) % WAGON_COLORS.size()])
			_part(car, rbox, wm, Vector3(0, 0.58, 0.5), Vector3(0.84, 0.42, 0.1))
			_part(car, rbox, wm, Vector3(0, 0.58, -0.5), Vector3(0.84, 0.42, 0.1))
			_part(car, rbox, wm, Vector3(0.37, 0.58, 0), Vector3(0.1, 0.42, 1.08))
			_part(car, rbox, wm, Vector3(-0.37, 0.58, 0), Vector3(0.1, 0.42, 1.08))
			# Cargo: marbles in one wagon, blocks in the next.
			if k % 2 == 1:
				var cargo: Array[Color] = [Color("ffd94d"), Color("ff80b3"), Color("66e680"), Color("fbfbf7")]
				for j in 4:
					_part(car, ToyKit.sphere(), ToyKit.plastic(cargo[j]), Vector3(-0.15 + 0.3 * (j % 2), 0.72 + 0.04 * j, -0.25 + 0.5 * (j / 2)), Vector3.ONE * 0.4)
			else:
				_part(car, rbox, ToyKit.matte(BLOCK_COLORS[0]), Vector3(-0.08, 0.72, 0.2), Vector3.ONE * 0.4, Vector3(0, 0.3, 0))
				_part(car, rbox, ToyKit.matte(BLOCK_COLORS[3]), Vector3(0.1, 0.7, -0.24), Vector3.ONE * 0.36, Vector3(0, -0.2, 0))


## The movable crate: a toy chest on wheels.
func _build_crate() -> void:
	crate = Node3D.new()
	crate.name = "Crate"
	add_child(crate)
	var s := Config.CRATE_HALF * 2.0
	var sh := ToyKit.shadow(s * 1.7)
	sh.position = Vector3(0.15, 0.02, 0.12)
	crate.add_child(sh)
	var rbox := ToyKit.rounded_box(0.12)
	var band := ToyKit.plastic(CHEST_BAND)
	_part(crate, rbox, ToyKit.matte(CHEST_WOOD), Vector3(0, 0.2 + s * 0.31, 0), Vector3(s, s * 0.62, s))
	_part(crate, rbox, ToyKit.matte(CHEST_WOOD.lightened(0.15)), Vector3(0, 0.2 + s * 0.62 + 0.09, 0), Vector3(s + 0.06, 0.2, s + 0.06))
	for sx: float in [-1.0, 1.0]:
		_part(crate, rbox, band, Vector3(s * 0.28 * sx, 0.2 + s * 0.31 + 0.1, 0), Vector3(0.22, s * 0.62 + 0.46, s + 0.1))
		for sz: float in [-1.0, 1.0]:
			_part(crate, ToyKit.cylinder(), ToyKit.plastic(TRAIN_DARK), Vector3((s * 0.5 - 0.02) * sx, 0.2, s * 0.32 * sz), Vector3(0.4, 0.14, 0.4), Vector3(0, 0, PI * 0.5))
	_part(crate, ToyKit.sphere(), ToyKit.plastic(RIBBON), Vector3(0, 0.2 + s * 0.45, s * 0.5 + 0.04), Vector3.ONE * 0.2)


## The breakable box: a wrapped present. When it breaks, a copy of it bursts into its pieces.
func _build_box() -> void:
	box = Node3D.new()
	box.name = "Box"
	box.position = Vector3(Config.BOX_POS.x, 0, Config.BOX_POS.y)
	add_child(box)
	_present(box, false)
	var dbg := Node3D.new()
	dbg.name = "BoxDebris"
	dbg.position = box.position
	add_child(dbg)
	_present(dbg, true)
	dbg.visible = false


func _present(parent: Node3D, debris: bool) -> void:
	var s := Config.BOX_HALF * 2.0
	var paper := ToyKit.plastic(PRESENT)
	var ribbon := ToyKit.plastic(RIBBON)
	var rbox := ToyKit.rounded_box(0.15)
	var parts: Array[MeshInstance3D] = []
	parts.append(_part(parent, rbox, paper, Vector3(0, s * 0.38, 0), Vector3(s, s * 0.76, s)))
	parts.append(_part(parent, rbox, ToyKit.plastic(PRESENT.lightened(0.15)), Vector3(0, s * 0.86, 0), Vector3(s * 1.08, s * 0.26, s * 1.08)))
	for sx: float in [-1.0, 1.0]:
		parts.append(_part(parent, ToyKit.sphere(), ribbon, Vector3(0.2 * sx, s + 0.14, 0), Vector3(0.48, 0.28, 0.24), Vector3(0, 0, 0.5 * sx)))
	parts.append(_part(parent, ToyKit.sphere(), ribbon, Vector3(0, s + 0.1, 0), Vector3.ONE * 0.2))
	if not debris:
		var sh := ToyKit.shadow(s * 1.8)
		sh.position = Vector3(0.12, 0.02, 0.1)
		parent.add_child(sh)
		_part(parent, rbox, ribbon, Vector3(0, s * 0.5, 0), Vector3(s * 1.16, s * 1.14, 0.26))
		_part(parent, rbox, ribbon, Vector3(0, s * 0.5, 0), Vector3(0.26, s * 1.14, s * 1.16))
		return
	for pt in parts:
		_debris.append(pt)
		_debris_v.append(Vector3.ZERO)
		_debris_w.append(Vector3.ZERO)
		pt.set_meta("home", pt.transform)


func box_break() -> void:
	var dbg := get_node("BoxDebris") as Node3D
	dbg.visible = true
	for k in _debris.size():
		var pt := _debris[k]
		pt.transform = pt.get_meta("home")
		var dir := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.5, 3.0)
		_debris_v[k] = Vector3(dir.x, _rng.randf_range(3.0, 5.5), dir.y)
		_debris_w[k] = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-6, 6), _rng.randf_range(-8, 8))
	_debris_t = 0.0


func update(sim: Sim, alpha: float, dt: float) -> void:
	_time += dt
	var cp := sim.prev_crate_pos.lerp(sim.crate_pos, alpha)
	crate.position = Vector3(cp.x, 0, cp.y)
	box.visible = sim.box_active
	_update_train(sim, alpha)
	if _debris_t < 0.0:
		return
	_debris_t += dt
	var dbg := get_node("BoxDebris") as Node3D
	if _debris_t >= BOX_DEBRIS_TIME:
		_debris_t = -1.0
		dbg.visible = false
		return
	var shrink := clampf((BOX_DEBRIS_TIME - _debris_t) / 0.25, 0.0, 1.0)
	for k in _debris.size():
		var pt := _debris[k]
		var v := _debris_v[k]
		v.y -= 18.0 * dt
		var p := pt.position + v * dt
		if p.y < 0.15 and v.y < 0.0:
			p.y = 0.15
			v = Vector3(v.x * 0.6, -v.y * 0.35, v.z * 0.6)
		_debris_v[k] = v
		pt.position = p
		var sc := (pt.get_meta("home") as Transform3D).basis.get_scale()
		pt.basis = (Basis.from_euler(_debris_w[k] * _debris_t)).scaled(sc * shrink)


## The train where the sim has it (hidden while it is switched off), rattling a little, wheels turning.
func _update_train(sim: Sim, alpha: float) -> void:
	var s := lerpf(sim.prev_train_s, sim.train_s, alpha)
	for k in cars.size():
		var cs := TrainTrack.car_s(s, k)
		var pt := TrainTrack.point(cs)
		var d := TrainTrack.dir(cs)
		var car := cars[k]
		car.visible = sim.cfg.train_speed > 0.0
		car.position = Vector3(pt.x, 0.0, pt.y)
		car.rotation = Vector3(0.0, atan2(d.x, d.y), sin(_time * 9.0 + k * 1.7) * 0.03)
	for w in _wheels:
		w.rotation.x = s / 0.19


const CARPET_SHADER := """
shader_type spatial;
uniform vec2 size;
uniform vec3 col_a : source_color;
uniform vec3 col_b : source_color;
uniform vec3 seam : source_color;
uniform float tile = 1.6;

void fragment() {
	vec2 p = UV * size;
	vec2 c = floor(p / tile);
	vec3 col = mix(col_a, col_b, mod(c.x + c.y, 2.0));
	float edge = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	if (edge < 0.18) {
		col = seam;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
"""

const FLOOR_SHADER := """
shader_type spatial;
uniform vec2 size = vec2(60.0, 40.0);
uniform vec3 wood : source_color;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 m = UV * size;
	float row = floor(m.y / 0.6);
	float x = m.x + hash(vec2(row, 3.0)) * 4.0;
	float board = floor(x / 3.2);
	float fy = fract(m.y / 0.6);
	float fx = fract(x / 3.2);
	float seam = smoothstep(0.0, 0.04, fy) * smoothstep(0.0, 0.04, 1.0 - fy) * smoothstep(0.0, 0.008, fx) * smoothstep(0.0, 0.008, 1.0 - fx);
	vec3 c = wood * (0.86 + 0.16 * hash(vec2(row, board)));
	c *= 0.97 + 0.03 * sin(m.x * 7.0 + hash(vec2(board, row)) * 20.0);
	ALBEDO = c * mix(0.62, 1.0, seam);
	ROUGHNESS = 0.55;
}
"""
