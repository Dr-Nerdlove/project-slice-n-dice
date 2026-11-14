class_name Playroom
extends Node3D
## The first arena dressed as a children's room seen from above: wooden floorboards, a calm play carpet inside a
## low toy fence (the outer walls), big wooden building blocks (the obstacles), a cardboard box (the movable crate)
## and a little tower of blocks (the breakable box) that tumbles apart when it breaks. View only: reads the sim.
## The colours avoid the player colours so the figures and their yo-yos stay the loudest things on screen.

const CARPET := Color("5d6a7d")         # muted slate blue: darker than every player colour
const CARPET_BAND := Color("75839a")
const CARPET_DOTS := Color("6d7a8f")
const FLOOR_WOOD := Color("b88a5c")
const FENCE_COLORS: Array[Color] = [Color("f3ead7"), Color("e9d3a8"), Color("cfe0e8")]
const BLOCK_COLORS: Array[Color] = [Color("dcb47e"), Color("3c51b5"), Color("b9473d"), Color("efe2c2")]
const CARDBOARD := Color("c7955c")
const TAPE := Color("e8d6ad")
const BLOCK_HEIGHT := 1.1
const FENCE_HEIGHT := 0.9
const PICKET_SPACING := 0.6
const BOX_DEBRIS_TIME := 0.9

var crate: Node3D
var box: Node3D
var _debris: Array[Node3D] = []
var _debris_v: Array[Vector3] = []
var _debris_w: Array[Vector3] = []
var _debris_t := -1.0
var _rng := RandomNumberGenerator.new()


func build(sim: Sim) -> void:
	_rng.seed = 7
	var a := Config.ARENA_SIZE
	_build_floor(a)
	_build_fence(a)
	for i in range(sim.wall_count, sim.statics.size()):
		_build_block(sim.statics[i], i - sim.wall_count)
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
			{"base_col": CARPET, "band_col": CARPET_BAND, "dot_col": CARPET_DOTS})
	carpet.name = "Carpet"


