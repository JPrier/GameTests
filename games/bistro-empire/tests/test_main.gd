extends GameTest


func _econ(concept := "diner") -> Econ:
	var e := Econ.new()
	e.new_game()
	e.prestiges = 5
	e.choose_concept(concept)
	e.prestiges = 0
	return e


func _fresh() -> Node:
	var main = await load_scene("res://main.tscn")
	main.wipe_save()
	main.E.new_game()
	main.E.choose_concept("diner")
	main.modal = ""
	main._refresh_cache(true)
	return main


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
			assert_gt(float(u.star), 0.0, "legacy star cost " + String(u.name))
		else:
			var c := e.upgrade_cost(u)
			assert_true(c > 0.0 and c < 1e250 and not is_inf(c) and not is_nan(c), "cost range " + String(u.name))
		assert_ne(e.effect_text(u.eff), "", "effect text " + String(u.name))
		assert_ne(e.req_text(u) if not u.legacy else "x", "", "requirement text " + String(u.name))


# ------------------------------------------------------------------ economy

func test_starting_state():
	var e := _econ()
	assert_eq(e.cash, 5.0, "start with $5")
	assert_gt(e.income(), 0.0, "something trickles in from the start")
	assert_eq(String(e.income_info(e.agg()).limit), "seating", "first bottleneck is seats")


func test_buy_rep_costs_and_grows():
	var e := _econ()
	e.cash = 1000.0
	var c1 := e.rep_cost("tables", 1)
	assert_true(e.buy_rep("tables", 1), "buy a table")
	assert_near(e.cash, 1000.0 - c1, 1e-6, "paid the price")
	assert_gt(e.rep_cost("tables", 1), c1, "next one costs more")
	var c10 := e.rep_cost("tables", 10)
	var sum := 0.0
	for i in 10:
		sum += e.rep_cost_at("tables", int(e.reps.tables) + i, float(e.agg().cost.tables))
	assert_near(c10, sum, sum * 1e-9, "bulk cost is the geometric sum")
	e.cash = 0.0
	assert_false(e.buy_rep("ads", 1), "can't buy when broke")


func test_max_affordable_is_exact():
	var e := _econ()
	e.cash = 12345.0
	for r in Econ.REPS:
		var k := e.rep_max_affordable(r)
		assert_true(e.rep_cost(r, k) <= e.cash + 1e-6, "max fits " + r)
		assert_gt(e.rep_cost(r, k + 1), e.cash, "max+1 does not fit " + r)


func test_bottleneck_caps_service():
	var e := _econ()
	e.reps.ads = 200
	var inf := e.income_info(e.agg())
	assert_true(float(inf.served) <= float(inf.cap) + 1e-9, "never serve more than capacity")
	assert_true(String(inf.limit) == "seating" or String(inf.limit) == "kitchen", "lots of ads, capacity limits")
	var before := float(inf.total)
	e.reps.ads = 300
	var after := float(e.income_info(e.agg()).total)
	assert_near(after, before, before * 0.001, "more ads past the bottleneck bring in nothing")
	assert_gt(float(e.income_info(e.agg()).upkeep), float(inf.upkeep), "but they still cost upkeep")
	e.reps.tables = 50
	e.reps.cooks = 50
	assert_gt(float(e.income_info(e.agg()).total), before * 3.0, "raising both capacities pays off")


func test_best_price_beats_neighbours():
	var e := _econ()
	e.reps.ads = 150
	e.reps.tables = 20
	e.reps.cooks = 20
	var u: Dictionary = e.upgrades[e.by_key["b_0"]]
	e.owned[u.id] = true
	e.mark_dirty()
	var a := e.agg()
	assert_true(e.price_unlocked(a), "Price Tags unlocks pricing")
	var best := e.best_price(a)
	e.price = best
	var at := float(e.income_info(a).total)
	for f in [0.8, 0.9, 1.1, 1.25]:
		e.price = clampf(best * f, Econ.PRICE_MIN, e.ceiling(a))
		assert_true(float(e.income_info(a).total) <= at * 1.0001, "best price is a local maximum (x%s)" % f)
	e.price = 100.0
	assert_near(e.effective_price(a), e.ceiling(a), 1e-9, "price clamps to the brand ceiling")


func test_concepts_differ():
	var d := _econ("diner")
	var f := _econ("fastfood")
	var fd := _econ("fine")
	assert_gt(f.stat("demand", f.agg()), d.stat("demand", d.agg()), "fast food draws more guests")
	assert_gt(fd.stat("ticket", fd.agg()), d.stat("ticket", d.agg()), "fine dining has bigger bills")
	assert_lt(fd.stat("seating", fd.agg()), d.stat("seating", d.agg()), "fine dining has fewer seats")
	var e := Econ.new()
	e.new_game()
	assert_false(e.choose_concept("fine"), "fine dining locked before first sale")
	assert_true(e.choose_concept("fastfood"), "fast food open from the start")


