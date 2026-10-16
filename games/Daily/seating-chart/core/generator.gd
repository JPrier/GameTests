extends RefCounted
## Deterministic puzzle generator. No randomness other than the seeded RNG passed in.
##
##  1. pick guests and a random complete seating (the answer),
##  2. list every clue that is true of that seating,
##  3. draw clues (weighted by tier) until the exhaustive solver finds exactly one answer,
##     then keep drawing until the logic solver can finish it within the tier's level cap,
##  4. remove every clue the logic solver can do without (no redundant clues),
##  5. rate it, and re-roll (deterministically) if it doesn't fit the tier.

const Model = preload("res://core/model.gd")
const C = preload("res://core/constraints.gd")
const S = preload("res://core/solver.gd")
const L = preload("res://core/logic.gd")
const D = preload("res://core/difficulty.gd")
const Daily = preload("res://core/daily.gd")
const Names = preload("res://core/names.gd")

const MAX_ATTEMPTS := 400
const GEN_VERSION := 1        # bump when generated puzzles change; then rerun tools/precompute.gd

var last_reject := ""
var stats: Dictionary = {}           # reject reason -> count (for tests / dev panel)


## The puzzle for a calendar date.
static func for_date(d: String):
	var gen = load("res://core/generator.gd").new()
	return gen.generate(d, Daily.tier_for(d))


func generate(d: String, tier: int):
	stats = {}
	# Fast path: the shipped table says which attempt this date lands on. Regenerating just that
	# attempt gives exactly what the full search below would; if it doesn't pass (table stale
	# after a generator change), fall through to the full search.
	var known := known_attempt(d)
	if known > 0 and tier == Daily.tier_for(d):
		var krng := RandomNumberGenerator.new()
		krng.seed = Daily.seed_for(d, known - 1)
		var km = attempt_puzzle(krng, tier)
		if km != null:
			km.date = d
			km.number = Daily.day_number(d)
			km.seed_value = Daily.seed_for(d, known - 1)
			km.attempts = known
			return km
	return generate_full(d, tier)


## The full deterministic search: the first attempt (from attempt 0) that passes every check.
func generate_full(d: String, tier: int):
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = Daily.seed_for(d, attempt)
		var m = attempt_puzzle(rng, tier)
		if m != null:
			m.date = d
			m.number = Daily.day_number(d)
			m.seed_value = Daily.seed_for(d, attempt)
			m.attempts = attempt + 1
			return m
		stats[last_reject] = int(stats.get(last_reject, 0)) + 1
	# Never expected; fall back to an easier tier so a day always has a puzzle.
	if tier > 0:
		return generate_full(d, tier - 1)
	return null


# ------------------------------------------------------------------ attempt table

const ATTEMPTS_PATH := "res://core/attempts.json"
static var _attempts: Dictionary = {}
static var _attempts_loaded := false


## Which attempt (1-based) a date's puzzle comes from, per tools/precompute.gd, or 0 if unknown.
static func known_attempt(d: String) -> int:
	if not _attempts_loaded:
		_attempts_loaded = true
		if FileAccess.file_exists(ATTEMPTS_PATH):
			var data = JSON.parse_string(FileAccess.get_file_as_string(ATTEMPTS_PATH))
			if data is Dictionary and int(data.get("version", 0)) == GEN_VERSION:
				_attempts = data.get("days", {})
	return int(_attempts.get(d, 0))


# ------------------------------------------------------------------ helpers

static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Weighted random order (Efraimidis-Spirakis): heavier items tend to come first.
static func weighted_order(items: Array, weights: Array, rng: RandomNumberGenerator) -> Array:
	var keyed: Array = []
	for i in items.size():
		var w: float = weights[i]
		if w <= 0.0:
			continue
		keyed.append([pow(rng.randf_range(1e-9, 1.0), 1.0 / w), i])
	keyed.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out: Array = []
	for k in keyed:
		out.append(items[k[1]])
	return out


func make_guests(m, rng: RandomNumberGenerator) -> void:
	var names: Array = Names.NAMES.duplicate()
	var descs: Array = Names.DESCS.duplicate()
	var cols: Array = range(Names.COLORS.size())
	shuffle(names, rng)
	shuffle(descs, rng)
	shuffle(cols, rng)
	m.guests = []
	for g in m.guest_count():
		m.guests.append({"name": names[g], "desc": descs[g], "color": cols[g % cols.size()]})


func random_seating(m, rng: RandomNumberGenerator) -> PackedInt32Array:
	var order: Array = range(m.guest_count())
	shuffle(order, rng)
	var seat_of: PackedInt32Array = m.empty_seating()
	for i in order.size():
		seat_of[order[i]] = i          # seat i = table i / seats, position i % seats
	return m.canonical(seat_of)


