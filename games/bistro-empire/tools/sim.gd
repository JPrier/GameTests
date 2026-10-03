extends SceneTree
## Balance simulator: a greedy bot plays Bistro Empire and logs progress.
##   godot --headless --path . --script res://tools/sim.gd -- hours=12 concept=diner taps=1
## Options: noprestige=1 nobiz=1 events=0 stars=N log=SECONDS
## Decisions use net income (after food, upkeep and interest), including side businesses.
## Not exported (tools/* is excluded).

var e
var taps_per_s := 1.0
var no_prestige := false
var no_biz := false
var log_every := 600.0
var next_log := 0.0
var events: Array = []
var start_stars := 0.0
var real_agg := {}
var reserve_s := 60.0   # careful players keep this many seconds of income in the bank


func _init() -> void:
	var hours := 12.0
	var concept := "diner"
	var ev_on := true
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
			"nobiz": no_biz = kv[1] == "1"
			"events": ev_on = kv[1] != "0"
			"stars": start_stars = float(kv[1])
			"reserve": reserve_s = float(kv[1])
	e = load("res://econ.gd").new()
	e.rng.seed = 12345
	e.events_on = ev_on
	print("upgrades in catalogue: ", e.upgrades.size())
	e.new_game()
	e.prestiges = 2
	e.choose_concept(concept)
	e.prestiges = 0
	e.stars = start_stars
	e.stars_earned = start_stars
	_autos_off()
	var limit := hours * 3600.0
	var decisions := 0
	var t0 := Time.get_ticks_msec()
	while e.play_time < limit:
		decisions += 1
		if Time.get_ticks_msec() - t0 > 110000:
			printerr("wall limit")
			break
		_step(concept)
		if e.play_time >= next_log:
			_log()
			next_log += log_every
	_log()
	print("decisions: %d  wall: %.1fs" % [decisions, (Time.get_ticks_msec() - t0) / 1000.0])
	print("owned upgrades this run: %d  legacy: %d  grit %s  bankruptcies %d" % [e.owned.size(), e.legacy.size(), e.grit, e.bankruptcies])
	var cats := {}
	for id in e.owned:
		var c: String = e.upgrades[id].cat
		cats[c] = int(cats.get(c, 0)) + 1
	print("by category: ", cats)
	for ev in events:
		print(ev)
	quit()


func _autos_off() -> void:
	for k in ["auto_ads", "auto_tables", "auto_cooks", "auto_recipes", "auto_upg"]:
		e.auto_on[k] = false


## Net income with optional overrides. Businesses read e.agg(), so swap the aggregate in.
func _inc(a: Dictionary, ro: Dictionary = {}, co: Array = [], bo := {}) -> float:
	var swap: bool = a != e._agg
	var saved: Dictionary = e._agg
	if swap:
		e._agg = a
		e._dirty = false
	var inf: Dictionary = e.income_info(a, ro, co, e.price_unlocked(a))
	var net := float(inf.net)
	for i in e.biz.size():
		var s: Dictionary = e.biz[i]
		if bo.has(i):
			s = bo[i]
		var est: Dictionary = Biz.estimate(i, s, e, false)
		net += float(est.rev) - float(est.cost)
	net -= e.interest_per_s()
	if swap:
		e._agg = saved
	return net


func _event(s: String) -> void:
	events.append("[%s] %s" % [e.fmt_time(e.play_time), s])