func test_concept_upgrades_are_exclusive():
	var e := _econ("diner")
	e.run_earned = 1e300
	var diner_u: Dictionary = e.upgrades[e.by_key["k_diner_0"]]
	var cafe_u: Dictionary = e.upgrades[e.by_key["k_cafe_0"]]
	assert_true(e.available(diner_u), "own concept's signature upgrade shows")
	assert_false(e.available(cafe_u), "other concept's does not")


func test_crossroads_lock_the_other_side():
	var e := _econ()
	var a_id: int = e.by_key["x_0_0_a"]
	var b_id: int = e.by_key["x_0_0_b"]
	e.run_earned = 1e12
	e.cash = 1e12
	assert_true(e.available(e.upgrades[a_id]) and e.available(e.upgrades[b_id]), "both sides offered")
	assert_true(e.buy_upgrade(a_id), "pick a side")
	assert_false(e.available(e.upgrades[b_id]), "other side locked")
	assert_false(e.buy_upgrade(b_id), "can't buy the locked side")
	e.cash = 1e40
	e.life_earned = 1e40
	e.prestige()
	e.run_earned = 1e12
	assert_true(e.available(e.upgrades[b_id]), "selling the company reopens the choice")


func test_upgrade_requirements():
	var e := _econ()
	var m: Dictionary = e.upgrades[e.by_key["m_ads_25"]]
	e.cash = 1e30
	assert_false(e.available(m), "milestone hidden before 25 ads")
	e.reps.ads = 25
	assert_true(e.available(m), "milestone shows at 25 ads")
	var before := e.stat("demand", e.agg())
	assert_true(e.buy_upgrade(int(m.id)), "buy milestone")
	assert_near(e.stat("demand", e.agg()), before * 2.0, before * 1e-9, "milestone doubles demand")


func test_franchise_and_ventures():
	var e := _econ()
	assert_false(e.franchise_unlocked(), "franchising locked at start")
	e.run_earned = Econ.cp(1.0e7)
	assert_true(e.franchise_unlocked(), "franchising unlocks with earnings")
	assert_true(e.city_unlocked(0), "first city open")
	assert_false(e.city_unlocked(1), "second city needs the first")
	var base := e.income()
	e.cash = 1e40
	assert_true(e.buy_city(0), "open in the first city")
	assert_gt(e.income(), base, "royalties raise income")
	assert_eq(e.locations(), 1, "one location")
	assert_false(e.ventures_unlocked(), "ventures need 15 locations")
	for i in 14:
		e.buy_city(0)
	assert_true(e.ventures_unlocked(), "ventures open at 15 locations")
	var d := e.stat("demand", e.agg())
	assert_true(e.buy_vent(0), "start the food trucks")
	assert_gt(e.stat("demand", e.agg()), d, "food trucks raise demand")


# ------------------------------------------------------------------ prestige & save

func test_prestige_keeps_stars_and_legacy():
	var e := _econ()
	assert_false(e.can_prestige(), "nothing to sell at first")
	e.life_earned = Econ.cp(1.0e14)
	e.run_earned = e.life_earned
	e.reps.ads = 50
	e.cities[0] = 3
	var g := e.stars_pending()
	assert_gt(g, 0.0, "stars pending")
	var got := e.prestige()
	assert_eq(got, g, "granted the pending stars")
	assert_eq(e.stars, g, "stars kept")
	assert_eq(int(e.reps.ads), 0, "builds reset")
	assert_eq(e.locations(), 0, "franchises reset")
	assert_eq(e.prestiges, 1, "counted the sale")
	assert_false(e.concept_chosen, "pick a new concept after selling")
	assert_eq(e.stars_pending(), 0.0, "no double counting")
	assert_gt(e.star_mult(e.agg()), 1.0, "stars boost income")
	var lid: int = e.by_key["l_global_0"]
	e.stars = 1000.0
	assert_true(e.buy_legacy(lid), "buy a legacy perk")
	assert_false(e.legacy_available(e.upgrades[e.by_key["l_global_2"]]), "tiers must be bought in order")
	e.life_earned *= 10.0
	e.prestige()
	assert_true(e.legacy.has(lid), "legacy perks survive selling")


