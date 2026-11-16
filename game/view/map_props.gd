class_name MapProps
extends Node3D
## The toys of the five newer maps (MapDef.Id 1..5) and what their twists show: conveyor belts with running arrows,
## the puzzle mat with blinking and burning tiles, trampolines with painted landing spots, the two magnets with
## their fields, the piggy bank with the coins on its back. View only: reads the sim, never writes it. Everything
## is built once; each frame only moves, scales, shows or hides nodes and swaps between shared materials
## (ToyKit), so nothing is allocated while a round runs. Design: docs/maps.md.

const BELT_RUBBER := Color("2b2f3a")
const BELT_RAIL := Color("ffb02e")
const BELT_ROLLER := Color("c2c7d1")
const BELT_ARROW := Color("ffe14d")
const BELT_ARROW_STOP := Color("ff5a3c")
const ARROW_SPACING := 1.3
const MAT_COLORS: Array[Color] = [Color("46587a"), Color("5b4a78"), Color("3d6068"), Color("6b4a62")]
const PAD_COLORS: Array[Color] = [Color("ff7a59"), Color("59c7ff"), Color("9be564"), Color("ffd24d")]
const PAD_CLOTH := Color("23283a")
const PAD_KICK_TIME := 0.45
const MAGNET_PULL := Color("e5383b")
const MAGNET_PUSH := Color("3a86ff")
const MAGNET_IDLE := Color("8d93a1")
const MAGNET_TIP := Color("dfe3ea")
const MAGNET_BASE := Color("3a3d4a")
const FIELD_RINGS := 3
const PIG_PINK := Color("ff8fb1")
const PIG_DARK := Color("e0668c")
const PIG_EYE := Color("2a2230")
const COIN := Color("ffd94d")
const RUG := Color("6b4f7d")
const RUG_TRIM := Color("8d6fa3")
const PIG_KICK_TIME := 0.5

static var _meshes := {}

var map_id := 0
var _time := 0.0
# belts
var _arrows: Array[MultiMeshInstance3D] = []
var _lamps: Array[MeshInstance3D] = []
# lava
var _tiles: Array[MeshInstance3D] = []
var _warn_mat: ShaderMaterial
var _hot_mat: ShaderMaterial
# trampolines
var _pad_cloth: Array[Node3D] = []
var _pad_kick: Array[float] = []
var _land_fill: Array[MeshInstance3D] = []
var _land_ring: Array[MeshInstance3D] = []
# magnets
var _magnet_parts: Array = []            # per magnet: Array[MeshInstance3D] that take the polarity colour
var _field_edge: Array[MeshInstance3D] = []
var _field_rings: Array = []             # per magnet: Array[MeshInstance3D]
# pig
var _pig: Node3D
var _pig_kick := -1.0
var _coins: Array[MeshInstance3D] = []


func build(sim: Sim) -> void:
	map_id = sim.map_id
	match map_id:
		MapDef.Id.BELTS:
			_build_belts()
		MapDef.Id.LAVA:
			_build_lava()
		MapDef.Id.BOUNCE:
			_build_pads()
		MapDef.Id.MAGNETS:
			_build_magnets()
		MapDef.Id.PIGGY:
			_build_pig()


func update(sim: Sim, _alpha: float, dt: float) -> void:
	_time += dt
	if sim.map_id != map_id:
		return   # the playroom is about to be rebuilt for the other map
	match map_id:
		MapDef.Id.BELTS:
			_update_belts(sim)
		MapDef.Id.LAVA:
			_update_lava(sim)
		MapDef.Id.BOUNCE:
			_update_pads(sim, dt)
		MapDef.Id.MAGNETS:
			_update_magnets(sim)
		MapDef.Id.PIGGY:
			_update_pig(sim, dt)


## Sim events the props react to (ArenaView forwards them).
func on_event(e: Dictionary) -> void:
	match e["type"]:
		"launch":
			var k: int = e.get("pad", -1)
			if k >= 0 and k < _pad_kick.size():
				_pad_kick[k] = 0.0
		"pig":
			_pig_kick = 0.0


