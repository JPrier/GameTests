extends SceneTree
## Balance simulator: a greedy bot plays Bistro Empire and logs progress.
##   godot --headless --path . --script res://tools/sim.gd -- hours=12 concept=diner taps=1
## Options: noprestige=1 nobiz=1 events=0 stars=LOG log=SECONDS reserve=SECONDS taps=N
##   policy=greedy|skilled|random|cheapest challenge=ID audit=SECONDS wall=SECONDS
## Money is in logs (see num.gd); decisions compare signed net incomes [log, negative].
## Not exported (tools/* is excluded).

var e
var taps_per_s := 1.0
var no_prestige := false
var no_biz := false
var log_every := 600.0
var next_log := 0.0
var events: Array = []
var start_stars := Num.ZERO
var reserve_s := 60.0   # careful players keep this many seconds of income as cash
var audit_every := 0.0
var next_audit := 0.0
var challenge_id := ""   # play this challenge (level I) instead of a normal run
var goal_logged := false
var policy := "greedy"   # greedy | skilled | random | cheapest
var wall := 110.0
var quiet_events := false


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
			"audit": audit_every = float(kv[1])
			"policy": policy = kv[1]
			"challenge": challenge_id = kv[1]
			"wall": wall = float(kv[1])
			"quiet": quiet_events = kv[1] == "1"
	e = load("res://econ.gd").new()
	e.rng.seed = 12345
	e.events_on = ev_on
	print("upgrades in catalogue: ", e.upgrades.size(), "  infinite lines: ", e.tracks.size())
	e.new_game()
	e.prestiges = 2
	e.choose_concept(concept)
	e.prestiges = 0
	if challenge_id != "":
		e.start_challenge(challenge_id)
		e.choose_concept(concept)
	if policy == "skilled":
		reserve_s = maxf(reserve_s, 150.0)
		e.insured = challenge_id != ""
	e.stars_l = start_stars
	e.stars_earned_l = start_stars
	e.mark_dirty()
	_autos_off()
	var limit := hours * 3600.0
	var decisions := 0
	var t0 := Time.get_ticks_msec()
	while e.play_time < limit:
		decisions += 1
		if Time.get_ticks_msec() - t0 > wall * 1000.0:
			printerr("wall limit")
			break
		_step(concept)
		if audit_every > 0.0 and e.play_time >= next_audit:
			_audit()
			next_audit += audit_every
		if e.play_time >= next_log:
			_log()
			next_log += log_every
	_log()
	print("decisions: %d  wall: %.1fs" % [decisions, (Time.get_ticks_msec() - t0) / 1000.0])
	print("owned this run: %d (+%d generated)  legacy: %d (+%d generated)  grit %s  bankruptcies %d" % [
		e.owned.size(), _sum(e.inf), e.legacy.size(), _sum(e.perk_inf), Num.fmt(e.grit_l), e.bankruptcies])
	print("generated tiers: ", e.inf, " perks: ", e.perk_inf)
	if not quiet_events:
		for ev in events:
			print(ev)
	quit()


func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


func _autos_off() -> void:
	for k in ["auto_ads", "auto_tables", "auto_cooks", "auto_recipes", "auto_upg"]:
		e.auto_on[k] = false


## Signed net income [log, negative] with optional overrides. Businesses read e.agg(), so swap
## the aggregate in.
func _inc(a: Dictionary, ro: Dictionary = {}, co: Array = [], bo := {}) -> Array:
	var swap: bool = a != e._agg
	var saved: Dictionary = e._agg
	if swap:
		e._agg = a
		e._dirty = false
	var info: Dictionary = e.income_info(a, ro, co, e.price_unlocked(a))
	var net: Array = Econ.net_of(info)
	for i in e.biz.size():
		var s: Dictionary = e.biz[i]
		if bo.has(i):
			s = bo[i]
		if not s.open:
			continue
		var est: Dictionary = Biz.estimate(i, s, e, false)
		net = Num.sadd(net, Num.diff(float(est.rev_l), float(est.cost_l)))
	net = Num.sadd(net, [e.interest_l(), true])
	if swap:
		e._agg = saved
	return net


