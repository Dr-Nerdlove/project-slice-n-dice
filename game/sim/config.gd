class_name Config
extends RefCounted
## The ONE place for every tunable number. Units: metres, seconds.
## Runtime-tunable values are instance variables (see DEFAULTS); fixed layout data are constants.

enum OutVariant { DRAG, LEASH, RIGID }  # A, B, C
enum BotMode { OFF, DUMMY, ACTIVE }

# --- Arena layout (fixed) ---
const ARENA_SIZE := Vector2(32.0, 14.4)   # 20:9 like a phone screen
const WALL_THICKNESS := 2.0
## The building blocks: the layout of the first 28 x 12.6 arena scaled by 8/7 (centre block, two point-symmetric
## blocks, one small block near the top wall).
const OBSTACLES: Array[Rect2] = [
	Rect2(14.75, 5.6, 2.5, 3.2),
	Rect2(6.65, 2.75, 1.8, 1.8),
	Rect2(23.55, 9.85, 1.8, 1.8),
	Rect2(21.5, 1.8, 1.4, 1.4),
]
const CRATE_START := Vector2(16.0, 2.3)
const BOX_POS := Vector2(16.0, 12.1)
const SPAWNS: Array[Vector2] = [
	Vector2(2.8, 7.2), Vector2(29.2, 7.2), Vector2(10.9, 1.5), Vector2(21.1, 12.9),
	Vector2(2.8, 2.3), Vector2(29.2, 12.1), Vector2(2.8, 12.1), Vector2(29.2, 2.3),
]

# --- Sim constants (fixed) ---
const TICK_RATE := 60.0
const NUM_PLAYERS := 4
const SKIN_COUNT := 8              # player figures to choose from (presentation only); must equal ToyFigure.NAMES.size()
const MOVE_DEADZONE := 0.1
const SUBSTEP_FACTOR := 0.5        # max movement per substep as a fraction of the radius
const CRATE_HALF := 0.7
const BOX_HALF := 0.6
const CRATE_PUSH_RATIO := 0.3      # share of a player's push that moves the crate (rest slows the player)
const BOX_RESPAWN_TIME := 6.0
const PLAYER_SEPARATION_SHARE := 0.5
const SPAWN_NOISE := 0.5
const TRAIN_HIT_SHARE := 0.6       # share of the player radius that counts when a train car hits (a little forgiving)
const HEAD_BOUNCE_EXTRA := 0.6     # extra knock distance when two heads collide
const CATCH_MARGIN := 0.1
const MAX_ACCUMULATED_TIME := 0.25
const RETRACT_MIN_PROGRESS := 0.3  # a retract step that gains less than this share of its length counts as blocked

# --- Bot behaviour (fixed) ---
const BOT_MOVE_SCALE := 0.6
const BOT_AVOID_DIST := 1.8
const BOT_AVOID_WEIGHT := 1.5
const BOT_WANDER_TIME := Vector2(1.5, 3.5)
const BOT_ATTACK_WAIT := Vector2(1.2, 3.0)
const BOT_AIM_ERROR := 0.3          # radians
const BOT_RETRACT_WAIT := Vector2(0.4, 1.2)
const BOT_PULL_CHANCE := 0.2
const BOT_THROW_MORE_CHANCE := 0.6  # with extra yo-yos in hand: throw another instead of calling them back
const BOT_NEXT_THROW_WAIT := 0.25
const BOT_PULL_HOLD_EXTRA := 0.6
const BOT_DASH_CHANCE := 0.004      # per tick while idle
const BOT_ATTACK_RANGE_FACTOR := 1.2
const BOT_MARGIN := 1.8
const BOT_TRAIN_AVOID_DIST := 3.0   # bots steer away from a train car (or the rails ahead of it) closer than this
const BOT_TRAIN_AVOID_WEIGHT := 3.0

# --- Feel / presentation (fixed) ---
const HITSTOP_TIME := 0.07
const SHAKE_STRENGTH := 0.35
const SHAKE_TIME := 0.25
const VIBRATE_MS := 40
const CAMERA_PITCH_DEG := 65.0
const CAMERA_FOV := 55.0
const CAMERA_MARGIN := 1.2
const HEAD_SPIN_SPEED := 18.0
const AIM_LINE_WIDTH := 0.14

