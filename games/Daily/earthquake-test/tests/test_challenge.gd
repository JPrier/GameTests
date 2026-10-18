extends GameTest
## Daily challenge generator v2: determinism, archetype character, site validity, candidate
## selection, novelty, waveform sanity, solver stability, a several-thousand-day fuzz, and the
## modifiers / briefing as they show up in the game.

const Gen = preload("res://challenge/generator.gd")
const Arch = preload("res://challenge/archetypes.gd")
const Site = preload("res://site/site_generator.gd")
const Waveform = preload("res://quake/waveform.gd")
const Fingerprint = preload("res://challenge/fingerprint.gd")
const Validator = preload("res://challenge/validator.gd")
const Canon = preload("res://reference/canonical.gd")
const QuakeV1 = preload("res://quake/quake_v1.gd")
const Terrain = preload("res://site/terrain.gd")

const FUZZ_DAYS := 3000
const FUZZ_SYNTH_EVERY := 3


func _day(i: int) -> String:
	return Gen.date_of(i)


func _fresh_main(d: String) -> Node:
	var main = await load_scene("res://main.tscn")
	main.tut_open = false
	main.date = d
	main.wipe_save()
	main.target_score = 0
	main.dev_set_day(d)
	return main


## First day (from the cutover) whose challenge matches `pred`.
func _find(pred: Callable, limit := 800) -> String:
	for i in limit:
		var c = Gen.generate(_day(i))
		if pred.call(c):
			return _day(i)
	return ""


# ------------------------------------------------------------------ determinism

func test_same_date_same_challenge():
	for i in [0, 5, 13, 14, 40, 200]:
		var d := _day(i)
		Gen.clear_cache()
		var a = Gen.generate(d)
		var qa = a.make_quake()
		Gen.clear_cache()
		var b = Gen.generate(d)
		var qb = b.make_quake()
		assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), d + ": same challenge data")
		assert_eq(qa.dx, qb.dx, d + ": byte-identical horizontal record")
		assert_eq(qa.dy, qb.dy, d + ": byte-identical vertical record")
	assert_ne(JSON.stringify(Gen.generate(_day(1)).to_dict()), JSON.stringify(Gen.generate(_day(2)).to_dict()), "different days differ")


func test_generation_order_does_not_matter():
	var dates: Array = []
	for i in range(0, 45, 3):
		dates.append(_day(i))
	Gen.clear_cache()
	var forward := {}
	for d in dates:
		forward[d] = JSON.stringify(Gen.generate(d).to_dict())
	var shuffled := dates.duplicate()
	shuffled.reverse()
	for d in shuffled:
		Gen.clear_cache()   # every date cold, newest first
		assert_eq(JSON.stringify(Gen.generate(d).to_dict()), forward[d], d + ": same result generated cold, in reverse order")


## Published days must never change silently. If this fails after a generator change,
## the change must start from a new cutover date instead (like Gen.TERRAIN_FROM).
## 2026-10-18 is the first v2 day, played before terrain existed: it must stay as it was.
const SNAPSHOT := [
		["2026-10-18", "slow_burner", "narrow", "soft", "", "", 45, [[600, 0], [800, 0]], 1136965944, 873009621],
		["2026-10-19", "vertical", "split", "firm", "heavy_top", "ledge", 65, [[200, 300], [400, 0], [1200, 0]], 1955254614, 4107297662],
		["2026-10-31", "broadband", "asymmetric", "firm", "aftershock", "ledge", 75, [[300, 300], [500, 0], [1000, 0]], 1293930833, 913309345],
		["2026-11-01", "jackhammer", "split", "firm", "", "hump", 45, [[200, 0], [400, 0], [1200, 0]], 1552982132, 2989917136],
		["2026-11-14", "slow_burner", "three_point", "soft", "timber_shortage", "hump", 70, [[200, 0], [600, 0], [1000, 0]], 1860488293, 1145766438],
		["2027-01-26", "long_roller", "wide", "soft", "", "outcrop", 70, [[200, 0], [1200, 0]], 4098531068, 1877154209],
		["2027-10-18", "slow_burner", "asymmetric", "firm", "", "slope", 50, [[500, 215], [900, 119], [1200, 48]], 3431115755, 1854487084],
		["2029-07-14", "near_fault", "wide", "soft", "", "outcrop", 65, [[300, 0], [1100, 0]], 1052887621, 2127358720],
]


