extends GameTest
## Saved game restoration and share formatting.

const DAY := "2030-04-02"


func test_save_round_trip():
	var p := PTGen.generate(DAY)
	var st := PTSave.fresh()
	var wrong := PTValidate.decoys(p)
	st.guesses = [wrong[0], wrong[1]]
	st.hints = 2
	st.hint_plan = wrong[2]
	st.crossed = [wrong[0]]
	st.seconds = 73.4
	# Through JSON, exactly like the real save file.
	var data = JSON.parse_string(JSON.stringify(PTSave.encode(p, st)))
	var back := PTSave.decode(p, data)
	assert_eq(back.guesses, [wrong[0], wrong[1]])
	assert_eq(back.hints, 2)
	assert_eq(back.hint_plan, wrong[2])
	assert_eq(back.crossed, [wrong[0]])
	assert_near(back.seconds, 73.4, 0.11)
	assert_false(back.done)


func test_save_marks_done_on_answer():
	var p := PTGen.generate(DAY)
	var st := PTSave.fresh()
	st.guesses = [int(p.target)]
	st.done = true
	var back := PTSave.decode(p, JSON.parse_string(JSON.stringify(PTSave.encode(p, st))))
	assert_true(back.done)


func test_save_for_another_puzzle_is_ignored():
	var p := PTGen.generate(DAY)
	var other := PTGen.generate(PTDaily.date_add(DAY, 1))
	var st := PTSave.fresh()
	st.guesses = [0]
	var back := PTSave.decode(p, JSON.parse_string(JSON.stringify(PTSave.encode(other, st))))
	assert_eq(back.guesses, [], "signature mismatch gives a fresh state")


func test_corrupt_save_is_safe():
	var p := PTGen.generate(DAY)
	assert_eq(PTSave.decode(p, null).guesses, [])
	assert_eq(PTSave.decode(p, "junk").guesses, [])
	var bad := PTSave.encode(p, PTSave.fresh())
	bad.guesses = [99, -3, 0, 0]
	bad.hints = 17
	bad.hint_conflict = {"plan": int(p.target), "friend": 0, "rule": 0}
	var back := PTSave.decode(p, JSON.parse_string(JSON.stringify(bad)))
	assert_eq(back.guesses, [0], "drops out-of-range and duplicate guesses")
	assert_eq(back.hints, 3, "clamps hints")
	assert_true(back.hint_conflict.is_empty(), "rejects a conflict that isn't real")


func test_share_format():
	var p := PTGen.generate(DAY)
	var wrong: int = PTValidate.decoys(p)[0]
	var txt := PTShare.text(p, 83, [wrong, int(p.target)], 0, 74)
	var lines := txt.split("\n")
	assert_eq(lines[0], "Plans Tonight? #83")
	assert_eq(lines[1], "🍻 2/%d · ⏱️ 1:14" % p.plans.size())
	assert_eq(lines[2].length(), p.friends.size(), "one square per friend")
	assert_true(lines[2].contains("🟥"), "a wrong guess has at least one veto")
	assert_eq(lines[3], "🟩".repeat(p.friends.size()), "the answer is all green")
	assert_eq(lines[4], PTShare.URL)
	for plan in p.plans:
		assert_false(txt.contains(plan.name), "never names a plan")
	assert_false(txt.contains("day="), "no day in the link")
	assert_false(txt.contains("dev"), "no dev flag")


func test_share_shows_hints_only_when_used():
	var p := PTGen.generate(DAY)
	assert_false(PTShare.text(p, 1, [int(p.target)], 0, 5).contains("💡"))
	assert_true(PTShare.text(p, 1, [int(p.target)], 2, 5).contains("💡2"))
	assert_eq(PTShare.clock(3725), "1:02:05")
	assert_eq(PTShare.label(p, [0, 1]), "2/%d" % p.plans.size())


func test_game_restores_after_reload():
	var main = await load_scene("res://main.tscn")
	main.dev_mode = true
	main.load_day(DAY)
	main.wipe_save()
	main.load_day(DAY)
	var wrong: Array = PTValidate.decoys(main.puzzle)
	main.guess_plan(wrong[0])
	main.close_modal()
	main.toggle_cross(wrong[1])
	main.use_hint()
	main.st.seconds = 42.0
	main._save_state()
	main.load_day(PTDaily.date_add(DAY, 1))
	main.load_day(DAY)
	assert_eq(main.st.guesses, [wrong[0]], "guesses restored")
	assert_eq(main.st.crossed, [wrong[1]], "crossed-off plans restored")
	assert_eq(main.st.hints, 1, "hints restored")
	assert_near(float(main.st.seconds), 42.0, 0.2, "timer restored")
	main.wipe_save()
	main.date = PTDaily.date_add(DAY, 1)
	main.wipe_save()
