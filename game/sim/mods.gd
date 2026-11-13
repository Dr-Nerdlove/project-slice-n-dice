class_name Mods
extends RefCounted
## The ONE table of all modifiers: ids, German names, descriptions per level, price tiers and every
## number a modifier uses. Units: metres, seconds. Levels 1..3 are indexed 0..2 in the arrays.
## Nothing else in the code base may hard-code a modifier number.

enum Tier { CHEAP, MEDIUM, EXPENSIVE }

## Copies of one modifier needed for level 1 / 2 / 3.
const COPIES_FOR_LEVEL: Array[int] = [1, 3, 6]
const MAX_LEVEL := 3
## Placeholder shop prices per tier (not used yet).
const PRICES := {Tier.CHEAP: 3, Tier.MEDIUM: 5, Tier.EXPENSIVE: 8}
const ROMAN: Array[String] = ["", "I", "II", "III"]

# --- numbers shared by the mechanics (not level dependent) ---
const WIRE_HALF_WIDTH := 0.06        # tripwire: half thickness for touching
const WIRE_MIN_LENGTH := 0.4         # no wire is left for a shorter string
const BODY_LETHAL_MARGIN := 0.15    # lethal body reach beyond touching (players are pushed apart at exactly touching)
const FLING_MIN_PROGRESS := 0.3      # a fling step that gains less than this share ends the fling
const PIERCE_EXIT_STEP := 0.1        # step used to leave a block a pierced head landed in
const PIERCE_EXIT_MAX_STEPS := 400
const ARC_MAX_BULGE_RATIO := 1.0     # the arc never bulges more than this times the string length
const ARC_MIN_CHORD := 0.6           # shorter strings come home straight
const EXPLOSION_VIEW_TIME := 0.35    # presentation only

const ORDER: Array[String] = [
	"tripwire", "bighead", "elastic", "extradash", "bounce",
	"arc", "pierce", "shards", "warhead", "twin",
]

