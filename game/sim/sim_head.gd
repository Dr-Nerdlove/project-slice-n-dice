class_name SimHead
extends RefCounted
## Plain-data state of one yo-yo head.

enum S { HAND, FLIGHT, OUT, RETRACT }

var state: int = S.HAND
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var throw_dir := Vector2.RIGHT
var flight_dist := 0.0
var flown := 0.0
var bounces := 0
var speed_mult := 1.0
var limit := 1e9              # string limit while OUT (ratchets down to the normal length)
var queued_retract := false   # a tap happened during FLIGHT: retract as soon as it lands
# retract along an arc (Bogenwurf)
var arc_on := false
var arc_start := Vector2.ZERO
var arc_t := 0.0
var arc_len := 1.0
var arc_bulge := 0.0
var arc_side := 1.0           # +1 left, -1 right of the travel direction
var circ_left := 0.0          # radians of the opening circle still to sweep
var circ_angle := 0.0
var circ_r := 0.0


func lethal() -> bool:
	return state != S.HAND
