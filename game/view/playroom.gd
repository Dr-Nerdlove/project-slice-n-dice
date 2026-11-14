class_name Playroom
extends Node3D
## The arena as a playroom: a play carpet framed by wooden beams, building blocks as obstacles, a toy chest on
## wheels (the pushable crate), a wrapped present (the breakable box) and the toy train on its loop.
## Presentation only: every shape is drawn where the simulation says it is.

const CARPET_A := Color(0.33, 0.29, 0.43)
const CARPET_B := Color(0.38, 0.33, 0.48)
const CARPET_TILE := 1.4
const WOOD := Color(0.86, 0.69, 0.46)
const WOOD_DARK := Color(0.62, 0.45, 0.27)
const BLOCK_WOOD := Color(0.94, 0.86, 0.7)
const BLOCK_COLORS: Array[Color] = [
	Color(1.0, 0.62, 0.3), Color(0.3, 0.8, 0.8), Color(0.72, 0.56, 1.0), Color(1.0, 0.55, 0.78)]
const BLOCK_LETTERS := "JOYO"
const WALL_HEIGHT := 0.9
const BLOCK_HEIGHT := 1.3
const PRESENT := Color(0.8, 0.3, 0.7)
const RIBBON := Color(1.0, 0.85, 0.3)
const RAIL := Color(0.75, 0.77, 0.82)
const SLEEPER := Color(0.5, 0.36, 0.24)
const RAIL_GAUGE := 0.3
const TRAIN_RED := Color(0.85, 0.16, 0.14)
const TRAIN_DARK := Color(0.16, 0.16, 0.2)
const TRAIN_YELLOW := Color(1.0, 0.82, 0.2)
const WAGON_COLORS: Array[Color] = [Color(0.25, 0.7, 0.72), Color(0.6, 0.45, 0.9)]

var _crate: Node3D
var _present: Node3D
var _cars: Array[Node3D] = []
var _wheels: Array[Node3D] = []
var _time := 0.0


func setup(sim: Sim) -> void:
	_build_floor()
	_build_walls(sim)
	_build_blocks(sim)
	_build_track()
	_build_train()
	_crate = _build_chest()
	_present = _build_present()
	_present.position = Vector3(Config.BOX_POS.x, 0.0, Config.BOX_POS.y)


## Moves what moves. `alpha` blends between the last two ticks.
func render(sim: Sim, alpha: float, delta: float) -> void:
	_time += delta
	var cp := sim.prev_crate_pos.lerp(sim.crate_pos, alpha)
	_crate.position = Vector3(cp.x, 0.0, cp.y)
	_present.visible = sim.box_active
	_present.rotation.y = sin(_time * 1.3) * 0.05
	var s := lerpf(sim.prev_train_s, sim.train_s, alpha)
	for k in _cars.size():
		var cs := TrainTrack.car_s(s, k)
		var pt := TrainTrack.point(cs)
		var d := TrainTrack.dir(cs)
		var car := _cars[k]
		car.visible = sim.cfg.train_speed > 0.0
		car.position = Vector3(pt.x, 0.0, pt.y)
		car.rotation.y = atan2(d.x, d.y)
		car.rotation.z = sin(_time * 9.0 + k * 1.7) * 0.03   # rattling along
	for w in _wheels:
		w.rotation.x = s / 0.16