func test_generator_snapshot():
	Gen.clear_cache()
	for row in SNAPSHOT:
		var c = Gen.generate(row[0])
		var got := [c.date, c.quake_archetype, c.site_archetype, c.soil, c.modifier, c.terrain_archetype, c.budget,
			c.anchors.map(func(a): return [a.x, a.y]), c.to_dict().spec_hash, str(Array(c.ground())).hash()]
		assert_eq(str(got), str(row), "%s is unchanged" % row[0])


func test_legacy_days_are_frozen():
	var c = Gen.generate("2026-10-02")
	assert_eq(c.version, 1, "days before the cutover use generator v1")
	assert_eq(c.anchors.map(func(a): return a.x), [300, 800, 1000], "quake #1 keeps its site")
	assert_eq(c.budget, 55, "quake #1 keeps its budget")
	var q = QuakeV1.new()
	q.make("2026-10-02")
	assert_eq(c.make_quake().trace, q.trace, "quake #1 keeps its seismogram")
	assert_eq(Gen.generate(Gen.CUTOVER).version, 2, "the cutover day is v2")


# ------------------------------------------------------------------ archetypes

func _specs(arch: String, n: int, soil := "firm") -> Array:
	var out: Array = []
	for k in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("test-arch:%s:%d" % [arch, k]).hash()
		out.append(Arch.draw_quake(arch, soil, "", rng))
	return out


func test_archetypes_stay_in_character():
	for arch in Arch.QUAKES:
		var lim: Dictionary = Arch.QUAKE_LIMITS[arch]
		var soils: Array = Arch.SOILS.filter(func(s): return Arch.affinity(Arch.SOIL_AFFINITY, arch, s) >= 0.5)
		for soil in soils:
			for spec in _specs(arch, 6, soil):
				var f := Waveform.dominant_hz(spec)
				assert_true(f >= lim.f[0] and f <= lim.f[1], "%s on %s: dominant %.2f Hz in %s" % [arch, soil, f, str(lim.f)])
				assert_true(spec.duration >= lim.dur[0] and spec.duration <= lim.dur[1], "%s: %.1f s in %s" % [arch, spec.duration, str(lim.dur)])
	for spec in _specs("long_roller", 10):
		assert_lt(Waveform.dominant_hz(spec), 1.16, "Long Roller is slow")
		assert_gt(spec.duration, 14.0, "Long Roller is long")
	for spec in _specs("jackhammer", 10):
		assert_gt(Waveform.dominant_hz(spec), 1.79, "Jackhammer is fast")
		assert_lt(spec.duration, 10.0, "Jackhammer is short")
	for spec in _specs("near_fault", 10):
		assert_true(spec.pulses.size() >= 1, "Fault Pulse has a pulse")
		assert_lt(float(spec.events[0].level), 0.5, "background shaking is well below the pulse")
	for spec in _specs("double_tap", 6):
		assert_eq(spec.events.size(), 2, "Double Tap has two bursts")
		var e1: Dictionary = spec.events[0]
		var gap: float = float(spec.events[1].t0) - (float(e1.t0) + e1.rise + e1.strong + e1.decay)
		assert_gt(gap, 2.0, "with a lull between them")
	for spec in _specs("vertical", 6):
		assert_gt(float(spec.v_ratio), 1.0, "Vertical Jolt: vertical beats horizontal")
	for spec in _specs("slow_burner", 6):
		assert_gt(float(spec.events[0].strong), 12.0, "Slow Burner has a long strong phase")


