extends GameTest
## Money is kept as base-10 logs (see num.gd): e.cash_l = 3.0 means $1,000. Tests set amounts
## with Num.L(x) and compare logs.


func _econ(concept := "diner") -> Econ:
	var e := Econ.new()
	e.new_game()
	e.prestiges = 5
	e.choose_concept(concept)
	e.prestiges = 0
	return e


## An econ in a Tight Margins challenge run: running costs, the bank and going bust apply.
func _econ_ch(concept := "diner", id := "margins") -> Econ:
	var e := _econ(concept)
	e.challenge = id
	e.mark_dirty()
	return e


func _fresh() -> Node:
	var main = await load_scene("res://main.tscn")
	main.wipe_save()
	main.E.new_game()
	main.E.choose_concept("diner")
	main.modal = ""
	main._refresh_cache(true)
	return main


func _net(info: Dictionary) -> float:
	return -Num.V(float(info.net_l)) if bool(info.net_neg) else Num.V(float(info.net_l))


# ------------------------------------------------------------------ big numbers

func test_num_arithmetic():
	assert_near(Num.V(Num.add(Num.L(300.0), Num.L(700.0))), 1000.0, 1e-9, "add")
	assert_near(Num.V(Num.sub(Num.L(1000.0), Num.L(250.0))), 750.0, 1e-9, "sub")
	assert_true(Num.is_zero(Num.sub(Num.L(5.0), Num.L(9.0))), "sub floors at zero")
	assert_true(Num.is_zero(Num.ZERO) and Num.V(Num.ZERO) == 0.0, "zero")
	assert_eq(Num.add(5000.0, 10.0), 5000.0, "tiny next to huge is ignored, not an error")
	var d := Num.diff(Num.L(3.0), Num.L(10.0))
	assert_true(d[1] and absf(Num.V(d[0]) - 7.0) < 1e-9, "signed difference")
	var s := Num.sadd([Num.L(10.0), false], [Num.L(4.0), true])
	assert_near(Num.V(s[0]), 6.0, 1e-9, "signed add")
	assert_eq(Num.scmp([Num.L(2.0), true], [Num.L(1.0), false]), -1, "negative < positive")
	# geometric prices
	var c := Num.geo(Num.L(10.0), 1.15, 20)
	var sum := 0.0
	for k in 20:
		sum += 10.0 * pow(1.15, k)
	assert_near(Num.V(c), sum, sum * 1e-9, "geo sum")
	var k := Num.geo_max(Num.L(12345.0), Num.L(10.0), 1.15)
	assert_true(Num.geo(Num.L(10.0), 1.15, k) <= Num.L(12345.0) + 1e-12 and Num.geo(Num.L(10.0), 1.15, k + 1) > Num.L(12345.0), "geo_max exact")
	# and far past what a float can hold
	var big := Num.geo(1.0e6, 1.15, 10)
	assert_true(big > 1.0e6 and big < 1.0e6 + 3.0, "geo works at $1e1,000,000")
	assert_eq(Num.geo_max(1.0e6 + 0.5, 1.0e6, 1.15), 2, "geo_max works up there too")


func test_number_format():
	assert_eq(Num.fmt_money(Num.L(5.0)), "$5", "small")
	assert_eq(Num.fmt_money(Num.L(1234.0)), "$1.23K", "thousands")
	assert_eq(Num.fmt_money(Num.L(999999.0)), "$1.00M", "rounds up a suffix")
	assert_eq(Num.fmt(Num.L(2.5e15)), "2.50Qa", "quadrillions")
	assert_eq(Num.fmt(63.2), "1.58Vg", "vigintillions")
	assert_eq(Num.fmt(93.0), "1.00Tg", "the last named suffix")
	assert_eq(Num.fmt(100.0), "1.00e100", "then exponents")
	assert_eq(Num.fmt(12345.3), "2.00e12,345", "grouped exponents")
	assert_eq(Num.fmt(1.0e9), "1.00e1,000,000,000", "a billion digits")
	assert_eq(Num.fmt(Num.ZERO), "0", "zero")
	assert_eq(Num.fmt_signed_money(Num.L(42.0), true), "-$42", "negative money")
	assert_eq(Econ.roman(14), "XIV", "roman numerals")
	assert_eq(Econ.fmt_count(1234), "1,234", "counts")
	assert_eq(Econ.fmt_count(12345678), "12.35M", "big counts")


# ------------------------------------------------------------------ catalogue

func test_at_least_1000_upgrades():
	var e := Econ.new()
	var run := 0
	var leg := 0
	var gr := 0
	for u in e.upgrades:
		if u.legacy and e.currency(u) == "grit":
			gr += 1
		elif u.legacy:
			leg += 1
		else:
			run += 1
	assert_gt(e.upgrades.size(), 1000, "over 1000 upgrades")
	assert_gt(run, 1000, "over 1000 bought with cash")
	assert_eq(leg, 80, "legacy perks")
	assert_eq(gr, 73, "grit perks")


func test_upgrade_keys_and_names_unique():
	var e := Econ.new()
	var keys := {}
	var names := {}
	for u in e.upgrades:
		assert_false(keys.has(u.key), "duplicate key " + String(u.key))
		keys[u.key] = true
		assert_false(names.has(u.name), "duplicate name " + String(u.name))
		names[u.name] = true
	assert_eq(e.by_key.size(), e.upgrades.size(), "lookup covers every upgrade")


func test_costs_finite_and_effects_described():
	var e := Econ.new()
	for u in e.upgrades:
		if u.legacy:
			assert_true(float(u.star_l) >= 0.0, "legacy price " + String(u.name))
		else:
			var c := float(u.cost_l)
			assert_true(c > 0.0 and c < 300.0 and not is_nan(c), "cost range " + String(u.name))
		assert_ne(e.effect_text(u.eff), "", "effect text " + String(u.name))
		assert_ne(e.req_text(u) if not u.legacy else "x", "", "requirement text " + String(u.name))


# ------------------------------------------------------------------ infinite lines

## Owns every catalogue tier of a line.
func _finish_line(e: Econ, tid: String) -> void:
	var t: Dictionary = e.track_by_id[tid]
	for k in t.keys:
		if t.perm:
			e.legacy[e.by_key[k]] = true
		else:
			e.owned[e.by_key[k]] = true
	e.mark_dirty()


func test_every_line_goes_on_forever():
	var e := _econ()
	var run_lines := 0
	for t in e.tracks:
		if t.perm:
			continue
		run_lines += 1
		# far along the line, tiers still exist and keep getting pricier
		var a: Dictionary = (t.gen as Callable).call((t.keys as Array).size() + 5)
		var b: Dictionary = (t.gen as Callable).call((t.keys as Array).size() + 500)
		assert_true(float(b.cost_l) > float(a.cost_l), "%s keeps getting pricier" % t.id)
		assert_ne(e.effect_text(a.eff), "", "%s tiers do something" % t.id)
		assert_ne(String(a.name), String(b.name), "%s tiers have their own names" % t.id)
	assert_gt(run_lines, 60, "dozens of run lines go on forever")


func test_buying_past_the_catalogue():
	var e := _econ()
	assert_true(e.track_next(e.track_by_id["t_demand"]).is_empty(), "nothing generated until the line is finished")
	_finish_line(e, "t_demand")
	var u := e.track_next(e.track_by_id["t_demand"])
	assert_false(u.is_empty(), "the 61st tier appears")
	assert_true(int(u.id) >= Econ.VID, "with a generated id")
	e.run_l = float(u.cost_l) + 1.0
	e.cash_l = float(u.cost_l) + 1.0
	var shown := false
	for v in e.visible_upgrades():
		if int(v.id) == int(u.id):
			shown = true
	assert_true(shown, "it shows in the upgrade list")
	var d0 := e.stat_l("demand", e.agg())
	assert_true(e.buy_upgrade(int(u.id)), "bought")
	assert_eq(int(e.inf.t_demand), 1, "counted")
	assert_near(e.stat_l("demand", e.agg()) - d0, Num.L(float(u.eff[0][2])), 1e-9, "its effect applies")
	var u2 := e.track_next(e.track_by_id["t_demand"])
	assert_gt(float(u2.cost_l), float(u.cost_l), "the next tier costs more")
	# buy a hundred more
	for k in 100:
		var nx := e.track_next(e.track_by_id["t_demand"])
		e.cash_l = float(nx.cost_l) + 1.0
		e.run_l = maxf(e.run_l, float(nx.cost_l) + 1.0)
		assert_true(e.buy_upgrade(int(nx.id)), "tier %d" % (62 + k))
	assert_eq(int(e.inf.t_demand), 101, "101 generated tiers")
	assert_gt(e.stat_l("demand", e.agg()), d0 + 15.0, "demand far beyond any fixed list")
	# saved, and reset by selling
	var f := Econ.new()
	f.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_eq(int(f.inf.t_demand), 101, "saved")
	assert_near(f.stat_l("demand", f.agg()), e.stat_l("demand", e.agg()), 1e-9, "same effect after loading")
	e.life_l = 400.0
	e.prestige()
	assert_true(e.inf.is_empty(), "run lines reset when you sell")


func test_star_and_grit_perks_go_on_forever():
	var e := _econ()
	_finish_line(e, "l_global")
	_finish_line(e, "gr_empire")
	var u := e.track_next(e.track_by_id["l_global"])
	assert_false(u.is_empty(), "Reputation XXI exists")
	assert_eq(String(u.name), "Reputation XXI", "named")
	e.stars_l = float(u.star_l)
	var g0 := e.global_l(e.agg())
	assert_true(e.buy_legacy(int(u.id)), "bought with stars")
	assert_true(Num.is_zero(e.stars_l), "stars spent")
	assert_near(e.global_l(e.agg()) - g0, Num.L(2.0), 1e-9, "x2 income")
	var gu := e.track_next(e.track_by_id["gr_empire"])
	e.grit_l = float(gu.star_l)
	assert_true(e.buy_legacy(int(gu.id)), "Grit lines go on too")
	# the lines show in the Legacy tab's list
	var found := false
	for ln in e.perk_lines("star"):
		if String(ln.kind) == "global":
			found = true
			assert_eq(int(ln.owned), 21, "21 tiers owned")
			assert_true(int(ln.next.id) >= Econ.VID, "next is generated")
	assert_true(found, "line listed")
	# perk prices outgrow the effect, so stars can't snowball through perks
	var t: Dictionary = e.track_by_id["l_global"]
	var p100 := float((t.gen as Callable).call(100).star_l)
	var p200 := float((t.gen as Callable).call(200).star_l)
	assert_gt(p200 - p100, 2.0 * (p100 - float((t.gen as Callable).call(0).star_l)), "each hundred tiers costs far more than the last")
	# kept through a sale and saved
	e.life_l = 400.0
	e.prestige()
	assert_eq(int(e.perk_inf.l_global), 1, "perks survive selling")
	var f := Econ.new()
	f.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_eq(int(f.perk_inf.gr_empire), 1, "saved")


func test_huge_numbers_play_normally():
	var e := _econ()
	e.stars_earned_l = 300.0          # an absurd star count: income x1e298
	e.mark_dirty()
	e.reps.ads = 50
	e.reps.tables = 50
	e.reps.cooks = 50
	var info := e.income_info(e.agg())
	assert_gt(float(info.total_l), 300.0, "income past 1e300 a second")
	assert_false(is_nan(float(info.total_l)) or is_inf(float(info.total_l)), "and still a real number")
	e.cash_l = 0.0
	e.tick(1.0)
	assert_near(e.cash_l, float(info.total_l), 1e-6, "a second of it lands in cash")
	assert_true(e.buy_rep("ads", e.rep_max_affordable("ads")), "buying works")
	assert_gt(int(e.reps.ads), 1000, "thousands of ads at once")
	var tv := e.tap_value_l()
	assert_gt(tv, float(info.total_l) - 1.0, "taps scale too")
	var s := Num.fmt_money(e.cash_l)
	assert_true(s.begins_with("$") and s.length() < 16, "displays compactly: " + s)
	var f := Econ.new()
	f.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_near(f.cash_l, e.cash_l, 1e-9, "saves past 1e308")


