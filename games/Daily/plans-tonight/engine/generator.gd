class_name PTGen
extends RefCounted
## Deterministic puzzle generator.
##   1. make candidate plans with structured attributes
##   2. pick the target plan
##   3. list every rule the target passes, with the wrong plans each one rules out
##   4. choose rules until every wrong plan is ruled out (a set cover)
##   5. drop rules that aren't needed, so every clue matters
##   6. hand the rules out to friends and give them personalities
##   7. validate + score difficulty; re-roll (deterministically) until it fits the day
## Every random choice comes from an RNG seeded by the date, so all players get the same puzzle.

const MAX_ATTEMPTS := 600
const TYPE_WEIGHT := {
	"max_price": 3.0, "min_start": 2.5, "max_start": 1.5, "max_end": 2.5, "min_end": 1.2,
	"max_travel": 2.5, "setting": 2.0, "wants_food": 2.0, "no_food_type": 1.2, "no_activity": 1.0,
	"not_loud": 1.6, "not_quiet": 1.2, "max_duration": 1.4, "min_duration": 1.2,
}
const MAX_DINNERS := 3
const NAMING := ["no_activity", "no_food_type"]


static func generate(date: String) -> Dictionary:
	var p := generate_with(PTDaily.config(date), PTDaily.seed_key(date))
	p.date = date
	return p


static func generate_with(cfg: Dictionary, key: String) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := 99
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s#%d" % [key, attempt])
		var p := attempt_puzzle(rng, cfg)
		if p.is_empty() or not PTValidate.problems(p).is_empty():
			continue
		var d := PTDifficulty.analyse(p)
		p.difficulty = d
		p.attempt = attempt
		p.seed = hash(key)
		var gap := absi(PTDifficulty.rank(String(d.label)) - PTDifficulty.rank(String(cfg.label)))
		if gap == 0:
			return p
		if gap < best_gap:
			best_gap = gap
			best = p
	return best


## One try with a given RNG. Returns {} when this roll can't make a good puzzle.
static func attempt_puzzle(rng: RandomNumberGenerator, cfg: Dictionary) -> Dictionary:
	var plans := make_plans(rng, int(cfg.plans))
	if plans.is_empty():
		return {}
	var target := rng.randi_range(0, plans.size() - 1)
	var probe := {"plans": plans, "target": target, "friends": []}
	var cands := candidates(rng, plans, target, cfg.types)
	var chosen := cover(rng, cands, PTValidate.decoys(probe), float(cfg.max_elim), bool(cfg.small))
	if chosen.is_empty():
		return {}
	chosen = minimize(rng, chosen, PTValidate.decoys(probe))
	var m := chosen.size()
	if m < 3:
		return {}
	var nf := clampi(int(cfg.friends), 3, m)
	while nf * 2 < m and nf < 6:
		nf += 1
	if nf * 3 < m:
		return {}
	var friends := assign(rng, chosen, nf, String(cfg.theme))
	if friends.is_empty():
		return {}
	return {"plans": plans, "friends": friends, "target": target, "theme": String(cfg.theme)}


# ---------------------------------------------------------------- 1. plans

static func make_plans(rng: RandomNumberGenerator, n: int) -> Array:
	var pool: Array = PTCatalog.TEMPLATES.duplicate()
	var picked: Array = []
	var dinners := 0
	var guard := 0
	while picked.size() < n and guard < 200:
		guard += 1
		var t: Dictionary = _weighted(rng, pool, func(x): return float(x.w))
		if t.is_empty():
			break
		pool.erase(t)
		if t.activity == "Dinner":
			if dinners >= MAX_DINNERS:
				continue
			dinners += 1
		picked.append(t)
	# Need at least one dinner and one thing to do, or it isn't much of a night out.
	if dinners == 0 or dinners == picked.size() or picked.size() < n:
		return []
	_shuffle(rng, picked)
	var plans: Array = []
	var names := {}
	for t in picked:
		var plan := make_plan(rng, t)
		if names.has(plan.name):
			return []
		names[plan.name] = true
		plan.id = plans.size()
		plans.append(plan)
	return plans