func test_archetypes_load_structures_differently():
	# where on the period axis each archetype hits hardest (analytic response, peak index)
	var peak_period := {}
	for arch in Arch.QUAKES:
		var tot := PackedFloat32Array()
		tot.resize(Waveform.PERIODS.size())
		for spec in _specs(arch, 8):
			var psa: PackedFloat32Array = Waveform.estimate(spec).psa
			for j in psa.size():
				tot[j] += psa[j]
		var best := 0
		for j in tot.size():
			if tot[j] > tot[best]:
				best = j
		peak_period[arch] = float(Waveform.PERIODS[best])
	assert_gt(peak_period.long_roller, peak_period.jackhammer, "Long Roller loads longer periods than Jackhammer")
	assert_true(peak_period.long_roller >= 0.8, "Long Roller peaks at flexible periods (%.2f s)" % peak_period.long_roller)
	assert_true(peak_period.jackhammer <= 0.45, "Jackhammer peaks at stiff periods (%.2f s)" % peak_period.jackhammer)


func test_soil_shapes_frequency_content():
	var soft := 0.0
	var rock := 0.0
	for spec in _specs("broadband", 8, "soft"):
		soft += Waveform.dominant_hz(spec)
	for spec in _specs("broadband", 8, "bedrock"):
		rock += Waveform.dominant_hz(spec)
	assert_lt(soft, rock, "soft soil shifts the shaking slower than bedrock")


# ------------------------------------------------------------------ sites

func test_site_archetypes_are_valid_and_distinct():
	for arch in Arch.SITES:
		for k in 150:
			var rng := RandomNumberGenerator.new()
			rng.seed = ("test-site:%s:%d" % [arch, k]).hash()
			var a := Site.make(arch, rng)
			assert_eq(Site.problem(a), "", "%s #%d buildable: %s" % [arch, k, str(a)])
			var f := Site.features(a)
			match arch:
				"wide":
					assert_true(f.count == 2 and f.spread >= 8.0, "wide: two far anchors")
				"narrow":
					assert_true(f.count == 2 and f.spread <= 3.0, "narrow: two close anchors")
				"three_point":
					assert_true(f.count == 3 and f.min_gap >= 3.0, "three-point: even spread")
				"asymmetric":
					assert_true(f.count == 3 and f.asym >= 0.14, "lopsided: uneven gaps")
				"center_cluster":
					assert_true(f.count == 3 and f.spread <= 5.0 and f.offset <= 1.5, "cluster: tight and central")
				"split":
					assert_true(f.count == 3 and f.asym >= 0.5, "split: a pair and a far anchor")


# ------------------------------------------------------------------ selection + novelty

func test_candidate_selection_completes():
	for i in 60:
		var c = Gen.generate(_day(i))
		assert_true(c.fallback or (c.candidate >= 0 and c.candidate < Gen.N_CANDIDATES), "winner is one of the candidates")
		assert_true(c.rejected <= Gen.N_CANDIDATES, "rejections bounded")
		assert_true(Validator.problems(c).is_empty(), _day(i) + ": the winner is valid " + str(Validator.problems(c)))
	var fb = Gen.fallback("2030-01-01")
	assert_true(fb.fallback, "fallback is marked")
	assert_true(Validator.problems(fb).is_empty(), "fallback is valid")
	# a run where every candidate is forced invalid still returns a day
	var c = Gen.choose("2030-01-02", "broadband", false, [], "", "")
	assert_not_null(c, "choose always returns")


func test_novelty_metric():
	var c = Gen.generate(_day(3))
	assert_near(Fingerprint.novelty(c.fingerprint, [c.fingerprint]), 0.0, 1e-6, "identical challenge: zero novelty")
	var twin = Gen.make_candidate(c.date, str(c.candidate), c.quake_archetype, Gen.modifier_day(3), {}, Gen.site_for(3), Gen.soil_for(3, c.quake_archetype))
	assert_near(Fingerprint.distance(c.fingerprint, twin.fingerprint), 0.0, 1e-6, "regenerating the same candidate: zero distance")
	var other = Gen.generate(_day(4))
	assert_gt(Fingerprint.distance(c.fingerprint, other.fingerprint), 0.5, "a different archetype is far away")
	assert_eq(Fingerprint.novelty(c.fingerprint, []), 2.0, "no history: maximal novelty")


