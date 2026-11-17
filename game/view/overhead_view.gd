class_name OverheadView
extends CanvasLayer
## Markers above the figures' heads, drawn on the screen at the world point above each head (view only, reads the
## sim). Three kinds, bottom to top: the zone countdown (a big red number for a player outside the shrinking zone),
## the "YOU" tag with an arrow at the local player's figure, and the row of modifier icons the player bought. The
## decisions (what to show, how strong) are static functions so they can be tested without a screen. Owner
## decision 2026-11-17: an exception to "no UI during a round", like the countdown.

const ICONS_SHOW_PLAY := 1.5        # seconds of PLAY the icons stay (fading out)
const YOU_SHOW_PLAY := 2.0          # seconds of PLAY the YOU tag stays; it fades during the last YOU_FADE
const YOU_FADE := 0.5
const HEAD_RADII := 2.9             # world point above the floor, in player radii (the figures are 2..2.8 radii tall)
const ICON_PX := 26.0
const ZONE_COLOR := Color("ff2a1f")

var _boxes: Array[Control] = []
var _zone: Array[Label] = []
var _you: Array[Control] = []
var _you_label: Array[Label] = []
var _arrow: Array[Control] = []
var _icon_row: Array[Control] = []
var _icons: Array = []              # per player: Array[ModIcon]
var _counts: Array = []             # per player: Array[Label]


## Modifiers shown above player `i`: [[id, level], ...] in the build's key order. Empty in free play, for a slot
## that does not play, or once the round has run for ICONS_SHOW_PLAY seconds.
static func icons_for(sim: Sim, i: int) -> Array:
	var out: Array = []
	if icon_alpha(sim) <= 0.0 or i < 0 or i >= sim.players.size() or not sim.players[i].enabled:
		return out
	var lv := sim.mode.levels_of(i)
	for id: String in sim.mode.owned[i]:
		out.append([id, lv.get(id, 1)])
	return out


## How visible the icons are: full during the countdown, fading to nothing over the first seconds of PLAY.
static func icon_alpha(sim: Sim) -> float:
	var m := sim.mode
	if m.phase == MatchMode.Phase.COUNTDOWN:
		return 1.0
	if m.phase == MatchMode.Phase.PLAY:
		return clampf(1.0 - m.phase_t / ICONS_SHOW_PLAY, 0.0, 1.0)
	return 0.0


## How visible the YOU tag of player `i` is: only for the local slot, in a match, early in the round.
static func you_alpha(sim: Sim, i: int, local_slot: int) -> float:
	if i != local_slot or i < 0 or i >= sim.players.size() or not sim.players[i].enabled:
		return 0.0
	var m := sim.mode
	if m.phase == MatchMode.Phase.COUNTDOWN:
		return 1.0
	if m.phase == MatchMode.Phase.PLAY:
		return clampf((YOU_SHOW_PLAY - m.phase_t) / YOU_FADE, 0.0, 1.0)
	return 0.0


## The zone countdown above player `i` (3, 2, 1), or 0 for none: only outside the zone while the timer runs.
static func zone_number(sim: Sim, i: int) -> int:
	if i < 0 or i >= sim.players.size() or not sim.zone_active():
		return 0
	var p := sim.players[i]
	if not p.enabled or not p.alive or p.zone_t <= 0.0:
		return 0
	return maxi(ceili(MatchMode.ZONE_DEATH_TIME - p.zone_t), 0)


## 0..1, 1 right after the number changed, fading within a quarter second (drives a short pulse).
static func zone_pulse(sim: Sim, i: int) -> float:
	if zone_number(sim, i) <= 0:
		return 0.0
	var r: float = MatchMode.ZONE_DEATH_TIME - sim.players[i].zone_t
	return clampf(1.0 - (ceilf(r) - r) / 0.25, 0.0, 1.0)


