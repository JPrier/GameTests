extends RefCounted
## Puzzle analysis: proves the drink set works as a deduction game.
##
## - duplicates(): drinks the six attributes can never tell apart (must be empty)
## - near_pairs(): drinks that differ in only one attribute (reported, allowed)
## - solve_steps(): guesses a perfect-information greedy player needs (each guess picks the drink
##   that splits the remaining candidates most evenly)
## - first_guess_stats(): how many drinks are still left after an arbitrary first guess, and how
##   often a single first guess already leaves only the answer ("trivially identifiable")
## - difficulty(): a 0-100 score built from those numbers plus how crowded the target's
##   neighbourhood is; the tier is the score's third among all eligible answers, so Easy, Medium
##   and Hard stay about the same size as the database grows
## - eligibility(): whether a drink may be a daily answer, with reasons when not
##
## Everything runs on a precomputed guess x target feedback matrix over the whole database, and
## the greedy choice is memoised per candidate set, so whole-database sweeps stay fast.

const Schema = preload("res://core/schema.gd")
const DB = preload("res://core/db.gd")
const Cmp = preload("res://core/compare.gd")

const TIERS := ["Easy", "Medium", "Hard"]
const TRIVIAL_SINGLE := 0.6     # reject when >= 60% of first guesses isolate the answer
const MAX_FAME := 2             # fame 3 would be "too obscure" for an answer

static var _cache: Dictionary = {}
static var _cuts: Array = []
static var _n := 0
static var _codes := PackedInt32Array()
static var _index: Dictionary = {}
static var _best_memo: Dictionary = {}


static func clear_cache() -> void:
	_cache = {}
	_cuts = []
	_codes = PackedInt32Array()
	_index = {}
	_best_memo = {}
	_n = 0


# ------------------------------------------------------------------ feedback matrix

static func _ensure_matrix() -> void:
	var all := DB.all()
	if _n == all.size() and _codes.size() == _n * _n:
		return
	_n = all.size()
	_index = {}
	for i in _n:
		_index[all[i].id] = i
	_codes.resize(_n * _n)
	for g in _n:
		for t in _n:
			var fb := Cmp.compare(all[g], all[t])
			var c := 0
			for k in range(fb.size() - 1, -1, -1):
				c = c * 5 + fb[k]
			_codes[g * _n + t] = c


static func idx(d: Dictionary) -> int:
	_ensure_matrix()
	return int(_index[d.id])


## Feedback code (all six attributes packed in one int) for guess index g against target index t.
static func code(g: int, t: int) -> int:
	return _codes[g * _n + t]


static func _all_indices() -> PackedInt32Array:
	_ensure_matrix()
	var out := PackedInt32Array()
	out.resize(_n)
	for i in _n:
		out[i] = i
	return out


# ------------------------------------------------------------------ similarity

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


# ------------------------------------------------------------------ greedy solver

## Expected number of candidates left after guessing g (lower is better); cands are indices.
static func _expected_left(g: int, cands: PackedInt32Array) -> float:
	var counts := {}
	for c in cands:
		if c == g:
			continue
		var k := code(g, c)
		counts[k] = int(counts.get(k, 0)) + 1
	var s := 0.0
	for k in counts:
		s += float(counts[k]) * counts[k]
	return s / maxf(1.0, cands.size())


## The most informative guess index; ties prefer a guess that could win, then database order.
static func _best(cands: PackedInt32Array) -> int:
	if cands.size() == 1:
		return cands[0]
	var key := ",".join(Array(cands).map(func(x): return str(x)))
	if _best_memo.has(key):
		return _best_memo[key]
	var in_set := {}
	for c in cands:
		in_set[c] = true
	var best := -1
	var best_s := INF
	for g in _n:
		var s := _expected_left(g, cands) - (0.001 if in_set.has(g) else 0.0)
		if s < best_s - 1e-9:
			best_s = s
			best = g
	_best_memo[key] = best
	return best