func test_no_back_to_back_archetypes():
	var prev = null
	for i in 120:
		var c = Gen.generate(_day(i))
		if prev != null:
			assert_ne(c.quake_archetype, prev.quake_archetype, _day(i) + ": quake archetype changes every day")
			assert_false(c.modifier != "" and prev.modifier != "", _day(i) + ": no modifier two days running")
		prev = c


# ------------------------------------------------------------------ waveforms + solver

func test_quake_normalisation():
	for i in range(0, 70, 2):
		var c = Gen.generate(_day(i))
		var q = c.make_quake()
		var probs := Validator.quake_problems(q, c.quake_archetype, c.modifier)
		assert_true(probs.is_empty(), "%s %s: %s" % [_day(i), c.quake_archetype, str(probs)])
		assert_near(q.pga, float(c.quake_spec.pga), float(c.quake_spec.pga) * 0.02, "peak accel matches target")
		assert_near(q.pga_v / q.pga, float(c.quake_spec.v_ratio), 0.03, "vertical share matches")
		assert_eq(q.offset(-1.0), Vector2.ZERO, "still before the quake")
		assert_eq(q.offset(q.duration + 1.0), Vector2.ZERO, "still after it")


func test_estimate_tracks_time_domain_spectrum():
	var a: Array = []
	var b: Array = []
	for i in range(0, 28, 2):
		var c = Gen.generate(_day(i))
		var q = c.make_quake()
		var td := Waveform.response_spectrum(q.dx)
		for j in td.size():
			a.append(log(float(c.metrics.psa[j])))
			b.append(log(td[j] / q.pga))
	var ma := 0.0
	var mb := 0.0
	for k in a.size():
		ma += a[k] / a.size()
		mb += b[k] / b.size()
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for k in a.size():
		sab += (a[k] - ma) * (b[k] - mb)
		saa += (a[k] - ma) * (a[k] - ma)
		sbb += (b[k] - mb) * (b[k] - mb)
	assert_gt(sab / sqrt(saa * sbb), 0.9, "the cheap estimate the curator uses matches a real response spectrum")


func test_every_archetype_runs_stably_in_the_solver():
	var seen := {}
	for i in 60:
		var c = Gen.generate(_day(i))
		if seen.has(c.quake_archetype):
			continue
		seen[c.quake_archetype] = true
		for id in ["wood_tower", "mixed_tower", "lattice"]:
			var b := Canon.build(id, c.anchors, float(c.budget), c.mat_costs, c.ground())
			if id == "wood_tower":
				assert_gt(b.design.size(), 0, "%s: a wood tower builds on %s" % [_day(i), c.site_archetype])
			elif b.design.is_empty():
				continue   # some designs are unaffordable on some sites; that's information, not an error
			var r := Canon.run(b.design, c.anchors, c.make_quake(), c.top_mass(), c.ground())
			assert_false(r.unstable, "%s %s: no NaN or exploding joints" % [c.quake_archetype, id])
			assert_true(r.standing >= 0.0 and r.standing <= r.built + 0.5, "%s %s: sane height" % [c.quake_archetype, id])
	assert_eq(seen.size(), Arch.QUAKES.size(), "covered every archetype")


func test_canonical_runs_are_deterministic():
	var c = Gen.generate(_day(6))
	var b := Canon.build("lean_tower", c.anchors, float(c.budget), c.mat_costs, c.ground())
	var r1 := Canon.run(b.design, c.anchors, c.make_quake(), 0.0, c.ground())
	var r2 := Canon.run(b.design, c.anchors, c.make_quake(), 0.0, c.ground())
	assert_eq(r1, r2, "same structure + same day = same result")


# ------------------------------------------------------------------ fuzz