# ------------------------------------------------------------------ economy

func test_starting_state():
	var e := _econ()
	assert_near(Num.V(e.cash_l), 5.0, 1e-9, "start with $5")
	assert_false(Num.is_zero(e.income_l()), "something trickles in from the start")
	assert_eq(String(e.income_info(e.agg()).limit), "seating", "first bottleneck is seats")


func test_buy_rep_costs_and_grows():
	var e := _econ()
	e.cash_l = Num.L(1000.0)
	var c1 := e.rep_cost_l("tables", 1)
	assert_true(e.buy_rep("tables", 1), "buy a table")
	assert_near(Num.V(e.cash_l), 1000.0 - Num.V(c1), 1e-6, "paid the price")
	assert_gt(e.rep_cost_l("tables", 1), c1, "next one costs more")
	var c10 := e.rep_cost_l("tables", 10)
	var sum := 0.0
	var c0 := e.rep_c0_l("tables")
	for i in 10:
		sum += Num.V(c0 + i * e.rep_growth_l("tables"))
	assert_near(Num.V(c10), sum, sum * 1e-9, "bulk cost is the geometric sum")
	e.cash_l = Num.ZERO
	assert_false(e.buy_rep("ads", 1), "can't buy when broke")


func test_max_affordable_is_exact():
	var e := _econ()
	for cash in [12345.0, 1.0e40]:
		e.cash_l = Num.L(cash)
		for r in Econ.REPS:
			var k := e.rep_max_affordable(r)
			assert_true(e.rep_cost_l(r, k) <= e.cash_l + 1e-9, "max fits " + r)
			assert_gt(e.rep_cost_l(r, k + 1), e.cash_l, "max+1 does not fit " + r)


func test_bottleneck_caps_service():
	var e := _econ_ch()
	e.reps.ads = 200
	var info := e.income_info(e.agg())
	assert_true(float(info.served_l) <= float(info.cap_l) + 1e-9, "never serve more than capacity")
	assert_true(String(info.limit) == "seating" or String(info.limit) == "kitchen", "lots of ads, capacity limits")
	var before := float(info.total_l)
	e.reps.ads = 300
	var after := float(e.income_info(e.agg()).total_l)
	assert_near(after, before, 0.001, "more ads past the bottleneck bring in nothing")
	assert_gt(float(e.income_info(e.agg()).upkeep_l), float(info.upkeep_l), "but they still cost upkeep")
	e.reps.tables = 50
	e.reps.cooks = 50
	assert_gt(float(e.income_info(e.agg()).total_l), before + Num.L(3.0), "raising both capacities pays off")


func test_best_price_beats_neighbours():
	var e := _econ()
	e.reps.ads = 150
	e.reps.tables = 20
	e.reps.cooks = 20
	e.owned[e.by_key["b_0"]] = true
	e.mark_dirty()
	var a := e.agg()
	assert_true(e.price_unlocked(a), "Price Tags unlocks pricing")
	var best := e.best_price_l(a)
	e.price_l = best
	var at := float(e.income_info(a).total_l)
	for f in [0.8, 0.9, 1.1, 1.25]:
		e.price_l = clampf(best + Num.L(f), Num.L(Econ.PRICE_MIN), e.ceiling_l(a))
		assert_true(float(e.income_info(a).total_l) <= at + 1e-4, "best price is a local maximum (x%s)" % f)
	e.price_l = 2.0
	assert_near(e.effective_price_l(a), e.ceiling_l(a), 1e-9, "price clamps to the brand ceiling")


func test_concepts_differ():
	var d := _econ("diner")
	var f := _econ("fastfood")
	var fd := _econ("fine")
	assert_gt(f.stat_l("demand", f.agg()), d.stat_l("demand", d.agg()), "fast food draws more guests")
	assert_gt(fd.stat_l("ticket", fd.agg()), d.stat_l("ticket", d.agg()), "fine dining has bigger bills")
	assert_lt(fd.stat_l("seating", fd.agg()), d.stat_l("seating", d.agg()), "fine dining has fewer seats")
	var e := Econ.new()
	e.new_game()
	assert_false(e.choose_concept("fine"), "fine dining locked before first sale")
	assert_true(e.choose_concept("fastfood"), "fast food open from the start")


func test_concept_upgrades_are_exclusive():
	var e := _econ("diner")
	e.run_l = 300.0
	var diner_u: Dictionary = e.upgrades[e.by_key["k_diner_0"]]
	var cafe_u: Dictionary = e.upgrades[e.by_key["k_cafe_0"]]
	assert_true(e.available(diner_u), "own concept's signature upgrade shows")
	assert_false(e.available(cafe_u), "other concept's does not")
	_finish_line(e, "k_cafe")
	_finish_line(e, "k_diner")
	var vis := {}
	for u in e.visible_upgrades():
		vis[String(u.key)] = true
	assert_true(vis.has("k_diner#30"), "own concept's line goes on")
	assert_false(vis.has("k_cafe#30"), "another concept's line stays hidden")


func test_crossroads_lock_the_other_side():
	var e := _econ()
	var a_id: int = e.by_key["x_0_0_a"]
	var b_id: int = e.by_key["x_0_0_b"]
	e.run_l = 12.0
	e.cash_l = 12.0
	assert_true(e.available(e.upgrades[a_id]) and e.available(e.upgrades[b_id]), "both sides offered")
	assert_true(e.buy_upgrade(a_id), "pick a side")
	assert_false(e.available(e.upgrades[b_id]), "other side locked")
	assert_false(e.buy_upgrade(b_id), "can't buy the locked side")
	e.life_l = 40.0
	e.prestige()
	e.run_l = 12.0
	assert_true(e.available(e.upgrades[b_id]), "selling the company reopens the choice")


func test_upgrade_requirements():
	var e := _econ()
	var m: Dictionary = e.upgrades[e.by_key["m_ads_25"]]
	e.cash_l = 30.0
	assert_false(e.available(m), "milestone hidden before 25 ads")
	e.reps.ads = 25
	assert_true(e.available(m), "milestone shows at 25 ads")
	var before := e.stat_l("demand", e.agg())
	assert_true(e.buy_upgrade(int(m.id)), "buy milestone")
	assert_near(e.stat_l("demand", e.agg()), before + Num.L(2.0), 1e-9, "milestone doubles demand")


func test_franchise_and_ventures():
	var e := _econ()
	assert_false(e.franchise_unlocked(), "franchising locked at start")
	e.run_l = Econ.cp_l(7.0)
	assert_true(e.franchise_unlocked(), "franchising unlocks with earnings")
	assert_true(e.city_unlocked(0), "first city open")
	assert_false(e.city_unlocked(1), "second city needs the first")
	var base := e.income_l()
	e.cash_l = 40.0
	assert_true(e.buy_city(0), "open in the first city")
	assert_gt(e.income_l(), base, "royalties raise income")
	assert_eq(e.locations(), 1, "one location")
	assert_false(e.ventures_unlocked(), "ventures need 15 locations")
	for i in 14:
		e.buy_city(0)
	assert_true(e.ventures_unlocked(), "ventures open at 15 locations")
	var d := e.stat_l("demand", e.agg())
	assert_true(e.buy_vent(0), "start the food trucks")
	assert_gt(e.stat_l("demand", e.agg()), d, "food trucks raise demand")


# ------------------------------------------------------------------ prestige & save

func test_prestige_keeps_stars_and_legacy():
	var e := _econ()
	assert_false(e.can_prestige(), "nothing to sell at first")
	e.life_l = Econ.cp_l(14.0)
	e.run_l = e.life_l
	e.reps.ads = 50
	e.cities[0] = 3
	var g := e.stars_pending_l()
	assert_true(g >= 0.0, "stars pending")
	var got := e.prestige()
	assert_eq(got, g, "granted the pending stars")
	assert_eq(e.stars_l, g, "stars kept")
	assert_eq(int(e.reps.ads), 0, "builds reset")
	assert_eq(e.locations(), 0, "franchises reset")
	assert_eq(e.prestiges, 1, "counted the sale")
	assert_false(e.concept_chosen, "pick a new concept after selling")
	assert_true(e.stars_pending_l() < 0.0, "no double counting")
	assert_gt(e.star_l(e.agg()), 0.0, "stars boost income")
	var lid: int = e.by_key["l_global_0"]
	e.stars_l = Num.L(1000.0)
	assert_true(e.buy_legacy(lid), "buy a legacy perk")
	assert_false(e.legacy_available(e.upgrades[e.by_key["l_global_2"]]), "tiers must be bought in order")
	e.life_l += 1.0
	e.prestige()
	assert_true(e.legacy.has(lid), "legacy perks survive selling")


func test_save_roundtrip():
	var e := _econ("fastfood")
	e.reps.cooks = 17
	e.run_l = 12.0
	e.cash_l = 12.0
	assert_true(e.buy_upgrade(e.by_key["x_1_0_b"]), "bought a crossroads side")
	e.cash_l = Num.L(123456.0)
	e.stars_l = Num.L(42.0)
	e.legacy[e.by_key["l_tap_0"]] = true
	e.cities[0] = 2
	var d: Dictionary = JSON.parse_string(JSON.stringify(e.to_dict()))
	var f := Econ.new()
	f.from_dict(d)
	assert_eq(f.concept, "fastfood", "concept")
	assert_near(f.cash_l, e.cash_l, 1e-9, "cash")
	assert_eq(int(f.reps.cooks), 17, "builds")
	assert_true(f.owned.has(e.by_key["x_1_0_b"]), "owned upgrades by key")
	assert_true(f.legacy.has(e.by_key["l_tap_0"]), "legacy by key")
	assert_eq(int(f.cities[0]), 2, "franchises")
	assert_near(f.income_l(), e.income_l(), 1e-9, "same income after load")
	assert_true(Num.is_zero(f.owed_l) and Num.is_zero(f.debt_l), "zero survives JSON")


func test_old_float_saves_convert():
	# a save from before big numbers stored plain floats
	var old := {"v": 1, "econ": 4, "cash": 1.5e60, "run_earned": 2.0e61, "life_earned": 3.0e63, "stars": 1234.0,
		"stars_earned": 5678.0, "grit": 12.0, "grit_earned": 30.0, "prestiges": 9, "concept": "cafe", "concept_chosen": true,
		"reps": {"ads": 900, "tables": 950, "cooks": 940, "recipes": 800}, "owned": ["t_demand_0", "b_0"],
		"legacy": ["l_global_0", "l_global_1", "gr_empire_0"], "cities": [10, 5], "vents": [3], "price": 2.5,
		"best_income": 4.0e58, "biz": [{"open": true, "a": 120, "b": 30, "earned": 5.0e50}, {}, {"open": true, "a": 10, "b": 2,
			"offers": [{"name": "Gala", "crew": 2, "dur": 60.0, "pay": 1.0e40, "bonus": 1.2}], "jobs": [], "earned": 1.0}],
		"debt": 0.0, "event": {"id": "pipe", "r": 1.0e50}}
	var e := Econ.new()
	e.from_dict(old)
	assert_near(e.cash_l, 60.0 + Num.L(1.5), 1e-9, "cash")
	assert_near(e.life_l, 63.0 + Num.L(3.0), 1e-9, "lifetime earnings")
	assert_near(Num.V(e.stars_l), 1234.0, 1e-6, "stars")
	assert_near(Num.V(e.grit_earned_l), 30.0, 1e-9, "grit")
	assert_eq(int(e.reps.tables), 950, "builds")
	assert_eq(e.legacy.size(), 3, "perks")
	assert_near(e.price_l, Num.L(2.5), 1e-9, "menu price")
	assert_true(bool(e.biz[0].open) and int(e.biz[0].a) == 120, "businesses")
	assert_near(float(e.biz[0].earned_l), 50.0 + Num.L(5.0), 1e-9, "business earnings")
	assert_true((e.biz[2].offers as Array).is_empty(), "contracts priced the old way are dropped")
	assert_true(e.event.is_empty(), "an old event card is dropped")
	assert_true(e.perk_inf.is_empty() and e.inf.is_empty(), "nothing generated yet")
	assert_false(Num.is_zero(e.income_l()), "still earning")


