extends GameTest
## Every constraint type, its wording, its reasons and contradiction detection.

func _plan(over := {}) -> Dictionary:
	var p := {"id": 0, "name": "Test Plan", "icon": "1f3b3", "activity": "Bowling", "food": "", "price": 24,
		"start": 19 * 60, "end": 21 * 60, "travel": 18, "setting": "indoor", "noise": "lively"}
	for k in over:
		p[k] = over[k]
	return p


func _r(type: String, v = true) -> Dictionary:
	return {"type": type, "v": v}


func test_every_type_is_covered():
	for t in PTRules.TYPES:
		assert_true(PTRules.TOPIC.has(t), "%s has a topic" % t)
		assert_true(PTGen.TYPE_WEIGHT.has(t), "%s has a generator weight" % t)
		assert_true(t in PTDaily.HARD_TYPES, "%s is used on hard days" % t)


func test_max_price():
	assert_true(PTRules.does(_plan({"price": 29}), _r("max_price", 30)))
	assert_true(PTRules.does(_plan({"price": 30}), _r("max_price", 30)), "exactly the limit is fine")
	assert_false(PTRules.does(_plan({"price": 31}), _r("max_price", 30)))


func test_start_times():
	var p := _plan({"start": 19 * 60 + 30, "end": 21 * 60})
	assert_true(PTRules.does(p, _r("min_start", 19 * 60 + 30)), "can arrive right at the start")
	assert_false(PTRules.does(p, _r("min_start", 20 * 60)))
	assert_true(PTRules.does(p, _r("max_start", 19 * 60 + 30)))
	assert_false(PTRules.does(p, _r("max_start", 19 * 60)))


func test_end_times():
	var p := _plan({"start": 20 * 60, "end": 22 * 60 + 30})
	assert_true(PTRules.does(p, _r("max_end", 22 * 60 + 30)))
	assert_false(PTRules.does(p, _r("max_end", 22 * 60)))
	assert_true(PTRules.does(p, _r("min_end", 22 * 60)))
	assert_false(PTRules.does(p, _r("min_end", 23 * 60)))


func test_travel():
	assert_true(PTRules.does(_plan({"travel": 18}), _r("max_travel", 20)))
	assert_false(PTRules.does(_plan({"travel": 22}), _r("max_travel", 20)))


func test_setting():
	assert_true(PTRules.does(_plan({"setting": "outdoor"}), _r("setting", "outdoor")))
	assert_false(PTRules.does(_plan({"setting": "indoor"}), _r("setting", "outdoor")))
	assert_true(PTRules.does(_plan({"setting": "indoor"}), _r("setting", "indoor")))


func test_food_rules():
	assert_false(PTRules.does(_plan({"food": ""}), _r("wants_food")))
	assert_true(PTRules.does(_plan({"food": "Tacos"}), _r("wants_food")))
	assert_false(PTRules.does(_plan({"food": "Sushi"}), _r("no_food_type", "Sushi")))
	assert_true(PTRules.does(_plan({"food": "Tacos"}), _r("no_food_type", "Sushi")))
	assert_true(PTRules.does(_plan({"food": ""}), _r("no_food_type", "Sushi")), "no food means no sushi either")


func test_activity_rule():
	assert_false(PTRules.does(_plan({"activity": "Karaoke"}), _r("no_activity", "Karaoke")))
	assert_true(PTRules.does(_plan({"activity": "Bowling"}), _r("no_activity", "Karaoke")))


func test_noise_rules():
	assert_false(PTRules.does(_plan({"noise": "loud"}), _r("not_loud")))
	assert_true(PTRules.does(_plan({"noise": "lively"}), _r("not_loud")))
	assert_false(PTRules.does(_plan({"noise": "quiet"}), _r("not_quiet")))
	assert_true(PTRules.does(_plan({"noise": "loud"}), _r("not_quiet")))