func _mat(c: Color, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _flat(c: Color) -> StandardMaterial3D:
	var m := _mat(c)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, top: float, bottom: float, h: float, m: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, r: float, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## The play carpet: a soft two-tone chequer, made as a tiny texture so it is one draw call.
func _build_floor() -> void:
	var a := Config.ARENA_SIZE
	var nx := int(round(a.x / CARPET_TILE))
	var ny := int(round(a.y / CARPET_TILE))
	var img := Image.create(nx, ny, false, Image.FORMAT_RGB8)
	for y in ny:
		for x in nx:
			img.set_pixel(x, y, CARPET_A if (x + y) % 2 == 0 else CARPET_B)
	var m := _mat(Color(1, 1, 1), 0.95)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = a
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(a.x * 0.5, 0.0, a.y * 0.5)
	add_child(mi)
	# A lighter seam along the edge of the carpet.
	var seam := _mat(CARPET_B.lightened(0.25), 0.95)
	_box(self, Vector3(a.x, 0.02, 0.18), seam, Vector3(a.x * 0.5, 0.0, 0.09))
	_box(self, Vector3(a.x, 0.02, 0.18), seam, Vector3(a.x * 0.5, 0.0, a.y - 0.09))
	_box(self, Vector3(0.18, 0.02, a.y), seam, Vector3(0.09, 0.0, a.y * 0.5))
	_box(self, Vector3(0.18, 0.02, a.y), seam, Vector3(a.x - 0.09, 0.0, a.y * 0.5))


## Wooden beams around the carpet, with a few things left lying on them.
func _build_walls(sim: Sim) -> void:
	var wood := _mat(WOOD, 0.7)
	var trim := _mat(WOOD_DARK, 0.7)
	for i in sim.wall_count:
		var r := sim.statics[i]
		var c := r.get_center()
		_box(self, Vector3(r.size.x, WALL_HEIGHT, r.size.y), wood, Vector3(c.x, WALL_HEIGHT * 0.5, c.y))
	var a := Config.ARENA_SIZE
	var e := 0.12
	_box(self, Vector3(a.x + e * 2.0, 0.06, e), trim, Vector3(a.x * 0.5, WALL_HEIGHT, -e * 0.5))
	_box(self, Vector3(a.x + e * 2.0, 0.06, e), trim, Vector3(a.x * 0.5, WALL_HEIGHT, a.y + e * 0.5))
	_box(self, Vector3(e, 0.06, a.y), trim, Vector3(-e * 0.5, WALL_HEIGHT, a.y * 0.5))
	_box(self, Vector3(e, 0.06, a.y), trim, Vector3(a.x + e * 0.5, WALL_HEIGHT, a.y * 0.5))
	var top := WALL_HEIGHT
	# Crayons.
	var crayons: Array = [
		[Vector3(4.0, 0, -0.75), 1.45, Color(1.0, 0.45, 0.2)], [Vector3(5.3, 0, -0.55), 1.75, Color(0.3, 0.75, 0.95)],
		[Vector3(22.5, 0, -0.7), 1.3, Color(0.75, 0.5, 1.0)], [Vector3(-0.7, 0, 9.5), 0.2, Color(0.4, 0.85, 0.5)],
		[Vector3(28.65, 0, 3.2), -0.25, Color(1.0, 0.8, 0.3)]]
	for c: Array in crayons:
		var cr := Node3D.new()
		cr.position = (c[0] as Vector3) + Vector3(0, top + 0.11, 0)
		cr.rotation.y = c[1]
		add_child(cr)
		var cm := _mat(c[2], 0.5)
		_cyl(cr, 0.11, 0.11, 1.1, cm, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
		_cyl(cr, 0.0, 0.11, 0.25, cm, Vector3(0, 0, 0.67), Vector3(PI * 0.5, 0, 0))
		_cyl(cr, 0.115, 0.115, 0.5, _mat(Color(1, 1, 1), 0.8), Vector3(0, 0, -0.1), Vector3(PI * 0.5, 0, 0))
	# Marbles.
	var marbles: Array = [
		[Vector3(10.5, 0, -0.6), 0.2, Color(0.3, 0.9, 0.8)], [Vector3(11.1, 0, -0.9), 0.15, Color(1.0, 0.5, 0.7)],
		[Vector3(17.0, 0, -0.5), 0.17, Color(1.0, 0.85, 0.3)], [Vector3(-0.8, 0, 3.0), 0.2, Color(0.6, 0.5, 1.0)],
		[Vector3(28.7, 0, 8.6), 0.18, Color(0.4, 0.9, 0.5)], [Vector3(28.5, 0, 9.1), 0.13, Color(1.0, 0.55, 0.3)],
		[Vector3(7.5, 0, 13.1), 0.18, Color(1.0, 0.5, 0.7)], [Vector3(19.5, 0, 13.0), 0.2, Color(0.3, 0.75, 0.95)]]
	for mb: Array in marbles:
		var r: float = mb[1]
		_ball(self, r, _mat(mb[2], 0.1), (mb[0] as Vector3) + Vector3(0, top + r, 0))
	# A stacking ring tower in the far corners.
	for x: float in [-0.9, 28.9]:
		var ring_cols: Array[Color] = [Color(1.0, 0.45, 0.4), Color(1.0, 0.8, 0.3), Color(0.4, 0.8, 0.5), Color(0.35, 0.65, 1.0)]
		for k in 4:
			var tm := TorusMesh.new()
			tm.outer_radius = 0.6 - 0.1 * k
			tm.inner_radius = tm.outer_radius - 0.24
			tm.rings = 20
			tm.ring_segments = 8
			var mi := MeshInstance3D.new()
			mi.mesh = tm
			mi.material_override = _mat(ring_cols[k], 0.35)
			mi.position = Vector3(x, top + 0.12 + 0.22 * k, -0.9)
			add_child(mi)


## Building blocks with a coloured face and a letter on top.
func _build_blocks(sim: Sim) -> void:
	var wood := _mat(BLOCK_WOOD, 0.7)
	for i in range(sim.wall_count, sim.statics.size()):
		var k := i - sim.wall_count
		var r := sim.statics[i]
		var c := r.get_center()
		var col := BLOCK_COLORS[k % BLOCK_COLORS.size()]
		var h := BLOCK_HEIGHT + (0.3 if k == 0 else 0.0)
		_box(self, Vector3(r.size.x, h, r.size.y), wood, Vector3(c.x, h * 0.5, c.y))
		var inset := 0.16
		_box(self, Vector3(r.size.x - inset * 2.0, 0.05, r.size.y - inset * 2.0), _mat(col, 0.5), Vector3(c.x, h, c.y))
		_box(self, Vector3(r.size.x - inset * 2.0, h - inset * 2.0, 0.05), _mat(col, 0.5), Vector3(c.x, h * 0.5, r.end.y))
		var label := Label3D.new()
		label.text = BLOCK_LETTERS[k % BLOCK_LETTERS.length()]
		label.font_size = 160
		label.pixel_size = minf(r.size.x, r.size.y) * 0.0045
		label.outline_size = 0
		label.modulate = Color(1, 1, 1)
		label.shaded = false
		label.rotation.x = -PI * 0.5
		label.position = Vector3(c.x, h + 0.04, c.y)
		add_child(label)


## Sleepers and rails along the loop, as two multimeshes.
func _build_track() -> void:
	var n_sleepers := int(TrainTrack.LENGTH / 0.42)
	var sleepers := _multi(Vector3(0.95, 0.04, 0.16), _mat(SLEEPER, 0.9), n_sleepers)
	for k in n_sleepers:
		var s := TrainTrack.LENGTH * k / n_sleepers
		var p := TrainTrack.point(s)
		var d := TrainTrack.dir(s)
		sleepers.multimesh.set_instance_transform(k, Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(p.x, 0.025, p.y)))
	var n_rail := int(TrainTrack.LENGTH / 0.2)
	var seg := TrainTrack.LENGTH / n_rail
	var rails := _multi(Vector3(0.07, 0.07, seg * 1.3), _mat(RAIL, 0.25), n_rail * 2)
	for k in n_rail:
		var s := seg * k
		var p := TrainTrack.point(s)
		var d := TrainTrack.dir(s)
		var side := Vector2(d.y, -d.x) * RAIL_GAUGE
		var basis := Basis(Vector3.UP, atan2(d.x, d.y))
		rails.multimesh.set_instance_transform(k * 2, Transform3D(basis, Vector3(p.x + side.x, 0.07, p.y + side.y)))
		rails.multimesh.set_instance_transform(k * 2 + 1, Transform3D(basis, Vector3(p.x - side.x, 0.07, p.y - side.y)))


func _multi(size: Vector3, m: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = size
	mm.mesh = bm
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)
	return mmi


## Locomotive and wagons, modelled facing +Z around the centre of their circle.
func _build_train() -> void:
	var dark := _mat(TRAIN_DARK, 0.35)
	var red := _mat(TRAIN_RED, 0.3)
	var yellow := _mat(TRAIN_YELLOW, 0.3)
	for k in TrainTrack.CARS:
		var car := Node3D.new()
		add_child(car)
		_cars.append(car)
		_box(car, Vector3(0.8, 0.16, 1.12), red if k == 0 else dark, Vector3(0, 0.3, 0))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var pivot := Node3D.new()
				pivot.position = Vector3(0.42 * sx, 0.19, 0.32 * sz)
				car.add_child(pivot)
				_cyl(pivot, 0.19, 0.19, 0.1, dark, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
				_box(pivot, Vector3(0.11, 0.3, 0.07), yellow)
				_wheels.append(pivot)
		if k == 0:
			_cyl(car, 0.33, 0.33, 0.72, dark, Vector3(0, 0.68, 0.18), Vector3(PI * 0.5, 0, 0))
			_cyl(car, 0.34, 0.34, 0.08, yellow, Vector3(0, 0.68, 0.5), Vector3(PI * 0.5, 0, 0))
			_ball(car, 0.12, _flat(Color(1.0, 0.95, 0.6)), Vector3(0, 0.68, 0.56))
			_cyl(car, 0.15, 0.1, 0.36, dark, Vector3(0, 1.12, 0.3))
			_cyl(car, 0.2, 0.15, 0.1, red, Vector3(0, 1.32, 0.3))
			_ball(car, 0.11, yellow, Vector3(0, 1.04, 0.02))
			_box(car, Vector3(0.78, 0.66, 0.42), red, Vector3(0, 0.7, -0.33))
			_box(car, Vector3(0.9, 0.08, 0.56), yellow, Vector3(0, 1.07, -0.33))
			_box(car, Vector3(0.8, 0.12, 0.3), yellow, Vector3(0, 0.22, 0.66), Vector3(-0.5, 0, 0))
			var smoke := CPUParticles3D.new()
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
			var sm := _flat(Color(1, 1, 1, 0.7))
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			smoke.material_override = sm
			smoke.position = Vector3(0, 1.4, 0.3)
			car.add_child(smoke)
		else:
			var col := WAGON_COLORS[(k - 1) % WAGON_COLORS.size()]
			var wm := _mat(col, 0.35)
			_box(car, Vector3(0.82, 0.4, 0.08), wm, Vector3(0, 0.58, 0.5))
			_box(car, Vector3(0.82, 0.4, 0.08), wm, Vector3(0, 0.58, -0.5))
			_box(car, Vector3(0.08, 0.4, 1.08), wm, Vector3(0.37, 0.58, 0))
			_box(car, Vector3(0.08, 0.4, 1.08), wm, Vector3(-0.37, 0.58, 0))
			# Cargo: marbles in one wagon, blocks in the next.
			if k % 2 == 1:
				var cargo: Array[Color] = [Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 0.7), Color(0.4, 0.9, 0.5), Color(1, 1, 1)]
				for j in 4:
					_ball(car, 0.2, _mat(cargo[j], 0.1), Vector3(-0.15 + 0.3 * (j % 2), 0.72 + 0.04 * j, -0.25 + 0.5 * (j / 2)))
			else:
				_box(car, Vector3(0.4, 0.4, 0.4), _mat(BLOCK_COLORS[0], 0.5), Vector3(-0.08, 0.72, 0.2), Vector3(0, 0.3, 0))
				_box(car, Vector3(0.36, 0.36, 0.36), _mat(BLOCK_COLORS[3], 0.5), Vector3(0.1, 0.7, -0.24), Vector3(0, -0.2, 0))


## The pushable crate: a toy chest on wheels.
func _build_chest() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var w := Config.CRATE_HALF * 2.0
	var wood := _mat(Color(0.72, 0.5, 0.26), 0.7)
	var band := _mat(Color(0.3, 0.75, 0.85), 0.4)
	_box(n, Vector3(w, w * 0.62, w), wood, Vector3(0, 0.2 + w * 0.31, 0))
	_box(n, Vector3(w + 0.06, 0.18, w + 0.06), _mat(Color(0.56, 0.37, 0.18), 0.7), Vector3(0, 0.2 + w * 0.62 + 0.09, 0))
	_box(n, Vector3(0.2, w * 0.62 + 0.3, w + 0.08), band, Vector3(-w * 0.28, 0.2 + w * 0.31 + 0.1, 0))
	_box(n, Vector3(0.2, w * 0.62 + 0.3, w + 0.08), band, Vector3(w * 0.28, 0.2 + w * 0.31 + 0.1, 0))
	_ball(n, 0.1, _mat(RIBBON, 0.3), Vector3(0, 0.2 + w * 0.45, w * 0.5 + 0.04))
	var dark := _mat(TRAIN_DARK, 0.4)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cyl(n, 0.2, 0.2, 0.14, dark, Vector3((w * 0.5 - 0.02) * sx, 0.2, w * 0.32 * sz), Vector3(0, 0, PI * 0.5))
	return n


## The breakable box: a wrapped present with a ribbon and a bow.
func _build_present() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var w := Config.BOX_HALF * 2.0
	var ribbon := _mat(RIBBON, 0.35)
	_box(n, Vector3(w, w, w), _mat(PRESENT, 0.45), Vector3(0, w * 0.5, 0))
	_box(n, Vector3(w + 0.04, w + 0.04, 0.2), ribbon, Vector3(0, w * 0.5, 0))
	_box(n, Vector3(0.2, w + 0.04, w + 0.04), ribbon, Vector3(0, w * 0.5, 0))
	for sx: float in [-1.0, 1.0]:
		var loop := _ball(n, 0.2, ribbon, Vector3(0.2 * sx, w + 0.14, 0))
		loop.scale = Vector3(1.2, 0.7, 0.6)
		loop.rotation.z = 0.5 * sx
	_ball(n, 0.1, ribbon, Vector3(0, w + 0.1, 0))
	return n
