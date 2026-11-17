class_name HotPotato
extends LastStanding
## Hot Potato (free for all): one player at a time carries a bomb with a fuse. The carrier passes it on by hitting
## someone (with the yo-yo or any attack of his modifiers): the victim is not hurt and carries it now. When the fuse
## runs out the carrier dies (credit to the last passer). Yo-yo hits are never lethal in this mode; a hit by anyone
## else only stuns. Only the bomb and the hazards of the map kill. The round ends like Last Standing (the last
## player alive scores). No randomness in the numbers: who gets a bomb is the only dice roll.
## Everything here is state in the snapshot (the numbers below are fixed match rules, not `Config`).

const FUSE_BASE := 8.0           # seconds of fuse ...
const FUSE_PER_PLAYER := 2.0     # ... plus this much per player alive when the bomb is given out
const BOMB_GAP := 2.0            # seconds between a bomb being gone and the next one
const TAGBACK_TIME := 1.5        # seconds in which the bomb cannot go back to the player who just passed it
const CARRIER_SPEED := 1.15      # walking speed factor of the carrier
const POTATO_STUN := 0.6         # stun of a hit that does not pass the bomb (not while already stunned)
const BLINK_TIME := 3.0          # the view: the bomb blinks in the last seconds of the fuse

var bomb_holder := -1            # slot that carries the bomb, -1 none
var bomb_t := 0.0                # fuse left
var bomb_fuse := 0.0             # full fuse of this bomb (fixed when it was given out)
var bomb_gap := 0.0              # seconds until the next bomb while there is none
var bomb_from := -1              # the last passer (-1: the bomb was given out by the game)
var tagback_t := 0.0             # seconds left in which `bomb_from` cannot take the bomb back


## Full fuse for `alive` players: the same every time, no dice.
static func fuse_for(alive: int) -> float:
	return FUSE_BASE + FUSE_PER_PLAYER * alive


func uses_zone() -> bool:
	return false


func own_blast_kills() -> bool:
	return false


func speed_mult(i: int) -> float:
	return CARRIER_SPEED if i == bomb_holder and phase == Phase.PLAY else 1.0


## True while the bomb cannot go to `i` because `i` just passed it.
func tagback_locked(i: int) -> bool:
	return tagback_t > 0.0 and i == bomb_from


## A new round: no bomb yet (the first one comes with the first tick of PLAY).
func begin_round_coins() -> void:
	super()
	bomb_holder = -1
	bomb_t = 0.0
	bomb_fuse = 0.0
	bomb_gap = 0.0
	bomb_from = -1
	tagback_t = 0.0


## In a round no hit kills. The carrier's hit passes the bomb (not back to the passer within TAGBACK_TIME: a stun
## then); a hit by anybody else stuns. Outside a round (free play) hits kill as in Last Standing.
func on_hit(sim: Sim, a: int, v: int) -> bool:
	if phase != Phase.PLAY:
		return harms(a, v)
	if a == bomb_holder and not tagback_locked(v):
		bomb_holder = v
		bomb_from = a
		tagback_t = TAGBACK_TIME
		sim.events.append({"type": "bomb_pass", "from": a, "to": v})
		return false
	if v == bomb_holder and a == bomb_from and tagback_t > 0.0:
		return false   # the passer's own yo-yo still on the new carrier: nothing
	var victim := sim.players[v]
	if victim.stun_t <= 0.0:
		sim._stun(victim, POTATO_STUN)
	return false


func step(sim: Sim, dt: float) -> void:
	tagback_t = maxf(0.0, tagback_t - dt)
	if bomb_holder >= 0:
		var c := sim.players[bomb_holder]
		if not (c.enabled and c.alive):
			_bomb_gone()   # died another way (train, lava): the bomb is gone
			return
		bomb_t -= dt
		if bomb_t <= 0.0:
			bomb_t = 0.0
			sim.events.append({"type": "bomb_explode", "pos": c.pos, "victim": c.id})
			var killer: SimPlayer = null
			if bomb_from >= 0 and bomb_from != c.id:
				killer = sim.players[bomb_from]
			sim._kill(c, killer, "bomb")
			_bomb_gone()
		return
	var alive := _alive_roster(sim)
	if alive.size() < 2:
		return
	bomb_gap -= dt
	if bomb_gap > 0.0:
		return
	bomb_holder = alive[sim.rng.randi_range(0, alive.size() - 1)]
	bomb_fuse = fuse_for(alive.size())
	bomb_t = bomb_fuse
	bomb_from = -1
	tagback_t = 0.0


func _bomb_gone() -> void:
	bomb_holder = -1
	bomb_t = 0.0
	bomb_from = -1
	tagback_t = 0.0
	bomb_gap = BOMB_GAP
