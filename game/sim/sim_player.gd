class_name SimPlayer
extends RefCounted
## Plain-data state of one player and its yo-yo.

enum Yo { READY, CHARGING, FLIGHT, OUT, RETRACT, PULL }

var id := 0
var enabled := true
var alive := true
var respawn_t := 0.0
var kills := 0
var deaths := 0

var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var facing := Vector2.RIGHT
var dash_t := 0.0
var dash_cd := 0.0          # seconds until the next dash charge is back
var dash_charges := 1       # dashes available right now
var dash_dir := Vector2.RIGHT

var ystate: int = Yo.READY
var head := Vector2.ZERO
var prev_head := Vector2.ZERO
var charge_t := 0.0
var aim_dir := Vector2.RIGHT
var aimed := false
var throw_dir := Vector2.RIGHT
var flight_dist := 0.0
var flown := 0.0
var held_prev := false
var press_active := false
var press_t := 0.0
var tap_buffered := false   # a short tap happened during FLIGHT: retract as soon as the head lands


func head_is_lethal() -> bool:
	return ystate == Yo.FLIGHT or ystate == Yo.OUT or ystate == Yo.RETRACT or ystate == Yo.PULL