# --- Touch UI (fixed, in base-resolution pixels) ---
const STICK_RADIUS := 90.0
const STICK_KNOB_RADIUS := 36.0
const DASH_BUTTON_RADIUS := 62.0
const DASH_BUTTON_OFFSET := Vector2(120.0, 250.0)  # from the lower right corner
const GEAR_SIZE := 56.0
const STICK_REST_OFFSET_LEFT := Vector2(230.0, 230.0)    # resting centre of the left stick, from the lower left corner
const STICK_REST_OFFSET_RIGHT := Vector2(330.0, 230.0)   # resting centre of the right stick, from the lower right corner
const DASH_PIP_RADIUS := 6.0

# --- Tunable values (instance variables, defaults below) ---
var player_radius: float
var player_speed: float
var charge_speed_mult: float
var dash_distance: float
var dash_duration: float
var dash_cooldown: float
var dash_charges: int
var respawn_time: float
var head_radius: float
var min_range: float
var max_range: float
var charge_time: float
var flight_speed: float
var retract_speed: float
var pull_speed: float
var string_length: float
var tap_threshold: float
var aim_deadzone: float
var accidental_hold_time: float
var out_variant: int
var bot_mode: int
var train_speed: float
## Sandbox modifier levels (modifier id -> 0..3): one set for the human player, one shared by all bots.
var mods_you: Dictionary = Mods.empty_levels()
var mods_bots: Dictionary = Mods.empty_levels()
## The figure the human player chose (0..SKIN_COUNT-1). Saved with the settings, but not a tuning value: reset leaves it.
var character := 0

const DEFAULTS := {
	"player_radius": 0.5,
	"player_speed": 6.0,
	"charge_speed_mult": 0.6,
	"dash_distance": 3.0,
	"dash_duration": 0.12,
	"dash_cooldown": 1.2,
	"dash_charges": 1,
	"respawn_time": 1.5,
	"head_radius": 0.35,
	"min_range": 2.5,
	"max_range": 8.0,
	"charge_time": 0.7,
	"flight_speed": 28.0,
	"retract_speed": 22.0,
	"pull_speed": 20.0,
	"string_length": 9.0,
	"tap_threshold": 0.2,
	"aim_deadzone": 0.25,
	"accidental_hold_time": 0.07,
	"out_variant": OutVariant.DRAG,
	"bot_mode": BotMode.ACTIVE,
	"train_speed": 5.7,
}


func _init() -> void:
	reset()


func reset() -> void:
	for k: String in DEFAULTS:
		set(k, DEFAULTS[k])


func to_dict() -> Dictionary:
	var d := {}
	for k: String in DEFAULTS:
		d[k] = get(k)
	d["mods_you"] = mods_you.duplicate()
	d["mods_bots"] = mods_bots.duplicate()
	d["character"] = character
	return d


func from_dict(d: Dictionary) -> void:
	mods_you = Mods.sanitize(d.get("mods_you"))
	mods_bots = Mods.sanitize(d.get("mods_bots"))
	var ch: Variant = d.get("character")
	character = posmod(int(ch), SKIN_COUNT) if (ch is int or (ch is float and is_finite(ch))) else 0
	for k: String in DEFAULTS:
		if not d.has(k):
			continue
		var v: Variant = d[k]
		if not (v is float or v is int):
			continue
		if typeof(DEFAULTS[k]) == TYPE_INT:
			set(k, int(v))
		else:
			set(k, float(v))


## Largest throw distance actually usable (never longer than the string).
func effective_max_range() -> float:
	return minf(max_range, string_length)


func effective_min_range() -> float:
	return minf(min_range, effective_max_range())


## All current settings as one compact plain-text block (config keys with their values), for pasting into a chat.
## A trailing "*" marks a value that differs from the default.
func export_text() -> String:
	var lines: Array[String] = ["slice-n-dice settings (* = differs from default)"]
	for k: String in DEFAULTS:
		var v: Variant = get(k)
		var shown := str(v)
		if k == "out_variant":
			shown = OutVariant.keys()[int(v)]
		elif k == "bot_mode":
			shown = BotMode.keys()[int(v)]
		lines.append("%s=%s%s" % [k, shown, " *" if v != DEFAULTS[k] else ""])
	for group in ["mods_you", "mods_bots"]:
		var levels: Dictionary = get(group)
		var parts: Array[String] = []
		for id in Mods.ORDER:
			var lvl := int(levels.get(id, 0))
			parts.append("%s=%d%s" % [id, lvl, "*" if lvl != 0 else ""])
		lines.append("%s: %s" % [group, " ".join(parts)])
	return "\n".join(lines)