func test_save_roundtrip():
	var e := _econ("fastfood")
	e.reps.cooks = 17
	e.run_earned = 1e12
	e.cash = 1e12
	assert_true(e.buy_upgrade(e.by_key["x_1_0_b"]), "bought a crossroads side")
	e.cash = 123456.0
	e.stars = 42.0
	e.legacy[e.by_key["l_tap_0"]] = true
	e.cities[0] = 2
	var d: Dictionary = JSON.parse_string(JSON.stringify(e.to_dict()))
	var f := Econ.new()
	f.from_dict(d)
	assert_eq(f.concept, "fastfood", "concept")
	assert_near(f.cash, e.cash, 1e-6, "cash")
	assert_eq(int(f.reps.cooks), 17, "builds")
	assert_true(f.owned.has(e.by_key["x_1_0_b"]), "owned upgrades by key")
	assert_true(f.legacy.has(e.by_key["l_tap_0"]), "legacy by key")
	assert_eq(int(f.cities[0]), 2, "franchises")
	assert_near(f.income(), e.income(), absf(e.income()) * 1e-9, "same income after load")


func test_offline_gain_is_capped():
	var e := _econ()
	e.reps.tables = 20
	e.reps.cooks = 20
	e.reps.ads = 20
	var inc := e.income()
	assert_near(e.offline_gain(3600.0), inc * 3600.0 * Econ.OFFLINE_BASE, inc, "25% for an hour")
	assert_near(e.offline_gain(1e7), e.offline_gain(2.0 * 3600.0), inc, "capped at 2 hours")


func test_number_format():
	assert_eq(Econ.fmt_money(5.0), "$5", "small")
	assert_eq(Econ.fmt_money(1234.0), "$1.23K", "thousands")
	assert_eq(Econ.fmt_money(999999.0), "$1.00M", "rounds up a suffix")
	assert_eq(Econ.fmt_num(2.5e15), "2.50Qa", "quadrillions")
	assert_true(Econ.fmt_num(1e90).contains("e"), "falls back to exponent")
	assert_eq(Econ.roman(14), "XIV", "roman numerals")


# ------------------------------------------------------------------ UI

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
	var c0: float = main.E.cash
	var v: float = main.E.tap_value()
	main.serve()
	assert_near(main.E.cash, c0 + v, 1e-6, "tap adds its value")
	await press_key(KEY_SPACE)
	await wait_frames(1)
	assert_gt(main.E.taps, 1, "space serves too")


func test_tap_buy_button_and_tabs():
	var main = await _fresh()
	main.E.cash = 1000.0
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
	main.E.cash = 1e9
	main.E.run_earned = 1e9
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
	main.dev_add_cash(Econ.cp(1.0e14))
	main.press_button("tab:legacy")
	main.press_button("sell")
	assert_eq(main.modal, "sell", "confirm first")
	main.press_button("sell_yes")
	assert_eq(main.modal, "concept", "choose next concept")
	assert_gt(main.E.stars, 0.0, "got stars")
	main.press_button("concept:fine")
	assert_eq(main.E.concept, "fine", "fine dining unlocked after one sale")
	main.save_game()
	var again = await load_scene("res://main.tscn")
	assert_eq(again.E.prestiges, 1, "save restored")
	main.wipe_save()


# ------------------------------------------------------------------ saving safety

func _store() -> SaveStore:
	var s := SaveStore.new()
	s.erase_all()
	return s


func _sample_state(life: float) -> Dictionary:
	var e := _econ("fastfood")
	e.cash = 777.0
	e.life_earned = life
	e.reps.tables = 9
	return e.to_dict()


func test_pack_unpack_and_tamper():
	var st := _sample_state(1000.0)
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
	assert_eq(float(b.state.life_earned), 10.0, "with the right data")
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
	assert_true(FileAccess.file_exists("user://bistro_empire.corrupt-file-%d.json" % int(Time.get_unix_time_from_system())) or DirAccess.get_files_at("user://").size() > 0, "copy kept aside")
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
	main.E.life_earned = 1e12
	main.save_game()
	main.E.life_earned = 5.0   # a bug wiped progress
	main.save_game()
	var u := SaveStore.unpack(FileAccess.get_file_as_string(SaveStore.FILE))
	assert_eq(float(u.state.life_earned), 1e12, "good save not overwritten")
	main.wipe_save()


func test_export_import_code():
	var main = await _fresh()
	main.E.cash = 4242.0
	main.E.life_earned = 1e9
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
	assert_near(main.E.cash, 4242.0, 1e-6, "cash restored")
	assert_ne(main.store._ls_get(SaveStore.LS_PRE_IMPORT), "", "previous game kept")
	main.wipe_save()


