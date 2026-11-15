class_name Mods
extends RefCounted
## The ONE table of all modifiers: ids, names, descriptions per level, price tiers and every
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
const WIRE_HALF_WIDTH := 0.06        # tripwire: half thickness for touching (before the big-head synergy)
const WIRE_MIN_LENGTH := 0.4         # no wire is left for a shorter string
const BODY_LETHAL_MARGIN := 0.15    # lethal body reach beyond touching (players are pushed apart at exactly touching)
const FLING_MIN_PROGRESS := 0.3      # a fling step that gains less than this share ends the fling
const PIERCE_EXIT_STEP := 0.1        # step used to leave a block a pierced head landed in
const PIERCE_EXIT_MAX_STEPS := 400
const DASH_EXIT_STEP := 0.1          # step used to leave an obstacle a phasing dash ended in
const DASH_EXIT_MAX_STEPS := 100
const PATH_PIN_SPACING := 0.7        # a bent flight leaves a path point (pin) every this many metres flown
const MAX_PATH_PINS := 60            # no more pins than this per head (steered flight, telekinesis)
const STEER_MIN_TURN := 0.0005       # radians: a smaller change of direction in one step does not bend the string
const PIN_REACH := 0.15              # a head / player counts as having reached a pin within this distance
const PIN_STUCK_PROGRESS := 0.1      # a player step along the string that gains less than this share gives up the pin
const PIN_STUCK_MIN_MOVE := 0.02      # shorter player steps are too small to judge whether a pin is blocked
const CROSS_MIN_GAP := 0.6           # Crossfire: heads closer together than this just return normally
const EXPLOSION_VIEW_TIME := 0.35    # presentation only

const ORDER: Array[String] = [
	"tripwire", "bighead", "elastic", "extradash", "bounce",
	"steer", "pierce", "shards", "warhead", "twin",
]

## "n" holds one array of 3 values (level 1..3) per key. In descriptions {key} is replaced by that value.
const TABLE := {
	"tripwire": {
		"name": "Tripwire", "tier": Tier.CHEAP,
		"desc": [
			"When you retract, the string stays on the ground as a wire for {wire_time} s. Anyone who runs over it stumbles for {stun_time} s (max. {max_wires} wire).",
			"Wires last {wire_time} s, up to {max_wires} at once, stumble {stun_time} s.",
			"The wires are DEADLY! They last {wire_time} s, up to {max_wires} at once.",
		],
		"n": {
			"wire_time": [2.5, 5.0, 6.0], "stun_time": [0.6, 1.0, 0.0],
			"max_wires": [1, 2, 3], "lethal": [0, 0, 1],
		},
	},
	"bighead": {
		"name": "Big Chunk", "tier": Tier.CHEAP,
		"desc": [
			"The yo-yo head is {radius_mult}x as big, so it hits much more easily.",
			"The yo-yo head is {radius_mult}x as big.",
			"Giant head: {radius_mult}x as big! Hard to miss.",
		],
		"n": {"radius_mult": [1.5, 2.0, 2.8]},
	},
	"elastic": {
		"name": "Rubber Band", "tier": Tier.MEDIUM,
		"desc": [
			"You pull yourself to the yo-yo {pull_mult}x faster and get flung {fling_dist} m onward.",
			"Pull {pull_mult}x faster, fling {fling_dist} m. Your body is deadly while pulling and flung.",
			"Pull {pull_mult}x faster, fling {fling_dist} m, deadly body {body_mult}x as big.",
		],
		"n": {
			"pull_mult": [1.4, 1.7, 2.2], "fling_dist": [2.5, 4.5, 6.0],
			"fling_speed": [30.0, 30.0, 30.0],
			"body_lethal": [0, 1, 1], "body_mult": [1.0, 1.0, 1.5],
		},
	},
	"extradash": {
		"name": "Extra Dash", "tier": Tier.MEDIUM,
		"desc": [
			"+{charges} dash charge.",
			"+{charges} dash charges and cooldown ×{cooldown_mult}.",
			"+{charges} dash charges, cooldown ×{cooldown_mult}, the dash passes through obstacles and the crate.",
		],
		"n": {
			"charges": [1, 2, 3], "cooldown_mult": [1.0, 0.75, 0.5], "phase": [0, 0, 1],
		},
	},
	"bounce": {
		"name": "Ricochet", "tier": Tier.MEDIUM,
		"desc": [
			"The flying yo-yo bounces off walls {bounces} time(s); each bounce adds {bonus_dist} m of flight. The string bends at the bounce points.",
			"Up to {bounces} bounces, each +{bonus_dist} m of flight. The string follows the path through every bounce point.",
			"Up to {bounces} bounces, each +{bonus_dist} m of flight, {speed_pct} % faster after the first.",
		],
		"n": {
			"bounces": [1, 3, 5], "bonus_dist": [1.5, 3.0, 5.0], "speed_pct": [0, 0, 25],
		},
	},
	"steer": {
		"name": "Steered Throw", "tier": Tier.MEDIUM,
		"desc": [
			"Pull the aim stick during the flight to steer the yo-yo that way.",
			"Steers harder, range +{range_pct} %.",
			"Telekinesis: hold and drag the aim stick to move the lying or flying yo-yo freely (deadly). Holding without dragging pulls you to it, tapping retracts it.",
		],
		"n": {
			"turn_rate": [360.0, 600.0, 3600.0],   # degrees per second the flight direction turns towards the stick
			"range_pct": [0, 25, 25],
			"tk": [0, 0, 1], "tk_speed": [12.0, 12.0, 12.0],   # Telekinesis: m/s of a lying head at full stick
		},
	},
	"pierce": {
		"name": "Piercing", "tier": Tier.EXPENSIVE,
		"desc": [
			"The yo-yo passes through obstacle blocks in flight and when retracting (but not through the outer walls).",
			"Also through the crate, range +{range_pct} %.",
			"Also unstoppable in duels: enemy yo-yos are knocked away while yours flies on.",
		],
		"n": {
			"pass_flight": [1, 2, 2], "pass_retract": [1, 2, 2],
			"range_pct": [0, 20, 20], "duel": [0, 0, 1], "duel_knock": [1.5, 1.5, 1.5],
		},
	},
	"shards": {
		"name": "Shards", "tier": Tier.MEDIUM,
		"desc": [
			"When you retract, {count} deadly shards fly away from the yo-yo ({range} m).",
			"{count} shards, {range} m far.",
			"{count} shards, {range} m far, each bounces off a wall once.",
		],
		"n": {
			"count": [3, 6, 10], "range": [4.0, 6.0, 8.0], "speed": [20.0, 20.0, 20.0],
			"radius": [0.12, 0.12, 0.12], "bounces": [0, 0, 1],
		},
	},
	"warhead": {
		"name": "Warhead", "tier": Tier.EXPENSIVE,
		"desc": [
			"The yo-yo explodes where it lands (radius {radius} m). You too!",
			"Radius {radius} m, plus a second explosion on retract. You too!",
			"Huge explosions (radius {radius} m) on landing and on retract. You too!",
		],
		"n": {"radius": [1.6, 2.4, 3.4], "retract_blast": [0, 1, 1]},
	},
	"twin": {
		"name": "Twin", "tier": Tier.EXPENSIVE,
		"desc": [
			"You have {heads} yo-yos. A short tap retracts both, holding pulls you to the yo-yo in your running direction.",
			"Crossfire: on retract both yo-yos meet in the middle (deadly!) and then come back together.",
			"Crossfire, return {retract_mult}x as fast. Even with a yo-yo in hand: holding without the stick pulls you to the lying yo-yo.",
		],
		"n": {
			"heads": [2, 2, 2], "cross": [0, 1, 1], "retract_mult": [1.0, 1.0, 1.5], "pull_free": [0, 0, 1],
		},
	},
}

