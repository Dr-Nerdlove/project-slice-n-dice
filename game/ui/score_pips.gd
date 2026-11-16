class_name ScorePips
extends Control
## One player's score as a row of pips: `target` empty circles, one filled per point in the player's colour, drawn in
## groups of five with a wider gap between groups so it can be counted at a glance. `start_pop` makes the newest
## pip grow in. The layout maths are static so tests can check them without drawing.

const D := 14.0           # pip diameter
const GAP := 4.0          # gap between pips of a group
const GROUP := 5          # pips per group
const GROUP_GAP := 11.0   # gap between groups
const POP_TIME := 0.5

var target := 10
var points := 0
var color := Color.WHITE
var pop_index := -1       # the pip that grows in, -1 = none
var pop := 1.0            # 0..1 progress of that growth


## How many pips are filled for `points` points of `target`.
static func filled_count(p: int, tgt: int) -> int:
	return clampi(p, 0, maxi(tgt, 0))


## Left edge of pip `i`.
static func pip_x(i: int) -> float:
	return i * (D + GAP) + (i / GROUP) * (GROUP_GAP - GAP)


## Width of a row of `n` pips.
static func total_width(n: int) -> float:
	return 0.0 if n <= 0 else pip_x(n - 1) + D


func setup(tgt: int, p: int, col: Color) -> void:
	target = tgt
	points = p
	color = col
	custom_minimum_size = Vector2(total_width(tgt), D + 6.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## Lets the newest filled pip grow in (a short pulse).
func start_pop() -> void:
	pop_index = filled_count(points, target) - 1
	if pop_index < 0:
		return
	pop = 0.0
	var tw := create_tween()
	tw.tween_method(_set_pop, 0.0, 1.0, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_pop(v: float) -> void:
	pop = v
	queue_redraw()


func _draw() -> void:
	var filled := filled_count(points, target)
	var cy := size.y * 0.5
	for i in target:
		var c := Vector2(pip_x(i) + D * 0.5, cy)
		if i >= filled:
			draw_arc(c, D * 0.5 - 1.0, 0.0, TAU, 20, Color(UiKit.MUTE, 0.6), 2.0, true)
			continue
		var r := D * 0.5
		if i == pop_index and pop < 1.0:
			r *= 1.0 + 0.9 * (1.0 - pop)
			draw_arc(c, r + 3.0, 0.0, TAU, 24, Color(UiKit.TOMATO, 1.0 - pop), 3.0, true)
		draw_circle(c, r, color)
		draw_arc(c, r - 0.5, 0.0, TAU, 20, Color(UiKit.INK, 0.35), 1.5, true)
