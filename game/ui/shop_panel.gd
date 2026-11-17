class_name ShopPanel
extends PanelContainer
## The shop between rounds (phase SHOP): the own coins, the time left, the offer cards (icon, name, a few words,
## price, lock), the five build slots (icon, level, pips towards the next level; tap one to sell it), Reroll and Done.
## It only READS the sim it is given (`refresh`) and reports presses; main.gd sends them to the sim (Solo) or the
## server (`ClientCore.send_shop`), which decides. No scrolling: it must fit the smallest screen (a test checks it).

signal buy_pressed(k: int)
signal reroll_pressed
signal done_pressed
signal sell_pressed(n: int)   # index of the modifier in Mods.ORDER
signal lock_pressed(k: int)

## Progress dots of one build slot: `total` dots, `filled` of them lit.
class Pips extends Control:
	var filled := 0
	var total := 0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_pips(f: int, t: int) -> void:
		filled = f
		total = t
		queue_redraw()

	func _draw() -> void:
		var r := 6.0
		var gap := 6.0
		for k in total:
			var c := Vector2(r + k * (2.0 * r + gap), size.y / 2.0)
			if k < filled:
				draw_circle(c, r, UiKit.INK)
			else:
				draw_arc(c, r - 1.0, 0.0, TAU, 16, UiKit.MUTE, 2.0)

## Width of every offer card, sold or not (wide enough for the longest modifier name next to "Locked").
const CARD_WIDTH := 320.0
## Font size of the modifier name under a build slot.
const SLOT_NAME_SIZE := 14

var coins_tag: PanelContainer
var time_label: Label
var cards_box: HBoxContainer
var slots_box: HBoxContainer
var reroll_btn: Button
var sell_btn: Button
var done_btn: Button
var wait_label: Label
## One entry per offer card: {"icon", "name", "gain", "desc", "price", "buy", "lock", "panel"}.
var cards: Array = []
## One entry per build slot: {"panel", "icon", "level", "pips"}.
var slots: Array = []

var _key := ""
var _selected := ""   # id of the build slot selected for selling


func _init() -> void:
	theme_type_variation = "PaperPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	var head := UiKit.heading("Shop", 28)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	time_label = UiKit.label("", UiKit.SMALL_SIZE, UiKit.MUTE, true)
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(time_label)
	coins_tag = UiKit.price_tag("", UiKit.BODY_SIZE)
	top.add_child(coins_tag)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 10)
	box.add_child(cards_box)
	for k in Economy.OFFERS:
		cards_box.add_child(_make_card(k))
	slots_box = HBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 8)
	box.add_child(slots_box)
	for n in Economy.SLOTS:
		slots_box.add_child(_make_slot(n))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	box.add_child(bottom)
	reroll_btn = UiKit.button("Reroll  %d ¢" % Economy.REROLL_PRICE, "paper")
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_btn.custom_minimum_size.y = 48
	reroll_btn.pressed.connect(func() -> void: reroll_pressed.emit())
	bottom.add_child(reroll_btn)
	sell_btn = UiKit.button("Sell", "paper")
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.custom_minimum_size.y = 48
	sell_btn.pressed.connect(_on_sell)
	bottom.add_child(sell_btn)
	done_btn = UiKit.button("Done", "main")
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_btn.custom_minimum_size.y = 48
	done_btn.pressed.connect(func() -> void: done_pressed.emit())
	bottom.add_child(done_btn)
	wait_label = UiKit.heading("Waiting for the others …", 22)
	wait_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(wait_label)