func test_background_time_is_credited():
	var main = await _fresh()
	main.E.reps.tables = 20
	main.E.reps.cooks = 20
	main.E.reps.ads = 30
	main.E.mark_dirty()
	await wait_frames(2)
	var inc: float = main.E.income()
	# tab hidden for 30 seconds: full income
	var c0: float = main.E.cash
	main.last_frame_unix -= 30.0
	main._catch_up()
	assert_near(main.E.cash - c0, inc * 30.0, inc * 2.0, "short absence earns full income")
	# hidden for 2 hours: offline rate plus a welcome-back card
	c0 = main.E.cash
	main.last_frame_unix -= 7200.0
	main._catch_up()
	assert_near(main.E.cash - c0, main.E.offline_gain(7200.0), inc * 2.0, "long absence earns offline income")
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


# ------------------------------------------------------------------ expenses, loans, events, bankruptcy

func test_real_player_save_still_loads():
	# a real save code from before businesses, loans and bankruptcy existed
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
	assert_eq(e.debt, 0.0, "no debt")
	assert_gt(e.income(), 0.0, "still profitable after costs")
	assert_gt(e.stars_pending(), 15.0, "a worthwhile first sale is waiting")


func test_costs_reward_balance():
	var e := _econ()
	e.reps.ads = 30
	e.reps.tables = 30
	e.reps.cooks = 30
	var bal := e.income_info(e.agg())
	assert_gt(float(bal.food), 0.0, "food costs money")
	e.reps.tables = 300   # far more seats than guests
	var lop := e.income_info(e.agg())
	assert_gt(float(lop.rent), float(bal.rent), "empty seats cost rent")
	assert_lt(float(lop.net) / float(lop.total), float(bal.net) / float(bal.total), "lopsided builds have thinner margins")
	# franchise royalties carry half the running costs of your own plates, so they widen the margin
	var before := float(bal.food)
	e.reps.tables = 30
	e.cities[0] = 10
	var fr := e.income_info(e.agg())
	assert_near(float(fr.food), before * (1.0 + Econ.FR_COST * (float(fr.fr) - 1.0)), before * 1e-6, "royalties carry half the costs")
	assert_gt(float(fr.net) / float(fr.total), float(bal.net) / float(bal.total), "so franchising widens the margin")


func test_loans():
	var e := _econ()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	e.tick(1.0)
	var lim := e.credit_limit()
	assert_gt(lim, 0.0, "credit available")
	var c0 := e.cash
	var got := e.borrow(lim * 10.0)
	assert_near(got, lim, lim * 1e-6, "borrowing is capped at the limit")
	assert_near(e.cash, c0 + got, 1e-6, "cash received")
	assert_gt(e.interest_per_s(), 0.0, "interest accrues")
	assert_gt(e.interest_rate(), e.interest_rate(lim * 0.1), "maxed-out loans cost more")
	var net_debt := e.income()
	e.debt = 0.0
	assert_gt(e.income(), net_debt, "interest comes out of profit")
	e.debt = got
	e.repay(got * 0.5)
	assert_near(e.debt, got * 0.5, got * 1e-6, "partial repay")
	e.repay(1e300)
	assert_eq(e.debt, 0.0, "fully repaid")


func test_events_appear_and_resolve():
	var e := _econ()
	e.rng.seed = 7
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	e.run_earned = Econ.cp(1e7)
	e.run_time = 1000.0
	e.event_t = 0.5
	e.tick(1.0)
	assert_false(e.event.is_empty(), "an event shows up")
	var ev: Dictionary = e.event
	assert_true((ev.choices as Array).size() >= 1, "it has choices")
	# it waits for an answer
	for k in 50:
		e.tick(1.0)
	assert_false(e.event.is_empty(), "waits for the player")
	# every event resolves without errors, both ways
	for src in Events.LIST:
		var ev2: Dictionary = (src as Dictionary).duplicate(true)
		ev2["r"] = 100.0
		ev2["cost_mult"] = 1.0
		ev2["t"] = 30.0
		for k in (ev2.choices as Array).size():
			e.cash = 1e6
			e.event = ev2.duplicate(true)
			e.answer_event(k)
			assert_true(e.event.is_empty(), "%s choice %d resolved" % [src.id, k])


func test_effects_change_income_and_expire():
	var e := _econ()
	e.reps.ads = 10
	e.reps.tables = 40
	e.reps.cooks = 40
	var base := float(e.income_info(e.agg()).total)
	e.add_effect("demand", 2.0, 10.0, "test")
	assert_gt(float(e.income_info(e.agg()).total), base * 1.5, "guests x2 raises sales")
	e.add_effect("closed", 0.0, 5.0, "test")
	assert_eq(float(e.income_info(e.agg()).total), 0.0, "closed means no restaurant sales")
	e.tick(6.0, false)
	assert_gt(float(e.income_info(e.agg()).total), 0.0, "reopens")
	e.tick(6.0, false)
	assert_true(e.effects.is_empty(), "effects expire")


