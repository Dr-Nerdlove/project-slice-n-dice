class_name UiKit
extends RefCounted
## The building blocks of the menus, in the style of docs/ui-mockup.html: flat solid panels over a dimmed and
## blurred arena, one tomato-red accent, yellow price tags, big titles with an offset print shadow. Fonts:
## Unbounded (titles, numbers) and Rubik (everything else), both under the SIL Open Font License (ui/fonts/).
## Static helpers only. The shared `Theme` is built once; a menu screen sets `root.theme = UiKit.theme()`.
## Button kinds: "main" (tomato, the one primary action), "paper", "dark" (ink), "quiet" (translucent, no edge).

const INK := Color("141a2e")
const PAPER := Color("f7f5f0")
const LINE := Color("dcd8cf")
const MUTE := Color("6b7185")
const TOMATO := Color("ff5233")
const TOMATO_EDGE := Color("b8341c")
const SUN := Color("ffc23d")

const FONT_DISPLAY := "res://ui/fonts/Unbounded.ttf"
const FONT_TEXT := "res://ui/fonts/Rubik.ttf"
const WGHT := 0x77676874   # the OpenType tag "wght"
const BUTTON_HEIGHT := 60.0
const KINDS: Array[String] = ["main", "paper", "dark", "quiet"]
const BODY_SIZE := 22
const SMALL_SIZE := 18

static var _theme: Theme
static var _fonts := {}


## A variable font at one weight (cached): `display` is Unbounded, otherwise Rubik. `spacing` is extra space
## between letters in pixels.
static func font(display: bool, weight: int, spacing := 0) -> FontVariation:
	var key := "%s:%d:%d" % [display, weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = load(FONT_DISPLAY if display else FONT_TEXT)
	fv.variation_opentype = {WGHT: weight}
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


static func theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


static func _box(bg: Color, radius: int, edge := Color(0, 0, 0, 0), edge_width := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_width_bottom = edge_width
	sb.border_color = edge
	return sb


static func _button_boxes(bg: Color, edge: Color, edge_width: int) -> Dictionary:
	var out := {}
	for state in ["normal", "hover", "pressed", "disabled"]:
		var c := bg
		var w := edge_width
		if state == "hover":
			c = bg.lightened(0.06)
		elif state == "pressed":
			c = bg.darkened(0.08)
			w = maxi(edge_width - 3, 0)   # the key sinks into its edge
		elif state == "disabled":
			c = Color(bg.r, bg.g, bg.b, bg.a * 0.45)
		var sb := _box(c, 14, edge, w)
		sb.content_margin_left = 28.0
		sb.content_margin_right = 28.0
		sb.content_margin_top = 14.0 + (edge_width - w)
		sb.content_margin_bottom = 14.0 + w
		out[state] = sb
	return out


static func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(false, 500)
	t.default_font_size = BODY_SIZE
	t.set_color("font_color", "Label", PAPER)
	# One variation per button kind: Button.theme_type_variation = "MainButton" etc.
	var specs := {
		"main": [TOMATO, TOMATO_EDGE, 6, Color.WHITE],
		"paper": [PAPER, Color(0, 0, 0, 0.19), 6, INK],
		"dark": [INK, Color.BLACK, 6, PAPER],
		"quiet": [Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, PAPER],
	}
	t.set_type_variation("MainButton", "Button")
	t.set_type_variation("PaperButton", "Button")
	t.set_type_variation("DarkButton", "Button")
	t.set_type_variation("QuietButton", "Button")
	for kind: String in specs:
		var spec: Array = specs[kind]
		var type_name := kind.capitalize() + "Button"
		var boxes := _button_boxes(spec[0], spec[1], spec[2])
		for state: String in boxes:
			t.set_stylebox(state, type_name, boxes[state])
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		var fc: Color = spec[3]
		for cname in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(cname, type_name, fc)
		t.set_color("font_disabled_color", type_name, Color(fc.r, fc.g, fc.b, 0.5))
		t.set_font("font", type_name, font(false, 700))
		t.set_font_size("font_size", type_name, 24)
		t.set_constant("h_separation", type_name, 10)
	# Panels.
	t.set_type_variation("PaperPanel", "PanelContainer")
	t.set_type_variation("InkPanel", "PanelContainer")
	var paper := _box(PAPER, 22)
	paper.set_content_margin_all(24.0)
	paper.shadow_color = Color(0, 0, 0, 0.35)
	paper.shadow_size = 18
	paper.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "PaperPanel", paper)
	var ink := _box(INK, 22)
	ink.set_content_margin_all(24.0)
	ink.shadow_color = Color(0, 0, 0, 0.35)
	ink.shadow_size = 18
	ink.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "InkPanel", ink)
	# Fields and switches sit on paper panels.
	var field := _box(Color.WHITE, 12, LINE, 0)
	field.set_border_width_all(2)
	field.set_content_margin_all(12.0)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", TOMATO)
	t.set_color("font_placeholder_color", "LineEdit", MUTE)
	t.set_font_size("font_size", "LineEdit", 26)
	for cname in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(cname, "CheckButton", INK)
	t.set_color("font_disabled_color", "CheckButton", MUTE)
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	var flat := StyleBoxEmpty.new()
	flat.set_content_margin_all(4.0)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "CheckButton", flat)
	return t


# ---------------------------------------------------------------- widgets

## A big button of `kind` (see KINDS). `hint` is a small right-aligned second text ("Last Standing" under "Play").
static func button(text: String, kind := "paper", hint := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = kind.capitalize() + "Button"
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	if hint != "":
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var h := Label.new()
		h.text = hint
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_right = -28.0
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_theme_font_size_override("font_size", SMALL_SIZE)
		h.add_theme_color_override("font_color", Color.WHITE if kind == "main" else (INK if kind == "paper" else PAPER))
		h.modulate = Color(1, 1, 1, 0.7)
		b.add_child(h)
	return b


## A solid panel ("paper" or "ink") that holds one child; the caller adds the content to the returned panel.
static func panel(kind := "paper") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "InkPanel" if kind == "ink" else "PaperPanel"
	return p


## Plain text in Rubik (weight 500, or 700 for `bold`), in `color`.
static func label(text: String, size := BODY_SIZE, color := PAPER, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(false, 700 if bold else 500))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## Wrapping text in a muted colour for descriptions on paper (or on the dark arena with `on_dark`).
static func body(text: String, on_dark := false) -> Label:
	var l := label(text, SMALL_SIZE, Color(1, 1, 1, 0.8) if on_dark else MUTE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A heading in Unbounded (weight 800). Without `color` it is ink; use `title` for the big printed one.
static func heading(text: String, size := 28, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(true, 800))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## A big title: paper text with a tomato-red shadow offset down and right, like old print.
static func title(text: String, size := 84) -> Label:
	var l := heading(text, size, PAPER)
	l.add_theme_color_override("font_shadow_color", TOMATO)
	var off := maxi(roundi(size * 0.05), 2)
	l.add_theme_constant_override("shadow_offset_x", off)
	l.add_theme_constant_override("shadow_offset_y", off)
	return l


## A small spaced-out uppercase caption.
static func eyebrow(text: String, on_dark := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", font(false, 700, 2))
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("8e96ad") if on_dark else MUTE)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## The dimmed, blurred picture of what is behind a menu (the arena): a full-screen rectangle with a shader that
## reads the screen, blurs it (mipmap level), takes some colour out and darkens it.
static func backdrop(darkness := 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod = 2.5;
uniform float brightness = 0.55;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, 0.7);
	COLOR = vec4(c * brightness, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("brightness", darkness)
	r.material = mat
	return r