func test_offline_gain_is_capped():
	var e := _econ()
	e.reps.tables = 20
	e.reps.cooks = 20
	e.reps.ads = 20
	var inc := e.income_l()
	assert_near(e.offline_gain_l(3600.0), inc + Num.L(3600.0 * Econ.OFFLINE_BASE), 1e-6, "25% for an hour")
	assert_near(e.offline_gain_l(1e7), e.offline_gain_l(2.0 * 3600.0), 1e-9, "capped at 2 hours")


# ------------------------------------------------------------------ the slower curve

func test_stars_grow_slowly():
	# stars for lifetime earnings of 10^L: doubling the digits you've earned gives far fewer
	# than double the stars' digits, so each sale lifts the next run less than before
	var s30 := Econ.stars_for_l(30.0)
	var s60 := Econ.stars_for_l(60.0)
	var s120 := Econ.stars_for_l(120.0)
	assert_gt(s30, 0.0, "a first sale pays stars")
	assert_lt(s60 - s30, 3.5, "e30 to e60 earns under ~3,000x the stars")
	assert_near(s120 - s60, 60.0 / Econ.COST_POW * Econ.STAR_EXP, 0.01, "the curve is a fixed power")
	assert_lt(Econ.STAR_EXP / Econ.COST_POW, 0.2, "stars grow under a fifth as fast as earnings (in digits)")
	assert_gt(Econ.grit_for_l(Econ.cp_l(11.0)), Econ.grit_for_l(Econ.cp_l(8.0)), "more earnings, more Grit")
	assert_lt(Econ.GRIT_EXP, 0.2, "Grit grows slowly too")


# ------------------------------------------------------------------ UI basics

func test_scene_starts_with_concept_picker():
	var main = await load_scene("res://main.tscn")
	main.wipe_save()
	main.E.new_game()
	main.open_modal("concept")
	await wait_frames(2)
	assert_eq(main.modal, "concept", "concept picker shown")
	main.press_button("concept:fine")
	assert_eq(main.modal, "concept", "locked concept can't be picked")
	main.press_button("concept:fastfood")
	assert_eq(main.modal, "", "picker closes")
	assert_eq(main.E.concept, "fastfood", "concept set")


func test_serve_tap_earns():
	var main = await _fresh()
	await wait_frames(2)
	var c0: float = main.E.cash_l
	var v: float = main.E.tap_value_l()
	main.serve()
	assert_near(main.E.cash_l, Num.add(c0, v), 1e-6, "tap adds its value")
	await press_key(KEY_SPACE)
	await wait_frames(1)
	assert_gt(main.E.taps, 1, "space serves too")


func test_tap_buy_button_and_tabs():
	var main = await _fresh()
	main.E.cash_l = 3.0
	await wait_frames(3)
	var found := false
	for b in main.buttons:
		if b.id == "rep:tables":
			found = true
			var p: Vector2 = b.rect.get_center()
			main._on_press(p)
			main._on_release(p)
	assert_true(found, "table buy button on screen")
	assert_eq(int(main.E.reps.tables), 1, "tapping buys a table")
	for t in main.TABS:
		main.press_button("tab:" + t)
		await wait_frames(2)
		assert_eq(main.tab, t, "switched to " + t)
	assert_true(main.content_r.size.y > 200.0, "room for the list")


func test_drag_scrolls_instead_of_buying():
	var main = await _fresh()
	main.E.cash_l = 9.0
	main.E.run_l = 9.0
	main._refresh_cache(true)
	main.press_button("tab:upgrades")
	await wait_frames(3)
	assert_gt(main.scroll_max["upgrades"], 0.0, "upgrade list scrolls")
	var owned_before: int = main.E.owned.size()
	var start: Vector2 = main.content_r.get_center()
	main._on_press(start)
	main.press.moved = true
	main._scroll_by(120.0)
	main._on_release(start + Vector2(0, -120))
	assert_eq(main.E.owned.size(), owned_before, "a drag never buys")
	assert_gt(main.scroll["upgrades"], 0.0, "list moved")


func test_full_prestige_flow_via_buttons():
	var main = await _fresh()
	main.dev_add_cash_l(Econ.cp_l(14.0))
	main.press_button("tab:legacy")
	main.press_button("sell")
	assert_eq(main.modal, "sell", "confirm first")
	main.press_button("sell_yes")
	assert_eq(main.modal, "concept", "choose next concept")
	assert_gt(main.E.stars_l, 0.0, "got stars")
	main.press_button("concept:fine")
	assert_eq(main.E.concept, "fine", "fine dining unlocked after one sale")
	main.save_game()
	var again = await load_scene("res://main.tscn")
	assert_eq(again.E.prestiges, 1, "save restored")
	main.wipe_save()


func test_generated_upgrades_buy_from_the_list():
	var main = await _fresh()
	var e = main.E
	_finish_line(e, "g")
	e.run_l = 200.0
	e.cash_l = 200.0
	main._refresh_cache(true)
	var gen: Dictionary = {}
	for u in main.vis_cache:
		if int(u.id) >= Econ.VID and String(u.key).begins_with("g#"):
			gen = u
	assert_false(gen.is_empty(), "the next ambience tier is listed")
	main.press_button("upg:%d" % int(gen.id))
	assert_eq(int(e.inf.get("g", 0)), 1, "bought by button")
	main._refresh_cache(true)
	var nxt: Dictionary = {}
	for u in main.vis_cache:
		if String(u.key).begins_with("g#"):
			nxt = u
	assert_eq(String(nxt.key), "g#61", "and the one after takes its place")
	main.wipe_save()


# ------------------------------------------------------------------ saving safety

func _store() -> SaveStore:
	var s := SaveStore.new()
	s.erase_all()
	return s


func _sample_state(life: float) -> Dictionary:
	var e := _econ("fastfood")
	e.cash_l = Num.L(777.0)
	e.life_l = Num.L(life)
	e.reps.tables = 9
	return e.to_dict()


func test_pack_unpack_and_tamper():
	var st := _sample_state(1000.0)
	st["marker"] = 777
	var text := SaveStore.pack(st, 1234)
	var u := SaveStore.unpack(text)
	assert_false(u.is_empty(), "valid save unpacks")
	assert_eq(int(u.t), 1234, "time kept")
	assert_eq(int(u.state.reps.tables), 9, "state kept")
	assert_true(SaveStore.unpack(text.replace("777", "778")).is_empty(), "tampered data rejected by checksum")
	assert_true(SaveStore.unpack(text.substr(0, text.length() / 2)).is_empty(), "truncated save rejected")
	assert_true(SaveStore.unpack("").is_empty(), "empty rejected")
	# version 1 saves (the original format) still load
	var v1 := st.duplicate()
	v1["t"] = 99
	v1["cash"] = 777.0   # the original format stored plain numbers
	var u1 := SaveStore.unpack(JSON.stringify(v1))
	assert_false(u1.is_empty(), "v1 save loads")
	assert_eq(int(u1.t), 99, "v1 time")


func test_store_writes_two_places_and_recovers():
	var s := _store()
	assert_eq(s.write(_sample_state(10.0), 100, 0.0), 2, "file + local copy")
	assert_eq(String(s.best().src), "file", "newest valid copy")
	# corrupt the main file: the local copy takes over
	var f := FileAccess.open(SaveStore.FILE, FileAccess.WRITE)
	f.store_string("{\"game\":\"bistro-empire\",\"v\":2,\"da")
	f.close()
	var b := s.best()
	assert_eq(String(b.src), "local", "falls back to the second copy")
	assert_near(float(b.state.life_l), 1.0, 1e-9, "with the right data")
	s.erase_all()


func test_rolling_backup():
	var s := _store()
	s.write(_sample_state(1.0), 100, 0.0)
	s.write(_sample_state(2.0), 200, 10.0)
	s.write(_sample_state(3.0), 300, 500.0)   # backup refreshed from the t=200 copy
	var c := {}
	for x in s.candidates():
		c[x.src] = x
	assert_eq(int(c.file.t), 300, "main copy is newest")
	assert_eq(int(c.file_backup.t), 200, "file backup holds the previous save")
	assert_eq(int(c.local_backup.t), 200, "local backup too")
	# both main copies broken: the backups still restore progress
	for p in [SaveStore.FILE]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("garbage")
		f.close()
	s._ls_set(SaveStore.LS_KEY, "garbage")
	assert_eq(int(s.best().t), 200, "backup restores")
	s.erase_all()


func test_all_corrupt_is_quarantined_not_overwritten():
	var main = await load_scene("res://main.tscn")
	main.wipe_save()
	var f := FileAccess.open(SaveStore.FILE, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	assert_true(main.store.all_corrupt(), "detects unreadable save")
	main.load_game()
	var kept := false
	for n in DirAccess.get_files_at("user://"):
		if n.begins_with("bistro_empire.corrupt-file"):
			kept = true
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + n))
	assert_true(kept, "unreadable save quarantined")
	main.wipe_save()


func test_v1_save_file_still_loads():
	var main = await load_scene("res://main.tscn")
	main.wipe_save()
	var st := _sample_state(5e9)
	st["t"] = int(Time.get_unix_time_from_system())
	st["cash"] = 777.0   # the original format stored plain numbers
	var f := FileAccess.open(SaveStore.FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(st))
	f.close()
	assert_true(main.load_game(), "loads the original save format")
	assert_eq(main.E.concept, "fastfood", "concept restored")
	assert_eq(int(main.E.reps.tables), 9, "builds restored")
	main.save_game()
	assert_eq(int(SaveStore.unpack(FileAccess.get_file_as_string(SaveStore.FILE)).state.reps.tables), 9, "rewritten in the new format")
	main.wipe_save()


func test_refuses_to_save_lost_progress():
	var main = await _fresh()
	main.E.life_l = 12.0
	main.save_game()
	main.E.life_l = Num.L(5.0)   # a bug wiped progress
	main.save_game()
	var u := SaveStore.unpack(FileAccess.get_file_as_string(SaveStore.FILE))
	assert_eq(float(u.state.life_l), 12.0, "good save not overwritten")
	main.wipe_save()


func test_export_import_code():
	var main = await _fresh()
	main.E.cash_l = Num.L(4242.0)
	main.E.life_l = 9.0
	main.E.reps.cooks = 33
	var code: String = main.export_code()
	assert_true(code.begins_with("BISTRO1:"), "code prefix")
	assert_false(main.preview_import("BISTRO1:nonsense"), "garbage code rejected")
	assert_false(main.preview_import("hello"), "random text rejected")
	main.E.new_game()
	main.E.choose_concept("diner")
	assert_true(main.preview_import(code), "valid code accepted")
	assert_eq(main.modal, "import", "asks before replacing")
	main.press_button("import_yes")
	assert_eq(int(main.E.reps.cooks), 33, "progress restored")
	assert_near(Num.V(main.E.cash_l), 4242.0, 1e-6, "cash restored")
	assert_ne(main.store._ls_get(SaveStore.LS_PRE_IMPORT), "", "previous game kept")
	main.wipe_save()


