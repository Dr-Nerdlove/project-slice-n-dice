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