func _log() -> void:
	var em: Dictionary = e.empire()
	var bz := []
	for i in e.biz.size():
		var s: Dictionary = e.biz[i]
		var x: Dictionary = em.per[i]
		bz.append("%d/%d:%s" % [s.a, s.b, e.fmt_num(float(x.rev) - float(x.cost))] if s.open else "-")
	print("%9s run %8s | net %10s/s (rest %s, biz %s, costs %d%%) cash %10s | reps %s | upg %4d | locs %3d | biz %s | ★%s(+%s) G%s P%d B%d" % [
		e.fmt_time(e.play_time), e.fmt_time(e.run_time), e.fmt_money(em.net), e.fmt_money(em.rest_rev), e.fmt_money(em.biz_rev),
		int(100.0 * float(em.costs) / maxf(float(em.gross), 1e-9)), e.fmt_money(e.cash),
		str([e.reps.ads, e.reps.tables, e.reps.cooks, e.reps.recipes]), e.owned.size(), e.locations(),
		" ".join(bz), e.fmt_num(e.stars), e.fmt_num(e.stars_pending()), e.fmt_num(e.grit), e.prestiges, e.bankruptcies])


func _step(concept: String) -> void:
	# answer events: pay upfront if it's cheap, otherwise gamble
	if not e.event.is_empty():
		var ev: Dictionary = e.event
		var c0: float = Events.upfront(ev, ev.choices[0], e.cash)
		var pick := 0 if (c0 <= e.cash * 0.5 or (ev.choices as Array).size() == 1 or bool(ev.good)) else 1
		var line: String = e.answer_event(pick)
		_event("event %s -> %s" % [ev.title, line])
	if e.cash < 0.0:
		var got: float = e.borrow(-e.cash * 1.2)
		if got > 0.0:
			var em: Dictionary = e.empire()
			var per := []
			for x in em.per:
				per.append(e.fmt_money(float(x.rev) - float(x.cost)))
			_event("borrowed %s to stay afloat (net %s rest %s food %s up %s biz %s int %s fx %s)" % [e.fmt_money(got), e.fmt_money(em.net), e.fmt_money(em.rest_rev), e.fmt_money(em.food), e.fmt_money(em.rest_upkeep), per, e.fmt_money(em.interest), e.effects.map(func(f): return f.kind)])
	elif e.debt > 0.0 and e.cash > e.debt * 2.0:
		e.repay(e.debt)
	if not e.concept_chosen:
		_event("BANKRUPT #%d: %s" % [e.bankruptcies, e.last_bankrupt])
		e.choose_concept(concept if e.concept_unlocked(concept) else "diner")
		_autos_off()
		return
	var a: Dictionary = e.agg()
	if e.price_unlocked(a):
		e.price = e.best_price(a)
	var cur := _inc(a)
	# --- prestige?
	var pend: float = e.stars_pending()
	if not no_prestige and pend >= maxf(15.0, e.stars_earned * 1.2) and e.run_time > 900.0:
		_event("sell company #%d after %s: +%s stars (net %s/s)" % [e.prestiges + 1, e.fmt_time(e.run_time), e.fmt_num(pend), e.fmt_money(cur)])
		e.prestige()
		_spend_stars()
		e.choose_concept(concept if e.concept_unlocked(concept) else "diner")
		_autos_off()
		return
	var best := {}
	var best_score := INF
	for r in e.REPS:
		var c: float = e.rep_cost(r, 1)
		var g := _inc(a, {r: int(e.reps[r]) + 1}) - cur
		var nm: int = e.next_milestone(r)
		if nm > 0 and nm - int(e.reps[r]) <= 3:
			g += absf(cur) * 0.15
		var sc := _score(c, g, cur)
		if sc < best_score:
			best_score = sc
			best = {"k": "rep", "r": r, "c": c}
	var vis: Array = e.visible_upgrades()
	var n := 0
	for u in vis:
		n += 1
		if n > 80:
			break
		var c: float = u.cost
		var g := _inc(e.copy_with(a, u.eff)) - cur
		if g <= absf(cur) * 1e-6:
			if c <= e.cash * 0.2 or c <= absf(cur) * 30.0:
				g = absf(cur) * 0.05
			else:
				continue
		var sc := _score(c, g, cur)
		if sc < best_score:
			best_score = sc
			best = {"k": "upg", "id": u.id, "c": c}
	for i in e.NC:
		if not e.city_unlocked(i):
			continue
		var c: float = e.city_next_cost(i)
		var co: Array = e.cities.duplicate()
		co[i] = int(co[i]) + 1
		var g := _inc(a, {}, co) - cur
		for m in e.CITY_MILESTONES:
			if int(e.cities[i]) + 1 == m:
				g *= 1.5
		var sc := _score(c, g, cur)
		if sc < best_score:
			best_score = sc
			best = {"k": "city", "i": i, "c": c}
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
	if not no_biz:
		for i in Biz.N:
			var s: Dictionary = e.biz[i]
			if not s.open:
				if e.biz_unlocked(i):
					var c := Biz.open_cost(i)
					var s2 := s.duplicate(true)
					s2.open = true
					s2.a = 1
					var g := _inc(a, {}, [], {i: s2}) - cur
					# opening pays off slowly at first; value the growth to come
					g = maxf(g, absf(cur) * 0.05)
					var sc := _score(c, g, cur)
					if sc < best_score:
						best_score = sc
						best = {"k": "open", "i": i, "c": c}
				continue
			for w in ["a", "b", "ab"]:
				var c: float = 0.0
				var s2 := s.duplicate(true)
				for ch in w:
					c += e.biz_cost(i, ch, 1)
					s2[ch] = int(s2[ch]) + 1
				var g := _inc(a, {}, [], {i: s2}) - cur
				var sc := _score(c, g, cur)
				if sc < best_score:
					best_score = sc
					best = {"k": "biz", "i": i, "w": w, "c": c}
	if best.is_empty():
		_wait(30.0)
		return
	var reserve: float = maxf(0.0, float(e.empire().gross)) * reserve_s
	if float(best.c) <= e.cash - reserve:
		var ok := true
		match String(best.k):
			"rep": ok = e.buy_rep(best.r, 1)
			"upg": ok = e.buy_upgrade(best.id)
			"city":
				if int(e.cities[best.i]) == 0:
					_event("opened in %s" % e.CITY_NAMES[best.i])
				ok = e.buy_city(best.i)
			"vent": ok = e.buy_vent(best.i)
			"open":
				_event("opened %s (net was %s/s)" % [Biz.DEFS[best.i].name, e.fmt_money(cur)])
				if cur < 0.0:
					printerr("NEG ", e.income_info(a), " int ", e.interest_per_s(), " debt ", e.debt, " fx ", e.effects, " cash ", e.cash)
				ok = e.open_biz(best.i)
			"biz":
				for ch in String(best.w):
					ok = e.buy_biz(best.i, ch, 1) and ok
		if not ok:
			printerr("buy failed ", best)
			_wait(1.0)
	else:
		var inc_total := maxf(cur, 0.0) + _tap_rate()
		_wait(clampf((float(best.c) + reserve - e.cash) / maxf(inc_total, 1e-9), 0.2, 30.0))


func _tap_rate() -> float:
	return e.tap_value() * taps_per_s


func _wait(dt: float) -> void:
	# step in chunks so events and businesses behave as they would live
	var left := dt
	while left > 0.0:
		var h := minf(left, 5.0)
		var tr := _tap_rate() * h
		e.cash += tr
		e.run_earned += tr
		e.life_earned += tr
		e.tick(h)
		left -= h
		if not e.event.is_empty() or e.cash < 0.0:
			break
	e.run_automation()


func _score(cost: float, gain: float, cur: float) -> float:
	if gain <= 0.0:
		return INF
	var wait := maxf(0.0, cost - e.cash) / maxf(maxf(cur, 0.0) + _tap_rate(), 1e-9)
	return cost / gain + wait


func _spend_stars() -> void:
	var changed := true
	while changed:
		changed = false
		for u in e.upgrades:
			if not e.legacy_available(u) or float(u.star) > e.wallet(e.currency(u)):
				continue
			if e.currency(u) == "grit":
				e.buy_legacy(u.id)
				changed = true
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
