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
# string path: the points the head flew through (bends of a steered flight and bounce points) in order from the
# player outwards; the last one is next to the head
var pins := PackedVector2Array()
var pin_acc := 0.0            # distance flown since the last pin
var turning := false        # Lenkwurf: the direction changed in the last step (a pin was laid when it began)
# Kreuzfeuer (Zwilling II): fly to the meeting point first, then return
var meet_on := false
var meet := Vector2.ZERO


func lethal() -> bool:
	return state != S.HAND
