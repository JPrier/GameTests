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
	for u in e.upgrades:
		if u.legacy:
			leg += 1
		else:
			run += 1
	assert_gt(e.upgrades.size(), 1000, "over 1000 upgrades")
	assert_gt(run, 1000, "over 1000 bought with cash")
	assert_eq(leg, 80, "legacy perks")


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
			var c := float(u.cost)
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
	var after := e.income()
	assert_near(after, before, before * 0.001, "more ads past the bottleneck do nothing")
	e.reps.tables = 50
	e.reps.cooks = 50
	assert_gt(e.income(), before * 3.0, "raising both capacities pays off")


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
	var at := e.income()
	for f in [0.8, 0.9, 1.1, 1.25]:
		e.price = clampf(best * f, Econ.PRICE_MIN, e.ceiling(a))
		assert_true(e.income() <= at * 1.0001, "best price is a local maximum (x%s)" % f)
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
	assert_near(f.income(), e.income(), e.income() * 1e-9, "same income after load")


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