## Gain from cur to nxt, as [log, negative].
func _gain(nxt: Array, cur: Array) -> Array:
	return Num.sadd(nxt, Num.sneg(cur))


func _pos(x: Array) -> float:
	return Num.ZERO if x[1] else float(x[0])


func _event(s: String) -> void:
	events.append("[%s] %s" % [Econ.fmt_time(e.play_time), s])


func _log() -> void:
	var em: Dictionary = e.empire()
	var bz := []
	for i in e.biz.size():
		var s: Dictionary = e.biz[i]
		var x: Dictionary = em.per[i]
		bz.append("%d/%d:%s" % [s.a, s.b, Num.fmt(float(x.rev_l))] if s.open else "-")
	print("%9s run %8s | net %10s/s (rest %s, biz %s) cash %10s | reps %s | upg %4d+%d | locs %3d | biz %s | ★%s(+%s) G%s P%d" % [
		Econ.fmt_time(e.play_time), Econ.fmt_time(e.run_time), Num.fmt_signed_money(float(em.net_l), bool(em.net_neg)),
		Num.fmt_money(float(em.rest_l)), Num.fmt_money(float(em.biz_rev_l)), Num.fmt_money(e.cash_l),
		str([e.reps.ads, e.reps.tables, e.reps.cooks, e.reps.recipes]), e.owned.size(), _sum(e.inf), e.locations(),
		" ".join(bz), Num.fmt(e.stars_l), Num.fmt(maxf(e.stars_pending_l(), Num.ZERO)), Num.fmt(e.grit_l), e.prestiges])


