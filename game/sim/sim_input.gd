class_name SimInput
extends RefCounted
## Per-player input for one tick. Produced by touch / gamepad / keyboard / bots.

var move := Vector2.ZERO      # left stick, length <= 1
var aim := Vector2.ZERO       # right stick, length <= 1
var aim_held := false         # right stick held (touched / deflected)
var dash := false