## A low wooden toy fence just outside the arena edge (on the sim's outer walls): two rails and pickets, the
## pickets as one MultiMesh (one draw call).
func _build_fence(a: Vector2) -> void:
	var fence := Node3D.new()
	fence.name = "Fence"
	add_child(fence)
	var off := 0.32
	var rail := ToyKit.matte(FENCE_COLORS[0])
	var rbox := ToyKit.rounded_box(0.25)
	var sides := [
		[Vector3(a.x * 0.5, 0, -off), Vector3(a.x + 2.0 * off, 0, 0)],
		[Vector3(a.x * 0.5, 0, a.y + off), Vector3(a.x + 2.0 * off, 0, 0)],
		[Vector3(-off, 0, a.y * 0.5), Vector3(0, 0, a.y + 2.0 * off)],
		[Vector3(a.x + off, 0, a.y * 0.5), Vector3(0, 0, a.y + 2.0 * off)],
	]
	var xforms: Array[Transform3D] = []
	for sd in sides:
		var c: Vector3 = sd[0]
		var span: Vector3 = sd[1]
		var along := span.length()
		var horiz := span.x > 0.0
		for h in [0.3, 0.68]:
			var size := Vector3(along, 0.14, 0.12) if horiz else Vector3(0.12, 0.14, along)
			ToyKit.part(fence, rbox, rail, c + Vector3(0, h, 0), size)
		var n := int(along / PICKET_SPACING)
		for k in n + 1:
			var t := -along * 0.5 + along * float(k) / float(n)
			var p := c + (Vector3(t, 0, 0) if horiz else Vector3(0, 0, t))
			xforms.append(Transform3D(Basis().scaled(Vector3(0.26, FENCE_HEIGHT, 0.26)), p + Vector3(0, FENCE_HEIGHT * 0.5, 0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = rbox
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, FENCE_COLORS[k % FENCE_COLORS.size()])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "Pickets"
	fence.add_child(mmi)


## A big wooden building block filling the obstacle exactly, with a smaller block on top.
func _build_block(r: Rect2, idx: int) -> void:
	var n := Node3D.new()
	n.name = "Block%d" % idx
	n.position = Vector3(r.get_center().x, 0, r.get_center().y)
	add_child(n)
	var col := BLOCK_COLORS[idx % BLOCK_COLORS.size()]
	var shadow := ToyKit.shadow(maxf(r.size.x, r.size.y) * 1.55)
	shadow.position = Vector3(0.25, 0.02, 0.2)
	n.add_child(shadow)
	ToyKit.part(n, ToyKit.rounded_box(0.12), ToyKit.matte(col), Vector3(0, BLOCK_HEIGHT * 0.5, 0), Vector3(r.size.x, BLOCK_HEIGHT, r.size.y))
	# An inset square on the top face, as on real blocks.
	ToyKit.part(n, ToyKit.rounded_box(0.12), ToyKit.matte(col.darkened(0.12)), Vector3(0, BLOCK_HEIGHT, 0), Vector3(r.size.x * 0.72, 0.04, r.size.y * 0.72))
	var top := BLOCK_COLORS[(idx + 1) % BLOCK_COLORS.size()]
	var m := minf(r.size.x, r.size.y)
	if idx % 2 == 0:
		ToyKit.part(n, ToyKit.cylinder(), ToyKit.matte(top), Vector3(0, BLOCK_HEIGHT + 0.3, 0), Vector3(m * 0.55, 0.6, m * 0.55))
	else:
		ToyKit.part(n, ToyKit.rounded_box(0.12), ToyKit.matte(top), Vector3(0, BLOCK_HEIGHT + 0.3, 0), Vector3(m * 0.6, 0.6, m * 0.6), Vector3(0, 0.4, 0))


## The movable crate: a cardboard box with a tape strip and the flap seam.
func _build_crate() -> void:
	crate = Node3D.new()
	crate.name = "Crate"
	add_child(crate)
	var s := Config.CRATE_HALF * 2.0
	var sh := ToyKit.shadow(s * 1.7)
	sh.position = Vector3(0.15, 0.02, 0.12)
	crate.add_child(sh)
	ToyKit.part(crate, ToyKit.rounded_box(0.08), ToyKit.matte(CARDBOARD), Vector3(0, s * 0.5, 0), Vector3(s, s, s))
	ToyKit.part(crate, ToyKit.rounded_box(0.08), ToyKit.matte(CARDBOARD.darkened(0.35)), Vector3(0, s + 0.005, 0), Vector3(s * 0.98, 0.02, 0.04))
	ToyKit.part(crate, ToyKit.rounded_box(0.08), ToyKit.matte(TAPE), Vector3(0, s + 0.01, 0), Vector3(0.32, 0.03, s * 1.01))
	ToyKit.part(crate, ToyKit.rounded_box(0.08), ToyKit.matte(TAPE), Vector3(0, s * 0.75, s * 0.5), Vector3(0.32, s * 0.5, 0.03))


## The breakable box: a tower of three blocks. When it breaks, a copy of the tower tumbles apart.
func _build_box() -> void:
	box = Node3D.new()
	box.name = "Box"
	box.position = Vector3(Config.BOX_POS.x, 0, Config.BOX_POS.y)
	add_child(box)
	_tower(box, false)
	var dbg := Node3D.new()
	dbg.name = "BoxDebris"
	dbg.position = box.position
	add_child(dbg)
	_tower(dbg, true)
	dbg.visible = false


func _tower(parent: Node3D, debris: bool) -> void:
	var s := Config.BOX_HALF * 2.0
	if not debris:
		var sh := ToyKit.shadow(s * 1.8)
		sh.position = Vector3(0.12, 0.02, 0.1)
		parent.add_child(sh)
	var parts: Array[MeshInstance3D] = []
	parts.append(ToyKit.part(parent, ToyKit.rounded_box(0.15), ToyKit.matte(BLOCK_COLORS[0]), Vector3(0, s * 0.22, 0), Vector3(s, s * 0.44, s)))
	parts.append(ToyKit.part(parent, ToyKit.rounded_box(0.15), ToyKit.matte(BLOCK_COLORS[1]), Vector3(0, s * 0.62, 0), Vector3(s * 0.8, s * 0.36, s * 0.8), Vector3(0, 0.35, 0)))
	parts.append(ToyKit.part(parent, ToyKit.cylinder(), ToyKit.matte(BLOCK_COLORS[2]), Vector3(0, s * 0.95, 0), Vector3(s * 0.55, s * 0.3, s * 0.55)))
	if debris:
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
	var cp := sim.prev_crate_pos.lerp(sim.crate_pos, alpha)
	crate.position = Vector3(cp.x, 0, cp.y)
	box.visible = sim.box_active
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


const CARPET_SHADER := """
shader_type spatial;
render_mode specular_disabled;
uniform vec2 size = vec2(32.0, 14.4);
uniform vec3 base_col : source_color;
uniform vec3 band_col : source_color;
uniform vec3 dot_col : source_color;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 m = UV * size;
	vec3 c = base_col;
	float d = min(min(m.x, size.x - m.x), min(m.y, size.y - m.y));
	vec2 cell = m / 2.4;
	vec2 g = fract(cell) - 0.5;
	float checker = mod(floor(cell.x) + floor(cell.y), 2.0);
	float dots = (1.0 - smoothstep(0.15, 0.19, length(g))) * step(1.5, d);
	c = mix(c, dot_col, dots * (0.55 + 0.45 * checker));
	float band = smoothstep(0.55, 0.6, d) * (1.0 - smoothstep(0.95, 1.0, d));
	c = mix(c, band_col, band);
	c *= 0.95 + 0.05 * hash(floor(m * 24.0));
	ALBEDO = c;
	ROUGHNESS = 1.0;
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
