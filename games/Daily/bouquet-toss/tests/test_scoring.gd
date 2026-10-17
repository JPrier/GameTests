extends GameTest
## Scoring, share text and saved state.

const Scoring = preload("res://core/scoring.gd")
const Share = preload("res://core/share.gd")
const Save = preload("res://core/save.gd")

const URL := "https://jprier.github.io/GameTests/bouquet-toss/"


func test_accuracy():
	assert_eq(Scoring.accuracy(0.0, 34.0), 100, "dead centre")
	assert_eq(Scoring.accuracy(34.0, 34.0), Scoring.MIN_ACCURACY, "edge of the zone")
	assert_eq(Scoring.accuracy(17.0, 34.0), 80, "halfway")
	assert_eq(Scoring.accuracy(99.0, 34.0), Scoring.MIN_ACCURACY, "clamped")
	assert_eq(Scoring.accuracy(-1.0, 34.0), 0, "no catch, no accuracy")
	var last := 101
	for i in 35:
		var a := Scoring.accuracy(float(i), 34.0)
		assert_true(a <= last, "never better further out")
		last = a


func test_ratings_par_style():
	assert_eq(Scoring.rating(1), "Perfect", "1")
	assert_eq(Scoring.rating(2), "Great", "2")
	assert_eq(Scoring.rating(3), "Good", "3")
	assert_eq(Scoring.rating(5), "Nice", "5")
	assert_eq(Scoring.rating(9), "Caught", "9")


func test_ordering_throws_then_accuracy_then_time():
	var a := {"throws": 2, "accuracy": 70, "seconds": 90}
	var b := {"throws": 3, "accuracy": 100, "seconds": 5}
	assert_true(Scoring.better(a, b), "fewer throws wins")
	var c := {"throws": 2, "accuracy": 90, "seconds": 120}
	assert_true(Scoring.better(c, a), "then accuracy")
	var d := {"throws": 2, "accuracy": 90, "seconds": 30}
	assert_true(Scoring.better(d, c), "then time")
	assert_eq(Scoring.compare(d, d.duplicate()), 0, "equal")


func test_labels_and_clock():
	assert_eq(Scoring.label({"throws": 1, "accuracy": 94}), "1 try · 94%", "singular")
	assert_eq(Scoring.label({"throws": 9, "accuracy": 70}), "9 tries · 70%", "plural")
	assert_eq(Scoring.clock(65), "1:05", "clock")
	assert_eq(Scoring.clock(3725), "1:02:05", "hours")
	for o in ["catch", "splat", "fumble", "floor", "rest", "out", "timeout"]:
		assert_ne(Scoring.outcome_text(o, ["table"]), "", "text for " + o)


func test_share_text_is_spoiler_free():
	var res := {"throws": 8, "accuracy": 91, "seconds": 141.5, "holes": [
		["catch"], ["splat", "catch"], ["floor", "fumble", "catch"], ["catch"], ["rest", "catch"]]}
	var t := Share.text(127, res, URL)
	var lines := t.split("\n")
	assert_eq(lines[0], "Bouquet Toss #127 💐", "title")
	assert_eq(lines[1], "🎯 8 tries for 5 throws · Good", "tries + rating")
	assert_eq(lines[2], "✨ 91%", "accuracy")
	assert_eq(lines[3], "1️⃣ 💐", "throw 1")
	assert_eq(lines[5], "3️⃣ ⬇️ 💨 💐", "throw 3, one emoji per try")
	assert_eq(lines[7], "5️⃣ 🪑 💐", "throw 5")
	assert_eq(lines[8], URL, "plain link, no day, no dev flag")
	assert_false(t.contains("°"), "no angles")
	assert_false(t.contains("dev"), "no dev flag")
	assert_false(t.contains("?"), "no query string")
	var perfect := Share.text(1, {"throws": 5, "accuracy": 100, "holes": [["catch"], ["catch"], ["catch"], ["catch"], ["catch"]]}, URL)
	assert_true(perfect.contains("🎯 5 tries for 5 throws · Perfect"), "par")


func test_share_text_stays_short_for_long_runs():
	var outs: Array = []
	for i in 30:
		outs.append("floor")
	outs.append("catch")
	var t := Share.text(5, {"throws": 35, "accuracy": 60, "holes": [outs, ["catch"], ["catch"], ["catch"], ["catch"]]}, URL)
	var marks := t.split("\n")[3]
	assert_lt(marks.length(), 40, "compressed")
	assert_true(marks.ends_with("💐"), "still ends with the catch")


func test_day_rating_against_par():
	assert_eq(Scoring.rating_total(5, 5), "Perfect", "par")
	assert_eq(Scoring.rating_total(7, 5), "Great", "+2")
	assert_eq(Scoring.rating_total(10, 5), "Good", "+5")
	assert_eq(Scoring.rating_total(14, 5), "Nice", "+9")
	assert_eq(Scoring.rating_total(20, 5), "Caught", "lots")


func test_save_round_trip_and_dev_separation():
	var real := Save.new(false)
	var dev := Save.new(true)
	var d := "2099-01-01"
	real.wipe_day(d)
	dev.wipe_day(d)
	var state := {"v": 2, "throws": [{"a": 45, "p": 60, "o": "floor", "acc": 0}], "done": false, "result": {}, "seconds": 12.5, "practice": 0, "aim": [45, 60]}
	dev.save_day(d, state)
	assert_true(real.load_day(d).is_empty(), "dev saves never touch the player's file")
	var back := dev.load_day(d)
	assert_eq(back.throws.size(), 1, "throws survive")
	assert_eq(int(back.throws[0].p), 60, "values survive")
	assert_near(float(back.seconds), 12.5, 0.001, "time survives")
	dev.record_result(d, "2 throws · 90%")
	assert_eq(String(dev.load_results()[d]), "2 throws · 90%", "result recorded")
	assert_false(real.load_results().has(d), "not in the real results")
	dev.wipe_day(d)
	assert_true(dev.load_day(d).is_empty(), "wiped")
	assert_false(dev.load_results().has(d), "result wiped too")


func test_corrupt_save_is_ignored():
	var dev := Save.new(true)
	var d := "2099-01-02"
	var f := FileAccess.open(dev.day_path(d), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	assert_true(dev.load_day(d).is_empty(), "garbage file")
	Save.write_json(dev.day_path(d), {"throws": "nope"})
	assert_true(dev.load_day(d).is_empty(), "wrong shape")
	dev.wipe_day(d)
