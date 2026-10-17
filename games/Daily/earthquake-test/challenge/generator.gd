extends RefCounted
## The daily challenge curator (generator v2).
##
## For each date:
##   1. The plan: the quake archetype comes from a shuffled two-week bag (every archetype
##      twice per fortnight, never twice in a row) and a hash decides whether the day may
##      carry an engineering modifier (never two modifier days in a row). A second bag
##      suggests a site so each archetype meets different footings over time, and the
##      soil is drawn with the quake's soil affinities as odds.
##   2. N_CANDIDATES seeded candidates vary the site, modifier and every quake
##      parameter within the archetype.
##   3. Each candidate is validated and scored from a cheap analytic response estimate:
##      archetype/site/soil fit, how differently stiff vs flexible structures are loaded,
##      difficulty in band, and novelty against the earlier days of its 14-day run.
##   4. The best valid candidate wins (lowest index on ties); a fixed fallback search
##      guarantees a day even if every candidate fails.
##
## Days are curated in 14-day runs starting at CUTOVER: a day's novelty is measured against
## exactly the challenges published earlier in its run, so generating any date in any
## order gives the same result. Dates before CUTOVER use the frozen v1 generator.
## Changing any rule here must bump VERSION/SALT and move CUTOVER forward.

const Challenge = preload("res://challenge/challenge.gd")
const Arch = preload("res://challenge/archetypes.gd")
const Site = preload("res://site/site_generator.gd")
const Waveform = preload("res://quake/waveform.gd")
const Fingerprint = preload("res://challenge/fingerprint.gd")
const Validator = preload("res://challenge/validator.gd")
const Legacy = preload("res://challenge/legacy_v1.gd")

const VERSION := 2
const SALT := "eq-v2"
const CUTOVER := "2026-10-18"
const N_CANDIDATES := 20
const RUN := 14
const BAG_DAYS := 14
const FALLBACK_TRIES := 8

static var _cache := {}
static var stats := {"generated": 0}


# ------------------------------------------------------------------ dates