func _step(concept: String) -> void:
	# answer events: pay upfront if it's cheap, otherwise gamble
	if not e.event.is_empty():
		var ev: Dictionary = e.event
		var c0: float = Events.upfront(ev, ev.choices[0], e.cash_l)
		var pick := 0 if (c0 <= e.cash_l + Num.L(0.5) or (ev.choices as Array).size() == 1 or bool(ev.good)) else 1
		if policy == "random" or policy == "cheapest":
			pick = e.rng.randi() % (ev.choices as Array).size()
		var line: String = e.answer_event(pick)
		_event("event %s -> %s" % [ev.title, line])
	if e.in_red():
		var got: float = e.borrow(e.owed_l + Num.L(1.2))
		if not Num.is_zero(got):
			_event("borrowed %s to stay afloat" % Num.fmt_money(got))
	elif not Num.is_zero(e.debt_l) and e.cash_l > e.debt_l + Num.L(2.0):
		e.repay(e.debt_l)
	if not e.concept_chosen:
		_event("BANKRUPT #%d: %s" % [e.bankruptcies, e.last_bankrupt])
		e.choose_concept(concept if e.concept_unlocked(concept) else "diner")
		_autos_off()
		return
	if challenge_id != "" and not goal_logged and e.challenge_done():
		goal_logged = true
		_event("CHALLENGE GOAL reached after %s: +%s Grit" % [Econ.fmt_time(e.run_time), Num.fmt(e.challenge_reward_l())])
	var a: Dictionary = e.agg()
	if policy == "random" or policy == "cheapest":
		_sloppy()
		return
	if e.price_unlocked(a):
		e.price_l = e.best_price_l(a)
	var cur := _inc(a)
	var cur_l := _pos(cur)
	# --- prestige? once the sale would at least double the stars ever earned
	var pend: float = e.stars_pending_l()
	if not no_prestige and pend >= maxf(Num.L(15.0), e.stars_earned_l + Num.L(1.2)) and e.run_time > 900.0:
		_event("sell company #%d after %s: +%s stars (net %s/s)" % [e.prestiges + 1, Econ.fmt_time(e.run_time), Num.fmt(pend), Num.fmt_money(cur_l)])
		e.prestige()
		_spend_stars()
		e.choose_concept(concept if e.concept_unlocked(concept) else "diner")
		_autos_off()
		return
	var best := {}
	var best_score := INF
	for r in e.REPS:
		var c: float = e.rep_cost_l(r, 1)
		var g := _gain(_inc(a, {r: int(e.reps[r]) + 1}), cur)
		var nm: int = e.next_milestone(r)
		if nm > 0 and nm - int(e.reps[r]) <= 3:
			g = Num.sadd(g, [cur_l + Num.L(0.15), false])
		var sc := _score(c, g, cur_l)
		if sc < best_score:
			best_score = sc
			best = {"k": "rep", "r": r, "c": c}
	var vis: Array = e.visible_upgrades()
	var n := 0
	for u in vis:
		n += 1
		if n > 80:
			break
		var c: float = float(u.cost_l)
		var g := _gain(_inc(e.copy_with(a, u.eff)), cur)
		if g[1] or float(g[0]) <= cur_l - 6.0:
			if c <= e.cash_l + Num.L(0.2) or c <= cur_l + Num.L(30.0):
				g = [cur_l + Num.L(0.05), false]
			else:
				continue
		var sc := _score(c, g, cur_l)
		if sc < best_score:
			best_score = sc
			best = {"k": "upg", "id": u.id, "c": c}
	for i in e.NC:
		if not e.city_unlocked(i):
			continue
		var c: float = e.city_next_cost_l(i)
		var co: Array = e.cities.duplicate()
		co[i] = int(co[i]) + 1
		var g := _gain(_inc(a, {}, co), cur)
		var sc := _score(c, g, cur_l)
		if sc < best_score:
			best_score = sc
			best = {"k": "city", "i": i, "c": c}
	for i in e.NV:
		if not e.vent_unlocked(i):
			continue
		var c: float = e.vent_next_cost_l(i)
		e.vents[i] = int(e.vents[i]) + 1
		var g := _gain(_inc(a), cur)
		e.vents[i] = int(e.vents[i]) - 1
		var sc := _score(c, g, cur_l)
		if sc < best_score:
			best_score = sc
			best = {"k": "vent", "i": i, "c": c}
	if not no_biz:
		for i in Biz.N:
			var s: Dictionary = e.biz[i]
			if not s.open:
				if e.biz_unlocked(i):
					# value opening by what the first 50 builds would make
					var s2 := s.duplicate(true)
					s2.open = true
					s2.a = 50
					s2.b = 15 if Biz.DEFS[i].id != "catering" else 2
					var c := Num.sum([Biz.open_cost_l(i), Biz.cost_of_l(i, "a", 1, 49), Biz.cost_of_l(i, "b", 1, int(s2.b) - 1)])
					var g := _gain(_inc(a, {}, [], {i: s2}), cur)
					var sc := _score(c, g, cur_l)
					if sc < best_score:
						best_score = sc
						best = {"k": "open", "i": i, "c": Biz.open_cost_l(i)}
				continue
			for w in ["a", "b", "ab"]:
				var c := Num.ZERO
				var s2 := s.duplicate(true)
				for ch in w:
					c = Num.add(c, e.biz_cost_l(i, ch, 1))
					s2[ch] = int(s2[ch]) + 1
				var g := _gain(_inc(a, {}, [], {i: s2}), cur)
				var sc := _score(c, g, cur_l)
				if sc < best_score:
					best_score = sc
					best = {"k": "biz", "i": i, "w": w, "c": c}
	if best.is_empty():
		_wait(30.0)
		return
	var reserve: float = float(e.empire().gross_l) + Num.L(reserve_s)
	if Num.add(float(best.c), reserve) <= e.cash_l + 1e-9:
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
				_event("opened %s (net was %s/s)" % [Biz.DEFS[best.i].name, Num.fmt_money(cur_l)])
				ok = e.open_biz(best.i)
			"biz":
				for ch in String(best.w):
					ok = e.buy_biz(best.i, ch, 1) and ok
		if not ok:
			printerr("buy failed ", best)
			_wait(1.0)
	else:
		var inc_total := Num.add(cur_l, _tap_rate_l())
		var need := Num.sub(Num.add(float(best.c), reserve), e.cash_l)
		if OS.get_environment("SIMDBG") != "" and e.play_time > float(OS.get_environment("SIMDBG")) and e.play_time < float(OS.get_environment("SIMDBG")) + 120.0:
			print("WAIT ", best, " need ", Num.fmt(need), " inc ", Num.fmt(inc_total), " cash ", Num.fmt(e.cash_l), " reserve ", Num.fmt(reserve))
		_wait(clampf(Econ.secs_to_l(need, inc_total), 0.2, 30.0))