func test_background_time_is_credited():
	var main = await _fresh()
	main.E.reps.tables = 20
	main.E.reps.cooks = 20
	main.E.reps.ads = 30
	main.E.mark_dirty()
	await wait_frames(2)
	var inc: float = Num.V(main.E.income_l())
	# tab hidden for 30 seconds: full income
	var c0: float = Num.V(main.E.cash_l)
	main.last_frame_unix -= 30.0
	main._catch_up()
	assert_near(Num.V(main.E.cash_l) - c0, inc * 30.0, inc * 2.0, "short absence earns full income")
	# hidden for 2 hours: offline rate plus a welcome-back card
	c0 = Num.V(main.E.cash_l)
	main.last_frame_unix -= 7200.0
	main._catch_up()
	assert_near(Num.V(main.E.cash_l) - c0, Num.V(main.E.offline_gain_l(7200.0)), inc * 2.0, "long absence earns offline income")
	assert_eq(main.modal, "welcome", "welcome back shown")
	main.wipe_save()


func test_upgrade_keys_never_disappear():
	# saves store upgrades by key; renaming or removing one would silently drop it from players' saves
	if not FileAccess.file_exists("res://tests/fixtures/upgrade_keys_v1.txt"):
		return   # fixtures aren't exported to the web build; the headless run (and CI) checks this
	var e := Econ.new()
	var lines := FileAccess.get_file_as_string("res://tests/fixtures/upgrade_keys_v1.txt").split("\n", false)
	assert_eq(lines.size(), 1241, "fixture size")
	for k in lines:
		assert_true(e.by_key.has(k), "upgrade key still exists: " + k)


func test_project_name_pins_save_location():
	# user:// on the web is keyed by the project name; renaming it would orphan every save
	assert_eq(String(ProjectSettings.get_setting("application/config/name")), "Bistro Empire", "project name unchanged")
	assert_eq(SaveStore.LS_KEY, "bistro-empire:save", "localStorage key unchanged")


func test_real_player_save_still_loads():
	# a real save code from before businesses, loans and bankruptcy existed (plain-number money)
	var path := "res://tests/fixtures/player_save_2026-10-03.txt"
	if not FileAccess.file_exists(path):
		return
	var text := SaveStore.decode_code(FileAccess.get_file_as_string(path))
	var u := SaveStore.unpack(text)
	assert_false(u.is_empty(), "code decodes")
	var e := Econ.new()
	e.from_dict(u.state)
	assert_eq(int(e.reps.tables), 123, "builds kept")
	assert_eq(int(e.cities[0]), 7, "franchises kept")
	assert_eq(e.owned.size(), 69, "upgrades kept")
	assert_eq(e.biz.size(), Biz.N, "businesses added")
	assert_true(Num.is_zero(e.debt_l), "no debt")
	assert_false(Num.is_zero(e.income_l()), "still earning")
	assert_gt(e.stars_pending_l(), Num.L(15.0), "a worthwhile first sale is waiting")


# ------------------------------------------------------------------ challenge costs, loans, events, going bust

func test_costs_reward_balance_in_challenges():
	var e := _econ_ch()
	e.reps.ads = 30
	e.reps.tables = 30
	e.reps.cooks = 30
	var bal := e.income_info(e.agg())
	assert_false(Num.is_zero(float(bal.food_l)), "food costs money")
	e.reps.tables = 300   # far more seats than guests
	var lop := e.income_info(e.agg())
	assert_gt(float(lop.rent_l), float(bal.rent_l), "empty seats cost rent")
	assert_lt(_net(lop) / Num.V(float(lop.total_l)), _net(bal) / Num.V(float(bal.total_l)), "lopsided builds have thinner margins")
	# franchise royalties carry half the running costs of your own plates, so they widen the margin
	var before := float(bal.food_l)
	e.reps.tables = 30
	e.cities[0] = 10
	var fr := e.income_info(e.agg())
	assert_near(float(fr.food_l), before + Num.L(1.0 + Econ.FR_COST * (Num.V(float(fr.fr_l)) - 1.0)), 1e-6, "royalties carry half the costs")
	assert_gt(_net(fr) / Num.V(float(fr.total_l)), _net(bal) / Num.V(float(bal.total_l)), "so franchising widens the margin")


func test_loans():
	var e := _econ_ch()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	e.tick(1.0)
	var lim := e.credit_limit_l()
	assert_false(Num.is_zero(lim), "credit available")
	var c0 := e.cash_l
	var got := e.borrow(lim + 1.0)
	assert_near(got, lim, 1e-9, "borrowing is capped at the limit")
	assert_near(e.cash_l, Num.add(c0, got), 1e-9, "cash received")
	assert_false(Num.is_zero(e.interest_l()), "interest accrues")
	assert_gt(e.interest_rate(), e.interest_rate(lim - 1.0), "maxed-out loans cost more")
	var net_debt := _net(e.empire())
	e.debt_l = Num.ZERO
	assert_gt(_net(e.empire()), net_debt, "interest comes out of profit")
	e.debt_l = got
	e.repay(got + Num.L(0.5))
	assert_near(e.debt_l, got + Num.L(0.5), 1e-9, "partial repay")
	e.cash_l = 300.0
	e.repay(300.0)
	assert_true(Num.is_zero(e.debt_l), "fully repaid")


func test_events_appear_and_resolve():
	var e := _econ()
	e.rng.seed = 7
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	e.run_l = Econ.cp_l(7.0)
	e.run_time = 1000.0
	e.event_t = 0.5
	e.tick(1.0)
	assert_false(e.event.is_empty(), "an event shows up")
	var ev: Dictionary = e.event
	assert_true((ev.choices as Array).size() >= 1, "it has choices")
	assert_true(ev.has("r_l"), "priced as a log")
	# it waits for an answer
	for k in 50:
		e.tick(1.0)
	assert_false(e.event.is_empty(), "waits for the player")
	# every event resolves without errors, both ways
	for src in Events.LIST:
		var ev2: Dictionary = (src as Dictionary).duplicate(true)
		ev2["r_l"] = 2.0
		ev2["cost_mult"] = 1.0
		ev2["t"] = 30.0
		for k in (ev2.choices as Array).size():
			e.cash_l = 6.0
			e.event = ev2.duplicate(true)
			e.answer_event(k)
			assert_true(e.event.is_empty(), "%s choice %d resolved" % [src.id, k])


func test_effects_change_income_and_expire():
	var e := _econ()
	e.reps.ads = 10
	e.reps.tables = 40
	e.reps.cooks = 40
	var base := float(e.income_info(e.agg()).total_l)
	e.add_effect("demand", 2.0, 10.0, "test")
	assert_gt(float(e.income_info(e.agg()).total_l), base + Num.L(1.5), "guests x2 raises sales")
	e.add_effect("closed", 0.0, 5.0, "test")
	assert_true(Num.is_zero(float(e.income_info(e.agg()).total_l)), "closed means no restaurant sales")
	e.tick(6.0, false)
	assert_false(Num.is_zero(float(e.income_info(e.agg()).total_l)), "reopens")
	e.tick(6.0, false)
	assert_true(e.effects.is_empty(), "effects expire")


func test_challenge_bust_ends_the_run():
	var e := _econ_ch()
	e.challenge_level = 2
	e.run_l = Econ.cp_l(9.0)
	e.life_l = Econ.cp_l(13.0)
	e.reps.ads = 50
	e.debt_l = 6.0
	var pend_stars := e.stars_pending_l()
	assert_true(pend_stars >= 0.0, "stars were on the table")
	var g0 := e.grit_l
	e.cash_l = Num.ZERO
	e.owed_l = 12.0
	for k in int(e.deadline()) + 2:
		e.tick(1.0)
	assert_eq(e.bankruptcies, 1, "went bust after the deadline")
	assert_eq(e.challenge, "", "the challenge is over")
	assert_eq(e.grit_l, g0, "no Grit for going bust")
	assert_eq(e.stars_pending_l(), pend_stars, "nothing else is lost: the stars still wait for a sale")
	assert_true(Num.is_zero(e.debt_l) and Num.is_zero(e.owed_l), "debt wiped")
	assert_eq(int(e.reps.ads), 0, "run reset")
	assert_false(e.concept_chosen, "pick a new concept")
	assert_eq(int(e.challenge_best.get("margins", 0)), 0, "the level isn't completed")
	assert_eq(String(e.last_bankrupt.challenge), "margins", "UI is told which challenge")
	assert_false(e.concept_unlocked("fine"), "going bust in a challenge doesn't unlock concepts")
	e.old_busts = 1
	assert_true(e.concept_unlocked("fine"), "bankruptcies from the old rules still do")


func test_normal_runs_cannot_lose():
	var e := _econ()
	e.reps.ads = 2000
	e.reps.tables = 10
	e.reps.cooks = 10
	var info := e.income_info(e.agg())
	assert_true(Num.is_zero(float(info.cost_l)), "no running costs at all")
	assert_eq(float(info.net_l), float(info.total_l), "income is all profit")
	assert_true(Num.is_zero(e.borrow(9.0)), "no bank")
	e.cash_l = Num.L(50.0)
	e.run_time = 1000.0
	e.run_l = 12.0
	var ev := e.new_event(9.0, {}, "lawsuit")
	assert_true(bool(ev.soft), "events are soft")
	assert_near(Events.upfront(ev, ev.choices[0], e.cash_l), Num.L(50.0), 1e-9, "a bill never asks for more than you have")
	e.event = ev
	e.answer_event(0)
	assert_true(Num.is_zero(e.owed_l), "and can't take you below $0")
	e.charge(20.0)
	for k in 400:
		e.tick(1.0)
	assert_eq(e.bankruptcies, 0, "no bankruptcy outside challenges")
	assert_false(e.in_red(), "cash is floored at $0")
	# businesses cost nothing either
	e.run_l = 30.0
	e.cash_l = 40.0
	e.open_biz(0)
	e.buy_biz(0, "a", 50)
	assert_true(Num.is_zero(float(Biz.estimate(0, e.biz[0], e).cost_l)), "businesses have no running costs")


func test_challenges_pay_grit():
	var e := _econ()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	e.run_l = 9.7
	assert_true(e.start_challenge("health"), "start")
	assert_eq(e.challenge, "health", "in the challenge")
	assert_eq(e.challenge_level, 0, "level I")
	assert_eq(int(e.reps.ads), 0, "starting one begins a fresh run")
	assert_true(e.costs_on(), "costs are on")
	assert_false(e.insurance_on(), "Health Code sells no insurance")
	assert_true(e.bank_on(), "but the bank lends")
	assert_false(e.can_prestige() and e.challenge_done(), "goal not reached yet")
	e.choose_concept("diner")
	e.run_l = e.challenge_goal_l() + Num.L(2.0)
	assert_true(e.challenge_done(), "goal reached")
	var reward := e.challenge_reward_l()
	assert_true(reward >= 0.0, "pays Grit")
	var g0 := e.grit_earned_l
	e.prestige()
	assert_near(e.grit_earned_l, Num.add(g0, reward), 1e-9, "Grit collected on sale")
	assert_eq(e.challenge, "", "back to normal")
	assert_eq(e.challenge_next_level("health"), 1, "next time it's level II")
	assert_gt(e.challenge_goal_l(1), e.challenge_goal_l(0), "and harder")
	# levels never run out
	e.challenge_best["health"] = 500
	assert_true(e.start_challenge("health"), "level 501 exists")
	assert_eq(e.challenge_level, 500, "at level 501")
	assert_gt(e.challenge_goal_l(), 1000.0, "with a goal past 1e1000")
	e.abandon_challenge()
	# shoestring: no bank, no starting cash
	for t in 6:
		e.legacy[e.by_key["l_startcash_%d" % t]] = true
	e.mark_dirty()
	e.start_challenge("shoestring")
	assert_false(e.bank_on(), "no loans in Shoestring")
	assert_true(e.cash_l <= Num.L(5.0) + 1e-9, "no Legacy starting cash")
	e.abandon_challenge()
	assert_eq(e.challenge, "", "leaving ends it")
	assert_gt(e.cash_l, Num.L(5.0), "normal runs get the starting cash back")
	# one restaurant: no businesses or franchises
	e.start_challenge("solo")
	e.run_l = 40.0
	assert_false(e.biz_unlocked(0), "no businesses")
	assert_false(e.franchise_unlocked(), "no franchises")
	# saved and loaded
	var f := Econ.new()
	f.from_dict(e.to_dict())
	assert_eq(f.challenge, "solo", "challenge saved")
	assert_eq(int(f.challenge_best.get("health", 0)), 500, "progress saved")


