class_name MatchMode
extends RefCounted
## Round and match state shared by every game mode: the phase machine and the score. The rules of a mode live in
## the three hooks below (`round_over`, `round_scorer`, `match_winner`), which a subclass overrides.
## `Sim` drives the phases; everything here is plain data, so a snapshot (StateIO) carries it.

## SHOP comes after RESULT (not after the deciding round); it is last so the numbers of the others stay.
enum Phase { OFF, COUNTDOWN, PLAY, RESULT, MATCH_OVER, SHOP }

const COUNTDOWN_TIME := 3.0
const RESULT_TIME := 4.0
## Points needed to win a match (the host picks one).
const TARGETS: Array[int] = [10, 15, 20]
const DEFAULT_TARGET := 10

## The shrinking zone (Last Standing, phase PLAY only; fixed match rules, not tunable): the whole arena for
## ZONE_FULL_TIME seconds, then a rectangle shrinks for ZONE_SHRINK_TIME seconds (every edge linearly) to one of
## `Config.ZONE_SPOTS` and stays. A player whose centre is outside fills a personal timer and dies at ZONE_DEATH_TIME;
## inside, the timer drains at the same rate.
const ZONE_FULL_TIME := 20.0
const ZONE_SHRINK_TIME := 30.0
const ZONE_DEATH_TIME := 3.0

## OFF is free play (Training, the warm-up before the host starts): respawns as always, no rounds.
var phase := Phase.OFF
var phase_t := 0.0                 # seconds spent in the current phase
var round := 0                     # 1-based while a match runs
var target := DEFAULT_TARGET
var points: Array = []             # int per slot
var roster: Array = []             # bool per slot: who takes part, fixed at match start
var last_scorer := -1              # who scored the last round (-1: nobody)
var zone_t := 0.0                  # seconds of PLAY in this round so far (kept through RESULT, reset by the next round)
var zone_spot := 0                 # index into Config.ZONE_SPOTS: where the zone ends this round
var winner := -1                   # the match winner once MATCH_OVER (-1: none)
## Coins (numbers in `Economy`), per slot. `coins` is what a player has (saved over rounds, zeroed at match start);
## `earned` what the last finished round gave; `round_kills` / `leader_kills` count this round's kills (with kill
## credit) and the kills of a leader among them; `underdog` / `leader` are fixed at round start from the points.
var coins: Array = []
var earned: Array = []
var round_kills: Array = []
var leader_kills: Array = []
var underdog: Array = []
var leader: Array = []
## Coins a map handed out during this round (Piggy Bank), per slot; paid with the round's coins.
var bonus: Array = []
## The shop, per slot: `owned` modifier id -> copies (kept for the match); `offers` the current offers (ids, ""
## for one already bought); `shop_ready` done shopping; `shop_seq` counts shop actions, so a repeated request
## (a double tap, a resent message) is refused instead of buying or rerolling twice. `locked` is a bool per offer index
## (empty or shorter than `offers` = unlocked): a locked offer survives a reroll and the next shop; buying clears it.
## The build slots are the keys of `owned` in insertion order (the sell command names the id as well).
var owned: Array = []
var offers: Array = []
var locked: Array = []
var shop_ready: Array = []
var shop_seq: Array = []
## Map rotation (`Config.map == MAP_ROTATE`): a shuffled list of all map ids, `map_bag_i` the next to play. Each map
## comes once before any repeats; the list is reshuffled when used up (Sim does the drawing).
var map_bag: Array = []
var map_bag_i := 0


func _init() -> void:
	for i in Config.NUM_PLAYERS:
		points.append(0)
		roster.append(false)
		coins.append(0)
		earned.append(0)
		round_kills.append(0)
		leader_kills.append(0)
		underdog.append(false)
		leader.append(false)
		bonus.append(0)
		owned.append({})
		offers.append([])
		locked.append([])
		shop_ready.append(false)
		shop_seq.append(0)


## True while the world stands still (countdown, result screen, shop, match over).
func frozen() -> bool:
	return phase == Phase.COUNTDOWN or phase == Phase.RESULT or phase == Phase.MATCH_OVER or phase == Phase.SHOP


## True while a match is running and not over (countdown, play, result, shop): nobody new may join.
func running() -> bool:
	return phase == Phase.COUNTDOWN or phase == Phase.PLAY or phase == Phase.RESULT or phase == Phase.SHOP


## Modifier levels of slot `i` from its copies (id -> 1..3, only the owned ones).
func levels_of(i: int) -> Dictionary:
	var d := {}
	for id: String in owned[i]:
		d[id] = Mods.level_for_copies(owned[i][id])
	return d


## Can slot `i` take one more copy of `id`? Not beyond the top level, and a new modifier needs a free slot.
func can_take(i: int, id: String) -> bool:
	var copies: int = owned[i].get(id, 0)
	if copies >= Mods.COPIES_FOR_LEVEL[Mods.MAX_LEVEL - 1]:
		return false
	return copies > 0 or owned[i].size() < Economy.SLOTS


func is_locked(i: int, k: int) -> bool:
	return k >= 0 and k < locked[i].size() and locked[i][k]


## Coins selling modifier `id` of slot `i` gives back (half the price of every copy, rounded down); 0 if not owned.
func sell_refund(i: int, id: String) -> int:
	return int(owned[i].get(id, 0)) * Mods.price(id) / 2


## Rule hook: has the round ended?
func round_over(_sim: Sim) -> bool:
	return false


## Rule hook: the slot that scores for the finished round, -1 for nobody.
func round_scorer(_sim: Sim) -> int:
	return -1


## Rule hook: the slot that has won the match, -1 for not yet.
func match_winner(_sim: Sim) -> int:
	return -1


## Round start: clears this round's kill counts and decides underdog (all tied for the fewest points) and leader
## (all tied for the most) among the roster; nobody is either while everybody is level.
func begin_round_coins() -> void:
	var lo := 1 << 30
	var hi := -1
	for i in roster.size():
		round_kills[i] = 0
		leader_kills[i] = 0
		bonus[i] = 0
		if roster[i]:
			lo = mini(lo, points[i])
			hi = maxi(hi, points[i])
	for i in roster.size():
		underdog[i] = roster[i] and hi > lo and points[i] == lo
		leader[i] = roster[i] and hi > lo and points[i] == hi


## A kill with credit during a round (never a self-kill).
func note_kill(victim: int, killer: int) -> void:
	if killer < 0 or killer == victim or killer >= round_kills.size():
		return
	round_kills[killer] += 1
	if leader[victim]:
		leader_kills[killer] += 1


## What slot `i` gets for the round that just ended (`scorer`: who scored it, -1 nobody), by part:
## base, kills, survivor, underdog, leader, bonus (what a map paid, e.g. the piggy bank). Empty for a slot outside the roster.
func coin_parts(i: int, scorer: int) -> Dictionary:
	if not roster[i]:
		return {}
	return {
		"base": Economy.COINS_BASE,
		"kills": Economy.COINS_KILL * int(round_kills[i]),
		"survivor": Economy.COINS_SURVIVOR if i == scorer else 0,
		"underdog": Economy.COINS_UNDERDOG if underdog[i] else 0,
		"leader": Economy.COINS_LEADER_KILL * int(leader_kills[i]),
		"bonus": int(bonus[i]),
	}


## Round end: pays every roster player (also one who is away or left: the place is kept).
func award_coins(scorer: int) -> void:
	for i in roster.size():
		var sum := 0
		for v: int in coin_parts(i, scorer).values():
			sum += v
		earned[i] = sum
		coins[i] += sum
