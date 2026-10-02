extends SceneTree
## Balance simulator: a greedy bot plays Bistro Empire and logs progress.
##   godot --headless --path . --script res://tools/sim.gd -- hours=12 concept=diner taps=1
## Not exported (tools/* is excluded).

var e
var taps_per_s := 1.0
var no_prestige := false
var log_every := 600.0
var next_log := 0.0
var events: Array = []
var last_best := {}
var debug_at := -1.0
var start_stars := 0.0


func _init() -> void:
	var hours := 12.0
	var concept := "diner"
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"hours": hours = float(kv[1])
			"concept": concept = kv[1]
			"taps": taps_per_s = float(kv[1])
			"log": log_every = float(kv[1])
			"noprestige": no_prestige = kv[1] == "1"
			"debug": debug_at = float(kv[1])
			"stars": start_stars = float(kv[1])
	e = load("res://econ.gd").new()
	print("upgrades in catalogue: ", e.upgrades.size())
	e.new_game()
	e.prestiges = 2
	e.choose_concept(concept)
	e.prestiges = 0
	e.stars = start_stars
	e.stars_earned = start_stars
	for k in ["auto_ads", "auto_tables", "auto_cooks", "auto_recipes", "auto_upg"]:
		e.auto_on[k] = false
	var limit := hours * 3600.0
	var decisions := 0
	var t0 := Time.get_ticks_msec()
	while e.play_time < limit:
		decisions += 1
		if false:
			printerr("d=%d t=%.1f cash=%s inc=%s tap=%s last=%s %s" % [decisions, e.play_time, e.fmt_money(e.cash), e.fmt_money(e.income()), e.fmt_money(e.tap_value()), last_best, e.upgrades[last_best.get("id",0)].name if last_best.get("k","")=="upg" else ""])
		if Time.get_ticks_msec() - t0 > 100000:
			printerr("wall limit")
			break
		_step(concept)
		if e.play_time >= next_log:
			_log()
			next_log += log_every
	_log()
	print("decisions: %d  wall: %.1fs" % [decisions, (Time.get_ticks_msec() - t0) / 1000.0])
	print("owned upgrades this run: %d  legacy: %d" % [e.owned.size(), e.legacy.size()])
	var cats := {}
	for id in e.owned:
		var c: String = e.upgrades[id].cat
		cats[c] = int(cats.get(c, 0)) + 1
	print("by category: ", cats)
	for ev in events:
		print(ev)
	_breakdown()
	quit()


func _inc(a: Dictionary, ro: Dictionary = {}, co: Array = []) -> float:
	return float(e.income_info(a, ro, co, e.price_unlocked(a)).total)


func _event(s: String) -> void:
	events.append("[%s] %s" % [e.fmt_time(e.play_time), s])


func _log() -> void:
	var a: Dictionary = e.agg()
	var inf: Dictionary = e.income_info(a, {}, [], e.price_unlocked(a))
	print("%9s  run %8s | inc %10s/s cash %10s | reps %s | upg %4d | locs %3d vents %s | ★%s (+%s pending) P%d | limit %s price %.2f" % [
		e.fmt_time(e.play_time), e.fmt_time(e.run_time), e.fmt_money(inf.total), e.fmt_money(e.cash),
		str([e.reps.ads, e.reps.tables, e.reps.cooks, e.reps.recipes]), e.owned.size(), e.locations(),
		str(e.vents.slice(0, 4)), e.fmt_num(e.stars), e.fmt_num(e.stars_pending()), e.prestiges, inf.limit, inf.price])