func test_bonuses_count_everything_ever_earned():
	var e := _econ()
	e.stars_l = Num.L(100.0)
	e.stars_earned_l = Num.L(100.0)
	e.grit_l = Num.L(50.0)
	e.grit_earned_l = Num.L(50.0)
	var sm := e.star_l(e.agg())
	var gm := e.grit_mult_l()
	e.stars_l = Num.ZERO
	e.grit_l = Num.ZERO
	assert_eq(e.star_l(e.agg()), sm, "spending stars doesn't lower the bonus")
	assert_eq(e.grit_mult_l(), gm, "spending Grit doesn't lower the bonus")
	assert_near(Num.V(sm), 1.0 + 100.0 * Econ.STAR_BASE, 1e-9, "every star counts")
	assert_near(Num.V(gm), 1.0 + 50.0 * Econ.GRIT_BASE, 1e-9, "every Grit counts")


func test_recovering_from_the_red():
	var e := _econ_ch()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	e.cash_l = Num.ZERO
	e.owed_l = 12.0
	e.tick(1.0)
	assert_true(e.in_red(), "in the red")
	assert_gt(e.red_t, 0.0, "clock running")
	e.add_cash(13.0)
	assert_false(e.in_red(), "money in pays off what's owed first")
	assert_gt(e.cash_l, 12.0, "and the rest is cash")
	e.tick(1.0)
	assert_eq(e.red_t, 0.0, "clock resets once you're back above zero")
	assert_eq(e.bankruptcies, 0, "survived")


func test_grit_perks():
	var e := _econ()
	var id: int = e.by_key["gr_credit_0"]
	assert_false(e.buy_legacy(id), "can't afford without grit")
	e.grit_l = Num.L(100.0)
	var lim0: float = e.agg().credit_l
	assert_true(e.buy_legacy(id), "buy with grit")
	assert_gt(float(e.agg().credit_l), float(lim0), "credit limit raised")
	assert_lt(e.grit_l, Num.L(100.0), "grit spent, not stars")
	assert_true(e.legacy_available(e.upgrades[e.by_key["gr_credit_1"]]), "next tier opens")
	e.life_l = Econ.cp_l(14.0)
	e.prestige()
	assert_true(e.legacy.has(id), "grit perks survive selling")


# ------------------------------------------------------------------ side businesses

func _with_biz(i: int) -> Econ:
	var e := _econ()
	e.run_l = Biz.unlock_at_l(i)
	e.cash_l = 300.0
	assert_true(e.open_biz(i), "opened " + String(Biz.DEFS[i].name))
	return e


func test_businesses_open_and_earn():
	for i in Biz.N:
		var e := _econ()
		assert_false(e.biz_unlocked(i), "%s locked at first" % Biz.DEFS[i].name)
		e.run_l = Biz.unlock_at_l(i)
		assert_true(e.biz_unlocked(i), "unlocks with earnings")
		e.cash_l = Biz.open_cost_l(i) - 0.01
		assert_false(e.open_biz(i), "can't open without the money")
		e.cash_l = 300.0
		assert_true(e.open_biz(i), "opens")
		assert_true(e.buy_biz(i, "a", 10), "buy builds")
		assert_true(e.buy_biz(i, "b", 5), "buy the second build")
		var est := Biz.estimate(i, e.biz[i], e)
		assert_false(Num.is_zero(float(est.rev_l)), "%s makes money" % Biz.DEFS[i].name)
		# run it live for a while; every twist must produce money without errors
		e.events_on = false
		var earned := Num.ZERO
		for k in 600:
			var r := Biz.step(i, e.biz[i], e, 0.5)
			earned = Num.add(earned, float(r.rev_l))
			if String(Biz.DEFS[i].id) == "catering":
				Biz.auto_accept(i, e.biz[i], e)
			if String(Biz.DEFS[i].id) == "wholesale" and k % 60 == 59:
				earned = Num.add(earned, Biz.sell_stock_l(i, e.biz[i], e))
		assert_false(Num.is_zero(earned), "%s earns when run live" % Biz.DEFS[i].name)


func test_truck_spots():
	var e := _with_biz(0)
	var s: Dictionary = e.biz[0]
	s.spots = [0.5, 2.0, 1.0, 1.0]
	s.spot = 0
	s.spot_t = 100.0
	var low := Num.L(Biz.truck_u(s, e, 0.5)) + Biz.rev_base_l(0, e)
	assert_true(Biz.move_truck(s, 1), "move")
	var r := Biz.step(0, s, e, 1.0)
	assert_true(Num.is_zero(float(r.rev_l)), "no sales while driving")
	s.move_t = 0.0
	r = Biz.step(0, s, e, 1.0)
	assert_near(float(r.rev_l), low + Num.L(4.0), 1e-9, "the busy spot sells 4x the quiet one")


func test_bakery_balance():
	var e := _with_biz(1)
	e.challenge = "margins"
	e.mark_dirty()
	var s: Dictionary = e.biz[1]
	s.a = 20
	s.b = 1
	var lop := Biz.estimate(1, s, e)
	s.b = 13
	var bal := Biz.estimate(1, s, e)
	assert_eq(Num.scmp(Num.diff(float(bal.rev_l), float(bal.cost_l)), Num.diff(float(lop.rev_l), float(lop.cost_l))), 1, "enough counters to sell what you bake")


func test_catering_contracts():
	var e := _with_biz(2)
	var s: Dictionary = e.biz[2]
	s.a = 10
	s.offers = [{"name": "Wedding", "crew": 6, "dur": 30.0, "pay_u": 1000.0, "bonus": 1.0},
		{"name": "Gala", "crew": 6, "dur": 30.0, "pay_u": 1000.0, "bonus": 1.0}]
	s.offer_t = 999.0
	assert_true(Biz.accept(s, 0), "take a job")
	assert_false(Biz.can_accept(s, 0), "not enough free crew for the second")
	var paid := Num.ZERO
	for k in 31:
		paid = Num.add(paid, float(Biz.step(2, s, e, 1.0).rev_l))
	assert_near(paid, Num.L(1000.0) + Biz.rev_base_l(2, e), 1e-9, "job pays on completion")
	assert_true((s.jobs as Array).is_empty(), "crew is free again")


func test_bar_bouncers_and_happy_hour():
	var e := _with_biz(3)
	var s: Dictionary = e.biz[3]
	s.a = 30
	s.b = 0
	var wild := Biz.bar_incident_rate(s, e)
	s.b = 10
	var calm := Biz.bar_incident_rate(s, e)
	assert_lt(calm, wild * 0.2, "bouncers keep the peace")
	s.happy = true
	assert_gt(Biz.bar_incident_rate(s, e), calm, "happy hour is rowdier")
	var hh := Biz.estimate(3, s, e)
	s.happy = false
	assert_gt(float(hh.rev_l), float(Biz.estimate(3, s, e).rev_l) + Num.L(0.5), "but sells plenty")


func test_hotel_rates_and_seasons():
	var e := _with_biz(4)
	var s: Dictionary = e.biz[4]
	s.a = 20
	s.b = 10
	var peak := Biz.hotel_best_rate(4, s, e, 0)
	var off := Biz.hotel_best_rate(4, s, e, 2)
	assert_gt(peak, off, "charge more in peak season")
	var best := float(Biz.hotel_rev(4, s, e, 0, peak).rev_l)
	assert_gt(best, float(Biz.hotel_rev(4, s, e, 0, peak * 0.6).rev_l), "underpricing leaves money behind")
	assert_gt(best, float(Biz.hotel_rev(4, s, e, 0, peak * 1.6).rev_l), "overpricing empties rooms")


func test_wholesale_market_and_food_cut():
	var e := _with_biz(5)
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	# normal runs: delivery trucks boost the restaurant's income, and the buy row sees it
	var inc0 := float(e.income_info(e.agg()).total_l)
	var s3: Dictionary = e.biz[5].duplicate(true)
	s3.b = 20
	var g := e.biz_gain_with(5, s3)
	assert_true(not g[1] and not Num.is_zero(g[0]), "buying trucks shows a gain")
	e.biz[5].b = 20
	assert_gt(float(e.income_info(e.agg()).total_l), inc0, "delivery trucks boost restaurant income")
	# challenges: they cut food costs instead
	e.challenge = "margins"
	e.mark_dirty()
	e.biz[5].b = 1
	var food0 := e.food_cost_pct()
	e.biz[5].b = 20
	assert_lt(e.food_cost_pct(), food0, "in a challenge, delivery trucks cut food costs everywhere")
	assert_eq(e.supply_mult(), 1.0, "and don't also boost income")
	var s: Dictionary = e.biz[5]
	s.stock = 100.0
	s.mprice = 2.0
	var hi := Biz.sell_stock_l(5, s, e)
	s.stock = 100.0
	s.mprice = 0.5
	var lo := Biz.sell_stock_l(5, s, e)
	assert_near(hi, lo + Num.L(4.0), 1e-9, "timing the market matters")


func test_business_upgrades_and_save():
	var e := _with_biz(0)
	e.buy_biz(0, "a", 30)
	var m0 := Biz.mult_l(0, e)
	var id: int = e.by_key["bz_truck_a10"]
	assert_true(e.available(e.upgrades[id]), "milestone upgrade offered")
	assert_true(e.buy_upgrade(id), "bought")
	assert_near(Biz.mult_l(0, e), m0 + Num.L(Biz.MILESTONE_X), 1e-9, "milestone boosts the truck's income")
	var d: Dictionary = JSON.parse_string(JSON.stringify(e.to_dict()))
	var f := Econ.new()
	f.from_dict(d)
	assert_true(f.biz[0].open, "business saved")
	assert_eq(int(f.biz[0].a), int(e.biz[0].a), "builds saved")
	assert_near(Biz.mult_l(0, f), Biz.mult_l(0, e), 1e-9, "upgrades saved")


func test_selling_off_to_survive():
	var e := _with_biz(1)
	e.challenge = "margins"
	e.mark_dirty()
	e.cities[0] = 3
	e.cash_l = Num.ZERO
	e.owed_l = 300.0
	var v := e.sell_biz(1)
	assert_false(Num.is_zero(v), "selling a business raises cash")
	assert_false(e.biz[1].open, "it's gone")
	assert_false(Num.is_zero(e.sell_location()), "selling a franchise raises cash")
	assert_eq(int(e.cities[0]), 2, "one fewer location")