func test_fuzz_thousands_of_days():
	Gen.clear_cache()
	var counts := {}
	var sites := {}
	var bad := 0
	var fallbacks := 0
	for i in FUZZ_DAYS:
		var d := _day(i)
		var c = Gen.generate(d)
		counts[c.quake_archetype] = int(counts.get(c.quake_archetype, 0)) + 1
		sites[c.site_archetype] = int(sites.get(c.site_archetype, 0)) + 1
		if c.fallback:
			fallbacks += 1
		var probs := Validator.problems(c)
		if not probs.is_empty():
			bad += 1
			fail("%s invalid: %s" % [d, str(probs)])
		if i % FUZZ_SYNTH_EVERY == 0:
			var q = c.make_quake()
			var qp := Validator.quake_problems(q, c.quake_archetype, c.modifier)
			if not qp.is_empty():
				bad += 1
				fail("%s waveform: %s" % [d, str(qp)])
			c._quake = null   # don't keep thousands of records alive
	assert_eq(bad, 0, "no invalid days or waveforms in %d days" % FUZZ_DAYS)
	assert_lt(fallbacks, FUZZ_DAYS / 100, "fallbacks are rare")
	for a in Arch.QUAKES:
		var share := float(counts.get(a, 0)) / FUZZ_DAYS
		assert_true(share > 0.12 and share < 0.17, "%s share %.3f" % [a, share])
	for s in Arch.SITES:
		var share := float(sites.get(s, 0)) / FUZZ_DAYS
		assert_true(share > 0.09 and share < 0.26, "%s share %.3f" % [s, share])
	Gen.clear_cache()


# ------------------------------------------------------------------ in the game

func test_briefing_shows_once_per_day():
	var d := _day(2)
	var main = await _fresh_main(d)
	assert_true(main.brief_open, "a new day opens on its briefing")
	assert_true(main.overlay_open(), "the briefing blocks the board")
	var ids: Array = main.buttons.map(func(b): return String(b.id))
	assert_true(ids.has("brief_close"), "briefing has its button")
	main.close_brief()
	assert_false(main.brief_open, "dismissed")
	main.load_day(d)
	assert_false(main.brief_open, "not shown again for the same day")
	main.open_brief()
	assert_true(main.brief_open, "can be reopened")
	main.close_brief()
	main.load_day("2026-10-05")
	assert_false(main.brief_open, "legacy days have no briefing")
	assert_false(main.can_brief(), "legacy days can't open one")


## A small braced triangle over the closest pair of anchors, clear of the ground.
func _triangle(main) -> int:
	var best := 0
	for i in range(1, main.anchors.size() - 1):
		if main.anchors[i + 1].x - main.anchors[i].x < main.anchors[best + 1].x - main.anchors[best].x:
			best = i
	var a: Vector2i = main.anchors[best]
	var b: Vector2i = main.anchors[best + 1]
	var top := maxi(a.y, b.y)
	for lift in [200, 300, 400, 500, 600]:
		var apex := Vector2i(roundi((a.x + b.x) / 200.0) * 100, (ceili((top + lift) / 100.0)) * 100)
		var n: int = main.add_chain(a, apex)
		if n == 0:
			continue
		var m: int = main.add_chain(b, apex)
		if m > 0:
			main.add_chain(a, b)   # tie the feet together (no-op if it would cut through the ground)
			return n + m
		main.clear_design()
	return 0


func test_v2_day_plays_and_scores():
	for i in [0, 1, 3]:
		var main = await _fresh_main(_day(i))
		main.brief_open = false
		assert_gt(_triangle(main), 0, _day(i) + ": a triangle fits over two anchors")
		if not main.height_ok():
			var top: Vector2i = main.design[-1].b
			main.add_chain(top, Vector2i(top.x, ceili(main.min_height() + 1.0) * 100))
		var design: Array = main.design.duplicate(true)
		var r1: Dictionary = main.run_instant()
		assert_false(r1.is_empty(), _day(i) + ": the quake ran")
		if r1.is_empty():
			continue
		main.back_to_build()
		main.design = design
		var r2: Dictionary = main.run_instant()
		assert_eq(r1.end_x, r2.end_x, "quakes replay identically")
		assert_true(String(main.share_text()).contains(main.challenge.quake_name()), "share text names the quake")


