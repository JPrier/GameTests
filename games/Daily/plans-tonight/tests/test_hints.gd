extends GameTest
## Hint correctness against the puzzle model.

const DAY := "2030-03-15"


func test_restrictive_friend_rules_out_the_most():
	var p := PTGen.generate(DAY)
	var best := PTHints.restrictive_friend(p)
	var count := func(fi):
		var seen := {}
		for r in p.friends[fi].rules:
			for d in PTValidate.elim(p, r):
				seen[d] = true
		return seen.size()
	for fi in p.friends.size():
		assert_true(count.call(best) >= count.call(fi), "nobody rules out more than the hinted friend")


func test_eliminate_skips_known_plans_and_answer():
	var p := PTGen.generate(DAY)
	var out: Array = []
	for i in PTValidate.decoys(p).size():
		var e := PTHints.eliminate(p, out)
		assert_true(e >= 0, "still a plan to rule out")
		assert_ne(e, int(p.target), "never the answer")
		assert_false(e in out, "never one the player already ruled out")
		out.append(e)
	assert_eq(PTHints.eliminate(p, out), -1, "nothing left once every wrong plan is known")


func test_conflict_is_real_and_prefers_near_misses():
	var p := PTGen.generate(DAY)
	var kills := PTValidate.kill_counts(p)
	var c := PTHints.conflict(p, [])
	assert_false(c.is_empty())
	var plan: Dictionary = p.plans[int(c.plan)]
	assert_false(PTRules.does(plan, p.friends[int(c.friend)].rules[int(c.rule)]), "the plan really breaks that rule")
	var min_k := 99
	for d in kills:
		min_k = mini(min_k, kills[d])
	assert_eq(kills[int(c.plan)], min_k, "points at the hardest-to-spot wrong plan")
	assert_true(PTHints.conflict(p, PTValidate.decoys(p)).is_empty(), "empty when every wrong plan is known")


func test_in_game_hints_progress():
	var main = await load_scene("res://main.tscn")
	main.dev_mode = true
	main.load_day(DAY)
	main.wipe_save()
	main.load_day(DAY)
	assert_true(main.hint_available())
	assert_true(main.use_hint(), "hint 1")
	assert_true(main.hint_text(1).contains(main.puzzle.friends[PTHints.restrictive_friend(main.puzzle)].name))
	assert_true(main.use_hint(), "hint 2")
	var hp: int = main.st.hint_plan
	assert_true(hp >= 0 and hp != int(main.puzzle.target), "hint 2 marks a wrong plan")
	assert_true(hp in main.ruled_out())
	assert_true(main.use_hint(), "hint 3")
	assert_false(main.st.hint_conflict.is_empty())
	assert_ne(int(main.st.hint_conflict.plan), hp, "hint 3 shows a different plan")
	assert_false(main.hint_available(), "only three hints")
	assert_false(main.use_hint())
	assert_eq(main.st.hints, 3)
	main.wipe_save()
