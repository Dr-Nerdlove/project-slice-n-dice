class_name ShopPanel
extends PanelContainer
## The shop between rounds (phase SHOP): the own coins, the time left, the three offers with their price tags, the
## own build (modifiers and slots), Reroll and Done. It only READS the sim it is given (`refresh`) and reports
## presses; main.gd sends them to the sim (Solo) or the server (`ClientCore.send_shop`), which decides.

signal buy_pressed(k: int)
signal reroll_pressed
signal done_pressed

var coins_tag: PanelContainer
var time_label: Label
var cards_box: HBoxContainer
var build_label: Label
var reroll_btn: Button
var done_btn: Button
var wait_label: Label
## One entry per offer card: {"name": Label, "level": Label, "desc": Label, "buy": Button}.
var cards: Array = []

var _key := ""


func _init() -> void:
	theme_type_variation = "PaperPanel"
	custom_minimum_size.x = 900.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	var head := UiKit.heading("Shop", 30)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	time_label = UiKit.label("", UiKit.BODY_SIZE, UiKit.MUTE, true)
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(time_label)
	coins_tag = UiKit.price_tag("", UiKit.BODY_SIZE)
	top.add_child(coins_tag)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 12)
	box.add_child(cards_box)
	for k in Economy.OFFERS:
		cards_box.add_child(_make_card(k))
	build_label = UiKit.label("", UiKit.SMALL_SIZE, UiKit.INK)
	build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(build_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	reroll_btn = UiKit.button("Reroll  %d ¢" % Economy.REROLL_PRICE, "paper")
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_btn.pressed.connect(func() -> void: reroll_pressed.emit())
	bottom.add_child(reroll_btn)
	done_btn = UiKit.button("Done", "main")
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_btn.pressed.connect(func() -> void: done_pressed.emit())
	bottom.add_child(done_btn)
	wait_label = UiKit.heading("Waiting for the others …", 22)
	wait_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(wait_label)


func _make_card(k: int) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = UiKit.LINE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(260, 200)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var n := UiKit.heading("", 20)
	v.add_child(n)
	var l := UiKit.eyebrow("")
	v.add_child(l)
	var d := UiKit.body("")
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	var b := UiKit.button("", "dark")
	b.pressed.connect(func() -> void: buy_pressed.emit(k))
	v.add_child(b)
	cards.append({"name": n, "level": l, "desc": d, "buy": b})
	return card


## "New", "Level II", "Copy 2 of 3 for level II": what one more copy of `id` does for a player with `copies`.
static func level_text(copies: int) -> String:
	var now := Mods.level_for_copies(copies)
	var after := Mods.level_for_copies(copies + 1)
	if copies == 0:
		return "New"
	if after > now:
		return "Level %s" % Mods.ROMAN[after]
	var need: int = Mods.COPIES_FOR_LEVEL[now]
	return "Copy %d of %d for level %s" % [copies + 1 - Mods.COPIES_FOR_LEVEL[now - 1], need - Mods.COPIES_FOR_LEVEL[now - 1], Mods.ROMAN[now + 1]]


## "Build 2/5: Tripwire II, Ricochet I" (or "Build 0/5: nothing yet").
static func build_text(m: MatchMode, i: int) -> String:
	var parts: Array[String] = []
	for id in Mods.ORDER:
		if m.owned[i].has(id):
			parts.append("%s %s" % [Mods.mod_name(id), Mods.ROMAN[Mods.level_for_copies(m.owned[i][id])]])
	return "Build %d/%d: %s" % [m.owned[i].size(), Economy.SLOTS, ", ".join(parts) if not parts.is_empty() else "nothing yet"]


## Shows the shop of slot `own` in `sim` (call every frame while it is visible).
func refresh(sim: Sim, own: int) -> void:
	var m := sim.mode
	time_label.text = "%d s" % ceili(maxf(Economy.SHOP_TIME - m.phase_t, 0.0))
	var key := "%s|%s|%s|%s|%s" % [m.coins[own], str(m.offers[own]), str(m.owned[own]), m.shop_ready[own], m.shop_seq[own]]
	if key == _key:
		return
	_key = key
	var coins: int = m.coins[own]
	var done: bool = m.shop_ready[own]
	(coins_tag.get_node("Text") as Label).text = "%d ¢" % coins
	var offers: Array = m.offers[own]
	for k in cards.size():
		var c: Dictionary = cards[k]
		var id: String = offers[k] if k < offers.size() else ""
		var buy: Button = c["buy"]
		if id == "":
			c["name"].text = "Sold" if k < offers.size() else "—"
			c["level"].text = ""
			c["desc"].text = ""
			buy.text = ""
			buy.visible = false
			continue
		var copies: int = m.owned[own].get(id, 0)
		c["name"].text = Mods.mod_name(id)
		c["level"].text = level_text(copies)
		c["desc"].text = Mods.describe(id, maxi(Mods.level_for_copies(copies + 1), 1))
		buy.visible = true
		buy.text = "Buy  %d ¢" % Mods.price(id)
		buy.disabled = done or coins < Mods.price(id) or not m.can_take(own, id)
	build_label.text = build_text(m, own)
	reroll_btn.disabled = done or coins < Economy.REROLL_PRICE
	reroll_btn.visible = not done
	done_btn.visible = not done
	wait_label.visible = done