func test_duration_rules():
	var p := _plan({"start": 19 * 60, "end": 21 * 60 + 30})
	assert_eq(PTRules.duration(p), 150)
	assert_true(PTRules.does(p, _r("max_duration", 150)))
	assert_false(PTRules.does(p, _r("max_duration", 120)))
	assert_true(PTRules.does(p, _r("min_duration", 120)))
	assert_false(PTRules.does(p, _r("min_duration", 180)))


func test_wording_states_the_value():
	assert_eq(PTRules.text(_r("max_price", 30)), "Won't spend more than $30")
	assert_eq(PTRules.text(_r("min_start", 20 * 60)), "Can't get there before 8pm")
	assert_eq(PTRules.text(_r("max_end", 22 * 60 + 30)), "Has to head home by 10:30pm")
	assert_eq(PTRules.text(_r("max_travel", 25)), "Won't travel more than 25 minutes")
	assert_eq(PTRules.text(_r("no_activity", "Karaoke")), "Refuses to do karaoke again")
	assert_eq(PTRules.text(_r("no_activity", "Wine bar")), "Refuses to go to a wine bar again")
	assert_eq(PTRules.text(_r("no_food_type", "BBQ")), "Won't eat BBQ")
	assert_eq(PTRules.text(_r("max_duration", 90)), "Can only stay out for 1½ hours, tops")
	for t in PTRules.TYPES:
		var v = 60 if t.contains("duration") else ("indoor" if t == "setting" else ("Sushi" if t == "no_food_type" else ("Karaoke" if t == "no_activity" else 20 * 60)))
		assert_ne(PTRules.text(_r(t, v)), t, "%s has wording" % t)


func test_reasons_explain_the_break():
	assert_eq(PTRules.reason(_plan({"price": 32}), _r("max_price", 30)), "$32 is over the $30 limit")
	assert_eq(PTRules.reason(_plan({"travel": 27}), _r("max_travel", 20)), "27 min away, more than 20")
	assert_eq(PTRules.reason(_plan({"setting": "indoor"}), _r("setting", "outdoor")), "It's indoors")
	assert_eq(PTRules.reason(_plan({"activity": "Arcade"}), _r("no_activity", "Arcade")), "It's an arcade")
	assert_eq(PTRules.reason(_plan({"start": 19 * 60, "end": 22 * 60}), _r("max_duration", 120)), "Runs 3 hours")


func test_clock_format():
	assert_eq(PTRules.clock(19 * 60), "7pm")
	assert_eq(PTRules.clock(19 * 60 + 30), "7:30pm")
	assert_eq(PTRules.clock(24 * 60), "midnight")
	assert_eq(PTRules.clock(12 * 60), "12pm")
	assert_eq(PTRules.time_range(_plan({"start": 19 * 60 + 30, "end": 21 * 60})), "7:30–9pm")
	assert_eq(PTRules.time_range(_plan({"start": 22 * 60, "end": 24 * 60})), "10pm–midnight")


func test_contradictions():
	assert_true(PTRules.contradicts(_r("setting", "indoor"), _r("setting", "outdoor")))
	assert_false(PTRules.contradicts(_r("setting", "indoor"), _r("setting", "indoor")))
	assert_true(PTRules.contradicts(_r("min_start", 21 * 60), _r("max_start", 20 * 60)))
	assert_true(PTRules.contradicts(_r("max_start", 20 * 60), _r("min_start", 21 * 60)), "order doesn't matter")
	assert_true(PTRules.contradicts(_r("min_start", 22 * 60), _r("max_end", 22 * 60 + 30)), "no plan fits in 30 minutes")
	assert_false(PTRules.contradicts(_r("min_start", 20 * 60), _r("max_end", 22 * 60)))
	assert_true(PTRules.contradicts(_r("min_end", 23 * 60), _r("max_end", 22 * 60)))
	assert_true(PTRules.contradicts(_r("min_duration", 180), _r("max_duration", 120)))
	assert_false(PTRules.contradicts(_r("not_loud"), _r("not_quiet")), "lively satisfies both")
	assert_false(PTRules.contradicts(_r("max_price", 20), _r("max_travel", 10)))
