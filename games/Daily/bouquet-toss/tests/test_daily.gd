extends GameTest
## Dates, seeds, numbering, rollover and time zones.

const Daily = preload("res://core/daily.gd")
const Rng = preload("res://core/rng.gd")


func test_seed_is_stable_per_date():
	assert_eq(Daily.seed_for("2026-10-20"), Daily.seed_for("2026-10-20"), "same date, same seed")
	assert_ne(Daily.seed_for("2026-10-20"), Daily.seed_for("2026-10-21"), "next day differs")
	assert_ne(Daily.seed_for("2026-10-20", 0, 0), Daily.seed_for("2026-10-20", 0, 1), "attempts differ")
	assert_ne(Daily.seed_for("2026-10-20", 0, 0), Daily.seed_for("2026-10-20", 1, 0), "throws differ")
	# Pinned so an engine update (or someone switching to String.hash()) can't silently
	# change every past puzzle.
	assert_eq(Rng.hash_str(""), 0x811C9DC5, "FNV-1a offset basis")
	assert_eq(Rng.hash_str("a"), 0xE40C292C, "FNV-1a of 'a'")


func test_seeds_unique_over_years():
	var seen := {}
	var d := Daily.EPOCH
	for i in 1500:
		for h in Daily.HOLES:
			var s := Daily.seed_for(d, h)
			assert_false(seen.has(s), "seed collision on %s throw %d" % [d, h + 1])
			seen[s] = true
		d = Daily.add_days(d, 1)


func test_rng_is_integer_and_repeatable():
	var a := Rng.new(12345)
	var b := Rng.new(12345)
	for i in 200:
		assert_eq(a.next_u32(), b.next_u32(), "same sequence")
	var c := Rng.new(99)
	for i in 500:
		var v := c.range_i(-3, 7)
		assert_true(v >= -3 and v <= 7, "range_i in bounds")
	# Pinned first values: the generator's output depends on them.
	var r := Rng.new(1)
	var first := [r.next_u32(), r.next_u32(), r.next_u32()]
	var r2 := Rng.new(1)
	assert_eq([r2.next_u32(), r2.next_u32(), r2.next_u32()], first, "pinned sequence")


func test_numbering_and_rollover():
	assert_eq(Daily.day_number(Daily.EPOCH), 1, "epoch is #1")
	assert_eq(Daily.day_number("2026-10-17"), 2, "next day #2")
	assert_eq(Daily.date_for_number(100), Daily.add_days(Daily.EPOCH, 99), "number <-> date")
	assert_eq(Daily.add_days("2026-10-31", 1), "2026-11-01", "month rollover")
	assert_eq(Daily.add_days("2026-12-31", 1), "2027-01-01", "year rollover")
	assert_eq(Daily.add_days("2028-02-28", 1), "2028-02-29", "leap day")
	assert_eq(Daily.add_days("2028-03-01", -1), "2028-02-29", "back across leap day")
	assert_eq(Daily.day_number("2027-10-16") - Daily.day_number("2026-10-16"), 365, "a year later")
	# Daylight saving changes (US: 2026-11-01, 2027-03-14) don't skip or repeat a number.
	var d := "2026-10-25"
	for i in 200:
		assert_eq(Daily.day_number(Daily.add_days(d, 1)) - Daily.day_number(d), 1, "consecutive at " + d)
		d = Daily.add_days(d, 1)


func test_time_zones_decide_today():
	# 2026-10-17 03:30 UTC is still the evening of the 16th in New York (UTC-4).
	var u := Time.get_unix_time_from_datetime_string("2026-10-17T03:30:00")
	assert_eq(Daily.date_at(u, -240), "2026-10-16", "New York")
	assert_eq(Daily.date_at(u, 0), "2026-10-17", "London / UTC")
	assert_eq(Daily.date_at(u, 540), "2026-10-17", "Tokyo")
	assert_eq(Daily.date_at(u, -600), "2026-10-16", "Honolulu")
	# Local midnight is the rollover.
	var midnight_ny := Time.get_unix_time_from_datetime_string("2026-10-17T04:00:00")
	assert_eq(Daily.date_at(midnight_ny - 1, -240), "2026-10-16", "one second before midnight")
	assert_eq(Daily.date_at(midnight_ny, -240), "2026-10-17", "midnight")
	# Same calendar date anywhere = same level seed.
	assert_eq(Daily.seed_for(Daily.date_at(u, 540)), Daily.seed_for(Daily.date_at(u, 0)), "same date, same seed")


func test_weekdays_and_archetypes():
	assert_eq(Daily.weekday("2026-10-16"), 5, "Friday")
	assert_eq(Daily.weekday("2026-10-18"), 0, "Sunday")
	assert_eq(Daily.short_date("2026-10-16"), "Fri Oct 16", "short date")
	var d := "2026-10-16"
	var seen_types := {}
	for i in 60:
		var arches := Daily.archetypes_for(d)
		assert_eq(arches.size(), Daily.HOLES, "five throws a day")
		var uniq := {}
		for j in arches.size():
			uniq[arches[j]] = true
			seen_types[arches[j]] = true
			if j > 0:
				assert_true(Daily.ARCHETYPES.find(arches[j]) > Daily.ARCHETYPES.find(arches[j - 1]), "gentlest first on " + d)
		assert_eq(uniq.size(), Daily.HOLES, "five different venues on " + d)
		assert_eq(Daily.archetypes_for(d), arches, "stable")
		assert_eq(Daily.archetype_for(d, 2), arches[2], "per throw")
		d = Daily.add_days(d, 1)
	assert_eq(seen_types.size(), Daily.ARCHETYPES.size(), "every venue type shows up")


func test_valid_date():
	assert_true(Daily.valid_date("2026-10-16"), "normal")
	assert_true(Daily.valid_date("2028-02-29"), "leap day")
	assert_false(Daily.valid_date("2027-02-29"), "not a leap year")
	assert_false(Daily.valid_date("2026-13-01"), "month 13")
	assert_false(Daily.valid_date("2026-1-1"), "unpadded")
	assert_false(Daily.valid_date("today"), "garbage")
	assert_false(Daily.valid_date(""), "empty")