## Every supported clue that is true of the answer.
func true_clues(m) -> Array:
	var out: Array = []
	var sol: PackedInt32Array = m.solution
	for a in m.guest_count():
		for b in range(a + 1, m.guest_count()):
			var adjacent: bool = m.ring_adjacent(sol[a], sol[b])
			var together: bool = m.table_of(sol[a]) == m.table_of(sol[b])
			out.append(C.make(C.ADJACENT if adjacent else C.NOT_ADJACENT, a, b))
			out.append(C.make(C.SAME_TABLE if together else C.DIFFERENT_TABLE, a, b))
	for a in m.guest_count():
		out.append(C.make(C.AT_TABLE, a, -1, m.table_of(sol[a])))
	return out


func _solvable(m, clues: Array, level_cap: int) -> bool:
	return L.solvable(m, clues, level_cap)


# ------------------------------------------------------------------ one attempt

func attempt_puzzle(rng: RandomNumberGenerator, tier: int):
	var cfg: Dictionary = D.TIERS[tier]
	var level_cap: int = cfg.cap
	var m = Model.new()
	m.tier = tier
	make_guests(m, rng)
	m.solution = random_seating(m, rng)

	var pool := true_clues(m)
	var weights: Array = []
	for c in pool:
		weights.append(float(cfg.weights[String(c.type)]))
	var order := weighted_order(pool, weights, rng)

	var clues: Array = []
	var at_count := 0
	# every puzzle names a table at least once (the tables aren't interchangeable)
	var g0 := rng.randi_range(0, m.guest_count() - 1)
	var first := C.make(C.AT_TABLE, g0, -1, m.table_of(m.solution[g0]))
	clues.append(first)
	at_count = 1
	order = order.filter(func(c): return C.key(c) != C.key(first))
	var idx := 0
	# draw until the clues can be reasoned out within the tier's cap (which also proves the
	# answer is unique; the exhaustive solver double-checks at the end)
	# (what-if checks are slow when they fail, so draw against level 3 and let the pruning
	# below take a hard puzzle down to needing what-ifs)
	# Checking is the slow part, so don't check until there are enough clues to stand a chance,
	# then every other clue; any overshoot is pruned below.
	while clues.size() < 8 or (clues.size() % 2 == 1) or not _solvable(m, clues, mini(level_cap, 3)):
		if idx >= order.size():
			last_reject = "can't make it deducible"
			return null
		var c2: Dictionary = order[idx]
		idx += 1
		if String(c2.type) == C.AT_TABLE:
			if at_count >= int(cfg.max_at):
				continue
			at_count += 1
		clues.append(c2)

	# drop every clue the reasoning can do without. On hard days strong clues go first (direct
	# placements, then neighbours, then shared tables), so what's left leans on harder reasoning.
	var strength := {C.AT_TABLE: 0, C.ADJACENT: 1, C.SAME_TABLE: 2, C.DIFFERENT_TABLE: 3, C.NOT_ADJACENT: 4}
	var removal: Array = range(clues.size())
	if tier == 3:
		removal.sort_custom(func(x, y):
			var sx: int = strength[String(clues[x].type)]
			var sy: int = strength[String(clues[y].type)]
			return sx < sy or (sx == sy and x > y))
	else:
		removal.reverse()        # newest first suits the easier tiers better
	var keep: Array = []
	keep.resize(clues.size())
	keep.fill(true)
	for i in removal:
		keep[i] = false
		var trial: Array = []
		for k in clues.size():
			if keep[k]:
				trial.append(clues[k])
		if not _solvable(m, trial, level_cap):
			keep[i] = true
	var kept: Array = []
	for k in clues.size():
		if keep[k]:
			kept.append(clues[k])
	clues = kept

	# presentation: random order and phrasing
	shuffle(clues, rng)
	for c3 in clues:
		c3["v"] = rng.randi_range(0, C.variant_count(String(c3.type)) - 1)

	# cheap early exit before the full (explained) rating
	if level_cap > 1 and tier > 0 and _solvable(m, clues, level_cap - 1):
		last_reject = "too easy for tier"
		return null
	var r := D.rate(m, clues, tier)
	var why := D.reject_reason(r)
	if why != "":
		last_reject = why
		return null
	# ground truth: exactly one answer, and it's ours
	var sols := S.solutions(m, clues, 2)
	if sols.size() != 1 or sols[0] != m.solution:
		last_reject = "BUG: exhaustive check disagrees"
		return null
	m.clues = clues
	m.rating = r
	return m