static func make_plan(rng: RandomNumberGenerator, t: Dictionary) -> Dictionary:
	var settings: Array = []
	if not t["in"].is_empty():
		settings.append("indoor")
	if not t["out"].is_empty():
		settings.append("outdoor")
	var setting: String = settings[rng.randi_range(0, settings.size() - 1)]
	var names: Array = t["in"] if setting == "indoor" else t["out"]
	var food: String = t.food[rng.randi_range(0, t.food.size() - 1)]
	var price := rng.randi_range(int(t.price[0]), int(t.price[1]))
	if price % 5 == 0:  # never sit exactly on a "$X max" threshold
		price += 1 if price < int(t.price[1]) else -1
	var lo := int(t.start[0]) / 30
	var hi := int(t.start[1]) / 30
	var start := rng.randi_range(lo, hi) * 30
	var dur: int = t.dur[rng.randi_range(0, t.dur.size() - 1)]
	if start + dur > 24 * 60:
		start = 24 * 60 - dur
	return {
		"id": 0, "key": t.key, "name": names[rng.randi_range(0, names.size() - 1)], "icon": t.icon,
		"activity": t.activity, "food": food, "price": price, "start": start, "end": start + dur,
		"travel": PTCatalog.TRAVEL[rng.randi_range(0, PTCatalog.TRAVEL.size() - 1)],
		"setting": setting, "noise": t.noise[rng.randi_range(0, t.noise.size() - 1)],
	}


# ---------------------------------------------------------------- 3. candidate rules

static func values_for(type: String, plans: Array) -> Array:
	match type:
		"max_price": return range(10, 101, 5)
		"min_start": return range(18 * 60, 22 * 60 + 1, 30)
		"max_start": return range(18 * 60 + 30, 21 * 60 + 1, 30)
		"max_end": return range(20 * 60, 24 * 60, 30)
		"min_end": return range(21 * 60, 24 * 60 + 1, 30)
		"max_travel": return range(10, 41, 5)
		"setting": return ["indoor", "outdoor"]
		"max_duration", "min_duration": return [60, 90, 120, 150, 180]
		"wants_food", "not_loud", "not_quiet": return [true]
		"no_food_type":
			var foods := {}
			for p in plans:
				if p.food != "":
					foods[p.food] = true
			return foods.keys()
		"no_activity":
			var acts := {}
			for p in plans:
				acts[p.activity] = true
			return acts.keys()
	return []


## Rules the target passes, each with the wrong plans it rules out. Rules that rule out the
## same plans are merged, keeping a random threshold that no plan sits exactly on (if any).
static func candidates(rng: RandomNumberGenerator, plans: Array, target: int, types: Array) -> Array:
	var groups := {}
	var order: Array = []
	for type in types:
		for v in values_for(type, plans):
			var r := {"type": type, "v": v}
			if not PTRules.does(plans[target], r):
				continue
			var e: Array = []
			for p in plans:
				if int(p.id) != target and not PTRules.does(p, r):
					e.append(int(p.id))
			if e.is_empty():
				continue
			var gk := "%s:%s" % [type, str(e)]
			if not groups.has(gk):
				groups[gk] = []
				order.append(gk)
			groups[gk].append({"type": type, "v": v, "elim": e, "edge": on_edge(r, plans)})
	var out: Array = []
	for gk in order:
		var opts: Array = groups[gk]
		var clean := opts.filter(func(c): return not c.edge)
		var from: Array = clean if not clean.is_empty() else opts
		out.append(from[rng.randi_range(0, from.size() - 1)])
	return out


## True when some plan sits exactly on the rule's threshold (legal, but easy to misread).
static func on_edge(r: Dictionary, plans: Array) -> bool:
	for p in plans:
		match String(r.type):
			"max_price":
				if int(p.price) == int(r.v): return true
			"min_start", "max_start":
				if int(p.start) == int(r.v): return true
			"max_end", "min_end":
				if int(p.end) == int(r.v): return true
			"max_travel":
				if int(p.travel) == int(r.v): return true
			"max_duration", "min_duration":
				if PTRules.duration(p) == int(r.v): return true
	return false


# ---------------------------------------------------------------- 4–5. cover + minimise

