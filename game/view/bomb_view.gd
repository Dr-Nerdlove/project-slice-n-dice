class_name BombView
extends Node3D
## The Hot Potato bomb over the carrier's head (view only, reads the sim; no numbers on screen, the owner chose fuse
## and blinking). One toy bomb per player slot, built once and shown only over the slot that carries the bomb in
## the sim THAT figure is drawn from, so the bomb always sits on the figure it belongs to. The fuse is a short
## stick that shrinks with `bomb_t / bomb_fuse`, a spark sits at its tip; in the last `HotPotato.BLINK_TIME` seconds the
## body blinks red, faster towards 0. The decisions are static functions so they can be tested without a screen.
## Sizes are in player radii (the node is scaled by the radius).

const BODY_COLOR := Color("1d1d24")
const RED := Color("e0231a")
const CAP_COLOR := Color("8a8a96")
const FUSE_COLOR := Color("d8c9a0")
const SPARK_COLOR := Color("ffb02e")
const BODY_R := 0.55            # bomb ball radius
const CENTRE_Y := 3.35          # height of its centre above the floor
const FUSE_MAX := 0.9           # fuse stick length at a full fuse
const FUSE_MIN := 0.04          # what is left when the fuse is nearly out
## Top of the bomb (cap, full fuse and spark) above the floor, in player radii: the overhead markers stack above it.
const TOP_RADII := CENTRE_Y + BODY_R * 0.95 + 0.08 + FUSE_MAX + 0.15
const BLINK_START_HZ := 2.0
const BLINK_END_HZ := 10.0

var _nodes: Array[Node3D] = []
var _bodies: Array[MeshInstance3D] = []
var _fuses: Array[MeshInstance3D] = []
var _sparks: Array[MeshInstance3D] = []


## Slot that carries the bomb in `sim`, -1 for none: only in a Hot Potato round, only a living, enabled player.
static func holder(sim: Sim) -> int:
	if not (sim.mode is HotPotato) or sim.mode.phase != MatchMode.Phase.PLAY:
		return -1
	var h: int = sim.mode.bomb_holder
	if h < 0 or h >= sim.players.size() or not (sim.players[h].enabled and sim.players[h].alive):
		return -1
	return h


## How much of the fuse is left, 0..1.
static func fuse_fraction(sim: Sim) -> float:
	if not (sim.mode is HotPotato) or sim.mode.bomb_fuse <= 0.0:
		return 0.0
	return clampf(sim.mode.bomb_t / sim.mode.bomb_fuse, 0.0, 1.0)


## Length of the fuse stick for a fraction left.
static func fuse_length(fraction: float) -> float:
	return lerpf(FUSE_MIN, FUSE_MAX, clampf(fraction, 0.0, 1.0))


## Is the bomb red right now? Never above BLINK_TIME seconds of fuse; below, the blink speeds up from
## BLINK_START_HZ to BLINK_END_HZ as the fuse runs out (a function of `bomb_t` alone, so the pace is smooth).
static func blink_red(bomb_t: float) -> bool:
	if bomb_t > HotPotato.BLINK_TIME or bomb_t < 0.0:
		return false
	var e := HotPotato.BLINK_TIME - bomb_t     # seconds into the blinking
	var rate := (BLINK_END_HZ - BLINK_START_HZ) / HotPotato.BLINK_TIME
	var cycles := BLINK_START_HZ * e + 0.5 * rate * e * e
	return fposmod(cycles, 1.0) < 0.5


func build(player_count: int) -> void:
	for _i in player_count:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		_nodes.append(root)
		var body := ToyKit.part(root, ToyKit.sphere(), ToyKit.plastic(BODY_COLOR), Vector3.ZERO, Vector3.ONE * BODY_R * 2.0)
		body.name = "BombBody"
		_bodies.append(body)
		ToyKit.part(root, ToyKit.cylinder(), ToyKit.plastic(CAP_COLOR), Vector3(0, BODY_R * 0.95, 0), Vector3(0.3, 0.16, 0.3))
		var fuse := ToyKit.part(root, ToyKit.cylinder(), ToyKit.matte(FUSE_COLOR), Vector3.ZERO, Vector3(0.07, FUSE_MAX, 0.07))
		fuse.name = "BombFuse"
		_fuses.append(fuse)
		var spark := ToyKit.part(root, ToyKit.sphere(), ToyKit.unshaded(SPARK_COLOR), Vector3.ZERO, Vector3.ONE * 0.2)
		spark.name = "BombSpark"
		_sparks.append(spark)


## Shows or hides the bomb of slot `i`. `src` is the sim the figure of slot `i` is drawn from, `pos` the figure's
## ground position, `lift` its height above the floor (a trampoline flight), `radius` the player radius, `time` the
## view clock (the spark flickers).
func show_player(i: int, src: Sim, pos: Vector2, lift: float, radius: float, time: float) -> void:
	var on := holder(src) == i
	var root := _nodes[i]
	root.visible = on
	if not on:
		return
	var m: HotPotato = src.mode
	root.position = Vector3(pos.x, CENTRE_Y * radius + lift, pos.y)
	root.scale = Vector3.ONE * radius
	_bodies[i].material_override = ToyKit.plastic(RED if blink_red(m.bomb_t) else BODY_COLOR)
	var flen := fuse_length(fuse_fraction(src))
	var top := BODY_R * 0.95 + 0.08
	_fuses[i].scale = Vector3(0.07, flen, 0.07)
	_fuses[i].position = Vector3(0, top + flen * 0.5, 0)
	_sparks[i].position = Vector3(0, top + flen + 0.05, 0)
	_sparks[i].scale = Vector3.ONE * (0.2 + 0.06 * sin(time * 38.0))
