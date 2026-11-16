class_name ModIcon
extends Control
## A small drawn symbol for one modifier (a coloured round badge with a white pictogram), used by the shop. View only.
## Coordinates of the symbols are in a unit square (0..1) and scaled to the control's size.

const COLORS := {
	"tripwire": Color("e0642b"), "bighead": Color("2f8f5b"), "elastic": Color("d2467a"), "extradash": Color("2b7de0"),
	"bounce": Color("8a52d6"), "steer": Color("1f9fb0"), "pierce": Color("5a6378"), "shards": Color("c98a12"),
	"warhead": Color("d6342c"), "twin": Color("3f6ad6"),
}

var id := "":
	set(v):
		id = v
		queue_redraw()


func _init(mod_id := "", px := 44.0) -> void:
	id = mod_id
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _p(x: float, y: float) -> Vector2:
	return Vector2(x, y) * size


func _line(pts: Array, w: float) -> void:
	var out := PackedVector2Array()
	for q: Vector2 in pts:
		out.append(_p(q.x, q.y))
	draw_polyline(out, Color.WHITE, w, true)


func _draw() -> void:
	if not COLORS.has(id):
		return
	var c := size / 2.0
	draw_circle(c, size.x / 2.0, COLORS[id])
	var w := maxf(size.x * 0.07, 2.0)
	match id:
		"tripwire":
			_line([Vector2(0.22, 0.7), Vector2(0.22, 0.4)], w)
			_line([Vector2(0.78, 0.7), Vector2(0.78, 0.4)], w)
			_line([Vector2(0.22, 0.55), Vector2(0.78, 0.55)], w * 0.6)
		"bighead":
			draw_circle(_p(0.5, 0.5), size.x * 0.27, Color.WHITE)
			draw_circle(_p(0.5, 0.5), size.x * 0.13, COLORS[id])
		"elastic":
			_line([Vector2(0.18, 0.5), Vector2(0.3, 0.3), Vector2(0.42, 0.7), Vector2(0.54, 0.3), Vector2(0.66, 0.7), Vector2(0.82, 0.5)], w)
		"extradash":
			_line([Vector2(0.24, 0.3), Vector2(0.46, 0.5), Vector2(0.24, 0.7)], w)
			_line([Vector2(0.5, 0.3), Vector2(0.72, 0.5), Vector2(0.5, 0.7)], w)
		"bounce":
			_line([Vector2(0.2, 0.28), Vector2(0.4, 0.74), Vector2(0.6, 0.28), Vector2(0.8, 0.74)], w)
		"steer":
			_line([Vector2(0.22, 0.72), Vector2(0.3, 0.45), Vector2(0.5, 0.3), Vector2(0.76, 0.3)], w)
			_line([Vector2(0.64, 0.2), Vector2(0.78, 0.3), Vector2(0.64, 0.42)], w)
		"pierce":
			_line([Vector2(0.5, 0.2), Vector2(0.5, 0.8)], w * 1.4)
			_line([Vector2(0.15, 0.5), Vector2(0.85, 0.5)], w)
			_line([Vector2(0.7, 0.36), Vector2(0.85, 0.5), Vector2(0.7, 0.64)], w)
		"shards":
			draw_colored_polygon(PackedVector2Array([_p(0.2, 0.7), _p(0.4, 0.25), _p(0.5, 0.7)]), Color.WHITE)
			draw_colored_polygon(PackedVector2Array([_p(0.55, 0.75), _p(0.7, 0.3), _p(0.82, 0.72)]), Color.WHITE)
		"warhead":
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * size.x * 0.12, c + d * size.x * (0.32 if k % 2 == 0 else 0.24), Color.WHITE, w)
		"twin":
			draw_circle(_p(0.35, 0.5), size.x * 0.17, Color.WHITE)
			draw_circle(_p(0.65, 0.5), size.x * 0.17, Color.WHITE)