func _style(edge: Color, width: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(margin)
	return sb


func _make_card(k: int) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(UiKit.LINE, 2, 8))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A fixed width: otherwise a sold (empty) card shrinks and the panel changes size after every buy,
	# and the panel's minimum width left no room for the names.
	card.custom_minimum_size.x = CARD_WIDTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var icon := ModIcon.new("", 40.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	row.add_child(names)
	var n := UiKit.heading("", 17)
	n.clip_text = true
	names.add_child(n)
	var g := UiKit.label("", UiKit.SMALL_SIZE - 3, UiKit.TOMATO, true)
	names.add_child(g)
	var lock := UiKit.compact(UiKit.button("Lock", "paper"), 44.0, 18)
	lock.toggle_mode = true
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.pressed.connect(func() -> void: lock_pressed.emit(k))
	row.add_child(lock)
	var d := UiKit.label("", UiKit.SMALL_SIZE - 2, UiKit.INK)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# exactly two lines high, so no card ever changes height
	var df := d.get_theme_font("font")
	var dsize := d.get_theme_font_size("font_size")
	d.custom_minimum_size = Vector2(0, 2.0 * df.get_height(dsize) + d.get_theme_constant("line_spacing"))
	v.add_child(d)
	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	v.add_child(buy_row)
	var price := UiKit.price_tag("", UiKit.BODY_SIZE)
	buy_row.add_child(price)
	var b := UiKit.button("", "dark")
	b.custom_minimum_size.y = 44
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: buy_pressed.emit(k))
	buy_row.add_child(b)
	cards.append({"icon": icon, "name": n, "gain": g, "desc": d, "price": price, "buy": b, "lock": lock, "panel": card})
	return card


## A locked offer's button is yellow (the shop's accent); an unlocked one is the theme's paper button.
func _style_lock(b: Button, locked: bool) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base: String = "pressed" if state == "hover_pressed" else state
		var sb := UiKit.theme().get_stylebox(base, "PaperButton").duplicate() as StyleBoxFlat
		if locked:
			sb.bg_color = UiKit.SUN.darkened(0.08) if base == "pressed" else UiKit.SUN
			sb.border_color = UiKit.SUN.darkened(0.35)
		sb.content_margin_left = 10.0
		sb.content_margin_right = 10.0
		sb.content_margin_top = 4.0 + (sb.content_margin_top - 14.0)
		sb.content_margin_bottom = 4.0 + (sb.content_margin_bottom - 14.0)
		b.add_theme_stylebox_override(state, sb)


func _make_slot(n: int) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, 70)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var icon := ModIcon.new("", 32.0)
	row.add_child(icon)
	var lv := UiKit.heading("", 20)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lv)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var sell := UiKit.price_tag("", SLOT_NAME_SIZE)
	sell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sell.visible = false
	row.add_child(sell)
	var nm := UiKit.label("", SLOT_NAME_SIZE, UiKit.INK, true)
	nm.name = "SlotName"
	v.add_child(nm)
	var pips := Pips.new()
	v.add_child(pips)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_slot(n))
	slots.append({"panel": p, "icon": icon, "level": lv, "name": nm, "sell": sell, "pips": pips, "id": ""})
	return p


func _on_slot(n: int) -> void:
	var id: String = slots[n]["id"]
	if id == "":
		return
	_selected = "" if _selected == id else id
	_key = ""   # redraw on the next refresh
	_apply_selection()


func _on_sell() -> void:
	if _selected != "":
		var n := Mods.ORDER.find(_selected)
		_selected = ""
		_key = ""
		sell_pressed.emit(n)


## Dots for a modifier with `copies`: filled / total towards the next level (full at the top level).
static func pips(copies: int) -> Vector2i:
	var lvl := Mods.level_for_copies(copies)
	if lvl <= 0:
		return Vector2i(0, Mods.COPIES_FOR_LEVEL[0])
	if lvl >= Mods.MAX_LEVEL:
		var span: int = Mods.COPIES_FOR_LEVEL[Mods.MAX_LEVEL - 1] - Mods.COPIES_FOR_LEVEL[Mods.MAX_LEVEL - 2]
		return Vector2i(span, span)
	var lo: int = Mods.COPIES_FOR_LEVEL[lvl - 1]
	return Vector2i(copies - lo, Mods.COPIES_FOR_LEVEL[lvl] - lo)


## What one more copy gives a player who has `copies`: "New", "→ II" (next level) or "Pip 2/3".
static func gain_text(copies: int) -> String:
	if copies <= 0:
		return "New · I"
	var after := Mods.level_for_copies(copies + 1)
	if after > Mods.level_for_copies(copies):
		return "→ %s" % Mods.ROMAN[after]
	var p := pips(copies + 1)
	return "Pip %d/%d" % [p.x, p.y]


## The build ids of slot `i` in slot order (insertion order of `owned`).
static func build_ids(m: MatchMode, i: int) -> Array:
	return m.owned[i].keys()