static func day_index(d: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(CUTOVER + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return int(round((b - a) / 86400.0))


static func date_of(idx: int) -> String:
	var a := Time.get_unix_time_from_datetime_string(CUTOVER + "T00:00:00")
	return Time.get_date_string_from_unix_time(a + idx * 86400)


static func clear_cache() -> void:
	_cache.clear()


## Uniform 0..1 from a key (String.hash's low bits are too regular for sequential keys,
## so it goes through PCG first).
static func _h01(key: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	return rng.randf()


# ------------------------------------------------------------------ entry point

static func generate(d: String):
	if d < CUTOVER:
		return Legacy.make(d)
	return _day(day_index(d))


static func _day(idx: int):
	if _cache.has(idx):
		return _cache[idx]
	var start := idx - posmod(idx, RUN)
	var refs: Array = []
	for k in range(start, idx):
		refs.append(_day(k))
	var quake := quake_for(idx)
	var c = choose(date_of(idx), quake, modifier_day(idx), refs, site_for(idx), soil_for(idx, quake))
	if _cache.size() > 600:
		_cache.clear()
	_cache[idx] = c
	return c


# ------------------------------------------------------------------ plan

## A fortnight's quake archetypes: each twice, shuffled, no back-to-back repeats.
static func _bag(period: int) -> Array:
	return _shuffled("bag", period, Arch.QUAKES + Arch.QUAKES)


## A fortnight's suggested sites: each twice plus two extras, shuffled, no repeats in a row.
## The curator prefers the suggestion but may pick another site that suits the quake better;
## the suggestion keeps the same archetype from always landing on the same favourite site.
static func site_for(idx: int) -> String:
	var p := floori(float(idx) / BAG_DAYS)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:sitebag-extra:%d" % [SALT, p]).hash()
	var items: Array = Arch.SITES + Arch.SITES
	items.append(Arch.SITES[rng.randi_range(0, Arch.SITES.size() - 1)])
	items.append(Arch.SITES[rng.randi_range(0, Arch.SITES.size() - 1)])
	return _shuffled("sitebag", p, items)[posmod(idx, BAG_DAYS)]


static func _shuffled(tag: String, period: int, items: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:%s:%d" % [SALT, tag, period]).hash()
	var bag: Array = items.duplicate()
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = bag[i]
		bag[i] = bag[j]
		bag[j] = t
	for _pass in 20:
		var clean := true
		for i in range(1, bag.size()):
			if bag[i] != bag[i - 1]:
				continue
			clean = false
			for j in range(bag.size()):
				var k := (i + 1 + j) % bag.size()
				if k == i or bag[k] == bag[i]:
					continue
				var t = bag[i]
				bag[i] = bag[k]
				bag[k] = t
				break
		if clean:
			break
	return bag


static func quake_for(idx: int) -> String:
	var p := floori(float(idx) / BAG_DAYS)
	var bag := _bag(p)
	# don't open a fortnight with the archetype the last one closed on. This fix only swaps
	# position 0 with a middle position, so the previous bag's last entry is never moved.
	var prev_last: String = _bag(p - 1)[-1]
	if bag[0] == prev_last:
		for j in range(2, bag.size() - 2):
			if bag[j] != prev_last and bag[j] != bag[1] and bag[j - 1] != bag[0] and bag[j + 1] != bag[0]:
				var t = bag[0]
				bag[0] = bag[j]
				bag[j] = t
				break
	return bag[posmod(idx, BAG_DAYS)]


## The day's ground, drawn with the quake's soil affinities as odds (so a Jackhammer is
## rarely on soft mud, which would filter out its fast shaking).
static func soil_for(idx: int, quake: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:soil:%d" % [SALT, idx]).hash()
	return _weighted(rng, Arch.SOILS, Arch.SOILS.map(func(s): return float(Arch.SOIL_WEIGHT[s]) * Arch.affinity(Arch.SOIL_AFFINITY, quake, s)))


static func modifier_day(idx: int) -> bool:
	var p := Arch.PROB_MODIFIER_DAY
	return _h01("%s:mod:%d" % [SALT, idx]) < p and _h01("%s:mod:%d" % [SALT, idx - 1]) >= p


# ------------------------------------------------------------------ candidates

static func _weighted(rng: RandomNumberGenerator, keys: Array, weights: Array) -> String:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	for i in keys.size():
		r -= float(weights[i])
		if r <= 0.0 and float(weights[i]) > 0.0:
			return keys[i]
	for i in range(keys.size() - 1, -1, -1):
		if float(weights[i]) > 0.0:
			return keys[i]
	return keys[0]


static func make_candidate(d: String, key: String, quake: String, may_modify: bool, force := {}, suggested_site := "", soil := ""):
	var rng := RandomNumberGenerator.new()
	var sd := ("%s:%s:%s" % [SALT, d, key]).hash()
	rng.seed = sd
	var c := Challenge.new()
	c.date = d
	c.version = VERSION
	c.rng_seed = sd
	c.quake_archetype = quake
	var site_pick := _weighted(rng, Arch.SITES, Arch.SITES.map(func(s): return Arch.affinity(Arch.SITE_AFFINITY, quake, s)))
	if suggested_site != "" and rng.randf() < 0.55:
		site_pick = suggested_site
	c.site_archetype = force.get("site", site_pick)
	c.suggested_site = suggested_site
	c.soil = force.get("soil", soil if soil != "" else _weighted(rng, Arch.SOILS, Arch.SOILS.map(func(s): return float(Arch.SOIL_WEIGHT[s]) * Arch.affinity(Arch.SOIL_AFFINITY, quake, s))))
	if may_modify:
		c.modifier = force.get("modifier", _weighted(rng, Arch.MODIFIERS, Arch.MODIFIERS.map(func(m): return Arch.affinity(Arch.MODIFIER_AFFINITY, quake, m))))
	c.anchors = Site.make(c.site_archetype, rng)
	c.quake_spec = Arch.draw_quake(quake, c.soil, c.modifier, rng)
	var budget_adj := 0
	match c.modifier:
		"steel_shortage", "cheap_steel", "timber_shortage":
			c.mat_costs = Arch.MODIFIER_INFO[c.modifier].costs.duplicate()
			budget_adj = -5 if c.modifier == "cheap_steel" else 5
		"heavy_top":
			c.modifier_params = {"top_mass": Arch.HEAVY_TOP_KG}
			budget_adj = 5
		"min_height":
			c.modifier_params = {"min_height": float(rng.randi_range(4, 6))}
			budget_adj = 5
	c.metrics = _metrics(c)
	budget_adj += int(SITE_BUDGET.get(c.site_archetype, 0))
	c.budget = clampi(_budget_for(float(c.metrics.difficulty)) + budget_adj + 5 * rng.randi_range(-1, 1), Validator.BUDGET_RANGE[0], Validator.BUDGET_RANGE[1])
	c.fingerprint = Fingerprint.make(quake, c.quake_spec, c.site_archetype, c.anchors, c.soil, c.budget, c.modifier, c.metrics)
	return c


## Analytic response metrics for a candidate.
static func _metrics(c) -> Dictionary:
	var q: Dictionary = c.quake_spec
	var est := Waveform.estimate(q)
	var psa: PackedFloat32Array = est.psa
	var energy: PackedFloat32Array = est.energy
	var mean := 0.0
	var logs: Array = []
	for x in psa:
		logs.append(log(maxf(x, 1e-6)))
		mean += log(maxf(x, 1e-6))
	mean /= psa.size()
	var var_ := 0.0
	for l in logs:
		var_ += (l - mean) * (l - mean)
	var spread := sqrt(var_ / psa.size())
	# demand: a pseudo-velocity spectrum summed over the reference periods (pga * PSA * T).
	# Calibrated against the canonical structures: what breaks real builds here is mostly
	# long-period sway (tall towers whipping) plus strong vertical shaking. ~1.0 = typical day.
	var pga := float(q.pga)
	var psv := 0.0
	for j in psa.size():
		psv += psa[j] * float(Waveform.PERIODS[j])
	var difficulty := pga * psv / 30.0 * (1.0 + 0.3 * pow(float(q.v_ratio), 2.0))
	if c.modifier == "heavy_top":
		difficulty *= 1.12
	var sustain := 0.0
	for j in range(1, 5):
		sustain += sqrt(energy[j]) / maxf(psa[j], 1e-6) / 4.0   # ~ sqrt(strong seconds)
	return {
		"psa": psa, "energy": energy, "dominant_hz": float(est.dominant_hz), "spread": spread,
		"difficulty": difficulty, "disp": float(est.disp_per_pga) * pga, "sustain": sustain,
	}


## Spread-out footings cost more material per metre of height (calibrated with the canonical
## structures: a wide site buys ~40% less height than a narrow one for the same money).
const SITE_BUDGET := {"wide": 10, "split": 5, "three_point": 5, "asymmetric": 5}


## Harder quakes get more money (multiples of 5, $40-65 before site, modifier and jitter).
static func _budget_for(difficulty: float) -> int:
	return 40 + 5 * int(round(clampf((difficulty - 0.55) / 0.22, 0.0, 5.0)))


# ------------------------------------------------------------------ scoring + selection

const DIFF_BAND := [0.35, 1.6]


## Quality of a candidate on its own (no history).
static func quality(c) -> float:
	var q := 0.0
	q += 1.2 * Arch.affinity(Arch.SITE_AFFINITY, c.quake_archetype, c.site_archetype)
	if c.site_archetype == c.suggested_site:
		q += 0.8
	q += 0.9 * Arch.affinity(Arch.SOIL_AFFINITY, c.quake_archetype, c.soil)
	if c.modifier != "":
		q += 0.7 * Arch.affinity(Arch.MODIFIER_AFFINITY, c.quake_archetype, c.modifier)
	# reward days where stiff and flexible structures are loaded very differently
	var w := 0.3 if c.quake_archetype == "broadband" else 1.0
	q += 0.8 * w * clampf(float(c.metrics.spread) / 0.55, 0.0, 1.0)
	var d := float(c.metrics.difficulty)
	if d < DIFF_BAND[0]:
		q -= 2.0 * (DIFF_BAND[0] - d) / DIFF_BAND[0]
	elif d > DIFF_BAND[1]:
		q -= 2.0 * (d - DIFF_BAND[1]) / DIFF_BAND[1]
	if float(c.metrics.disp) > 0.9:
		q -= 1.0
	return q


## Penalties for repeating the earlier days of the run (refs, oldest first).
static func repetition(c, refs: Array) -> float:
	var p := 0.0
	var n := refs.size()
	if n == 0:
		return 0.0
	if refs[n - 1].site_archetype == c.site_archetype:
		p += 1.6
	for k in range(maxi(0, n - 3), n - 1):
		if refs[k].site_archetype == c.site_archetype:
			p += 0.45
	if c.modifier != "":
		for r in refs:
			if r.modifier == c.modifier:
				p += 1.4
	var nov := Fingerprint.novelty(c.fingerprint, refs.map(func(r): return r.fingerprint))
	if nov < NOVELTY_FLOOR:
		p += (NOVELTY_FLOOR - nov) * 3.0
	return p

const NOVELTY_FLOOR := 0.45


static func choose(d: String, quake: String, may_modify: bool, refs: Array, suggested_site := "", soil := ""):
	var best = null
	var rejected := 0
	for i in N_CANDIDATES:
		var c = make_candidate(d, str(i), quake, may_modify, {}, suggested_site, soil)
		c.candidate = i
		if not Validator.problems(c).is_empty():
			rejected += 1
			continue
		c.novelty = Fingerprint.novelty(c.fingerprint, refs.map(func(r): return r.fingerprint))
		c.score = quality(c) - repetition(c, refs)
		if best == null or c.score > best.score:
			best = c
	if best == null:
		best = fallback(d)
		best.novelty = Fingerprint.novelty(best.fingerprint, refs.map(func(r): return r.fingerprint))
	best.rejected = rejected
	stats.generated = int(stats.generated) + 1
	return best


## A plain, always-reasonable day: an All-Rounder on firm ground at a three-point site.
static func fallback(d: String):
	var c = null
	for k in FALLBACK_TRIES:
		c = make_candidate(d, "fallback%d" % k, "broadband", false, {"site": "three_point", "soil": "firm"})
		if Validator.problems(c).is_empty():
			break
	c.candidate = -1
	c.fallback = true
	return c