func _step(concept: String) -> void:
	var a: Dictionary = e.agg()
	if e.price_unlocked(a):
		e.price = e.best_price(a)
	var cur := _inc(a)
	# --- prestige?
	var pend: float = e.stars_pending()
	if not no_prestige and pend >= maxf(15.0, e.stars_earned * 1.2) and e.run_time > 900.0:
		_event("sell company #%d after %s: +%s stars (income %s/s)" % [e.prestiges + 1, e.fmt_time(e.run_time), e.fmt_num(pend), e.fmt_money(cur)])
		e.prestige()
		_spend_stars()
		var names := []
		for id in e.legacy:
			names.append(e.upgrades[id].name)
		_event("legacy now: %s  stars left %s" % [names, e.stars])
		var pick := concept
		if not e.concept_unlocked(pick):
			pick = "diner"
		e.choose_concept(pick)
		for k in ["auto_ads", "auto_tables", "auto_cooks", "auto_recipes", "auto_upg"]:
			e.auto_on[k] = false
		return
	var best := {}
	var best_score := INF
	# repeatables
	for r in e.REPS:
		var c: float = e.rep_cost(r, 1)
		var ro := {r: int(e.reps[r]) + 1}
		var g := _inc(a, ro) - cur
		# milestone lookahead: value the next milestone a little
		var nm: int = e.next_milestone(r)
		if nm > 0 and nm - int(e.reps[r]) <= 3:
			g += cur * 0.15
		var sc := _score(c, g, cur)
		if sc < best_score:
			best_score = sc
			best = {"k": "rep", "r": r, "c": c}
	# upgrades
	var vis: Array = e.visible_upgrades()
	var n := 0
	for u in vis:
		n += 1
		if n > 80:
			break
		var c: float = u.cost
		var g := _inc(e.copy_with(a, u.eff)) - cur
		if g <= cur * 1e-6:
			# utility upgrades (costs, flags, offline, tap): buy when cheap
			if c <= e.cash * 0.2 or c <= cur * 30.0:
				g = cur * 0.05
			else:
				continue
		var sc := _score(c, g, cur)
		if sc < best_score:
			best_score = sc
			best = {"k": "upg", "id": u.id, "c": c}
	# franchise
	for i in e.NC:
		if not e.city_unlocked(i):
			continue
		var c: float = e.city_next_cost(i)
		var co: Array = e.cities.duplicate()
		co[i] = int(co[i]) + 1
		var g := _inc(a, {}, co) - cur
		# milestone lookahead
		for m in e.CITY_MILESTONES:
			if int(e.cities[i]) + 1 == m:
				g *= 1.5
		var sc := _score(c, g, cur)
		if sc < best_score:
			best_score = sc
			best = {"k": "city", "i": i, "c": c}
	# ventures
	for i in e.NV:
		if not e.vent_unlocked(i):
			continue
		var c: float = e.vent_next_cost(i)
		e.vents[i] = int(e.vents[i]) + 1
		var g := _inc(a) - cur
		e.vents[i] = int(e.vents[i]) - 1
		var sc := _score(c, g, cur)
		if sc < best_score:
			best_score = sc
			best = {"k": "vent", "i": i, "c": c}
	last_best = best
	if debug_at > 0.0 and e.play_time > debug_at:
		debug_at = -1.0
		var inf: Dictionary = e.income_info(a, {}, [], e.price_unlocked(a))
		printerr("DEBUG t=", e.play_time, " cash=", e.cash, " cur=", cur, " best=", best, " score=", best_score, "\n", inf)
		for r in e.REPS:
			printerr("  rep ", r, " n=", e.reps[r], " cost=", e.rep_cost(r, 1), " gain=", _inc(a, {r: int(e.reps[r]) + 1}) - cur)
		var shown := 0
		for u in vis:
			shown += 1
			if shown > 15:
				break
			printerr("  upg ", u.name, " cost=", u.cost, " gain=", _inc(e.copy_with(a, u.eff)) - cur)
	if best.is_empty():
		_wait(30.0)
		return
	if float(best.c) <= e.cash:
		var before_inf: Dictionary = e.income_info(e.agg(), {}, [], true)
		var ok := true
		match String(best.k):
			"rep": ok = e.buy_rep(best.r, 1)
			"upg": ok = e.buy_upgrade(best.id)
			"city":
				if e.locations() == 0:
					_event("first franchise (%s)" % e.CITY_NAMES[best.i])
				if int(e.cities[best.i]) == 0:
					_event("opened in %s" % e.CITY_NAMES[best.i])
				ok = e.buy_city(best.i)
			"vent":
				if int(e.vents[best.i]) == 0:
					_event("started venture %s" % e.VENTURES[best.i].name)
				ok = e.buy_vent(best.i)
		if not ok:
			printerr("buy failed ", best)
			_wait(1.0)
		var after_inf: Dictionary = e.income_info(e.agg(), {}, [], true)
		if float(after_inf.total) > float(before_inf.total) * 1.4 and e.play_time < 60:
			printerr("JUMP t=%.1f %s %s\n  before %s\n  after  %s" % [e.play_time, best, e.upgrades[best.get("id",0)].name if best.k=="upg" else "", before_inf, after_inf])
	else:
		var inc_total := cur + _tap_rate()
		_wait(clampf((float(best.c) - e.cash) / maxf(inc_total, 1e-9), 0.2, 120.0))