func test_business_tab_ui():
	var main = await _fresh()
	main.E.challenge = "margins"
	main.E.mark_dirty()
	main.E.run_l = Biz.unlock_at_l(2)
	main.E.cash_l = 30.0
	main._refresh_cache(true)
	main.press_button("tab:business")
	await wait_frames(2)
	assert_true(_has_button(main, "biz_open:0"), "open button shown")
	main.press_button("biz_open:0")
	main.press_button("biz_open:2")
	await wait_frames(2)
	assert_true(main.E.biz[0].open, "opened by button")
	assert_true(_has_button(main, "biz:2:a"), "build buttons on the newest business's page")
	main.press_button("biz_back")
	await wait_frames(2)
	assert_true(_has_button(main, "biz_page:0"), "list shows the truck")
	assert_true(_has_button(main, "borrow:1.0"), "bank shown")
	main.press_button("borrow:0.25")
	assert_false(Num.is_zero(main.E.debt_l), "borrowed by button")
	main.press_button("repay:1.0")
	assert_true(Num.is_zero(main.E.debt_l), "repaid by button")
	main.E.biz[2].offers = Biz.make_offers(2, main.E.biz[2], main.E)
	main.E.biz[2].a = 50
	main.press_button("accept:2:0")
	assert_eq((main.E.biz[2].jobs as Array).size(), 1, "accepted a contract")
	main.wipe_save()


func test_event_card_and_bankruptcy_ui():
	var main = await _fresh()
	main.E.challenge = "margins"
	main.E.mark_dirty()
	main.E.reps.ads = 30
	main.E.reps.tables = 30
	main.E.reps.cooks = 30
	main.E.run_l = Econ.cp_l(9.0)
	main.E.event = main.E.new_event(2.0)
	main._refresh_cache(true)
	await wait_frames(2)
	assert_eq(main.modal, "event", "an event opens as a pop-up")
	assert_true(_has_button(main, "event:0"), "event card has buttons")
	main.press_button("event:0")
	assert_false(main.E.event.is_empty(), "a tap right as it appears is ignored")
	main.modal_t -= 1.0
	main.press_button("event:0")
	assert_true(main.E.event.is_empty(), "answered")
	assert_eq(main.modal, "", "and closed")
	main.E.cash_l = Num.ZERO
	main.E.owed_l = 9.0
	await wait_frames(2)
	assert_true(_has_button(main, "red"), "the red banner replaces the stats strip")
	main.press_button("red")
	await wait_frames(2)
	assert_true(_has_button(main, "file"), "in-the-red options shown")
	main.press_button("file")
	assert_eq(main.modal, "file", "asks first")
	main.press_button("file_yes")
	await wait_frames(2)
	assert_eq(main.modal, "bankrupt", "challenge failed screen")
	main.press_button("after_bankrupt")
	assert_eq(main.modal, "concept", "then pick a concept")
	assert_eq(main.E.challenge, "", "back to a normal run")
	main.wipe_save()


func _has_button(main, id: String) -> bool:
	for b in main.buttons:
		if String(b.id) == id:
			return true
	return false


func test_business_builds_keep_paying_back():
	# while a business is small, the next build pays for itself in minutes
	for i in Biz.N:
		var e := _with_biz(i)
		var s: Dictionary = e.biz[i]
		s.a = 25
		s.b = 3 if Biz.DEFS[i].id == "catering" else int(25 * (0.7 if Biz.DEFS[i].id in ["bakery", "hotel"] else (0.6 if Biz.DEFS[i].id == "bar" else 0.3)))
		for u in e.upgrades:
			if not u.legacy and String(u.key).begins_with("bz_%s_a" % Biz.DEFS[i].id) and e.req_met(u):
				e.owned[u.id] = true
		e.mark_dirty()
		var s2 := s.duplicate(true)
		s2.a = 26
		var cost := e.biz_cost_l(i, "a", 1)
		if Biz.DEFS[i].id == "bakery":
			s2.b = int(s.b) + 1
			cost = Num.add(cost, e.biz_cost_l(i, "b", 1))
		var gain := e.biz_gain_with(i, s2)
		assert_false(gain[1] or Num.is_zero(gain[0]), "%s: the 26th build earns" % Biz.DEFS[i].name)
		assert_lt(Econ.secs_to_l(cost, gain[0]), 900.0, "%s: the 26th build pays back within 15 minutes" % Biz.DEFS[i].name)


func test_businesses_are_independent_of_the_restaurant():
	# restaurant upgrades and builds never change what a business earns or costs
	var e := _with_biz(0)
	e.buy_biz(0, "a", 40)
	var rev0 := float(Biz.estimate(0, e.biz[0], e).rev_l)
	var cost0 := e.biz_cost_l(0, "a", 1)
	var open0 := Biz.open_cost_l(0)
	e.reps.ads = 500
	e.reps.tables = 500
	e.reps.cooks = 500
	e.reps.recipes = 500
	for k in ["g_0", "g_1", "g_2", "t_ticket_0", "t_demand_0", "b_1", "k_diner_0"]:
		e.owned[e.by_key[k]] = true
	e.cities[0] = 40
	e.rest_peak_l = 80.0   # even a restaurant making 1e80 a second
	e.mark_dirty()
	assert_eq(float(Biz.estimate(0, e.biz[0], e).rev_l), rev0, "same sales however big the restaurant gets")
	assert_eq(e.biz_cost_l(0, "a", 1), cost0, "same build price")
	assert_eq(Biz.open_cost_l(0), open0, "same price to open, so a business is never out of reach")
	# its own upgrades and prestige do move it
	e.owned[e.by_key["bz_truck_x0"]] = true
	e.mark_dirty()
	assert_near(float(Biz.estimate(0, e.biz[0], e).rev_l), rev0 + Num.L(1.3), 1e-9, "its own upgrades raise it")
	var r1 := float(Biz.estimate(0, e.biz[0], e).rev_l)
	e.stars_earned_l = Num.L(1000.0)
	e.grit_earned_l = Num.L(100.0)
	e.mark_dirty()
	assert_near(float(Biz.estimate(0, e.biz[0], e).rev_l), r1 + e.star_l(e.agg()) + e.grit_mult_l(), 1e-9, "stars and Grit boost it like the restaurant")


func test_business_lines_go_on_forever():
	var e := _with_biz(0)
	var t: Dictionary = e.track_by_id["bz_truck_a"]
	_finish_line(e, "bz_truck_a")
	var u := e.track_next(t)
	assert_eq(String(u.name), "Food Truck: 1,025 Trucks", "a milestone every 25 trucks past 1,000")
	assert_eq(int(u.biz), 0, "on the truck's page")
	assert_false(e.req_met(u), "needs the trucks")
	e.biz[0].a = 1025
	assert_true(e.req_met(u), "then unlocks")
	e.cash_l = float(u.cost_l)
	assert_true(e.buy_upgrade(int(u.id)), "bought")
	assert_eq(String(e.track_next(t).name), "Food Truck: 1,050 Trucks", "next one")
	assert_eq(e.biz_next_milestone(0, "a"), 1050, "the page points at it")
	# extras and company-wide upgrades go on too
	_finish_line(e, "bz_truck_x")
	assert_false(e.track_next(e.track_by_id["bz_truck_x"]).is_empty(), "more extras past the list")
	_finish_line(e, "bz_all")
	assert_false(e.track_next(e.track_by_id["bz_all"]).is_empty(), "more company-wide upgrades")


func test_business_has_its_own_page():
	var main = await _fresh()
	var e = main.E
	e.run_l = 30.0
	e.cash_l = 12.0
	main.press_button("tab:business")
	await wait_frames(2)
	main.press_button("biz_open:0")
	await wait_frames(3)
	assert_true(bool(e.biz[0].open), "truck opened")
	assert_eq(main.biz_page, 0, "opening a business shows its page")
	var ids := []
	for b in main.buttons:
		ids.append(String(b.id))
	for want in ["biz_back", "biz:0:a", "biz:0:b", "sell_biz:0"]:
		assert_true(ids.has(want), "page has " + want)
	assert_false(ids.has("rep:tables"), "restaurant controls are not on the page")
	# tapping the scene sells for the truck, not the restaurant
	var taps0: int = e.taps
	var c0: float = e.cash_l
	var p: Vector2 = main.scene_r.get_center()
	main._on_press(p)
	main._on_release(p)
	assert_gt(e.cash_l, c0, "tapping the truck earns")
	assert_eq(e.taps, taps0, "it isn't a restaurant serve")
	# business upgrades live on the page, not in the global list
	main._refresh_cache(true)
	for u in main.glob_vis:
		assert_false(u.has("biz"), "no business upgrade in the Upgrades tab: " + String(u.name))
	var mine: Array = main.biz_vis[0]
	assert_gt(mine.size(), 0, "the truck has upgrades to buy on its page")
	# back to the list, and tapping the tab again also returns
	main.press_button("biz_back")
	await wait_frames(2)
	assert_eq(main.biz_page, -1, "back returns to the list")
	main.press_button("biz_page:0")
	assert_eq(main.biz_page, 0, "tile opens the page")
	main.press_button("tab:business")
	assert_eq(main.biz_page, -1, "tapping the tab again returns to the list")


func test_every_business_page_draws():
	var main = await _fresh()
	var e = main.E
	e.run_l = 30.0
	e.cash_l = 40.0
	for i in Biz.N:
		assert_true(e.open_biz(i), "open %d" % i)
		e.buy_biz(i, "a", 30)
		e.buy_biz(i, "b", 10)
	for i in Biz.N:
		main.open_biz_page(i)
		await wait_frames(2)
		var ids := []
		for b in main.buttons:
			ids.append(String(b.id))
		assert_true(ids.has("biz:%d:a" % i), "page %d draws its builds" % i)
		assert_false(Num.is_zero(e.biz_tap(i)), "page %d tap pays" % i)
	main.set_tab("build")
	await wait_frames(2)
	assert_false(main._on_biz_page(), "other tabs show the restaurant")


func test_limit_never_flips_back_to_guests():
	for auto in [false, true]:
		var e := _econ()
		e.reps.tables = 40
		e.reps.cooks = 40
		if auto:
			e.owned[e.by_key["a_price"]] = true
			e.mark_dirty()
		var left_demand := false
		for n in 200:
			e.reps.ads = n
			var lim := String(e.income_info(e.agg()).limit)
			if lim != "demand":
				left_demand = true
			elif left_demand:
				assert_true(false, "buying guests made guests the limit again at %d ads (auto price %s)" % [n, auto])
				return
		assert_true(left_demand, "enough ads moves the limit to seats or kitchen (auto price %s)" % auto)


func test_every_stat_costs_money_to_run_in_challenges():
	var e := _econ_ch()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	var base := e.income_info(e.agg())
	for r in ["ads", "tables", "cooks"]:
		var big := e.income_info(e.agg(), {r: 400})
		assert_lt(_net(big), _net(base), "overbuilding %s loses money" % r)
	# far too many seats sinks the restaurant
	assert_true(bool(e.income_info(e.agg(), {"tables": 2000}).net_neg), "a lopsided restaurant runs at a loss")
	# when the kitchen is the limit, cooks are what pay
	e.reps.cooks = 20
	var info := e.income_info(e.agg())
	assert_eq(String(info.limit), "kitchen", "kitchen limited")
	assert_gt(_net(e.income_info(e.agg(), {"cooks": 30})), _net(info), "and more cooks raise profit")