static func cover(rng: RandomNumberGenerator, cands: Array, decoys: Array, max_elim: float, small: bool) -> Array:
	var limit := mini(maxi(1, ceili(max_elim * decoys.size())), decoys.size() - 1)
	var pool := cands.filter(func(c): return c.elim.size() <= limit)
	var uncovered := decoys.duplicate()
	_shuffle(rng, uncovered)
	var chosen: Array = []
	var used := {}
	while not uncovered.is_empty():
		var d: int = uncovered[0]
		# At most one clue that just names a plan ("won't eat sushi", "refuses karaoke"): they're
		# fair but cheap, and a puzzle made of them is a matching exercise, not a deduction.
		var named := chosen.any(func(c): return c.type in NAMING)
		var opts := pool.filter(func(c): return d in c.elim and not chosen.has(c) and not (named and c.type in NAMING))
		if opts.is_empty():
			return []
		var c: Dictionary = _weighted(rng, opts, func(x):
			var w: float = TYPE_WEIGHT.get(x.type, 1.0) / (1.0 + 2.0 * used.get(x.type, 0))
			return w / x.elim.size() if small else w * (1.0 + 0.25 * x.elim.size()))
		chosen.append(c)
		used[c.type] = used.get(c.type, 0) + 1
		for x in c.elim:
			uncovered.erase(x)
	return chosen


## Removes rules (in a random order) while every wrong plan is still ruled out.
static func minimize(rng: RandomNumberGenerator, chosen: Array, decoys: Array) -> Array:
	var keep := chosen.duplicate()
	var order := keep.duplicate()
	_shuffle(rng, order)
	for c in order:
		var without := keep.duplicate()
		without.erase(c)
		if _covers(without, decoys):
			keep = without
	return keep


static func _covers(rules: Array, decoys: Array) -> bool:
	var seen := {}
	for c in rules:
		for x in c.elim:
			seen[x] = true
	for d in decoys:
		if not seen.has(d):
			return false
	return true


# ---------------------------------------------------------------- 6. friends

static func assign(rng: RandomNumberGenerator, chosen: Array, nf: int, theme: String) -> Array:
	var rules := chosen.duplicate()
	_shuffle(rng, rules)
	var buckets: Array = []
	for i in nf:
		buckets.append([])
	for i in rules.size():
		var c: Dictionary = rules[i]
		if i < nf:
			buckets[i].append(c)
			continue
		var best: Array = []
		var fewest := 99
		for fi in nf:
			var b: Array = buckets[fi]
			if b.size() >= 3 or b.any(func(x): return x.type == c.type or PTRules.contradicts(x, c)):
				continue
			if b.size() < fewest:
				fewest = b.size()
				best = [fi]
			elif b.size() == fewest:
				best.append(fi)
		if best.is_empty():
			return []
		buckets[best[rng.randi_range(0, best.size() - 1)]].append(c)
	var names: Array = PTCatalog.NAMES.duplicate()
	var avatars: Array = PTCatalog.AVATARS.duplicate()
	var colors: Array = PTCatalog.COLORS.duplicate()
	_shuffle(rng, names)
	_shuffle(rng, avatars)
	_shuffle(rng, colors)
	var friends: Array = []
	for fi in nf:
		var rs: Array = []
		for c in buckets[fi]:
			rs.append({"type": c.type, "v": c.v})
		rs.sort_custom(func(a, b): return PTRules.TYPES.find(a.type) < PTRules.TYPES.find(b.type))
		friends.append({
			"name": names[fi], "avatar": avatars[fi % avatars.size()], "color": colors[fi % colors.size()],
			"flavor": flavor(rng, rs, theme == "birthday" and fi == 0), "rules": rs,
			"birthday": theme == "birthday" and fi == 0,
		})
	return friends


static func flavor(rng: RandomNumberGenerator, rules: Array, birthday: bool) -> String:
	if birthday:
		return PTCatalog.BIRTHDAY_FLAVOR
	var lines: Array
	if rules.size() >= 2 and rng.randf() < 0.4:
		lines = PTCatalog.FLAVOR.multi
	else:
		var r: Dictionary = rules[0]
		var f = PTCatalog.FLAVOR.get(r.type, PTCatalog.FLAVOR.multi)
		lines = f[String(r.v)] if f is Dictionary else f
	return lines[rng.randi_range(0, lines.size() - 1)]


# ---------------------------------------------------------------- helpers

static func _shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _weighted(rng: RandomNumberGenerator, items: Array, weight: Callable) -> Dictionary:
	var total := 0.0
	for it in items:
		total += float(weight.call(it))
	if items.is_empty() or total <= 0.0:
		return {}
	var x := rng.randf() * total
	for it in items:
		x -= float(weight.call(it))
		if x <= 0.0:
			return it
	return items[items.size() - 1]
