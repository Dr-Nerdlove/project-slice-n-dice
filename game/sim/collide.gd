class_name Collide
extends RefCounted
## Pure geometry helpers for the simulation (circles vs axis-aligned boxes).


## Returns the correction vector that moves a circle out of a box (zero if no overlap).
static func push_out_rect(p: Vector2, r: float, rect: Rect2) -> Vector2:
	var closest := Vector2(
		clampf(p.x, rect.position.x, rect.end.x),
		clampf(p.y, rect.position.y, rect.end.y))
	var d := p - closest
	var d2 := d.length_squared()
	if d2 > 0.0:
		if d2 >= r * r:
			return Vector2.ZERO
		var dl := sqrt(d2)
		return d / dl * (r - dl)
	# Circle centre is inside (or exactly on the border of) the box: leave through the nearest side.
	var left := p.x - rect.position.x
	var right := rect.end.x - p.x
	var top := p.y - rect.position.y
	var bottom := rect.end.y - p.y
	var m := minf(minf(left, right), minf(top, bottom))
	if m == left:
		return Vector2(-(left + r), 0.0)
	if m == right:
		return Vector2(right + r, 0.0)
	if m == top:
		return Vector2(0.0, -(top + r))
	return Vector2(0.0, bottom + r)


## Returns the translation that moves box `a` out of box `b` (zero if they do not overlap).
static func push_out_rect_rect(a: Rect2, b: Rect2) -> Vector2:
	if not a.intersects(b):
		return Vector2.ZERO
	var to_left := a.end.x - b.position.x
	var to_right := b.end.x - a.position.x
	var to_up := a.end.y - b.position.y
	var to_down := b.end.y - a.position.y
	var m := minf(minf(to_left, to_right), minf(to_up, to_down))
	if m == to_left:
		return Vector2(-to_left, 0.0)
	if m == to_right:
		return Vector2(to_right, 0.0)
	if m == to_up:
		return Vector2(0.0, -to_up)
	return Vector2(0.0, to_down)