func _tap_rate() -> float:
	return e.tap_value() * taps_per_s


func _wait(dt: float) -> void:
	var tr := _tap_rate() * dt
	e.cash += tr
	e.run_earned += tr
	e.life_earned += tr
	e.tick(dt)
	e.run_automation()


func _score(cost: float, gain: float, cur: float) -> float:
	if gain <= 0.0:
		return INF
	var wait := maxf(0.0, cost - e.cash) / maxf(cur + _tap_rate(), 1e-9)
	return cost / gain + wait


func _spend_stars() -> void:
	var changed := true
	while changed:
		changed = false
		for u in e.upgrades:
			if not e.legacy_available(u) or float(u.star) > e.stars:
				continue
			var c: float = u.star
			var buy := false
			var eff: Array = u.eff
			var kind: String = eff[0][0]
			var r: float = e.STAR_BASE + float(e.agg().starpow)
			if kind == "mul" and eff[0][1] == "global":
				buy = (1.0 + r * (e.stars - c)) * 2.0 > 1.0 + r * e.stars
			elif kind == "mul" and eff[0][1] == "royalty":
				buy = (1.0 + r * (e.stars - c)) * 1.6 > 1.0 + r * e.stars
			elif kind == "starpow":
				buy = (1.0 + (r + 0.005) * (e.stars - c)) > 1.0 + r * e.stars
			else:
				buy = c <= e.stars * 0.05
			if buy:
				e.buy_legacy(u.id)
				changed = true


func _breakdown() -> void:
	# nats of income contributed by each category of owned upgrades
	var full: float = log(maxf(_inc(e.agg()), 1e-300))
	var cats := {}
	for id in e.owned:
		cats[e.upgrades[id].cat] = true
	print("income log10 = %.1f" % (full / log(10.0)))
	for c in cats:
		var keep := {}
		for id in e.owned:
			if e.upgrades[id].cat != c:
				keep[id] = true
		var a2: Dictionary = e._aggregate(keep)
		var v: float = log(maxf(_inc(a2), 1e-300))
		print("  %-9s %5.1f decades" % [c, (full - v) / log(10.0)])
	var a: Dictionary = e.agg()
	var base_reps := {"ads": 0, "tables": 0, "cooks": 0, "recipes": 0}
	print("  reps(lin) %5.1f decades" % ((full - log(maxf(_inc(a, base_reps), 1e-300))) / log(10.0)))
	var no_c: Array = []
	for i in e.NC:
		no_c.append(0)
	# franchise: compare with no cities
	var fr: float = e.franchise_mult(a)
	print("  franchise %5.1f decades, star %5.1f, ventures:" % [log(fr) / log(10.0), log(e.star_mult(a)) / log(10.0)], e.vents)