## A player who clicks whatever they can afford: never checks profit, never keeps a reserve.
func _sloppy() -> void:
	var opts: Array = []
	for r in e.REPS:
		if e.can_afford(e.rep_cost_l(r, 1)):
			opts.append(["rep", r, e.rep_cost_l(r, 1)])
	for u in e.visible_upgrades():
		if e.can_afford(float(u.cost_l)):
			opts.append(["upg", u.id, float(u.cost_l)])
	for i in e.NC:
		if e.city_unlocked(i) and e.can_afford(e.city_next_cost_l(i)):
			opts.append(["city", i, e.city_next_cost_l(i)])
	if opts.is_empty():
		_wait(2.0)
		return
	var o: Array
	if policy == "cheapest":
		opts.sort_custom(func(x, y): return float(x[2]) < float(y[2]))
		o = opts[0]
	else:
		o = opts[e.rng.randi() % opts.size()]
	match String(o[0]):
		"rep": e.buy_rep(o[1], 1)
		"upg": e.buy_upgrade(int(o[1]))
		"city": e.buy_city(int(o[1]))
	_wait(1.0)


func _tap_rate_l() -> float:
	return e.tap_value_l() + Num.L(taps_per_s) if taps_per_s > 0.0 else Num.ZERO


func _wait(dt: float) -> void:
	# step in chunks so events and businesses behave as they would live
	var left := dt
	while left > 0.0:
		var h := minf(left, 5.0)
		e.earn(_tap_rate_l() + Num.L(h))
		e.tick(h)
		left -= h
		if not e.event.is_empty() or e.in_red():
			break
	e.run_automation()


## Seconds to pay back plus seconds to wait for the money.
func _score(cost_l: float, gain: Array, cur_l: float) -> float:
	if gain[1] or Num.is_zero(gain[0]):
		return INF
	var wait := Econ.secs_to_l(Num.sub(cost_l, e.cash_l), Num.add(cur_l, _tap_rate_l()))
	return Econ.secs_to_l(cost_l, gain[0]) + wait


## Spends stars and Grit on perks: income perks while they beat what the stars are worth as
## income, anything else that costs under 5% of the stars.
func _spend_stars() -> void:
	for guard in 400:
		var changed := false
		for cur in ["star", "grit"]:
			for ln in e.perk_lines(cur):
				var u: Dictionary = ln.next
				if u.is_empty() or not e.legacy_available(u) or float(u.star_l) > e.wallet_l(cur) + 1e-9:
					continue
				if cur == "grit":
					e.buy_legacy(int(u.id))
					changed = true
					continue
				var c: float = float(u.star_l)
				var eff: Array = u.eff
				var kind: String = eff[0][0]
				var buy := false
				if kind == "mul" and (eff[0][1] == "global" or eff[0][1] == "royalty"):
					buy = c <= e.stars_l + Num.L(0.5)
				elif kind == "starpow":
					buy = c <= e.stars_l + Num.L(0.2)
				else:
					buy = c <= e.stars_l + Num.L(0.05)
				if buy:
					e.buy_legacy(int(u.id))
					changed = true
		if not changed:
			break


func _audit() -> void:
	var a: Dictionary = e.agg()
	var cur := _inc(a)
	var em: Dictionary = e.empire()
	print("---- AUDIT %s (run %s) net %s/s cash %s P%d stars %s (x%s) grit %s" % [Econ.fmt_time(e.play_time), Econ.fmt_time(e.run_time),
		Num.fmt_money(_pos(cur)), Num.fmt_money(e.cash_l), e.prestiges, Num.fmt(e.stars_earned_l), Econ.fmt_mult_l(e.star_l(a)), Num.fmt(e.grit_earned_l)])
	var line := "  biz:"
	for i in Biz.N:
		var s: Dictionary = e.biz[i]
		if s.open:
			line += " %s %d/%d=%s/s" % [Biz.DEFS[i].id, s.a, s.b, Num.fmt_money(float(em.per[i].rev_l))]
	print(line, "  rest ", Num.fmt_money(float(em.rest_l)))