func test_bankruptcy():
	var e := _econ()
	e.run_earned = Econ.cp(1e9)
	e.life_earned = Econ.cp(1e13)
	e.reps.ads = 50
	e.debt = 1e6
	var pend_stars := e.stars_pending()
	assert_gt(pend_stars, 0.0, "stars were on the table")
	var g := e.grit_pending()
	assert_gt(g, 0.0, "grit pending")
	e.cash = -1e12
	for k in int(e.deadline()) + 2:
		e.tick(1.0)
	assert_eq(e.bankruptcies, 1, "went bankrupt after the deadline")
	assert_eq(e.grit, g, "paid grit")
	assert_eq(e.stars_pending(), 0.0, "this run's stars are forfeited")
	assert_eq(e.debt, 0.0, "debt wiped")
	assert_eq(int(e.reps.ads), 0, "run reset")
	assert_false(e.concept_chosen, "pick a new concept")
	assert_false(e.last_bankrupt.is_empty(), "UI is told")
	assert_gt(e.grit_mult(), 1.0, "grit boosts income")
	assert_true(e.concept_unlocked("fine"), "a bankruptcy also counts towards unlocking concepts")


func test_recovering_from_the_red():
	var e := _econ()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	e.cash = -1e12
	e.tick(1.0)
	assert_true(e.in_red(), "in the red")
	assert_gt(e.red_t, 0.0, "clock running")
	e.cash = 100.0
	e.tick(1.0)
	assert_eq(e.red_t, 0.0, "clock resets once you're back above zero")
	assert_eq(e.bankruptcies, 0, "survived")


func test_grit_perks():
	var e := _econ()
	var id: int = e.by_key["gr_credit_0"]
	assert_false(e.buy_legacy(id), "can't afford without grit")
	e.grit = 100.0
	var lim0: float = e.agg().credit
	assert_true(e.buy_legacy(id), "buy with grit")
	assert_gt(float(e.agg().credit), float(lim0), "credit limit raised")
	assert_lt(e.grit, 100.0, "grit spent, not stars")
	assert_true(e.legacy_available(e.upgrades[e.by_key["gr_credit_1"]]), "next tier opens")
	e.life_earned = Econ.cp(1e14)
	e.prestige()
	assert_true(e.legacy.has(id), "grit perks survive selling")


# ------------------------------------------------------------------ side businesses

func _with_biz(i: int) -> Econ:
	var e := _econ()
	e.run_earned = Biz.unlock_at(i)
	e.cash = 1e300
	assert_true(e.open_biz(i), "opened " + String(Biz.DEFS[i].name))
	return e


func test_businesses_open_and_earn():
	for i in Biz.N:
		var e := _econ()
		assert_false(e.biz_unlocked(i), "%s locked at first" % Biz.DEFS[i].name)
		e.run_earned = Biz.unlock_at(i)
		assert_true(e.biz_unlocked(i), "unlocks with earnings")
		e.cash = Biz.open_cost(i, e) * 0.99
		assert_false(e.open_biz(i), "can't open without the money")
		e.cash = 1e300
		assert_true(e.open_biz(i), "opens")
		assert_true(e.buy_biz(i, "a", 10), "buy builds")
		assert_true(e.buy_biz(i, "b", 5), "buy the second build")
		var est := Biz.estimate(i, e.biz[i], e)
		assert_gt(float(est.rev), 0.0, "%s makes money" % Biz.DEFS[i].name)
		# run it live for a while; every twist must produce money without errors
		e.events_on = false
		var c0 := e.cash
		var earned := 0.0
		for k in 600:
			var r := Biz.step(i, e.biz[i], e, 0.5)
			earned += float(r.rev)
			if String(Biz.DEFS[i].id) == "catering":
				Biz.auto_accept(i, e.biz[i], e)
			if String(Biz.DEFS[i].id) == "wholesale" and k % 60 == 59:
				earned += Biz.sell_stock(i, e.biz[i], e)
		assert_gt(earned, 0.0, "%s earns when run live" % Biz.DEFS[i].name)