func _apply_selection() -> void:
	for s in slots:
		var on: bool = s["id"] != "" and s["id"] == _selected
		(s["panel"] as PanelContainer).add_theme_stylebox_override("panel", _style(UiKit.TOMATO if on else UiKit.LINE, 3 if on else 2, 6))


## Shows the shop of slot `own` in `sim` (call every frame while it is visible).
func refresh(sim: Sim, own: int) -> void:
	var m := sim.mode
	time_label.text = "%d s" % ceili(maxf(Economy.SHOP_TIME - m.phase_t, 0.0))
	var key := "%s|%s|%s|%s|%s|%s|%s" % [m.coins[own], str(m.offers[own]), str(m.owned[own]), m.shop_ready[own], m.shop_seq[own], str(m.locked[own]), _selected]
	if key == _key:
		return
	_key = key
	var coins: int = m.coins[own]
	var done: bool = m.shop_ready[own]
	(coins_tag.get_node("Text") as Label).text = "%d ¢" % coins
	var offers: Array = m.offers[own]
	var full: bool = m.owned[own].size() >= Economy.SLOTS
	for k in cards.size():
		var c: Dictionary = cards[k]
		var id: String = offers[k] if k < offers.size() else ""
		var buy: Button = c["buy"]
		var lock: Button = c["lock"]
		var panel: PanelContainer = c["panel"]
		panel.modulate = Color.WHITE
		if id == "":
			c["icon"].id = ""
			c["name"].text = "Sold" if k < offers.size() else "—"
			c["gain"].text = ""
			c["desc"].text = ""
			(c["price"] as Control).visible = false
			buy.text = ""
			buy.disabled = true
			buy.visible = false
			lock.visible = false
			continue
		var copies: int = m.owned[own].get(id, 0)
		var locked := m.is_locked(own, k)
		var can: bool = coins >= Mods.price(id) and m.can_take(own, id)
		c["icon"].id = id
		c["name"].text = Mods.mod_name(id)
		c["gain"].text = gain_text(copies)
		c["desc"].text = Mods.short(id, maxi(Mods.level_for_copies(copies + 1), 1))
		(c["price"].get_node("Text") as Label).text = "%d ¢" % Mods.price(id)
		(c["price"] as Control).visible = true
		buy.visible = true
		buy.text = "Buy"
		if copies >= Mods.COPIES_FOR_LEVEL[Mods.MAX_LEVEL - 1]:
			buy.text = "Max level"
		elif copies == 0 and full:
			buy.text = "Slots full – sell one"
		buy.disabled = done or not can
		lock.visible = not done
		lock.set_pressed_no_signal(locked)
		lock.text = "Locked" if locked else "Lock"
		_style_lock(lock, locked)
		panel.add_theme_stylebox_override("panel", _style(UiKit.SUN if locked else UiKit.LINE, 3 if locked else 2, 8))
		panel.modulate = Color(1, 1, 1, 0.6) if not can else Color.WHITE
	var ids := build_ids(m, own)
	if not ids.has(_selected):
		_selected = ""
	for n in slots.size():
		var s: Dictionary = slots[n]
		if n < ids.size():
			var copies: int = m.owned[own][ids[n]]
			var p := pips(copies)
			s["id"] = ids[n]
			s["icon"].id = ids[n]
			s["level"].text = Mods.ROMAN[Mods.level_for_copies(copies)]
			s["name"].text = Mods.mod_name(ids[n])
			(s["sell"].get_node("Text") as Label).text = "+%d ¢" % m.sell_refund(own, ids[n])
			(s["sell"] as Control).visible = true
			s["pips"].set_pips(p.x, p.y)
		else:
			s["id"] = ""
			s["icon"].id = ""
			s["level"].text = ""
			s["name"].text = ""
			(s["sell"] as Control).visible = false
			s["pips"].set_pips(0, 0)
	_apply_selection()
	reroll_btn.disabled = done or coins < Economy.REROLL_PRICE
	reroll_btn.visible = not done
	sell_btn.visible = not done and _selected != ""
	if _selected != "":
		sell_btn.text = "Sell %s  +%d ¢" % [Mods.mod_name(_selected), m.sell_refund(own, _selected)]
	done_btn.visible = not done
	wait_label.visible = done
