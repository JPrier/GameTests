extends SceneTree
## Headless simulation harness for the level generator.
##
##   godot --headless --path . -s tools/sweep.gd -- attempts 2000
##       Builds N raw generator attempts (spread over every archetype and many dates),
##       validates each and prints acceptance and solve-rate statistics per archetype, plus
##       counts of geometry-rule failures. Use it to tune generator.gd / validator.gd.
##   godot --headless --path . -s tools/sweep.gd -- days 365 [start]
##       Builds all five throws for N consecutive days and checks every invariant: five
##       different venue types, geometry rules, the validator accepts each level, its stored
##       solution catches, it is deterministic (rebuilt identically), and the search never
##       needed the fallback. Dates in core/attempts.json are checked through the table.
## Exits with code 1 if any invariant fails.

const Gen = preload("res://core/generator.gd")
const Levels = preload("res://core/levels.gd")
const V = preload("res://core/validator.gd")
const L = preload("res://core/level.gd")
const P = preload("res://core/physics.gd")
const Daily = preload("res://core/daily.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "attempts"
	var n := int(args[1]) if args.size() > 1 else 500
	var code := 0
	if mode == "days":
		code = _days(n, args[2] if args.size() > 2 else Daily.EPOCH)
	else:
		_attempts(n)
	quit(code)


func _attempts(n: int) -> void:
	var by: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	for i in n:
		var arche: String = Daily.ARCHETYPES[i % 7]
		var d := Daily.add_days(Daily.EPOCH, i / 7)
		var lv := Gen.make(d, 1, Daily.seed_for(d, 0, 500 + i), i, arche)
		var st := V.evaluate(lv)
		if not by.has(arche):
			by[arche] = {"n": 0, "ok": 0, "geom": 0, "unsolvable": 0, "fragile": 0, "hard": 0, "easy": 0, "rates": [], "routes": 0}
		var b: Dictionary = by[arche]
		b.n += 1
		if st.ok:
			b.ok += 1
			b.routes += st.routes.size()
		var rs := " ".join(st.reasons)
		if rs.contains("overlap") or rs.contains("leaves") or rs.contains("crowds") or rs.contains("blocks") or rs.contains("floating") or rs.contains("ceiling"):
			b.geom += 1
		elif st.solves == 0:
			b.unsolvable += 1
		elif st.robust == 0:
			b.fragile += 1
		elif rs.contains("too hard"):
			b.hard += 1
		elif rs.contains("too easy"):
			b.easy += 1
		if st.reasons.is_empty() or not rs.contains("overlap"):
			b.rates.append(st.rate)
	for arche in Daily.ARCHETYPES:
		if not by.has(arche):
			continue
		var b: Dictionary = by[arche]
		var rates: Array = b.rates
		rates.sort()
		var med: float = rates[rates.size() / 2] if not rates.is_empty() else 0.0
		var p25: float = rates[rates.size() / 4] if not rates.is_empty() else 0.0
		var p75: float = rates[rates.size() * 3 / 4] if not rates.is_empty() else 0.0
		print("%-10s n=%4d accepted=%5.1f%%  geometry=%d unsolvable=%d fragile=%d too-hard=%d too-easy=%d  rate p25/50/75=%.3f/%.3f/%.3f  routes/accepted=%.2f" % [
			arche, b.n, 100.0 * b.ok / b.n, b.geom, b.unsolvable, b.fragile, b.hard, b.easy, p25, med, p75, float(b.routes) / maxf(1, b.ok)])
	print("%d attempts in %.1f s" % [n, (Time.get_ticks_msec() - t0) / 1000.0])


func _days(n: int, start: String) -> int:
	var bad := 0
	var d := start
	var attempts_total := 0
	var worst := 0
	var levels := 0
	for i in n:
		var arches := Daily.archetypes_for(d)
		var distinct := {}
		for a in arches:
			distinct[a] = true
		if distinct.size() != Daily.HOLES:
			bad += 1
			print("FAIL %s: repeated venue types %s" % [d, str(arches)])
		for hole in Daily.HOLES:
			# Uses the precomputed table when it covers the date (verifying it), else searches.
			var lv := Levels.for_date(d, hole)
			levels += 1
			var problems: Array = []
			if int(lv.get("attempt", 0)) >= 1000:
				problems.append("needed the fallback")
			problems.append_array(L.geometry_errors(lv))
			var st := V.evaluate(lv)
			if not st.ok and int(lv.get("attempt", 0)) < 1000:
				problems.append("validator rejects it: " + ", ".join(st.reasons))
			var sol: Dictionary = lv.get("solution", {})
			if sol.is_empty() or P.throw(lv, int(sol.a), int(sol.p)).outcome != "catch":
				problems.append("stored solution does not catch")
			var again := Levels.make_attempt(d, hole, int(lv.attempt))
			again.solution = lv.solution
			again.stats = lv.stats
			if JSON.stringify(again) != JSON.stringify(lv):
				problems.append("not deterministic")
			attempts_total += int(lv.attempt) + 1
			worst = maxi(worst, int(lv.attempt))
			if not problems.is_empty():
				bad += 1
				print("FAIL %s throw %d %s: %s" % [d, hole + 1, lv.archetype, "; ".join(problems)])
		d = Daily.add_days(d, 1)
	print("%d days (%d levels), %d bad, avg attempts %.2f, worst attempt %d" % [n, levels, bad, float(attempts_total) / maxi(1, levels), worst])
	return 1 if bad > 0 else 0
