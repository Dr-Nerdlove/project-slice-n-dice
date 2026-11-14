class_name ToyKit
extends RefCounted
## Shared look of the toy world: the materials (glossy moulded plastic, plush, painted wood) and the few meshes
## every toy and block is built from. Everything is created once and shared, so a figure costs draw calls but no
## extra materials or meshes. Unit meshes: scale the MeshInstance3D to size.

const SPHERE_SEGMENTS := 18
const SPHERE_RINGS := 9

static var _mats := {}
static var _meshes := {}


## Glossy moulded plastic: low roughness, a clear coat for the sharp highlight and a little rim light so the
## silhouette reads against the floor.
static func plastic(c: Color) -> StandardMaterial3D:
	return _material("plastic", c)


## Soft fabric: rough, no highlight, strong rim light (the fuzz along the outline).
static func plush(c: Color) -> StandardMaterial3D:
	return _material("plush", c)


## Painted wood and cardboard: rough with a soft highlight.
static func matte(c: Color) -> StandardMaterial3D:
	return _material("matte", c)


static func unshaded(c: Color) -> StandardMaterial3D:
	return _material("unshaded", c)


## A new (not shared) plastic material, for parts whose colour changes at run time (a figure's body flashes).
static func new_plastic(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	_setup(m, "plastic", c)
	return m


static func _material(kind: String, c: Color) -> StandardMaterial3D:
	var key := "%s:%s" % [kind, c.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_setup(m, kind, c)
	_mats[key] = m
	return m


static func _setup(m: StandardMaterial3D, kind: String, c: Color) -> void:
	m.albedo_color = c
	match kind:
		"plastic":
			m.roughness = 0.28
			m.metallic_specular = 0.6
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
			m.clearcoat_roughness = 0.12
			m.rim_enabled = true
			m.rim = 0.2
			m.rim_tint = 0.6
		"plush":
			m.roughness = 1.0
			m.metallic_specular = 0.15
			m.rim_enabled = true
			m.rim = 0.7
			m.rim_tint = 0.85
		"matte":
			m.roughness = 0.7
			m.metallic_specular = 0.35
		"unshaded":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


static func sphere() -> Mesh:
	if not _meshes.has("sphere"):
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = SPHERE_SEGMENTS
		sm.rings = SPHERE_RINGS
		_meshes["sphere"] = sm
	return _meshes["sphere"]


## Unit cylinder (diameter 1, height 1).
static func cylinder() -> Mesh:
	if not _meshes.has("cylinder"):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 1.0
		cm.radial_segments = 16
		cm.rings = 1
		_meshes["cylinder"] = cm
	return _meshes["cylinder"]


## Unit cone (base diameter 1, height 1, tip up).
static func cone() -> Mesh:
	if not _meshes.has("cone"):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.5
		cm.height = 1.0
		cm.radial_segments = 12
		cm.rings = 1
		_meshes["cone"] = cm
	return _meshes["cone"]


## Unit ring (outer diameter 1) of the given thickness ratio.
static func torus() -> Mesh:
	if not _meshes.has("torus"):
		var tm := TorusMesh.new()
		tm.inner_radius = 0.34
		tm.outer_radius = 0.5
		tm.rings = 18
		tm.ring_segments = 8
		_meshes["torus"] = tm
	return _meshes["torus"]


## A diamond (octahedron-like sphere), for the dizzy stars.
static func diamond() -> Mesh:
	if not _meshes.has("diamond"):
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 4
		sm.rings = 2
		_meshes["diamond"] = sm
	return _meshes["diamond"]


## Unit cube with rounded edges, as a moulded toy or a sanded wooden block has them (a superellipsoid: `round` 0 is
## a sharp box, 1 a sphere). Size 1 x 1 x 1 like BoxMesh.
static func rounded_box(round := 0.35) -> Mesh:
	var key := "rbox:%.2f" % round
	if _meshes.has(key):
		return _meshes[key]
	var e := clampf(round, 0.05, 1.0)
	var seg_u := 28
	var seg_v := 14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in seg_v + 1:
		var v := PI * float(j) / float(seg_v)
		for i in seg_u + 1:
			var u := TAU * float(i) / float(seg_u)
			var d := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			var p := Vector3(_spow(d.x, e), _spow(d.y, e), _spow(d.z, e))
			var n := Vector3(_spow(d.x, 2.0 - e), _spow(d.y, 2.0 - e), _spow(d.z, 2.0 - e))
			st.set_normal(n.normalized() if n.length() > 0.0001 else d)
			st.set_uv(Vector2(float(i) / float(seg_u), float(j) / float(seg_v)))
			st.add_vertex(p * 0.5)
	for j in seg_v:
		for i in seg_u:
			var a := j * (seg_u + 1) + i
			var b := a + seg_u + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


static func _spow(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)


## A soft round shadow on the floor (shared by every figure, yo-yo and block).
static func shadow_material() -> StandardMaterial3D:
	if _mats.has("shadow"):
		return _mats["shadow"]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var a := 0.5 * (1.0 - smoothstep(0.35, 1.0, d))
			img.set_pixel(x, y, Color(0.08, 0.05, 0.06, a))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mats["shadow"] = m
	return m


## A flat shadow disc of the given diameter (metres), lying on the floor.
static func shadow(diameter: float) -> MeshInstance3D:
	if not _meshes.has("shadow"):
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		_meshes["shadow"] = pm
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["shadow"]
	mi.material_override = shadow_material()
	mi.scale = Vector3(diameter, 1.0, diameter)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Shadow"
	return mi


## A MeshInstance3D of `mesh` with `mat`, placed in `parent`.
static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