func build(player_count: int) -> void:
	layer = 2
	for _i in player_count:
		var box := Control.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.visible = false
		add_child(box)
		_boxes.append(box)
		var zl := _label(46, ZONE_COLOR)
		zl.visible = false
		box.add_child(zl)
		_zone.append(zl)
		var you := Control.new()
		you.mouse_filter = Control.MOUSE_FILTER_IGNORE
		you.visible = false
		box.add_child(you)
		_you.append(you)
		var yl := _label(22, Color.WHITE)
		you.add_child(yl)
		_you_label.append(yl)
		var arrow := _Arrow.new()
		you.add_child(arrow)
		_arrow.append(arrow)
		var row := Control.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		_icon_row.append(row)
		var icons: Array[ModIcon] = []
		var counts: Array[Label] = []
		for _k in Economy.SLOTS:
			var ic := ModIcon.new("", ICON_PX)
			ic.visible = false
			row.add_child(ic)
			icons.append(ic)
			var cl := _label(13, Color.WHITE)
			cl.visible = false
			row.add_child(cl)
			counts.append(cl)
		_icons.append(icons)
		_counts.append(counts)


func _label(px: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiKit.font(true, 800))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.2, 0.95))
	l.add_theme_constant_override("outline_size", maxi(px / 5, 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Places and fills the markers of player `i`. `src` is the sim the figure is drawn from (own zone timer), `sim`
## the one the match state is read from; `world` is the point above the head.
func show_player(i: int, camera: Camera3D, world: Vector3, src: Sim, sim: Sim, local_slot: int, colour: Color) -> void:
	var box := _boxes[i]
	var zn := zone_number(src, i)
	var ya := you_alpha(sim, i, local_slot)
	var ic := icons_for(sim, i)
	var ia := icon_alpha(sim)
	if camera == null or camera.is_position_behind(world) or (zn <= 0 and ya <= 0.0 and ic.is_empty()):
		box.visible = false
		return
	box.visible = true
	box.position = camera.unproject_position(world)
	var y := -6.0                     # stacking upwards from the head
	# Zone number.
	var zl := _zone[i]
	zl.visible = zn > 0
	if zn > 0:
		zl.text = str(zn)
		var pulse := zone_pulse(src, i)
		zl.pivot_offset = zl.size * 0.5
		zl.scale = Vector2.ONE * (1.0 + 0.4 * pulse)
		zl.position = Vector2(-zl.size.x * 0.5, y - zl.size.y)
		y -= zl.size.y
	# YOU tag with the arrow pointing down at the figure.
	_you[i].visible = ya > 0.0
	if ya > 0.0:
		_you[i].modulate.a = ya
		var yl := _you_label[i]
		yl.text = "YOU"
		yl.add_theme_color_override("font_color", colour)
		var arrow := _arrow[i] as _Arrow
		arrow.colour = colour
		arrow.size = Vector2(22, 14)
		arrow.position = Vector2(-11, y - 14)
		arrow.queue_redraw()
		y -= 14
		yl.position = Vector2(-yl.size.x * 0.5, y - yl.size.y + 4)
		y -= yl.size.y - 4
	# Icon row, centred.
	var shown := ic.size() if ia > 0.0 else 0
	_icon_row[i].modulate.a = ia
	var w := shown * (ICON_PX + 4.0) - 4.0
	for k in Economy.SLOTS:
		var icon: ModIcon = _icons[i][k]
		var cl: Label = _counts[i][k]
		icon.visible = k < shown
		cl.visible = false
		if k < shown:
			icon.id = ic[k][0]
			icon.position = Vector2(-w * 0.5 + k * (ICON_PX + 4.0), y - ICON_PX - 2.0)
			var lvl: int = ic[k][1]
			if lvl > 1:
				cl.visible = true
				cl.text = "x%d" % lvl
				cl.position = icon.position + Vector2(ICON_PX - 10.0, ICON_PX - 12.0)


## A small downward-pointing triangle in the player's colour.
class _Arrow extends Control:
	var colour := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x * 0.5, size.y)])
		draw_colored_polygon(pts, colour)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.1, 0.07, 0.2, 0.95), 2.0, true)