## Combinations of two modifiers (active when both have level >= 1). "by" names the modifier whose level
## picks the value of every key in "n"; "{key}" in the text is replaced by that value.
const SYNERGIES := {
	"shards_warhead": {
		"ids": ["shards", "warhead"], "by": "warhead",
		"desc": "Shards + Warhead: every shard explodes where it ends (radius {radius} m).",
		"n": {"radius": [0.8, 1.2, 1.6]},
	},
	"shards_pierce": {
		"ids": ["shards", "pierce"], "by": "pierce",
		"desc": "Shards + Piercing: shards fly through obstacle blocks (from Piercing II also through the crate).",
		"n": {},
	},
	"shards_bounce": {
		"ids": ["shards", "bounce"], "by": "bounce",
		"desc": "Shards + Ricochet: shards bounce off walls as often as your Ricochet allows.",
		"n": {},
	},
	"shards_bighead": {
		"ids": ["shards", "bighead"], "by": "bighead",
		"desc": "Shards + Big Chunk: the shards grow as much as your yo-yo head.",
		"n": {},
	},
	"bighead_warhead": {
		"ids": ["bighead", "warhead"], "by": "bighead",
		"desc": "Big Chunk + Warhead: all explosions are {radius_mult}x as big.",
		"n": {"radius_mult": [1.15, 1.3, 1.5]},
	},
	"bighead_tripwire": {
		"ids": ["bighead", "tripwire"], "by": "bighead",
		"desc": "Big Chunk + Tripwire: the wire gets as much wider as your yo-yo head is bigger.",
		"n": {},
	},
}
const SYNERGY_ORDER: Array[String] = [
	"shards_warhead", "shards_pierce", "shards_bounce", "shards_bighead", "bighead_warhead", "bighead_tripwire",
]


static func max_heads() -> int:
	var m := 1
	for v: Variant in (TABLE["twin"]["n"]["heads"] as Array):
		m = maxi(m, int(v))
	return m


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
	return String.num(v, 2)


## Player-facing text of one level (1..3).
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


## True when both modifiers of the synergy `key` have level >= 1 in `levels`.
static func syn_active(key: String, levels: Dictionary) -> bool:
	for id: String in (SYNERGIES[key]["ids"] as Array):
		if int(levels.get(id, 0)) <= 0:
			return false
	return true


## Synergy value `name` for `levels` (0 when the synergy is not active or has no such key).
static func syn_n(key: String, name: String, levels: Dictionary) -> float:
	if not syn_active(key, levels):
		return 0.0
	var syn: Dictionary = SYNERGIES[key]
	var arr: Array = (syn["n"] as Dictionary).get(name, [])
	if arr.is_empty():
		return 0.0
	var l := clampi(int(levels.get(syn["by"], 1)), 1, MAX_LEVEL)
	return float(arr[l - 1])


## Keys of the synergies that are active for `levels`, in display order.
static func active_synergies(levels: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in SYNERGY_ORDER:
		if syn_active(key, levels):
			out.append(key)
	return out


static func describe_synergy(key: String, levels: Dictionary) -> String:
	var text: String = SYNERGIES[key]["desc"]
	for name: String in (SYNERGIES[key]["n"] as Dictionary):
		text = text.replace("{" + name + "}", fmt_num(syn_n(key, name, levels)))
	return text
