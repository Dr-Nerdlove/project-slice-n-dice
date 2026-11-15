class_name LastStanding
extends MatchMode
## Last Standing: a round ends when at most one player of the roster is alive; the survivor scores a point
## (nobody if the last players died in the same tick). First to `target` points wins the match.


func _alive_roster(sim: Sim) -> Array:
	var out: Array = []
	for i in sim.players.size():
		var p := sim.players[i]
		if roster[i] and p.enabled and p.alive:
			out.append(i)
	return out


func round_over(sim: Sim) -> bool:
	return _alive_roster(sim).size() <= 1


func round_scorer(sim: Sim) -> int:
	var alive := _alive_roster(sim)
	return alive[0] if alive.size() == 1 else -1


func match_winner(_sim: Sim) -> int:
	var best := -1
	for i in points.size():
		if points[i] >= target and (best < 0 or points[i] > points[best]):
			best = i
	return best
