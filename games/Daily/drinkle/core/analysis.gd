extends RefCounted
## Puzzle analysis: proves the drink set works as a deduction game.
##
## - duplicates(): drinks the six attributes can never tell apart (must be empty)
## - near_pairs(): drinks that differ in only one attribute (reported, allowed)
## - solve_steps(): guesses a perfect-information greedy player needs (each guess picks the drink
##   that splits the remaining candidates most evenly)
## - first_guess_stats(): how many drinks are still left after an arbitrary first guess, and how
##   often a single first guess already leaves only the answer ("trivially identifiable")
## - difficulty(): a 0-100 score and tier built from those numbers plus how crowded the target's
##   neighbourhood is
## - eligibility(): whether a drink may be a daily answer, with reasons when not

const Schema = preload("res://core/schema.gd")
const DB = preload("res://core/db.gd")
const Cmp = preload("res://core/compare.gd")
const Cands = preload("res://core/candidates.gd")

const TIERS := ["Easy", "Medium", "Hard"]
const TRIVIAL_SINGLE := 0.6     # reject when >= 60% of first guesses isolate the answer
const MAX_FAME := 2             # fame 3 would be "too obscure" for an answer

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache = {}


static func distance(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	for id in Schema.ids():
		if a.get(id) != b.get(id):
			n += 1
	return n


static func duplicates(pool: Array = []) -> Array:
	if pool.is_empty():
		pool = DB.all()
	var seen := {}
	for d in pool:
		var k := DB.profile_key(d)
		if not seen.has(k):
			seen[k] = []
		seen[k].append(d.id)
	var out: Array = []
	for k in seen:
		if seen[k].size() > 1:
			out.append(seen[k])
	return out


static func near_pairs(max_diff: int = 1, pool: Array = []) -> Array:
	if pool.is_empty():
		pool = DB.all()
	var out: Array = []
	for i in pool.size():
		for j in range(i + 1, pool.size()):
			var dd := distance(pool[i], pool[j])
			if dd <= max_diff:
				var diff: Array = []
				for id in Schema.ids():
					if pool[i].get(id) != pool[j].get(id):
						diff.append(id)
				out.append({"a": pool[i].id, "b": pool[j].id, "diff": diff})
	return out


## How the candidates split by feedback for one guess: key -> count.
static func partition(guess: Dictionary, cands: Array) -> Dictionary:
	var p := {}
	for c in cands:
		var k: String = "WIN" if c.id == guess.id else Cmp.key(Cmp.compare(guess, c))
		p[k] = int(p.get(k, 0)) + 1
	return p


## Expected number of candidates left after this guess (lower is better).
static func expected_left(guess: Dictionary, cands: Array) -> float:
	var p := partition(guess, cands)
	var s := 0.0
	for k in p:
		if k != "WIN":
			s += float(p[k]) * p[k]
	return s / maxf(1.0, cands.size())


## The most informative guess; ties prefer a guess that could win, then database order.
static func best_guess(cands: Array, pool: Array = []) -> Dictionary:
	if cands.size() == 1:
		return cands[0]
	if pool.is_empty():
		pool = DB.all()
	var ids := {}
	for c in cands:
		ids[c.id] = true
	var best: Dictionary = {}
	var best_s := INF
	for g in pool:
		var s := expected_left(g, cands) - (0.001 if ids.has(g.id) else 0.0)
		if s < best_s - 1e-9:
			best_s = s
			best = g
	return best


## The guesses a perfect-information greedy player makes, ending with the target.
static func solve_path(target: Dictionary, opener: Dictionary = {}, pool: Array = []) -> Array:
	if pool.is_empty():
		pool = DB.all()
	var history: Array = []
	var cands: Array = pool
	var path: Array = []
	for step in 12:
		var g: Dictionary = opener if (step == 0 and not opener.is_empty()) else best_guess(cands, pool)
		path.append(g.id)
		if g.id == target.id:
			return path
		history.append(Cands.entry(g.id, target))
		cands = Cands.remaining(history, [], pool)
	return path


static func solve_steps(target: Dictionary) -> int:
	return solve_path(target).size()


## {avg_left, single}: average candidates left (answer included) after each possible wrong
## first guess, and the share of those guesses that leave only the answer.
static func first_guess_stats(target: Dictionary, pool: Array = []) -> Dictionary:
	if pool.is_empty():
		pool = DB.all()
	var total := 0
	var single := 0
	var n := 0
	for g in pool:
		if g.id == target.id:
			continue
		var fb := Cmp.compare(g, target)
		var left := 0
		for c in pool:
			if c.id != g.id and Cmp.compare(g, c) == fb:
				left += 1
		total += left
		if left == 1:
			single += 1
		n += 1
	return {"avg_left": float(total) / maxi(1, n), "single": float(single) / maxi(1, n)}


## Drinks within two attributes of the target: the look-alikes a player has to rule out.
static func crowd(target: Dictionary, pool: Array = []) -> int:
	if pool.is_empty():
		pool = DB.all()
	var n := 0
	for d in pool:
		if d.id != target.id and distance(d, target) <= 2:
			n += 1
	return n


## {score 0-100, tier 0-2, steps, avg_left, single, crowd}. Cached per drink.
static func difficulty(target: Dictionary) -> Dictionary:
	if _cache.has(target.id):
		return _cache[target.id]
	var steps := solve_steps(target)
	var st := first_guess_stats(target)
	var cr := crowd(target)
	var score := 0.0
	score += clampf((steps - 1) / 3.0, 0.0, 1.0) * 30.0                 # 1..4 steps
	score += clampf((st.avg_left - 1.5) / 5.5, 0.0, 1.0) * 35.0          # 1.5..7 left
	score += clampf(cr / 12.0, 0.0, 1.0) * 25.0                          # look-alikes
	score += (1.0 - st.single) * 10.0
	if target.get("fame", 1) >= 2:
		score += 5.0                                                     # less famous answer
	score = clampf(score, 0.0, 100.0)
	var out := {"score": int(round(score)), "steps": steps, "avg_left": st.avg_left,
		"single": st.single, "crowd": cr}
	out.tier = tier_for_score(out.score)
	_cache[target.id] = out
	return out


static func tier_for_score(score: int) -> int:
	if score < 45:
		return 0
	if score < 60:
		return 1
	return 2


## {ok, reasons[]}: may this drink be a daily answer?
static func eligibility(target: Dictionary) -> Dictionary:
	var reasons: Array = []
	if not target.target:
		reasons.append("disputed: " + String(target.get("why", "")))
	if int(target.fame) > MAX_FAME:
		reasons.append("too obscure")
	for group in duplicates():
		if group.has(target.id):
			reasons.append("indistinguishable from " + ", ".join(group.filter(func(x): return x != target.id)))
	if reasons.is_empty():
		var st := first_guess_stats(target)
		if st.single >= TRIVIAL_SINGLE:
			reasons.append("trivial: %d%% of first guesses already leave only this drink" % int(st.single * 100))
	return {"ok": reasons.is_empty(), "reasons": reasons}


## Every eligible daily answer, grouped by tier: [[easy ids], [medium ids], [hard ids]].
static func tier_pools() -> Array:
	var pools: Array = [[], [], []]
	for d in DB.all():
		if eligibility(d).ok:
			pools[int(difficulty(d).tier)].append(d.id)
	for p in pools:
		p.sort()
	return pools
