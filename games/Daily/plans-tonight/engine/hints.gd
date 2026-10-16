class_name PTHints
extends RefCounted
## Progressive hints, all derived from the puzzle model.
##   1. the most restrictive friend
##   2. one plan that can't work (no reason given)
##   3. one specific conflict: this plan breaks this friend's rule
## `out` is the list of plan ids the player already knows are wrong (guessed or hinted).

const MAX := 3


## Friend whose rules rule out the most wrong plans (ties: more rules, then list order).
static func restrictive_friend(p: Dictionary) -> int:
	var best := 0
	var best_n := -1
	var best_r := -1
	for fi in p.friends.size():
		var seen := {}
		for r in p.friends[fi].rules:
			for d in PTValidate.elim(p, r):
				seen[d] = true
		var nr: int = p.friends[fi].rules.size()
		if seen.size() > best_n or (seen.size() == best_n and nr > best_r):
			best = fi
			best_n = seen.size()
			best_r = nr
	return best


## A wrong plan the player hasn't ruled out yet: the one the most clues rule out (the clearest).
static func eliminate(p: Dictionary, out: Array) -> int:
	var kills := PTValidate.kill_counts(p)
	var best := -1
	var best_k := -1
	for d in PTValidate.decoys(p):
		if d in out:
			continue
		if kills[d] > best_k:
			best = d
			best_k = kills[d]
	return best


## {plan, friend, rule} for a wrong plan not ruled out yet, preferring a near miss (a plan only
## one clue catches, the hardest to spot). Empty when every wrong plan is already ruled out.
static func conflict(p: Dictionary, out: Array) -> Dictionary:
	var kills := PTValidate.kill_counts(p)
	var pick := -1
	var pick_k := 99
	for d in PTValidate.decoys(p):
		if d in out:
			continue
		if kills[d] < pick_k:
			pick = d
			pick_k = kills[d]
	if pick < 0:
		return {}
	for fi in p.friends.size():
		var rules: Array = p.friends[fi].rules
		for ri in rules.size():
			if not PTRules.does(p.plans[pick], rules[ri]):
				return {"plan": pick, "friend": fi, "rule": ri}
	return {}