# ------------------------------------------------------------------ terrain

func test_terrain_starts_after_the_live_day():
	assert_eq(Gen.generate("2026-10-18").version, 2, "the first v2 day stays flat (it was already played)")
	assert_eq(Gen.generate("2026-10-18").terrain_archetype, "", "no terrain on it")
	assert_eq(Gen.generate(Gen.TERRAIN_FROM).version, 3, "terrain from TERRAIN_FROM")


func test_terrain_archetypes_are_valid_and_shaped():
	var seen := {}
	for i in range(1, 400):
		var c = Gen.generate(_day(i))
		var t: String = c.terrain_archetype
		seen[t] = int(seen.get(t, 0)) + 1
		var h: PackedInt32Array = c.ground()
		assert_eq(Terrain.problem(h, c.anchors), "", "%s %s buildable" % [c.date, t])
		var f := Terrain.features(h, c.anchors)
		match t:
			"slope":
				assert_gt(f.relief, 1.9, "a hillside rises")
				assert_gt(f.anchor_spread, 0.0, "anchors at different heights")
			"ledge", "terraces":
				assert_gt(f.anchor_spread, 1.4, "%s: anchors on different levels" % t)
			"hump", "outcrop":
				assert_gt(f.relief, 1.9, "%s: something sticks up" % t)
				assert_eq(f.anchor_spread, 0.0, "%s: anchors on the base level" % t)
			"ravine":
				assert_gt(f.relief, 2.4, "a ravine is deep")
	for t in ["slope", "ledge", "hump", "ravine", "terraces", "outcrop"]:
		assert_gt(int(seen.get(t, 0)), 25, "%s turns up regularly (%d of 399)" % [t, int(seen.get(t, 0))])


func test_no_same_terrain_two_days_running():
	var prev := ""
	var repeats := 0
	for i in range(1, 300):
		var t: String = Gen.generate(_day(i)).terrain_archetype
		if t == prev:
			repeats += 1
		prev = t
	assert_lt(repeats, 6, "terrain rarely repeats on consecutive days (%d)" % repeats)


func test_ground_rules():
	var d := _find(func(c): return c.terrain_archetype == "hump")
	var main = await _fresh_main(d)
	main.brief_open = false
	var c = main.challenge
	var peak := 0
	for x in c.terrain.size():
		if c.terrain[x] > c.terrain[peak]:
			peak = x
	var top := Vector2i(peak * 100, c.terrain[peak])
	assert_true(main.grounded(top), "the hilltop is ground")
	assert_ne(main.check_beam(top + Vector2i(0, 100), top), "", "joints can't sit on the hill")
	assert_eq(main.check_beam(top + Vector2i(0, 100), top + Vector2i(0, 200)), "Start from an anchor or a joint", "the air above it is fine")
	# a beam straight through the hump between its two anchors is refused
	var a: Vector2i = c.anchors[0]
	var b: Vector2i = c.anchors[1]
	for i in c.anchors.size() - 1:
		if c.anchors[i].x < peak * 100 and c.anchors[i + 1].x > peak * 100:
			a = c.anchors[i]
			b = c.anchors[i + 1]
	assert_true(String(main.plan_chain(a, b, 3).why).contains("ground"), "no tunnelling through the hump")
	assert_eq(main.check_beam(a, a + Vector2i(150, 0)), "Only anchors can touch the ground", "no beams lying on the ground")
	assert_eq(main.plan_chain(a, a + Vector2i(0, 200), 2).why, "", "straight up from an anchor is fine")


func test_structures_rest_on_the_ground():
	var d := _find(func(c): return c.terrain_archetype == "ledge")
	var main = await _fresh_main(d)
	main.brief_open = false
	var c = main.challenge
	# anchors stand on the surface
	for a in c.anchors:
		assert_near(float(a.y), Terrain.height_at(c.terrain, a.x), 1.0, "anchor on the surface")
	assert_gt(_triangle(main), 0, "a frame fits")
	main.run()
	main.sim.run_to_end()
	for j in main.sim.n:
		var surf: float = main.sim.gy + main.sim.ground_at(main.sim.px[j] - main.sim.gx)
		assert_true(main.sim.py[j] >= surf - 0.011, "joint %d above the ground at the end" % j)