static func best_guess(cands: Array) -> Dictionary:
	_ensure_matrix()
	var ids := PackedInt32Array()
	for c in cands:
		ids.append(int(_index[c.id]))
	return DB.all()[_best(ids)]


## The guesses (ids) a perfect-information greedy player makes, ending with the target.
static func solve_path(target: Dictionary, opener: Dictionary = {}) -> Array:
	_ensure_matrix()
	var all := DB.all()
	var t := int(_index[target.id])
	var cands := _all_indices()
	var path: Array = []
	for step in 12:
		var g: int = int(_index[opener.id]) if (step == 0 and not opener.is_empty()) else _best(cands)
		path.append(all[g].id)
		if g == t:
			return path
		var f := code(g, t)
		var next := PackedInt32Array()
		for c in cands:
			if c != g and code(g, c) == f:
				next.append(c)
		cands = next
	return path


static func solve_steps(target: Dictionary) -> int:
	return solve_path(target).size()


# ------------------------------------------------------------------ difficulty

## {avg_left, single}: average candidates left (answer included) after each possible wrong
## first guess, and the share of those guesses that leave only the answer.
static func first_guess_stats(target: Dictionary) -> Dictionary:
	_ensure_matrix()
	var t := int(_index[target.id])
	var total := 0
	var single := 0
	var n := 0
	for g in _n:
		if g == t:
			continue
		var f := code(g, t)
		var left := 0
		for c in _n:
			if c != g and code(g, c) == f:
				left += 1
		total += left
		if left == 1:
			single += 1
		n += 1
	return {"avg_left": float(total) / maxi(1, n), "single": float(single) / maxi(1, n)}


## Drinks within two attributes of the target: the look-alikes a player has to rule out.
static func crowd(target: Dictionary) -> int:
	var n := 0
	for d in DB.all():
		if d.id != target.id and distance(d, target) <= 2:
			n += 1
	return n


## {score 0-100, steps, avg_left, single, crowd} without a tier. Cached per drink.
static func _scored(target: Dictionary) -> Dictionary:
	if _cache.has(target.id):
		return _cache[target.id]
	var steps := solve_steps(target)
	var st := first_guess_stats(target)
	var cr := crowd(target)
	var score := 0.0
	score += clampf((steps - 1) / 4.0, 0.0, 1.0) * 30.0                 # 1..5 steps
	score += clampf((st.avg_left - 1.5) / 8.5, 0.0, 1.0) * 35.0          # 1.5..10 left
	score += clampf(cr / 16.0, 0.0, 1.0) * 25.0                          # look-alikes
	score += (1.0 - st.single) * 10.0
	if target.get("fame", 1) >= 2:
		score += 5.0                                                     # less famous answer
	var out := {"score": int(round(clampf(score, 0.0, 100.0))), "steps": steps,
		"avg_left": st.avg_left, "single": st.single, "crowd": cr}
	_cache[target.id] = out
	return out


## Score cut points between Easy|Medium and Medium|Hard: the thirds of all eligible answers.
static func cuts() -> Array:
	if _cuts.is_empty():
		var scores: Array = []
		for d in DB.all():
			if eligibility(d).ok:
				scores.append(int(_scored(d).score))
		scores.sort()
		if scores.is_empty():
			_cuts = [0, 0]
		else:
			_cuts = [scores[scores.size() / 3], scores[(scores.size() * 2) / 3]]
	return _cuts


static func tier_for_score(score: int) -> int:
	var c := cuts()
	if score < int(c[0]):
		return 0
	if score < int(c[1]):
		return 1
	return 2


## {score 0-100, tier 0-2, steps, avg_left, single, crowd}.
static func difficulty(target: Dictionary) -> Dictionary:
	var out: Dictionary = _scored(target).duplicate()
	out.tier = tier_for_score(out.score)
	return out


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
