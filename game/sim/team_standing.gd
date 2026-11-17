class_name TeamStanding
extends LastStanding
## Teams: two teams (0 Red, 1 Blue) fight in Last Standing rounds. Nobody can hurt a teammate (the train, the zone,
## lava and an own blast still do). A round ends when at most one team has a living player of the roster; that team
## scores one point for EVERY member (dead or away included); if both are wiped out in the same tick nobody scores.
## The first team to `target` points wins. `last_scorer` and `winner` hold a TEAM index here, not a slot (use
## `scored(i)` / `won(i)`).

const TEAM_COUNT := 2
const NAMES: Array[String] = ["Red", "Blue"]
## Palette indices (`ArenaView.PLAYER_COLORS`: 0 pink, 1 cyan, 2 lime, 3 orange, 4 purple, 5 yellow, 6 red, 7 blue) of
## each team: warm colours for Red, cool ones for Blue. Both halves have four, so a team of four never runs out.
const COLOR_HALVES: Array = [[0, 3, 5, 6], [1, 2, 4, 7]]

## Team of every slot (snapshot state): slot i starts on team i % 2, `Sim.swap_team` exchanges two.
var team: Array = []


func _init() -> void:
	super()
	for i in Config.NUM_PLAYERS:
		team.append(i % TEAM_COUNT)


## Players of a Teams match: even (2v2, 3v3, 4v4); an odd number snaps up. The one place that decides it.
static func even_count(n: int) -> int:
	var k := clampi(n, Config.MIN_PLAYERS, Config.NUM_PLAYERS)
	return mini(k + (k % 2), Config.NUM_PLAYERS)


func harms(a: int, v: int) -> bool:
	return a == v or team[a] != team[v]


func scores(i: int, scorer: int) -> bool:
	return scorer >= 0 and i >= 0 and i < team.size() and team[i] == scorer


func is_team_mode() -> bool:
	return true


func team_of(i: int) -> int:
	return team[i] if i >= 0 and i < team.size() else -1


func allowed_colors(i: int) -> Array:
	return COLOR_HALVES[team_of(i)]


func survivor_label() -> String:
	return "team win"


func won(i: int) -> bool:
	return winner >= 0 and scores(i, winner)


## Points of a team: what each of its roster members has (they all score together).
func team_points(t: int) -> int:
	var best := 0
	for i in points.size():
		if roster[i] and team[i] == t:
			best = maxi(best, points[i])
	return best


## Teams that have a living, enabled roster player.
func _alive_teams(sim: Sim) -> Array:
	var out: Array = []
	for i in _alive_roster(sim):
		if not out.has(team[i]):
			out.append(team[i])
	return out


func round_over(sim: Sim) -> bool:
	return _alive_teams(sim).size() <= 1


func round_scorer(sim: Sim) -> int:
	var alive := _alive_teams(sim)
	return alive[0] if alive.size() == 1 else -1


func match_winner(_sim: Sim) -> int:
	var best := -1
	var best_p := 0
	for t in TEAM_COUNT:
		var p := team_points(t)
		if p >= target and p > best_p:
			best = t
			best_p = p
	return best
