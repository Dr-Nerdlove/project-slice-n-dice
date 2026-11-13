class_name SimInput
extends RefCounted
## Per-player input for one tick. Produced by touch / gamepad / keyboard / bots.

var move := Vector2.ZERO      # left stick, length <= 1
var aim := Vector2.ZERO       # right stick, length <= 1
var aim_held := false         # right stick held (touched / deflected)
var dash := false


## The input to assume for a tick whose real input is not known (extrapolating or repeating the last one):
## the sticks stay as they were, but the dash is an edge event that must never be repeated.
func repeated() -> SimInput:
	var r := SimInput.new()
	r.move = move
	r.aim = aim
	r.aim_held = aim_held
	r.dash = false
	return r