## "n" holds one array of 3 values (level 1..3) per key. In descriptions {key} is replaced by that value.
const TABLE := {
	"tripwire": {
		"name": "Stolperdraht", "tier": Tier.CHEAP,
		"desc": [
			"Beim Einholen bleibt die Schnur {wire_time} s als Draht am Boden. Wer drüberläuft, stolpert {stun_time} s (max. {max_wires} Draht).",
			"Der Draht hält {wire_time} s, bis zu {max_wires} Drähte gleichzeitig, Stolpern {stun_time} s.",
			"Die Drähte sind TÖDLICH! Sie halten {wire_time} s, bis zu {max_wires} gleichzeitig.",
		],
		"n": {
			"wire_time": [2.5, 5.0, 6.0], "stun_time": [0.6, 1.0, 0.0],
			"max_wires": [1, 2, 3], "lethal": [0, 0, 1],
		},
	},
	"bighead": {
		"name": "Dicker Brocken", "tier": Tier.CHEAP,
		"desc": [
			"Der Jojo-Kopf ist {radius_mult}-mal so groß – trifft viel leichter.",
			"Der Jojo-Kopf ist {radius_mult}-mal so groß.",
			"Riesenkopf: {radius_mult}-mal so groß! Kaum zu verfehlen.",
		],
		"n": {"radius_mult": [1.5, 2.0, 2.8]},
	},
	"elastic": {
		"name": "Gummiband", "tier": Tier.MEDIUM,
		"desc": [
			"Du ziehst dich {pull_mult}-mal schneller zum Jojo und wirst {fling_dist} m weitergeschleudert.",
			"Zug {pull_mult}-mal schneller, Schleudern {fling_dist} m. Dein Körper ist beim Ziehen und Schleudern tödlich.",
			"Zug {pull_mult}-mal schneller, Schleudern {fling_dist} m, tödlicher Körper {body_mult}-mal so groß.",
		],
		"n": {
			"pull_mult": [1.4, 1.7, 2.2], "fling_dist": [2.5, 4.5, 6.0],
			"fling_speed": [30.0, 30.0, 30.0],
			"body_lethal": [0, 1, 1], "body_mult": [1.0, 1.0, 1.5],
		},
	},
	"extradash": {
		"name": "Extra-Dash", "tier": Tier.MEDIUM,
		"desc": [
			"+{charges} Dash-Ladung.",
			"+{charges} Dash-Ladungen und Abklingzeit ×{cooldown_mult}.",
			"+{charges} Dash-Ladungen, Abklingzeit ×{cooldown_mult}, Dash {distance_mult}-mal so weit.",
		],
		"n": {
			"charges": [1, 2, 3], "cooldown_mult": [1.0, 0.75, 0.5], "distance_mult": [1.0, 1.0, 1.3],
		},
	},
	"bounce": {
		"name": "Abpraller", "tier": Tier.MEDIUM,
		"desc": [
			"Der fliegende Jojo prallt {bounces} mal von Wänden ab.",
			"Bis zu {bounces} Abpraller, jeder verlängert den Flug um {bonus_dist} m.",
			"Bis zu {bounces} Abpraller, jeder +{bonus_dist} m Flug, nach dem ersten {speed_pct} % schneller.",
		],
		"n": {
			"bounces": [1, 3, 5], "bonus_dist": [0.0, 2.0, 4.0], "speed_pct": [0, 0, 25],
		},
	},
	"arc": {
		"name": "Bogenwurf", "tier": Tier.MEDIUM,
		"desc": [
			"Der Jojo kommt im Bogen zurück ({bulge} m seitlich). Die Seite bestimmst du mit dem Laufstick.",
			"Größerer Bogen ({bulge} m) und {retract_mult}-mal schnellere Rückkehr.",
			"Erst kreist der Jojo einmal um dich, dann kommt er im Bogen heim. Schnell und weit.",
		],
		"n": {
			"bulge": [2.5, 4.5, 4.5], "retract_mult": [1.0, 1.3, 1.3],
			"circle": [0, 0, 1], "circle_time": [0.6, 0.6, 0.6],
		},
	},
	"pierce": {
		"name": "Durchschlag", "tier": Tier.EXPENSIVE,
		"desc": [
			"Der fliegende Jojo geht durch Hindernisblöcke (aber nicht durch die Außenwände).",
			"Auch beim Einholen durch Blöcke und Kiste, Reichweite +{range_pct} %.",
			"Dazu unaufhaltsam im Duell: Gegnerische Jojos werden weggeschlagen, deiner fliegt weiter.",
		],
		"n": {
			"pass_flight": [1, 2, 2], "pass_retract": [0, 2, 2],
			"range_pct": [0, 20, 20], "duel": [0, 0, 1], "duel_knock": [1.5, 1.5, 1.5],
		},
	},
	"shards": {
		"name": "Splitter", "tier": Tier.MEDIUM,
		"desc": [
			"Beim Einholen fliegen {count} tödliche Splitter ({range} m) vom Jojo weg.",
			"{count} Splitter, {range} m weit.",
			"{count} Splitter, {range} m weit, jeder prallt einmal von der Wand ab.",
		],
		"n": {
			"count": [3, 6, 10], "range": [4.0, 6.0, 8.0], "speed": [20.0, 20.0, 20.0],
			"radius": [0.12, 0.12, 0.12], "bounces": [0, 0, 1],
		},
	},
	"warhead": {
		"name": "Sprengkopf", "tier": Tier.EXPENSIVE,
		"desc": [
			"Der Jojo explodiert am Landepunkt (Radius {radius} m).",
			"Radius {radius} m, dazu eine zweite Explosion, wenn du ihn einholst.",
			"Riesige Explosionen (Radius {radius} m) beim Landen und beim Einholen.",
		],
		"n": {"radius": [1.6, 2.4, 3.4], "retract_blast": [0, 1, 1]},
	},
	"twin": {
		"name": "Zwilling", "tier": Tier.EXPENSIVE,
		"desc": [
			"Du hast {heads} Jojos. Kurz tippen holt alle ein, Halten zieht dich zum Jojo in Laufrichtung.",
			"Du hast {heads} Jojos.",
			"Du hast {heads} Jojos – ein ganzer Schwarm!",
		],
		"n": {"heads": [2, 3, 5]},
	},
}


static func max_heads() -> int:
	return int((TABLE["twin"]["n"]["heads"] as Array)[MAX_LEVEL - 1])


## Value of `key` of modifier `id` at `level` (1..3).
static func n(id: String, key: String, level: int) -> float:
	return float(((TABLE[id]["n"] as Dictionary)[key] as Array)[clampi(level, 1, MAX_LEVEL) - 1])


static func mod_name(id: String) -> String:
	return TABLE[id]["name"]


static func tier(id: String) -> int:
	return TABLE[id]["tier"]


static func price(id: String) -> int:
	return PRICES[tier(id)]


## Level reached with `copies` copies (0 = none).
static func level_for_copies(copies: int) -> int:
	var lv := 0
	for i in COPIES_FOR_LEVEL.size():
		if copies >= COPIES_FOR_LEVEL[i]:
			lv = i + 1
	return lv


static func fmt_num(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(int(roundf(v)))
	return String.num(v, 2).replace(".", ",")


## German player-facing text of one level (1..3).
static func describe(id: String, level: int) -> String:
	var text: String = (TABLE[id]["desc"] as Array)[clampi(level, 1, MAX_LEVEL) - 1]
	for key: String in (TABLE[id]["n"] as Dictionary):
		text = text.replace("{" + key + "}", fmt_num(n(id, key, level)))
	return text


static func empty_levels() -> Dictionary:
	var d := {}
	for id in ORDER:
		d[id] = 0
	return d


## Turns anything loaded from disk into a complete id -> 0..3 dictionary.
static func sanitize(src: Variant) -> Dictionary:
	var d := empty_levels()
	if src is Dictionary:
		for id in ORDER:
			var v: Variant = (src as Dictionary).get(id, 0)
			if v is float or v is int:
				d[id] = clampi(int(v), 0, MAX_LEVEL)
	return d