func test_canonical_structures_build_on_every_terrain():
	for t in ["slope", "ledge", "hump", "ravine", "terraces", "outcrop"]:
		var c = Gen.generate(_find(func(x): return x.terrain_archetype == t))
		var b := Canon.build("wood_tower", c.anchors, float(c.budget), c.mat_costs, c.ground())
		assert_gt(b.design.size(), 0, t + ": a reference tower builds")
		var anchors := {}
		for a in c.anchors:
			anchors[a] = true
		for bd in b.design:
			assert_true(Terrain.clear(c.ground(), bd.a, bd.b, anchors.has(bd.a), anchors.has(bd.b)), t + ": no beam through the ground")


func test_cost_modifiers_change_prices():
	var d := _find(func(c): return c.modifier in ["steel_shortage", "cheap_steel", "timber_shortage"])
	assert_ne(d, "", "a price modifier day exists")
	var main = await _fresh_main(d)
	var c = main.challenge
	var costs: Array = Arch.MODIFIER_INFO[c.modifier].costs
	assert_eq(main.mat_cost(0), float(costs[0]), "wood price")
	assert_eq(main.mat_cost(1), float(costs[1]), "steel price")
	main.brief_open = false
	main.set_mat(1)
	var a: Vector2i = main.anchors[0]
	main.add_beam(a, a + main.dot(0, 1))
	assert_near(main.design_cost(), float(costs[1]), 1e-6, "a 1 m steel post costs today's price")
	assert_true(String(main.challenge.modifier_text()).contains("$"), "the condition says the price")


func test_min_height_gates_the_quake():
	var d := _find(func(c): return c.modifier == "min_height")
	assert_ne(d, "", "a minimum-height day exists")
	var main = await _fresh_main(d)
	main.brief_open = false
	var need: float = main.min_height()
	assert_gt(need, 0.0, "needs some height")
	var a: Vector2i = main.anchors[0]
	main.add_beam(a, a + main.dot(0, 1))
	main.run()
	assert_eq(main.phase, main.Phase.BUILD, "too short: the quake won't start")
	var y := 1
	while y < int(ceil(need)):
		main.add_beam(a + main.dot(0, y), a + main.dot(0, y + 1))
		y += 1
	assert_true(main.height_ok(), "tall enough now")
	main.run()
	assert_eq(main.phase, main.Phase.RUN, "now it starts")


func test_heavy_top_rides_the_highest_joint():
	var d := _find(func(c): return c.modifier == "heavy_top")
	assert_ne(d, "", "a heavy-top day exists")
	var main = await _fresh_main(d)
	main.brief_open = false
	var a: Vector2i = main.anchors[0]
	main.add_beam(a, a + main.dot(0, 1))
	main.add_beam(a + main.dot(0, 1), a + main.dot(0, 2))
	if not main.height_ok():
		main.add_chain(a + main.dot(0, 2), a + main.dot(0, int(main.min_height()) + 1))
	assert_eq(main.heavy_point(), main.design.map(func(b): return b.b).reduce(func(m, p): return p if p.y > m.y else m), "the weight sits on the top joint")
	main.run()
	assert_gt(main.sim.heavy_joint, -1, "the solver carries it")
	assert_eq(main.sim.grid_pts[main.sim.heavy_joint], main.heavy_point(), "on the same joint the board shows")


func test_aftershock_adds_a_second_burst():
	var d := _find(func(c): return c.modifier == "aftershock")
	assert_ne(d, "", "an aftershock day exists")
	var c = Gen.generate(d)
	var base := 2 if c.quake_archetype == "double_tap" else 1
	assert_eq(c.quake_spec.events.size(), base + 1, "an extra burst is in the record (so it shows on the seismograph)")
