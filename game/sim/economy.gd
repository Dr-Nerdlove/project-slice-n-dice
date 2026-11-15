class_name Economy
extends RefCounted
## The ONE table of the match economy (coins now, the shop's numbers later): every number lives here so it can be
## tuned in play. Fixed match rules, not `Config` values: Play never sees tuned values. Prices of the modifiers are
## in `Mods.PRICES`. Rules (docs/PLAN.md, section 5): every roster player gets COINS_BASE at the end of every round,
## plus COINS_KILL per kill, COINS_SURVIVOR for scoring the round, COINS_UNDERDOG for being in last place and
## COINS_LEADER_KILL per kill of a leader. Underdog and leader are decided by points at the start of the round
## (ties count, nobody while everybody is level). A death without a killer (train, zone, own explosion) gives nothing.

const COINS_BASE := 3
const COINS_KILL := 1
const COINS_SURVIVOR := 2
const COINS_UNDERDOG := 2
const COINS_LEADER_KILL := 1

## The shop between rounds (phase SHOP): everybody shops at the same time for SHOP_TIME seconds or until all are
## ready. OFFERS random modifiers per player; REROLL_PRICE draws new ones. A player holds at most SLOTS different
## modifiers; buying one again adds a copy (levels by copies: `Mods.COPIES_FOR_LEVEL`).
const SHOP_TIME := 20.0
const OFFERS := 3
const REROLL_PRICE := 1
const SLOTS := 5
## Bots shop this long after the shop opens (so a human sees them in it for a moment), and reroll at most this often.
const BOT_SHOP_DELAY := 1.5
const BOT_REROLLS := 2
