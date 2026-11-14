class_name SimPlayer
extends RefCounted
## Plain-data state of one player and its yo-yo heads.

## Computed properties (below) are not state.
const STATE_SKIP := ["head", "prev_head", "ystate"]

## Derived summary of the yo-yo state (used by the view and the single-head helpers `ystate` / `head`).
enum Yo { READY, CHARGING, FLIGHT, OUT, RETRACT, PULL }

var id := 0
var skin := 0               # which figure is shown (CharacterRig.Kind); presentation only
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
var last_move := Vector2.ZERO

var mods := {}              # modifier id -> level 0..3
var stun_t := 0.0           # > 0: cannot move, dash or use the yo-yo
var fling_left := 0.0       # Gummiband: distance still to be flung
var fling_dir := Vector2.RIGHT
var fling_speed := 0.0

var heads: Array[SimHead] = []
var charging := false
var pulling := false
var pull_target := 0
var charge_t := 0.0
var aim_dir := Vector2.RIGHT
var aimed := false
var held_prev := false
var press_active := false
var press_t := 0.0


func _init() -> void:
	heads.append(SimHead.new())


func hand_index() -> int:
	for i in heads.size():
		if heads[i].state == SimHead.S.HAND:
			return i
	return -1


func count_state(s: int) -> int:
	var n := 0
	for h in heads:
		if h.state == s:
			n += 1
	return n


## True while at least one head is not in the hand.
func any_out() -> bool:
	for h in heads:
		if h.state != SimHead.S.HAND:
			return true
	return false


func head_is_lethal() -> bool:
	return any_out()


func body_is_moving_weapon() -> bool:
	return pulling or fling_left > 0.0


# --- single-head view of the state (head 0): keeps simple code and the old checks short ---

var head: Vector2:
	get:
		return heads[0].pos
	set(v):
		heads[0].pos = v

var prev_head: Vector2:
	get:
		return heads[0].prev_pos
	set(v):
		heads[0].prev_pos = v

var ystate: int:
	get:
		if charging:
			return Yo.CHARGING
		if pulling:
			return Yo.PULL
		match heads[0].state:
			SimHead.S.FLIGHT:
				return Yo.FLIGHT
			SimHead.S.OUT:
				return Yo.OUT
			SimHead.S.RETRACT:
				return Yo.RETRACT
		return Yo.READY
	set(v):
		charging = (v == Yo.CHARGING)
		pulling = (v == Yo.PULL)
		pull_target = 0
		match v:
			Yo.FLIGHT:
				heads[0].state = SimHead.S.FLIGHT
			Yo.OUT, Yo.PULL:
				heads[0].state = SimHead.S.OUT
			Yo.RETRACT:
				heads[0].state = SimHead.S.RETRACT
			_:
				heads[0].state = SimHead.S.HAND