func test_events_follow_how_you_run_it():
	var e := _econ()
	e.rng.seed = 3
	e.reps.ads = 60
	e.reps.tables = 60
	e.reps.cooks = 25    # kitchen flat out
	e.owned[e.by_key["a_price"]] = true   # prices clear the queue, so the kitchen is the whole story
	e.mark_dirty()
	var rk := Events.risks(e)
	assert_gt(float(rk.r.kitchen), 0.8, "an overloaded kitchen is high risk")
	var kitchen_bad := 0
	var bad := 0
	for k in 300:
		var ev := e.new_event(2.0, rk)
		if not bool(ev.good):
			bad += 1
			if String(ev.get("risk", "")) == "kitchen":
				kitchen_bad += 1
				assert_true(String(ev.get("why", "")).contains("kitchen"), "the card says why")
	assert_gt(bad, 200, "a badly run restaurant mostly gets bad news")
	assert_gt(float(kitchen_bad) / bad, 0.6, "and mostly from the kitchen")
	# with spare cooks, inspections pass and good news dominates
	e = _econ()
	e.reps.ads = 20
	e.reps.tables = 60
	e.reps.cooks = 60
	rk = Events.risks(e)
	assert_eq(float(rk.r.kitchen), 0.0, "spare kitchen is safe")
	var good := 0
	for k in 300:
		if bool(e.new_event(2.0, rk).good):
			good += 1
	assert_gt(good, 150, "a calm restaurant mostly gets good news")
	# gamble odds depend on the risk
	var hot := Events.make(e.rng, 2.0, 0.0, 1.0, {"r": {"kitchen": 1.0, "none": 0.0}, "raw": {"kitchen": 1.0}}, {}, 0.0, "inspection")
	var calm := Events.make(e.rng, 2.0, 0.0, 1.0, {"r": {"kitchen": 0.0, "none": 0.0}, "raw": {"kitchen": 0.5}}, {}, 0.0, "inspection")
	assert_lt(float(hot.choices[1].chance), float(calm.choices[1].chance), "winging it is riskier with a hot kitchen")


func test_insurance_hedges_events():
	var e := _econ_ch()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	var bare := e.new_event(3.0, {}, "lawsuit")
	e.insured = true
	var covered := e.new_event(3.0, {}, "lawsuit")
	var c0 := Events.upfront(bare, bare.choices[0], e.cash_l)
	var c1 := Events.upfront(covered, covered.choices[0], e.cash_l)
	assert_near(c1, c0 + Num.L(1.0 - Econ.INSURE_COVER), 1e-9, "insurance pays most of the bill")
	var em := e.empire()
	assert_near(float(em.insurance_l), float(em.gross_l) + Num.L(Econ.INSURE_RATE), 1e-9, "for a premium on sales")
	var f := Econ.new()
	f.from_dict(e.to_dict())
	assert_true(f.insured, "the choice is saved")


func test_nothing_jumps_when_trouble_starts():
	var main = await _fresh()
	main.E.challenge = "margins"   # debt and the red banner only exist in challenges
	main.E.mark_dirty()
	main.E.reps.ads = 40
	main.E.reps.tables = 40
	main.E.reps.cooks = 40
	main.E.run_l = 12.0
	main.E.cash_l = 9.0
	main._refresh_cache(true)
	var heights := {}
	for t in ["build", "business"]:
		main.press_button("tab:" + t)
		await wait_frames(2)
		heights[t] = main.scroll_max[t]
	var first_btn := {}
	for b in main.buttons:
		first_btn[String(b.id)] = b.rect
	# an event, debt and being in the red must not push anything around
	main.E.borrow(main.E.credit_available_l() + Num.L(0.5))
	main.E.event = main.E.new_event(2.0, {}, "lawsuit")
	main.E.cash_l = Num.ZERO
	main.E.owed_l = 6.0
	main.modal = ""
	main._refresh_cache(true)
	for t in ["build", "business"]:
		main.set_tab(t)
		main.modal = ""
		await wait_frames(2)
		assert_near(float(main.scroll_max[t]), float(heights[t]), 0.5, "%s tab keeps its height" % t)
	main.modal = ""
	await wait_frames(1)
	for b in main.buttons:
		var id := String(b.id)
		if first_btn.has(id) and String(b.layer) == "content":
			assert_true((b.rect as Rect2).position.is_equal_approx((first_btn[id] as Rect2).position), "%s stayed put" % id)
	main.wipe_save()


func test_saves_from_the_cost_rules_are_forgiven():
	var e := _econ()
	e.reps.ads = 300
	var d := e.to_dict()
	d["econ"] = 3
	d.erase("challenge")
	d.erase("cash_l")
	d.erase("debt_l")
	d.erase("owed_l")
	d["cash"] = -5e8
	d["debt"] = 1e9
	d["red_t"] = 200.0
	var f := Econ.new()
	f.from_dict(d)
	assert_true(f.rules_notice, "the player is told what changed")
	assert_true(Num.is_zero(f.debt_l), "debt forgiven")
	assert_false(f.in_red(), "no longer in the red")
	assert_eq(f.challenge, "", "a normal run")
	var g := Econ.new()
	g.from_dict(f.to_dict())
	assert_false(g.rules_notice, "only once")


# ------------------------------------------------------------------ text never overlaps or gets cut off

var _ui_problems: Array = []
var _ui_checked := 0


## Checks the frame just drawn: no two pieces of text overlap, nothing runs off screen,
## nothing is shrunk to an unreadable size.
func _check_text(main, where: String) -> void:
	var vs: Vector2 = main.get_viewport_rect().size
	var items: Array = []
	for t in main.text_log:
		if bool(t.deco):
			continue
		var r: Rect2 = t.r
		if t.cv == main.content and not r.intersects(main.content_r):
			continue
		if main.modal != "" and t.cv != main.overlay:
			continue   # covered by the pop-up
		items.append(t)
		_ui_checked += 1
		if r.position.x < -0.5 or r.end.x > vs.x + 0.5:
			_ui_problems.append("%s: off screen \"%s\" x %d..%d (screen %d)" % [where, t.s, r.position.x, r.end.x, vs.x])
		if int(t.size) < mini(10, int(t.req)) or int(t.size) < int(t.req) * 0.7:
			_ui_problems.append("%s: \"%s\" shrunk from %d to %d" % [where, t.s, t.req, t.size])
		if float(t.limit) > 0.0 and r.size.x > float(t.limit) + 0.5:
			_ui_problems.append("%s: \"%s\" wider than its box (%d > %d)" % [where, t.s, r.size.x, t.limit])
	for t in items:
		var tr: Rect2 = (t.r as Rect2).grow(-1.0)
		for b in main.button_log:
			if b.cv != t.cv:
				continue
			if main.modal != "" and b.cv != main.overlay:
				continue
			var br: Rect2 = b.r
			if b.cv == main.content and not br.intersects(main.content_r):
				continue
			if String(t.owner) == String(b.key):
				if not br.encloses(tr):
					_ui_problems.append("%s: label \"%s\" spills out of its button" % [where, t.s])
			elif tr.intersects(br):
				_ui_problems.append("%s: \"%s\" runs into the %s button" % [where, t.s, b.id])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			if a.cv != b.cv:
				continue
			var ra: Rect2 = (a.r as Rect2).grow(-1.0)
			var rb: Rect2 = (b.r as Rect2).grow(-1.0)
			if ra.intersects(rb):
				_ui_problems.append("%s: \"%s\" overlaps \"%s\"" % [where, a.s, b.s])


func _walk_tab(main, tab: String, where: String) -> void:
	if main.tab != tab:
		main.set_tab(tab)
	main.scroll[tab] = 0.0
	await wait_frames(2)
	var guard := 0
	while guard < 60:
		guard += 1
		_check_text(main, "%s @%d" % [where, int(main.scroll[tab])])
		if float(main.scroll[tab]) >= float(main.scroll_max[tab]) - 1.0:
			break
		main.scroll[tab] = minf(float(main.scroll_max[tab]), float(main.scroll[tab]) + main.content_r.size.y * 0.95)   # overlapping text sits together, so screen-sized steps see every pair
		await wait_frames(1)


func _modal_check(main, m: String, data: Dictionary, where: String) -> void:
	main.open_modal(m, data)
	await wait_frames(2)
	_check_text(main, where + " modal " + m)
	main.modal = ""


func _stress_state(main, big: bool) -> void:
	var e = main.E
	e.reps.ads = 1234 if big else 30
	e.reps.tables = 1234 if big else 34
	e.reps.cooks = 1234 if big else 26
	e.reps.recipes = 1234 if big else 20
	# big: numbers far past the named suffixes, so every label must fit an exponent like e12,345
	e.cash_l = 12345.6 if big else Num.L(5000.0)
	e.run_l = 12350.0 if big else 12.0
	e.life_l = 12360.0 if big else 12.0
	e.stars_l = 1234.5 if big else Num.ZERO
	e.stars_earned_l = 1234.6 if big else Num.ZERO
	e.grit_l = 345.6 if big else Num.ZERO
	e.grit_earned_l = 345.7 if big else Num.ZERO
	e.bankruptcies = 3 if big else 0
	e.prestiges = 4 if big else 0
	for i in e.NC:
		e.cities[i] = 250 if big else (7 if i == 0 else 0)
	for i in e.NV:
		e.vents[i] = 300 if big else 0
	if big:
		for u in e.upgrades:
			if String(u.key).begins_with("s_"):
				e.owned[int(u.id)] = true   # every synergy, so build rows show their "Also" line
	e.mark_dirty()
	for i in Biz.N:
		e.open_biz(i)
		e.buy_biz(i, "a", 400 if big else 30)
		e.buy_biz(i, "b", 120 if big else 8)
	main._refresh_cache(true)


func _ui_begin(width: int, big: bool):
	var main = await _fresh()
	main.log_text = true
	_ui_problems = []
	_ui_checked = 0
	get_tree().root.size = Vector2i(width, 780)
	main.E.new_game()
	main.E.prestiges = 3
	main.E.choose_concept("fastfood")
	main.modal = ""
	_stress_state(main, big)
	return main


func _ui_end(main, name: String) -> void:
	get_tree().root.size = Vector2i(390, 844)
	main.log_text = false
	var uniq := {}
	for p in _ui_problems:
		uniq[p] = true
	var dump := FileAccess.open("user://ui_%s.txt" % name, FileAccess.WRITE)
	if dump:
		for p in uniq:
			dump.store_line(String(p))
		dump.close()
	assert_gt(_ui_checked, 50, "the check really looked at the text on screen")
	assert_eq(uniq.size(), 0, "%d text problems (see user://ui_%s.txt)" % [uniq.size(), name])
	main.wipe_save()


func _ui_tabs(width: int, big: bool, which := ["build", "upgrades", "business", "franchise", "legacy", "more"]) -> void:
	var main = await _ui_begin(width, big)
	var tag := "%dpx %s" % [width, "big" if big else "early"]
	for t in which:
		await _walk_tab(main, t, tag + " " + t)
	_ui_end(main, "tabs_%d_%s_%d" % [width, big, which.size()])


func _ui_filters(width: int, big: bool, only := []) -> void:
	var main = await _ui_begin(width, big)
	var tag := "%dpx %s" % [width, "big" if big else "early"]
	for f in main.UPG_FILTERS:
		if f == "all" or (not only.is_empty() and not only.has(f)):
			continue   # "all" is covered by the tabs walk
		main.upg_filter = f
		await _walk_tab(main, "upgrades", tag + " upgrades/" + f)
	main.upg_filter = "all"
	_ui_end(main, "filters_%d_%s_%d" % [width, big, only.size()])


func _ui_pages(width: int, big: bool) -> void:
	var main = await _ui_begin(width, big)
	var tag := "%dpx %s" % [width, "big" if big else "early"]
	for i in Biz.N:
		main.open_biz_page(i)
		await _walk_tab(main, "business", tag + " page " + Biz.DEFS[i].name)
	main.biz_page = -1
	_ui_end(main, "pages_%d_%s" % [width, big])


