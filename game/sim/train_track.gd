class_name TrainTrack
extends RefCounted
## The loop of the toy train: pure geometry, shared by the simulation (where the train is) and the view (where the
## rails lie). A rounded rectangle around the middle of the arena, run clockwise as seen on screen. Metres.

const CENTER := Vector2(16.0, 7.2)
const HALF := Vector2(5.5, 3.6)
const CORNER := 1.7
const CARS := 3                  # locomotive first
const CAR_GAP := 1.3             # distance between the centres of two cars along the track
const CAR_RADIUS := 0.55         # each car is a circle for the game
const STRAIGHT_X := 2.0 * (HALF.x - CORNER)
const STRAIGHT_Y := 2.0 * (HALF.y - CORNER)
const ARC := PI * CORNER * 0.5
const LENGTH := 2.0 * STRAIGHT_X + 2.0 * STRAIGHT_Y + 4.0 * ARC


## The point of the track `s` metres along the loop (any number; the loop repeats).
static func point(s: float) -> Vector2:
	var t := fposmod(s, LENGTH)
	var in_x := HALF.x - CORNER
	var in_y := HALF.y - CORNER
	if t < STRAIGHT_X:
		return CENTER + Vector2(-in_x + t, -HALF.y)
	t -= STRAIGHT_X
	if t < ARC:
		return CENTER + Vector2(in_x, -in_y) + Vector2.from_angle(-PI * 0.5 + t / CORNER) * CORNER
	t -= ARC
	if t < STRAIGHT_Y:
		return CENTER + Vector2(HALF.x, -in_y + t)
	t -= STRAIGHT_Y
	if t < ARC:
		return CENTER + Vector2(in_x, in_y) + Vector2.from_angle(t / CORNER) * CORNER
	t -= ARC
	if t < STRAIGHT_X:
		return CENTER + Vector2(in_x - t, HALF.y)
	t -= STRAIGHT_X
	if t < ARC:
		return CENTER + Vector2(-in_x, in_y) + Vector2.from_angle(PI * 0.5 + t / CORNER) * CORNER
	t -= ARC
	if t < STRAIGHT_Y:
		return CENTER + Vector2(-HALF.x, in_y - t)
	t -= STRAIGHT_Y
	return CENTER + Vector2(-in_x, -in_y) + Vector2.from_angle(PI + t / CORNER) * CORNER


## Direction of travel at `s`.
static func dir(s: float) -> Vector2:
	return (point(s + 0.05) - point(s - 0.05)).normalized()


## Where car `k` (0 = locomotive) is when the locomotive is at `s`.
static func car_s(s: float, k: int) -> float:
	return s - CAR_GAP * k
