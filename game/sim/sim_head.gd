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
# string path: bounce points (pins) in order from the player outwards; the last one is next to the head
var pins := PackedVector2Array()
# arced throw (Bogenwurf): the flight follows a curve to throw_target
var throw_curved := false
var throw_origin := Vector2.ZERO
var throw_target := Vector2.ZERO
var throw_side := 1.0
var throw_bulge := 0.0
var throw_len := 1.0
# Kreuzfeuer (Zwilling II): fly to the meeting point first, then return
var meet_on := false
var meet := Vector2.ZERO


func lethal() -> bool:
	return state != S.HAND
