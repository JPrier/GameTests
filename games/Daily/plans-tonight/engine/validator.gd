class_name PTValidate
extends RefCounted
## Puzzle checks. A puzzle is {plans: [...], friends: [{rules: [...], ...}], target: plan id}.
## Plan ids are their index in `plans`.


## Every (friend, rule) pair as [friend_index, rule_index, rule].
static func all_rules(p: Dictionary) -> Array:
	var out: Array = []
	for fi in p.friends.size():
		var f: Dictionary = p.friends[fi]
		for ri in f.rules.size():
			out.append([fi, ri, f.rules[ri]])
	return out


## Plans that satisfy every rule. Pass `skip` = [fi, ri] to ignore one rule.
static func solutions(p: Dictionary, skip: Array = []) -> Array:
	var out: Array = []
	for plan in p.plans:
		var ok := true
		for fi in p.friends.size():
			var rules: Array = p.friends[fi].rules
			for ri in rules.size():
				if skip.size() == 2 and skip[0] == fi and skip[1] == ri:
					continue
				if not PTRules.does(plan, rules[ri]):
					ok = false
					break
			if not ok:
				break
		if ok:
			out.append(int(plan.id))
	return out


static func decoys(p: Dictionary) -> Array:
	var out: Array = []
	for plan in p.plans:
		if int(plan.id) != int(p.target):
			out.append(int(plan.id))
	return out


## Wrong plans this rule rules out.
static func elim(p: Dictionary, rule: Dictionary) -> Array:
	var out: Array = []
	for plan in p.plans:
		if int(plan.id) != int(p.target) and not PTRules.does(plan, rule):
			out.append(int(plan.id))
	return out


## How many rules each wrong plan breaks: {plan_id: count}.
static func kill_counts(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for d in decoys(p):
		out[d] = 0
	for e in all_rules(p):
		for d in elim(p, e[2]):
			out[d] += 1
	return out


## A rule is necessary when dropping it lets a second plan through.
static func necessary(p: Dictionary, fi: int, ri: int) -> bool:
	return solutions(p, [fi, ri]).size() > 1


## Rules that could be removed without changing the answer.
static func redundant(p: Dictionary) -> Array:
	var out: Array = []
	for e in all_rules(p):
		if not necessary(p, e[0], e[1]):
			out.append([e[0], e[1]])
	return out


## Pairs of rules no plan could ever satisfy together: [[fa, ra, fb, rb], ...].
static func contradictions(p: Dictionary) -> Array:
	var out: Array = []
	var rs := all_rules(p)
	for i in rs.size():
		for j in range(i + 1, rs.size()):
			if PTRules.contradicts(rs[i][2], rs[j][2]):
				out.append([rs[i][0], rs[i][1], rs[j][0], rs[j][1]])
	return out


## Everything wrong with a puzzle; empty means it's good to ship.
static func problems(p: Dictionary) -> Array:
	var probs: Array = []
	var n: int = p.plans.size()
	var nf: int = p.friends.size()
	if n < 4 or n > 8:
		probs.append("plan count %d" % n)
	if nf < 3 or nf > 6:
		probs.append("friend count %d" % nf)
	var sols := solutions(p)
	if sols.size() == 0:
		probs.append("no plan works")
	elif sols.size() > 1:
		probs.append("%d plans work" % sols.size())
	elif sols[0] != int(p.target):
		probs.append("answer is not the target")
	var ds := decoys(p)
	var rs := all_rules(p)
	for e in rs:
		var ex := elim(p, e[2])
		if ex.size() >= ds.size():
			probs.append("one clue gives it away: %s" % PTRules.text(e[2]))
	if redundant(p).size() > 0:
		probs.append("%d redundant clue(s)" % redundant(p).size())
	# One friend alone shouldn't settle it either: the group has to be combined.
	for fi in nf:
		var seen := {}
		for r in p.friends[fi].rules:
			for d in elim(p, r):
				seen[d] = true
		if seen.size() >= ds.size():
			probs.append("%s alone gives it away" % p.friends[fi].get("name", str(fi)))
	var kills := kill_counts(p)
	var m := rs.size()
	for d in kills:
		if m >= 3 and kills[d] >= maxi(3, ceili(0.75 * m)):
			probs.append("%s is ruled out by nearly every clue" % p.plans[d].name)
	var naming := rs.filter(func(e): return e[2].type in ["no_activity", "no_food_type"]).size()
	if naming > 1:
		probs.append("%d clues just name a plan" % naming)
	if contradictions(p).size() > 0:
		probs.append("contradictory clues")
	var names := {}
	for f in p.friends:
		if f.rules.is_empty() or f.rules.size() > 3:
			probs.append("%s has %d rules" % [f.get("name", "?"), f.rules.size()])
		var types := {}
		for r in f.rules:
			if types.has(r.type):
				probs.append("%s repeats a rule type" % f.get("name", "?"))
			types[r.type] = true
		names[f.get("name", "")] = true
	if names.size() != nf:
		probs.append("duplicate friend names")
	var plan_names := {}
	for plan in p.plans:
		plan_names[plan.name] = true
	if plan_names.size() != n:
		probs.append("duplicate plan names")
	return probs