func test_truck_spots():
	var e := _with_biz(0)
	var s: Dictionary = e.biz[0]
	s.spots = [0.5, 2.0, 1.0, 1.0]
	s.spot = 0
	s.spot_t = 100.0
	var low := Biz.truck_rev(0, s, e, 0.5)
	assert_true(Biz.move_truck(s, 1), "move")
	var r := Biz.step(0, s, e, 1.0)
	assert_eq(float(r.rev), 0.0, "no sales while driving")
	s.move_t = 0.0
	r = Biz.step(0, s, e, 1.0)
	assert_near(float(r.rev), low * 4.0, low * 0.04, "the busy spot sells 4x the quiet one (less a little saturation)")


func test_bakery_balance():
	var e := _with_biz(1)
	var s: Dictionary = e.biz[1]
	s.a = 20
	s.b = 1
	var lop := Biz.estimate(1, s, e)
	s.b = 13
	var bal := Biz.estimate(1, s, e)
	assert_gt(float(bal.rev) - float(bal.cost), float(lop.rev) - float(lop.cost), "enough counters to sell what you bake")


func test_catering_contracts():
	var e := _with_biz(2)
	var s: Dictionary = e.biz[2]
	s.a = 10
	s.offers = [{"name": "Wedding", "crew": 6, "dur": 30.0, "pay": 1000.0, "bonus": 1.0},
		{"name": "Gala", "crew": 6, "dur": 30.0, "pay": 1000.0, "bonus": 1.0}]
	s.offer_t = 999.0
	assert_true(Biz.accept(s, 0), "take a job")
	assert_false(Biz.can_accept(s, 0), "not enough free crew for the second")
	var paid := 0.0
	for k in 31:
		paid += float(Biz.step(2, s, e, 1.0).rev)
	assert_gt(paid, 0.0, "job pays on completion")
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
	assert_gt(float(hh.rev), float(Biz.estimate(3, s, e).rev) * 0.5, "but sells plenty")


func test_hotel_rates_and_seasons():
	var e := _with_biz(4)
	var s: Dictionary = e.biz[4]
	s.a = 20
	s.b = 10
	var peak := Biz.hotel_best_rate(4, s, e, 0)
	var off := Biz.hotel_best_rate(4, s, e, 2)
	assert_gt(peak, off, "charge more in peak season")
	var best := float(Biz.hotel_rev(4, s, e, 0, peak).rev)
	assert_gt(best, float(Biz.hotel_rev(4, s, e, 0, peak * 0.6).rev), "underpricing leaves money behind")
	assert_gt(best, float(Biz.hotel_rev(4, s, e, 0, peak * 1.6).rev), "overpricing empties rooms")


func test_wholesale_market_and_food_cut():
	var e := _with_biz(5)
	var food0 := e.food_cost_pct()
	e.biz[5].b = 20
	assert_lt(e.food_cost_pct(), food0, "delivery trucks cut food costs everywhere")
	var s: Dictionary = e.biz[5]
	s.stock = 100.0
	s.mprice = 2.0
	var hi := Biz.sell_stock(5, s, e)
	s.stock = 100.0
	s.mprice = 0.5
	var lo := Biz.sell_stock(5, s, e)
	assert_near(hi, lo * 4.0, lo * 0.01, "timing the market matters")


func test_business_upgrades_and_save():
	var e := _with_biz(0)
	e.buy_biz(0, "a", 30)
	var m0 := Biz.mult(0, e)
	var id: int = e.by_key["bz_truck_a10"]
	assert_true(e.available(e.upgrades[id]), "milestone upgrade offered")
	assert_true(e.buy_upgrade(id), "bought")
	assert_near(Biz.mult(0, e), m0 * Biz.MILESTONE_X, m0 * 1e-9, "milestone boosts the truck's income")
	var d: Dictionary = JSON.parse_string(JSON.stringify(e.to_dict()))
	var f := Econ.new()
	f.from_dict(d)
	assert_true(f.biz[0].open, "business saved")
	assert_eq(int(f.biz[0].a), int(e.biz[0].a), "builds saved")
	assert_near(Biz.mult(0, f), Biz.mult(0, e), 1e-9, "upgrades saved")


func test_selling_off_to_survive():
	var e := _with_biz(1)
	e.cities[0] = 3
	e.cash = -1e300
	var v := e.sell_biz(1)
	assert_gt(v, 0.0, "selling a business raises cash")
	assert_false(e.biz[1].open, "it's gone")
	var c := e.cash
	assert_gt(e.sell_location(), 0.0, "selling a franchise raises cash")
	assert_eq(int(e.cities[0]), 2, "one fewer location")


