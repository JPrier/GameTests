extends GameTest
## Generates thousands of consecutive days and checks every one is a good, fair puzzle
## that matches its weekday's difficulty. This is the "every day ships" guarantee.

const START := "2026-10-16"
const DAYS := 2500   # ~7 years


func test_thousands_of_days():
	var bad: Array = []
	var off_label := 0
	var worst_ms := 0
	var t0 := Time.get_ticks_msec()
	for i in DAYS:
		var d := PTDaily.date_add(START, i)
		var t1 := Time.get_ticks_msec()
		var p := PTGen.generate(d)
		worst_ms = maxi(worst_ms, Time.get_ticks_msec() - t1)
		if p.is_empty():
			bad.append("%s: no puzzle" % d)
			continue
		var probs := PTValidate.problems(p)
		if not probs.is_empty():
			bad.append("%s: %s" % [d, str(probs)])
		if p.difficulty.label != PTDaily.config(d).label:
			off_label += 1
	assert_eq(bad.size(), 0, "every day is valid. First problems: %s" % str(bad.slice(0, 5)))
	assert_lt(off_label, DAYS / 100, "difficulty matches the weekday on >99%% of days (%d off)" % off_label)
	assert_lt(worst_ms, 1500, "slowest day generates fast enough for a phone (%d ms)" % worst_ms)
	print("fuzz: %d days in %d ms, worst %d ms, %d off-label" % [DAYS, Time.get_ticks_msec() - t0, worst_ms, off_label])


func test_hints_hold_on_many_days():
	for i in 400:
		var p := PTGen.generate(PTDaily.date_add(START, i * 3))
		var out: Array = []
		var fi := PTHints.restrictive_friend(p)
		assert_true(fi >= 0 and fi < p.friends.size())
		var e := PTHints.eliminate(p, out)
		assert_ne(e, int(p.target), "hint 2 never removes the answer")
		out.append(e)
		var c := PTHints.conflict(p, out)
		assert_false(c.is_empty(), "hint 3 has something to show")
		assert_ne(int(c.plan), int(p.target), "hint 3 is about a wrong plan")
		assert_false(PTRules.does(p.plans[int(c.plan)], p.friends[int(c.friend)].rules[int(c.rule)]), "hint 3's conflict is real")
