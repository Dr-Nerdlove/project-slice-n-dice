class_name ZoneView
extends Node3D
## The shrinking zone of a match on the floor (view only, reads the sim): a darker veil over everything outside
## the zone, a bright line along its edge, and a ring under every player outside that fills over the time they
## have left. Nothing is drawn in free play (phase OFF) or while the zone still covers the whole arena. All
## nodes and materials are made once; each frame only moves and scales them.

const VEIL_COLOR := Color(0.05, 0.02, 0.1, 0.5)
const EDGE_COLOR := Color(1.0, 0.95, 0.45, 0.95)
const RING_BASE_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const RING_FILL_COLOR := Color(1.0, 0.2, 0.15, 0.8)
const EDGE_WIDTH := 0.14
const VEIL_Y := 0.03
const EDGE_Y := 0.045
const RING_Y := 0.06
const RING_RADII := 1.5              # ring radius in player radii

var _veil: Array[MeshInstance3D] = []     # top, bottom, left, right strips
var _edge: Array[MeshInstance3D] = []
var _ring_base: Array[MeshInstance3D] = []
var _ring_fill: Array[MeshInstance3D] = []


func build(player_count: int) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for _k in 4:
		_veil.append(_strip(box, ToyKit.overlay(VEIL_COLOR)))
		_edge.append(_strip(box, ToyKit.overlay(EDGE_COLOR)))
	for _i in player_count:
		_ring_base.append(_disc(ToyKit.overlay(RING_BASE_COLOR)))
		_ring_fill.append(_disc(ToyKit.overlay(RING_FILL_COLOR)))


func _strip(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _disc(mat: Material) -> MeshInstance3D:
	var mi := _strip(ToyKit.cylinder(), mat)
	return mi


## Veil and edge line. `sim` is the sim the zone is drawn from.
func show_zone(sim: Sim) -> void:
	var z := sim.zone_rect()
	var a := Config.ARENA_SIZE
	var shrunk := sim.zone_active() and z != Rect2(Vector2.ZERO, a)
	for mi in _veil:
		mi.visible = shrunk
	for mi in _edge:
		mi.visible = shrunk
	if not shrunk:
		return
	_place(_veil[0], Rect2(0.0, 0.0, a.x, z.position.y), VEIL_Y, 0.02)
	_place(_veil[1], Rect2(0.0, z.end.y, a.x, a.y - z.end.y), VEIL_Y, 0.02)
	_place(_veil[2], Rect2(0.0, z.position.y, z.position.x, z.size.y), VEIL_Y, 0.02)
	_place(_veil[3], Rect2(z.end.x, z.position.y, a.x - z.end.x, z.size.y), VEIL_Y, 0.02)
	var w := EDGE_WIDTH
	_place(_edge[0], Rect2(z.position.x - w * 0.5, z.position.y - w * 0.5, z.size.x + w, w), EDGE_Y, 0.02)
	_place(_edge[1], Rect2(z.position.x - w * 0.5, z.end.y - w * 0.5, z.size.x + w, w), EDGE_Y, 0.02)
	_place(_edge[2], Rect2(z.position.x - w * 0.5, z.position.y - w * 0.5, w, z.size.y + w), EDGE_Y, 0.02)
	_place(_edge[3], Rect2(z.end.x - w * 0.5, z.position.y - w * 0.5, w, z.size.y + w), EDGE_Y, 0.02)


func _place(mi: MeshInstance3D, r: Rect2, y: float, thickness: float) -> void:
	var empty := r.size.x <= 0.001 or r.size.y <= 0.001
	if empty:
		mi.visible = false
		return
	mi.position = Vector3(r.position.x + r.size.x * 0.5, y, r.position.y + r.size.y * 0.5)
	mi.scale = Vector3(r.size.x, thickness, r.size.y)


## The ring under player `i` at `pos`: shown while the player's timer `t` is above zero, the red fill grows with it.
func show_ring(i: int, pos: Vector2, t: float, player_radius: float, shown: bool) -> void:
	var on := shown and t > 0.0
	_ring_base[i].visible = on
	_ring_fill[i].visible = on
	if not on:
		return
	var r := player_radius * RING_RADII * 2.0   # the unit cylinder has diameter 1
	var f := clampf(t / MatchMode.ZONE_DEATH_TIME, 0.0, 1.0)
	_ring_base[i].position = Vector3(pos.x, RING_Y, pos.y)
	_ring_base[i].scale = Vector3(r, 0.02, r)
	_ring_fill[i].position = Vector3(pos.x, RING_Y + 0.01, pos.y)
	_ring_fill[i].scale = Vector3(r * f, 0.02, r * f)