func test_business_tab_ui():
	var main = await _fresh()
	main.E.run_earned = Biz.unlock_at(2)
	main.E.cash = 1e30
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
	assert_gt(main.E.debt, 0.0, "borrowed by button")
	main.press_button("repay:1.0")
	assert_eq(main.E.debt, 0.0, "repaid by button")
	main.E.biz[2].offers = Biz.make_offers(2, main.E.biz[2], main.E)
	main.E.biz[2].a = 50
	main.press_button("accept:2:0")
	assert_eq((main.E.biz[2].jobs as Array).size(), 1, "accepted a contract")
	main.wipe_save()


func test_event_card_and_bankruptcy_ui():
	var main = await _fresh()
	main.E.reps.ads = 30
	main.E.reps.tables = 30
	main.E.reps.cooks = 30
	main.E.run_earned = Econ.cp(1e9)
	main.E.event = main.E.new_event(100.0)
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
	main.E.cash = -1e9
	await wait_frames(2)
	assert_true(_has_button(main, "red"), "the red banner replaces the stats strip")
	main.press_button("red")
	await wait_frames(2)
	assert_true(_has_button(main, "file"), "in-the-red options shown")
	main.press_button("file")
	assert_eq(main.modal, "file", "asks first")
	main.press_button("file_yes")
	await wait_frames(2)
	assert_eq(main.modal, "bankrupt", "bankruptcy screen")
	main.press_button("after_bankrupt")
	assert_eq(main.modal, "concept", "then pick a concept")
	assert_gt(main.E.grit, 0.0, "got grit")
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
		var c0 := Biz.estimate(i, s, e)
		var s2 := s.duplicate(true)
		s2.a = 26
		var cost := e.biz_cost(i, "a", 1)
		if Biz.DEFS[i].id == "bakery":
			s2.b = int(s.b) + 1
			cost += e.biz_cost(i, "b", 1)
		var c1 := Biz.estimate(i, s2, e)
		var gain := (float(c1.rev) - float(c1.cost)) - (float(c0.rev) - float(c0.cost))
		assert_gt(gain, 0.0, "%s: the 26th build earns" % Biz.DEFS[i].name)
		assert_lt(cost / gain, 900.0, "%s: the 26th build pays back within 15 minutes" % Biz.DEFS[i].name)


func test_businesses_cannot_snowball():
	# however far you push a business, its sales level off at its market size (a share of the
	# restaurant's income), so it can never outgrow the restaurant that funds it
	for i in Biz.N:
		var e := _with_biz(i)
		var s: Dictionary = e.biz[i]
		s.a = 900
		s.b = 300 if Biz.DEFS[i].id != "catering" else 10
		for u in e.upgrades:
			if not u.legacy and u.has("biz") and int(u.biz) == i:
				e.owned[u.id] = true
		e.mark_dirty()
		var est := Biz.estimate(i, s, e)
		assert_lt(float(est.rev) / e.biz_ref(), Biz.market(i, e) * 1.0001, "%s sales capped by its market" % Biz.DEFS[i].name)
		assert_gt(float(est.sat), 0.9, "%s is saturated" % Biz.DEFS[i].name)
		# and over-building costs money: each extra build adds running costs but barely any sales
		var s2 := s.duplicate(true)
		s2.a = 901
		var e2 := Biz.estimate(i, s2, e)
		assert_lt(float(e2.rev) - float(e2.cost), float(est.rev) - float(est.cost) + float(est.rev) * 1e-3, "%s: over-building doesn't pay" % Biz.DEFS[i].name)


func test_business_value_tracks_the_restaurant():
	# the same business is worth the same share whether the restaurant makes $1M/s or $1T/s
	var shares: Array = []
	for p in [1.0e6, 1.0e12]:
		var e := _with_biz(0)
		e.rest_peak = p
		e.biz[0].a = 40
		var est := Biz.estimate(0, e.biz[0], e)
		shares.append(float(est.rev) / p)
		assert_near(e.biz_cost(0, "a", 1) / p, Biz.secs_at(0, "a", 40), 1e-9, "build price in seconds of income")
	assert_near(float(shares[0]), float(shares[1]), float(shares[0]) * 1e-6, "same share at any scale")


func test_business_has_its_own_page():
	var main = await _fresh()
	var e = main.E
	e.run_earned = 1e30
	e.cash = 1e12
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
	var c0: float = e.cash
	var p: Vector2 = main.scene_r.get_center()
	main._on_press(p)
	main._on_release(p)
	assert_gt(e.cash, c0, "tapping the truck earns")
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
	e.run_earned = 1e30
	e.cash = 1e40
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
		assert_gt(e.biz_tap(i), 0.0, "page %d tap pays" % i)
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