func _ui_popups(width: int, big: bool) -> void:
	var main = await _ui_begin(width, big)
	var tag := "%dpx %s" % [width, "big" if big else "early"]
	main.set_tab("build")   # the red banner, bank and loans are covered by the challenge walk
	for m in ["concept", "sell", "help", "reset", "rules"]:
		await _modal_check(main, m, {}, tag)
	await _modal_check(main, "welcome", {"away": 7300.0, "gain_l": 12345.6}, tag)
	await _modal_check(main, "import", {"stars_l": 1234.5, "cash_l": 12345.6, "life_l": 12360.0, "t": 1759000000}, tag)
	await _modal_check(main, "sell_biz", {"i": 5}, tag)
	await _modal_check(main, "concept", {"stars_l": 1234.5}, tag)
	for src in Events.LIST:
		main.E.event = main.E.new_event(12300.0, {}, String(src.id))
		await _modal_check(main, "event", {}, tag + " " + String(src.id))
	main.E.event = {}
	_ui_end(main, "popups_%d_%s" % [width, big])


func _ui_challenge(width: int, big: bool) -> void:
	var main = await _ui_begin(width, big)
	var tag := "%dpx %s challenge" % [width, "big" if big else "early"]
	main.E.challenge_best = {"margins": 3, "health": 10, "solo": 1234}
	main.E.challenge = "recession"
	main.E.challenge_level = 3456 if big else 9
	main.E.insured = true
	main.E.mark_dirty()
	main._refresh_cache(true)
	for t in ["build", "business", "legacy"]:
		await _walk_tab(main, t, tag + " " + t)
	main.E.run_l = main.E.challenge_goal_l() + Num.L(3.0)
	await _walk_tab(main, "legacy", tag + " legacy done")
	for m in ["sell", "abandon", "file"]:
		await _modal_check(main, m, {}, tag)
	await _modal_check(main, "challenge", {"id": "shoestring"}, tag)
	await _modal_check(main, "bankrupt", {"challenge": "recession", "level": 3456}, tag)
	await _modal_check(main, "concept", {"stars_l": 1234.5, "grit_l": 345.6, "done": {"id": "recession", "level": 3456, "grit_l": 345.6}}, tag)
	main.E.borrow(main.E.credit_available_l())
	main.E.owed_l = Num.add(main.E.cash_l, 6.0)
	main.E.cash_l = Num.ZERO
	await wait_frames(2)
	_check_text(main, tag + " in the red")
	await _modal_check(main, "red", {}, tag)
	_ui_end(main, "challenge_%d_%s" % [width, big])


func test_text_fits_challenge_360_early(): await _ui_challenge(360, false)
func test_text_fits_challenge_360_big(): await _ui_challenge(360, true)
func test_text_fits_challenge_412_big(): await _ui_challenge(412, true)
func test_text_fits_tabs_360_early(): await _ui_tabs(360, false)
func test_text_fits_tabs_360_big(): await _ui_tabs(360, true, ["build"])
func test_text_fits_tabs_360_big_upgrades(): await _ui_tabs(360, true, ["upgrades"])
func test_text_fits_tabs_360_big_rest(): await _ui_tabs(360, true, ["business", "franchise", "legacy", "more"])
func test_text_fits_tabs_412_early(): await _ui_tabs(412, false)
func test_text_fits_tabs_412_big(): await _ui_tabs(412, true, ["build"])
func test_text_fits_tabs_412_big_upgrades(): await _ui_tabs(412, true, ["upgrades"])
func test_text_fits_tabs_412_big_rest(): await _ui_tabs(412, true, ["business", "franchise", "legacy", "more"])
func test_text_fits_filters_360_early(): await _ui_filters(360, false)
func test_text_fits_filters_360_big(): await _ui_filters(360, true, ["afford", "stats"])
func test_text_fits_filters_360_big_more(): await _ui_filters(360, true, ["business", "growth", "cross"])
func test_text_fits_filters_412_big(): await _ui_filters(412, true, ["afford", "stats"])
func test_text_fits_filters_412_big_more(): await _ui_filters(412, true, ["business", "growth", "cross"])
func test_text_fits_pages_360_early(): await _ui_pages(360, false)
func test_text_fits_pages_360_big(): await _ui_pages(360, true)
func test_text_fits_pages_412_big(): await _ui_pages(412, true)
func test_text_fits_popups_360_early(): await _ui_popups(360, false)
func test_text_fits_popups_360_big(): await _ui_popups(360, true)
func test_text_fits_popups_412_big(): await _ui_popups(412, true)


func test_build_rows_explain_synergies():
	var main = await _fresh()
	var e = main.E
	e.reps.ads = 20
	e.reps.tables = 20
	var d0: Array = main.rep_deltas("ads", 1)
	assert_eq(d0.size(), 1, "without synergies, ads only add guests")
	assert_eq(String(d0[0].stat), "demand", "guests")
	e.owned[e.by_key["s_ads_seating_0"]] = true
	e.mark_dirty()
	var d1: Array = main.rep_deltas("ads", 1)
	var seats := Num.ZERO
	for dl in d1:
		if String(dl.stat) == "seating":
			seats = float(dl.d)
	assert_false(Num.is_zero(seats), "with Reservations by Ad, an ad also adds seats, and the row says so")
	var before: float = e.stat_l("seating", e.agg())
	e.cash_l = 12.0
	assert_true(e.buy_rep("ads", 1), "bought")
	assert_near(Num.sub(e.stat_l("seating", e.agg()), before), seats, 1e-6, "by exactly what it showed")
	assert_true(e.effect_text(e.upgrades[e.by_key["s_ads_seating_0"]].eff).begins_with("Each Ad Campaign you own"), "the upgrade says what it does")
	main.wipe_save()


func test_every_grit_perk_helps_a_normal_run():
	var lines := {}
	for u in Econ.new().upgrades:
		if String(u.get("cur", "")) == "grit":
			lines[String(u.req[1])] = u
	assert_eq(lines.size(), 10, "ten Grit perk lines")
	for kind in lines:
		var e := _econ()
		e.reps.ads = 40
		e.reps.tables = 40
		e.reps.cooks = 40
		e.reps.recipes = 30
		e.cities[0] = 3
		e.run_l = 30.0
		e.cash_l = 40.0
		e.open_biz(0)
		e.buy_biz(0, "a", 40)
		var before := [float(e.empire().gross_l), e.rep_cost_l("tables", 1), e.city_next_cost_l(0), e.ceiling_l(e.agg()), float(e.agg().startreps)]
		var u: Dictionary = lines[kind]
		e.legacy[int(u.id)] = true
		e.mark_dirty()
		var after := [float(e.empire().gross_l), e.rep_cost_l("tables", 1), e.city_next_cost_l(0), e.ceiling_l(e.agg()), float(e.agg().startreps)]
		var better: bool = after[0] > before[0] + 1e-5 or after[1] < before[1] - 1e-5 or after[2] < before[2] - 1e-5 \
			or after[3] > before[3] + 1e-5 or after[4] > before[4] or float(e.agg().luck) > 0.0
		assert_true(better, "%s does something in a normal run" % u.name)
		var txt := e.effect_text(u.eff)
		for word in ["Running costs", "Food costs", "Credit", "Loan", "recover from the red", "selling off"]:
			if txt.contains(word):
				assert_true(txt.contains("(challenges)"), "%s labels its challenge-only part" % u.name)


func test_challenge_rewards_and_difficulty():
	var e := _econ()
	e.start_challenge("margins")
	e.choose_concept("diner")
	var goal := e.challenge_goal_l(0)
	var g1 := e.challenge_reward_for_l("margins", 0, goal)
	var g20 := e.challenge_reward_for_l("margins", 0, goal + Num.L(Econ.REWARD_CAP))
	var g_farm := e.challenge_reward_for_l("margins", 0, goal + 9.0)
	assert_gt(g20, g1, "earning past the goal pays more")
	assert_eq(g_farm, g20, "but only up to 20x the goal")
	assert_gt(e.challenge_reward_for_l("margins", 1, e.challenge_goal_l(1)), g20, "the next level pays more than farming this one")
	assert_gt(e.challenge_reward_for_l("margins", 100, e.challenge_goal_l(100)), e.challenge_reward_for_l("margins", 99, e.challenge_goal_l(99)), "and so on forever")
	var up0 := float(e.agg().upkeep)
	e.challenge_level = 4
	e.mark_dirty()
	assert_gt(float(e.agg().upkeep), up0 * 1.5, "higher levels run hotter")


func test_events_without_running_costs_still_cost():
	var e := _econ()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	for id in ["supplier", "walkout"]:
		var ev := e.new_event(2.0, {}, id)
		var ch: Dictionary = ev.choices[0] if id == "walkout" else ev.choices[1]
		var kinds := []
		for op in ch.ops:
			kinds.append(String(op[1]) if String(op[0]) == "fx" else String(op[0]))
		assert_true(kinds.has("income"), "%s: the cost-only choice becomes an income penalty" % id)
		assert_false(kinds.has("food") or kinds.has("wages"), "%s: nothing that only touches running costs" % id)
	# a bill you can't cover comes out of income
	e.cash_l = 1.0
	var ev := e.new_event(6.0, {}, "lawsuit")
	e.event = ev
	var inc0 := float(e.income_info(e.agg()).total_l)
	e.answer_event(0)
	assert_true(Num.is_zero(e.cash_l), "paid what it had")
	assert_lt(float(e.income_info(e.agg()).total_l), inc0 + Num.L(0.75), "the rest comes out of income for a while")
	assert_gt(Events.shortfall_secs(ev, 8.0), 0.0, "for a time based on the shortfall")


func test_bar_and_hotel_still_bite_without_costs():
	var e := _with_biz(3)
	assert_eq(Biz.bar_close_secs(e), 30.0, "a fight shuts the bar longer outside challenges")
	e.challenge = "margins"
	assert_eq(Biz.bar_close_secs(e), 10.0, "in a challenge the fine does the work")
	var h := _with_biz(4)
	var s: Dictionary = h.biz[4]
	s.a = 40
	var sea := Biz.season(s)
	var best := Biz.hotel_best_rate(4, s, h, sea)
	var full: Dictionary = Biz.hotel_rev(4, s, h, sea, best)
	var pricey: Dictionary = Biz.hotel_rev(4, s, h, sea, best * 3.0)
	assert_lt(float(pricey.rev_l), float(full.rev_l), "overpricing empties rooms and costs income")


func test_fine_dining_has_a_downside():
	var d := _econ("diner")
	var f := _econ("fine")
	assert_gt(f.rep_cost_l("tables", 1), d.rep_cost_l("tables", 1) - Num.L(0.75), "Fine Dining's tables cost more")
	assert_gt(f.rep_cost_l("cooks", 1), d.rep_cost_l("cooks", 1), "and its cooks")


func test_challenge_only_buttons_do_nothing_in_normal_runs():
	var main = await _fresh()
	main.E.reps.tables = 33
	main.press_button("file_yes")
	main.press_button("abandon_yes")
	main.press_button("insure")
	assert_eq(int(main.E.reps.tables), 33, "the run is untouched")
	assert_eq(main.E.bankruptcies, 0, "no bust recorded")
	assert_false(main.E.insured, "no insurance outside challenges")
	# Shoestring has no bank: no emergency loan button
	main.E.start_challenge("shoestring")
	main.E.choose_concept("diner")
	main.modal = ""
	main.E.cash_l = Num.ZERO
	main.E.owed_l = 6.0
	main.open_modal("red")
	await wait_frames(2)
	assert_false(_has_button(main, "rescue"), "no loan offered without a bank")
	assert_true(_has_button(main, "file"), "giving up is")
	main.wipe_save()


func test_automation_waits_for_pop_ups():
	var main = await _fresh()
	var e = main.E
	e.owned[e.by_key["a_ads"]] = true
	e.mark_dirty()
	e.cash_l = 9.0
	e.event = e.new_event(2.0, {}, "outage")
	await wait_frames(2)
	assert_eq(main.modal, "event", "event open")
	var ads: int = e.reps.ads
	for k in 30:
		await wait_frames(1)
	assert_eq(int(e.reps.ads), ads, "managers don't spend while a pop-up waits")
	main.wipe_save()