# ---------------------------------------------------------------- helpers

static func _unit_box() -> Mesh:
	if not _meshes.has("box"):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		_meshes["box"] = bm
	return _meshes["box"]


static func _unit_plane() -> Mesh:
	if not _meshes.has("plane"):
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE
		_meshes["plane"] = pm
	return _meshes["plane"]


## A thin ring of outer diameter 1 (the floor rings of fields and landing spots).
static func _thin_ring() -> Mesh:
	if not _meshes.has("ring"):
		var tm := TorusMesh.new()
		tm.inner_radius = 0.47
		tm.outer_radius = 0.5
		tm.rings = 48
		tm.ring_segments = 4
		_meshes["ring"] = tm
	return _meshes["ring"]


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return ToyKit.part(parent, mesh, mat, pos, size, rot)


## A flat marking lying on the floor over `r` at height `y`.
func _flat(parent: Node3D, r: Rect2, y: float, mat: Material, thickness := 0.02) -> MeshInstance3D:
	var c := r.get_center()
	return _part(parent, _unit_box(), mat, Vector3(c.x, y, c.y), Vector3(r.size.x, thickness, r.size.y))


func _group(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	return n


static func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


# ---------------------------------------------------------------- 1 Assembly Line

func _build_belts() -> void:
	var root := _group("Belts")
	var rubber := ToyKit.matte(BELT_RUBBER)
	var rail := ToyKit.plastic(BELT_RAIL)
	var rbox := ToyKit.rounded_box(0.2)
	for k in MapDef.BELTS.size():
		var r: Rect2 = MapDef.BELTS[k][0]
		var fwd: Vector2 = MapDef.BELTS[k][1]
		var back: Vector2 = MapDef.BELTS[k][2]
		_flat(root, r, 0.03, rubber, 0.06)
		if fwd == -back:
			# A straight piece: a rail along both sides.
			var side := Vector2(fwd.y, fwd.x).abs()            # the axis across the belt
			var along := fwd.abs()
			var half_w := (r.size * side).length() * 0.5
			var run := (r.size * along).length()
			for s: float in [-1.0, 1.0]:
				var c := r.get_center() + side * s * half_w
				var size := along * run + side * 0.14
				_part(root, rbox, rail, _v3(c, 0.09), Vector3(maxf(size.x, 0.14), 0.18, maxf(size.y, 0.14)))
		# Arrows that run with the belt: two bars per chevron, one multimesh per piece.
		var length := (r.size * fwd.abs()).length() if fwd == -back else r.size.x
		var count := maxi(1, roundi(length / ARROW_SPACING))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _unit_box()
		mm.instance_count = count * 2
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Arrows%d" % k
		mmi.multimesh = mm
		mmi.material_override = ToyKit.unshaded(BELT_ARROW)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		_arrows.append(mmi)
	# A roller at both ends of the S and a signal lamp next to each: it goes red while the belt stands.
	var first: Rect2 = MapDef.BELTS[0][0]
	var last: Rect2 = MapDef.BELTS[MapDef.BELTS.size() - 1][0]
	var ends: Array[Vector2] = [Vector2(first.position.x, first.get_center().y), Vector2(last.end.x, last.get_center().y)]
	for e in ends:
		_part(root, ToyKit.cylinder(), ToyKit.plastic(BELT_ROLLER), _v3(e, 0.12), Vector3(0.3, first.size.y, 0.3), Vector3(PI * 0.5, 0, 0))
		var out := -1.0 if e.x < Config.ARENA_SIZE.x * 0.5 else 1.0
		_part(root, ToyKit.cylinder(), ToyKit.plastic(BELT_RUBBER), _v3(e + Vector2(out * 0.6, 0), 0.35), Vector3(0.16, 0.7, 0.16))
		_lamps.append(_part(root, ToyKit.sphere(), ToyKit.unshaded(BELT_ARROW), _v3(e + Vector2(out * 0.6, 0), 0.8), Vector3.ONE * 0.36))


func _update_belts(sim: Sim) -> void:
	var t := sim.map_t
	var cycle := MapDef.BELT_RUN + MapDef.BELT_STOP
	var forwards := int(floor(t / cycle)) % 2 == 0
	var standing := MapDef.belt_factor(t) == 0.0
	# While it stands, the arrows blink red; shortly before, the lamps already flicker.
	var arrow_mat := ToyKit.unshaded(BELT_ARROW_STOP if standing else BELT_ARROW)
	var shown := not standing or int(_time * 6.0) % 2 == 0
	var soon := MapDef.belt_time_left(t) < 1.0
	for lamp in _lamps:
		lamp.material_override = ToyKit.unshaded(BELT_ARROW_STOP if standing or (soon and int(_time * 8.0) % 2 == 0) else BELT_ARROW)
	var travel := MapDef.belt_travel(t)
	for k in _arrows.size():
		var mmi := _arrows[k]
		mmi.material_override = arrow_mat
		mmi.visible = shown
		var r: Rect2 = MapDef.BELTS[k][0]
		var dir: Vector2 = MapDef.BELTS[k][1] if forwards else MapDef.BELTS[k][2]
		var length := (r.size * dir.abs()).length()
		var mm := mmi.multimesh
		var count := mm.instance_count / 2
		var spacing := length / count
		var phase := fposmod(travel if forwards else -travel, spacing)
		var start := r.get_center() - dir * length * 0.5
		var yaw := atan2(dir.x, dir.y)
		var frame := Basis(Vector3.UP, yaw)
		for i in count:
			var s := i * spacing + phase
			var grow := clampf(minf(s, length - s) / 0.5, 0.0, 1.0)   # they slide in and out at the ends
			var p := start + dir * s
			for half in 2:
				var sx := -1.0 if half == 0 else 1.0
				var arm := Basis(Vector3.UP, 0.75 * sx).scaled_local(Vector3(0.85 * grow, 0.02, 0.17 * grow))
				var origin := _v3(p, 0.075) + frame * Vector3(0.3 * sx, 0, 0)
				mm.set_instance_transform(i * 2 + half, Transform3D(frame * arm, origin))


# ---------------------------------------------------------------- 2 Lava Mats

## The puzzle mat that replaces the carpet (Playroom asks for it).
static func mat_floor_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = MAT_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tile", MapDef.LAVA_TILE)
	for i in MAT_COLORS.size():
		m.set_shader_parameter("col%d" % i, MAT_COLORS[i])
	return m


func _build_lava() -> void:
	var root := _group("Lava")
	_warn_mat = _shader_material(WARN_SHADER)
	_hot_mat = _shader_material(HOT_SHADER)
	for c in MapDef.LAVA_COLS * MapDef.LAVA_ROWS:
		var r := MapDef.lava_rect(c).grow(-0.06)
		var mi := _part(root, _unit_plane(), _warn_mat, _v3(r.get_center(), 0.035), Vector3(r.size.x, 1.0, r.size.y))
		mi.name = "Tile%d" % c
		mi.visible = false
		_tiles.append(mi)


func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _update_lava(sim: Sim) -> void:
	var stage := MapDef.lava_stage(sim.map_t)
	var hot := stage == MapDef.Lava.HOT
	if stage == MapDef.Lava.WARN:
		# The blinking gets faster towards the moment the mats catch fire.
		var into := fposmod(sim.map_t, MapDef.LAVA_CALM + MapDef.LAVA_WARN + MapDef.LAVA_HOT) - MapDef.LAVA_CALM
		_warn_mat.set_shader_parameter("urgency", clampf(into / MapDef.LAVA_WARN, 0.0, 1.0))
	for c in _tiles.size():
		var mi := _tiles[c]
		var on := sim.lava_cells.has(c)
		mi.visible = on
		if on:
			mi.material_override = _hot_mat if hot else _warn_mat


# ---------------------------------------------------------------- 3 Bounce House

func _build_pads() -> void:
	var root := _group("Trampolines")
	var d := MapDef.PAD_RADIUS * 2.0
	for k in MapDef.PADS.size():
		var at: Vector2 = MapDef.PADS[k][0]
		var land: Vector2 = MapDef.PADS[k][1]
		var col := PAD_COLORS[k % PAD_COLORS.size()]
		var pad := Node3D.new()
		pad.name = "Pad%d" % k
		pad.position = _v3(at)
		root.add_child(pad)
		var sh := ToyKit.shadow(d * 1.5)
		sh.position = Vector3(0.12, 0.02, 0.1)
		pad.add_child(sh)
		_part(pad, ToyKit.torus(), ToyKit.plastic(col), Vector3(0, 0.26, 0), Vector3(d + 0.5, 1.0, d + 0.5))
		for a in 4:
			var leg := Vector2.from_angle(PI * 0.25 + a * PI * 0.5) * (MapDef.PAD_RADIUS + 0.1)
			_part(pad, ToyKit.cylinder(), ToyKit.plastic(BELT_ROLLER), Vector3(leg.x, 0.13, leg.y), Vector3(0.12, 0.26, 0.12))
		var cloth := Node3D.new()
		cloth.name = "Cloth"
		cloth.position = Vector3(0, 0.27, 0)
		pad.add_child(cloth)
		_part(cloth, ToyKit.cylinder(), ToyKit.matte(PAD_CLOTH), Vector3.ZERO, Vector3(d, 0.05, d))
		_part(cloth, ToyKit.cylinder(), ToyKit.unshaded(col), Vector3(0, 0.03, 0), Vector3(0.55, 0.02, 0.55))
		_part(cloth, _thin_ring(), ToyKit.unshaded(col), Vector3(0, 0.03, 0), Vector3(d * 0.7, 0.3, d * 0.7))
		_pad_cloth.append(cloth)
		_pad_kick.append(-1.0)
		# The landing spot in the pad's colour: the squash circle, a cross, and a dotted line from the pad.
		var faint := col
		faint.a = 0.5
		var spot := Node3D.new()
		spot.name = "Landing%d" % k
		spot.position = _v3(land)
		root.add_child(spot)
		var sd := MapDef.STOMP_RADIUS * 2.0
		_land_ring.append(_part(spot, _thin_ring(), ToyKit.overlay(faint), Vector3(0, 0.04, 0), Vector3(sd, 0.4, sd)))
		for rot: float in [PI * 0.25, -PI * 0.25]:
			_part(spot, _unit_box(), ToyKit.overlay(faint), Vector3(0, 0.035, 0), Vector3(0.9, 0.02, 0.14), Vector3(0, rot, 0))
		var danger := col
		danger.a = 0.35
		var fill := _part(spot, ToyKit.cylinder(), ToyKit.overlay(danger), Vector3(0, 0.03, 0), Vector3(sd, 0.02, sd))
		fill.visible = false
		_land_fill.append(fill)
		var dotted := col
		dotted.a = 0.3
		var dist := at.distance_to(land)
		var dots := int((dist - MapDef.PAD_RADIUS - MapDef.STOMP_RADIUS) / 0.8)
		for i in dots:
			var q := at.move_toward(land, MapDef.PAD_RADIUS + 0.6 + i * 0.8)
			_part(root, ToyKit.cylinder(), ToyKit.overlay(dotted), _v3(q, 0.03), Vector3(0.22, 0.02, 0.22))


func _update_pads(sim: Sim, dt: float) -> void:
	for k in _pad_cloth.size():
		# The cloth dips and swings out after a launch.
		var dip := 0.0
		if _pad_kick[k] >= 0.0:
			_pad_kick[k] += dt
			var u := _pad_kick[k] / PAD_KICK_TIME
			if u >= 1.0:
				_pad_kick[k] = -1.0
			else:
				dip = sin(u * TAU * 2.0) * (1.0 - u) * 0.16
		_pad_cloth[k].position.y = 0.27 + dip
		# Somebody is on the way to this landing spot: it fills and the ring closes in.
		var land: Vector2 = MapDef.PADS[k][1]
		var left := -1.0
		for p in sim.players:
			if p.enabled and p.alive and p.air_t > 0.0 and p.air_to.distance_squared_to(land) < 0.01:
				left = p.air_t if left < 0.0 else minf(left, p.air_t)
		_land_fill[k].visible = left >= 0.0
		var sd := MapDef.STOMP_RADIUS * 2.0
		var ring := sd * (1.0 + 0.8 * clampf(left / MapDef.AIR_TIME, 0.0, 1.0)) if left >= 0.0 else sd
		_land_ring[k].scale = Vector3(ring, 0.4, ring)


# ---------------------------------------------------------------- 4 Magnet Lab

func _build_magnets() -> void:
	var root := _group("Magnets")
	var rbox := ToyKit.rounded_box(0.3)
	for k in MapDef.MAGNETS.size():
		var c := MapDef.MAGNETS[k]
		var m := Node3D.new()
		m.name = "Magnet%d" % k
		m.position = _v3(c)
		# The horseshoe lies flat (it is seen from above) and opens towards the middle of the room.
		m.rotation.y = -PI * 0.5 if c.x < Config.ARENA_SIZE.x * 0.5 else PI * 0.5
		root.add_child(m)
		var sh := ToyKit.shadow(2.6)
		sh.position = Vector3(0.2, 0.02, 0.15)
		m.add_child(sh)
		_part(m, rbox, ToyKit.matte(MAGNET_BASE), Vector3(0, 0.3, 0), Vector3(1.6, 0.6, 1.6))
		var body := ToyKit.plastic(MAGNET_IDLE)
		var parts: Array[MeshInstance3D] = []
		for sx: float in [-1.0, 1.0]:
			parts.append(_part(m, rbox, body, Vector3(0.46 * sx, 0.85, -0.12), Vector3(0.44, 0.5, 0.86)))
			_part(m, rbox, ToyKit.plastic(MAGNET_TIP), Vector3(0.46 * sx, 0.85, -0.68), Vector3(0.46, 0.52, 0.3))
		parts.append(_part(m, rbox, body, Vector3(0, 0.85, 0.48), Vector3(1.36, 0.5, 0.44)))
		_magnet_parts.append(parts)
		# The field on the floor: its edge, and rings that run inwards (pull) or outwards (push).
		var d := MapDef.MAGNET_RADIUS * 2.0
		_field_edge.append(_part(root, _thin_ring(), ToyKit.overlay(Color(1, 1, 1, 0.2)), _v3(c, 0.03), Vector3(d, 0.15, d)))
		var rings: Array[MeshInstance3D] = []
		for _i in FIELD_RINGS:
			rings.append(_part(root, _thin_ring(), ToyKit.overlay(Color(1, 1, 1, 0.2)), _v3(c, 0.032), Vector3.ONE))
		_field_rings.append(rings)


func _update_magnets(sim: Sim) -> void:
	var d := MapDef.MAGNET_RADIUS * 2.0
	for k in _magnet_parts.size():
		var s := MapDef.magnet_sign(k, sim.map_t)
		var col := MAGNET_IDLE
		if s > 0.0:
			col = MAGNET_PULL
		elif s < 0.0:
			col = MAGNET_PUSH
		elif int(_time * 8.0) % 2 == 0:
			# Off and about to swap: it flickers in the colour it will have next.
			col = MAGNET_PULL if MapDef.magnet_sign(k, sim.map_t + MapDef.MAGNET_OFF) > 0.0 else MAGNET_PUSH
		var body := ToyKit.plastic(col)
		for mi: MeshInstance3D in _magnet_parts[k]:
			mi.material_override = body
		var edge_col := col
		edge_col.a = 0.35 if s != 0.0 else 0.15
		_field_edge[k].material_override = ToyKit.overlay(edge_col)
		var ring_col := col
		ring_col.a = 0.22
		var ring_mat := ToyKit.overlay(ring_col)
		var rings: Array = _field_rings[k]
		for i in rings.size():
			var ring: MeshInstance3D = rings[i]
			ring.visible = s != 0.0
			if s == 0.0:
				continue
			var u := fposmod(_time * 0.45 + float(i) / rings.size(), 1.0)
			var size := d * lerpf(0.12, 1.0, 1.0 - u if s > 0.0 else u)
			ring.scale = Vector3(size, 0.15, size)
			ring.material_override = ring_mat


# ---------------------------------------------------------------- 5 Piggy Bank

func _build_pig() -> void:
	var c := MapDef.PIG_RECT.get_center()
	var rug := _group("Rug")
	_part(rug, ToyKit.cylinder(), ToyKit.matte(RUG_TRIM), _v3(c, 0.01), Vector3(6.4, 0.02, 6.4))
	_part(rug, ToyKit.cylinder(), ToyKit.matte(RUG), _v3(c, 0.015), Vector3(6.0, 0.02, 6.0))
	_pig = _group("Pig")
	_pig.position = _v3(c)
	var sh := ToyKit.shadow(3.4)
	sh.position = Vector3(0.2, 0.03, 0.15)
	_pig.add_child(sh)
	var pink := ToyKit.plastic(PIG_PINK)
	var dark := ToyKit.plastic(PIG_DARK)
	var eye := ToyKit.plastic(PIG_EYE)
	# Modelled facing +z (towards the bottom of the screen), inside the 2 x 2 m block it is for the game.
	_part(_pig, ToyKit.sphere(), pink, Vector3(0, 0.95, -0.05), Vector3(1.9, 1.55, 2.0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_part(_pig, ToyKit.cylinder(), dark, Vector3(0.5 * sx, 0.2, 0.55 * sz - 0.05), Vector3(0.36, 0.4, 0.36))
		_part(_pig, ToyKit.cone(), dark, Vector3(0.48 * sx, 1.62, 0.5), Vector3(0.42, 0.5, 0.3), Vector3(0.5, 0, -0.35 * sx))
		_part(_pig, ToyKit.sphere(), eye, Vector3(0.3 * sx, 1.32, 0.78), Vector3.ONE * 0.16)
		_part(_pig, ToyKit.sphere(), eye, Vector3(0.11 * sx, 0.95, 1.1), Vector3(0.09, 0.14, 0.06))
	_part(_pig, ToyKit.cylinder(), dark, Vector3(0, 0.95, 0.95), Vector3(0.62, 0.3, 0.5), Vector3(PI * 0.5, 0, 0))
	_part(_pig, ToyKit.torus(), dark, Vector3(0, 1.1, -1.05), Vector3(0.36, 0.6, 0.36), Vector3(PI * 0.5, 0, 0.4))
	_part(_pig, _unit_box(), eye, Vector3(0, 1.72, -0.05), Vector3(0.6, 0.04, 0.12))
	# The coins lie in a row on its back (flat, to be seen from above); the next one grows while it is saved up.
	var gold := ToyKit.plastic(COIN)
	for k in MapDef.PIG_MAX:
		var coin := _part(_pig, ToyKit.cylinder(), gold, Vector3((k - (MapDef.PIG_MAX - 1) * 0.5) * 0.62, 2.0, -0.05), Vector3(0.56, 0.1, 0.56))
		coin.name = "Coin%d" % k
		coin.visible = false
		_coins.append(coin)


func _update_pig(sim: Sim, dt: float) -> void:
	for k in _coins.size():
		var coin := _coins[k]
		var have := k < sim.pig_coins
		var growing := k == sim.pig_coins
		coin.visible = have or (growing and sim.pig_t > 0.0)
		var size := 0.56 if have else 0.56 * clampf(sim.pig_t / MapDef.PIG_FILL, 0.0, 1.0) * 0.8
		coin.scale = Vector3(size, 0.1, size)
		coin.position.y = 2.0 + (sin(_time * 3.0 + k * 1.3) * 0.08 if have else 0.0)
		coin.rotation.z = sin(_time * 2.2 + k) * 0.25 if have else 0.0
	# A hit makes it jump and wobble.
	var squash := 0.0
	if _pig_kick >= 0.0:
		_pig_kick += dt
		var u := _pig_kick / PIG_KICK_TIME
		if u >= 1.0:
			_pig_kick = -1.0
		else:
			squash = sin(u * TAU * 2.0) * (1.0 - u)
	_pig.scale = Vector3(1.0 + squash * 0.12, 1.0 - squash * 0.15, 1.0 + squash * 0.12)
	_pig.rotation.z = squash * 0.08


# ---------------------------------------------------------------- shaders

const MAT_SHADER := """
shader_type spatial;
uniform vec2 size;
uniform vec2 tile = vec2(4.0, 3.6);
uniform vec3 col0 : source_color;
uniform vec3 col1 : source_color;
uniform vec3 col2 : source_color;
uniform vec3 col3 : source_color;

void fragment() {
	vec2 p = UV * size;
	vec2 c = floor(p / tile);
	vec2 f = fract(p / tile) * tile;
	float k = mod(c.x + c.y * 2.0, 4.0);
	vec3 col = k < 0.5 ? col0 : (k < 1.5 ? col1 : (k < 2.5 ? col2 : col3));
	// Foam texture: a faint grid of dimples, and a darker seam between the mats.
	vec2 g = fract(p / 0.4) - 0.5;
	col *= 1.0 - 0.05 * smoothstep(0.12, 0.05, length(g));
	float seam = min(min(f.x, tile.x - f.x), min(f.y, tile.y - f.y));
	col *= mix(0.55, 1.0, smoothstep(0.03, 0.09, seam));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
"""

const WARN_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
uniform float urgency = 0.0;
varying vec2 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float stripe = step(0.5, fract((wp.x + wp.y) * 0.9 - TIME * 0.8));
	float rate = mix(5.0, 16.0, urgency);
	float pulse = 0.5 + 0.5 * sin(TIME * rate);
	vec2 e = min(UV, 1.0 - UV);
	float border = 1.0 - smoothstep(0.0, 0.05, min(e.x, e.y));
	ALBEDO = mix(vec3(1.0, 0.78, 0.15), vec3(1.0, 0.38, 0.08), stripe);
	ALPHA = clamp(mix(0.3, 0.55 + 0.25 * urgency, pulse) * mix(0.75, 1.0, stripe) + border * 0.5, 0.0, 0.95);
}
"""

const HOT_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
varying vec2 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float n = sin(wp.x * 2.3 + TIME * 1.7) * sin(wp.y * 2.9 - TIME * 1.3);
	n += 0.5 * sin(wp.x * 5.1 - TIME * 2.1 + sin(wp.y * 3.3 + TIME));
	n += 0.25 * sin((wp.x + wp.y) * 9.0 + TIME * 3.0);
	n = n / 1.75 * 0.5 + 0.5;
	vec3 col = mix(vec3(0.75, 0.08, 0.02), vec3(1.0, 0.45, 0.05), smoothstep(0.25, 0.6, n));
	col = mix(col, vec3(1.0, 0.92, 0.4), smoothstep(0.7, 0.95, n));
	vec2 e = min(UV, 1.0 - UV);
	float border = 1.0 - smoothstep(0.0, 0.06, min(e.x, e.y));
	ALBEDO = mix(col, vec3(1.0, 0.95, 0.55), border);
	ALPHA = 0.93;
}
"""