func test_every_stat_costs_money_to_run():
	var e := _econ()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	var base := e.income_info(e.agg())
	for r in ["ads", "tables", "cooks"]:
		var ro := {r: 400}
		var big := e.income_info(e.agg(), ro)
		assert_lt(float(big.net), float(base.net), "overbuilding %s loses money" % r)
	# far too many seats sinks the restaurant
	assert_lt(float(e.income_info(e.agg(), {"tables": 2000}).net), 0.0, "a lopsided restaurant runs at a loss")
	# when the kitchen is the limit, cooks are what pay
	e.reps.cooks = 20
	var inf := e.income_info(e.agg())
	assert_eq(String(inf.limit), "kitchen", "kitchen limited")
	assert_gt(float(e.income_info(e.agg(), {"cooks": 30}).net), float(inf.net), "and more cooks raise profit")


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
		var ev := e.new_event(100.0, rk)
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
		if bool(e.new_event(100.0, rk).good):
			good += 1
	assert_gt(good, 150, "a calm restaurant mostly gets good news")
	# gamble odds depend on the risk
	var hot := Events.make(e.rng, 100.0, 0.0, 1.0, {"r": {"kitchen": 1.0, "none": 0.0}, "raw": {"kitchen": 1.0}}, {}, 0.0, "inspection")
	var calm := Events.make(e.rng, 100.0, 0.0, 1.0, {"r": {"kitchen": 0.0, "none": 0.0}, "raw": {"kitchen": 0.5}}, {}, 0.0, "inspection")
	assert_lt(float(hot.choices[1].chance), float(calm.choices[1].chance), "winging it is riskier with a hot kitchen")


func test_insurance_hedges_events():
	var e := _econ()
	e.reps.ads = 40
	e.reps.tables = 40
	e.reps.cooks = 40
	var bare := e.new_event(1000.0, {}, "lawsuit")
	e.insured = true
	var covered := e.new_event(1000.0, {}, "lawsuit")
	var c0 := Events.upfront(bare, bare.choices[0], e.cash)
	var c1 := Events.upfront(covered, covered.choices[0], e.cash)
	assert_near(c1, c0 * (1.0 - Econ.INSURE_COVER), c0 * 1e-6, "insurance pays most of the bill")
	var em := e.empire()
	assert_near(float(em.insurance), float(em.gross) * Econ.INSURE_RATE, float(em.gross) * 1e-6, "for a premium on sales")
	var f := Econ.new()
	f.from_dict(e.to_dict())
	assert_true(f.insured, "the choice is saved")


func test_businesses_never_outgrow_the_restaurant():
	var e := _econ()
	for t in 10:
		e.legacy[e.by_key["gr_hustle_%d" % t]] = true
	e.mark_dirty()
	assert_true(Biz.market(0, e) <= Biz.MARKET * 1.5 + 1e-9, "market perks stop at x1.5")
	e.reps.ads = 60
	e.reps.tables = 60
	e.reps.cooks = 60
	e.run_earned = 1e30
	e.cash = 1e40
	for i in Biz.N:
		e.open_biz(i)
		e.buy_biz(i, "a", 900)
		e.buy_biz(i, "b", 300)
	var em := e.empire()
	assert_lt(float(em.biz_rev), float(em.rest_rev) * Biz.N * Biz.MARKET * 1.5, "all businesses together stay under their markets")
	for x in em.per:
		assert_lt(float(x.rev), float(em.rest_rev) * 0.31, "no single business rivals the restaurant")


func test_nothing_jumps_when_trouble_starts():
	var main = await _fresh()
	main.E.reps.ads = 40
	main.E.reps.tables = 40
	main.E.reps.cooks = 40
	main.E.run_earned = 1e12
	main.E.cash = 1e9
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
	main.E.borrow(main.E.credit_available() * 0.5)
	main.E.event = main.E.new_event(100.0, {}, "lawsuit")
	main.E.cash = -1e6
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


func test_older_saves_get_time_to_adapt():
	var e := _econ()
	e.reps.ads = 300   # a demand-heavy restaurant from the old rules
	e.reps.tables = 10
	e.reps.cooks = 10
	var d := e.to_dict()
	d.erase("econ")
	d.erase("grace")
	var f := Econ.new()
	f.from_dict(d)
	assert_true(f.rules_notice, "the player is told the rules changed")
	assert_gt(f.grace, 0.0, "and gets a grace period")
	f.cash = -1e6
	f.run_time = 1000.0
	f.run_earned = 1e12
	f.event_t = 0.0
	for k in 300:
		f.tick(1.0)
	assert_eq(f.bankruptcies, 0, "no bankruptcy during the grace period")
	assert_true(f.event.is_empty(), "and no events")
	var g := Econ.new()
	g.from_dict(f.to_dict())
	assert_false(g.rules_notice, "only once")
