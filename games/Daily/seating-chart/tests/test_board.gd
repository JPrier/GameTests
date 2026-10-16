extends GameTest
## Board (undo / reset / checking), hints and share formatting.

const C = preload("res://core/constraints.gd")
const G = preload("res://core/generator.gd")
const Board = preload("res://core/board.gd")
const Hints = preload("res://core/hints.gd")
const Share = preload("res://core/share.gd")

const DAY := "2026-10-22"      # a Thursday (tricky)


func test_place_swap_unseat_undo_reset():
	var m = G.for_date(DAY)
	var b = Board.new(m)
	assert_true(b.place(0, 3), "seat guest 0")
	assert_true(b.place(1, 4), "seat guest 1")
	assert_false(b.place(1, 4), "same seat again is no change")
	assert_true(b.place(0, 4), "guest 0 onto guest 1's seat swaps them")
	assert_eq(b.seat_of[0], 4, "0 moved")
	assert_eq(b.seat_of[1], 3, "1 took 0's old seat")
	assert_true(b.place(2, 0), "seat guest 2")
	assert_true(b.unseat(2), "back to the list")
	assert_eq(b.seat_of[2], -1, "unseated")
	assert_true(b.undo(), "undo unseat")
	assert_eq(b.seat_of[2], 0, "back in seat")
	assert_true(b.reset(), "reset clears")
	assert_eq(b.seated_count(), 0, "empty after reset")
	assert_true(b.undo(), "reset can be undone")
	assert_eq(b.seated_count(), 3, "everyone back")
	while b.undo():
		pass
	assert_eq(b.seated_count(), 0, "undo all the way to the start")
	assert_false(b.undo(), "nothing left to undo")


func test_solution_solves_and_rotations_count():
	var m = G.for_date(DAY)
	var b = Board.new(m)
	for g in 10:
		b.place(g, m.solution[g])
	assert_true(b.is_solved(), "answer solves")
	assert_eq(b.broken_clues(), [], "nothing broken")
	# turn Table 1 by one seat and mirror Table 2: still solved
	var b2 = Board.new(m)
	for g in 10:
		var s: int = m.solution[g]
		var t: int = m.table_of(s)
		var p: int = m.pos_of(s)
		b2.place(g, m.seat(t, p + 1) if t == 0 else m.seat(t, -p))
	assert_true(b2.is_solved(), "rotated / mirrored tables are accepted")
	assert_eq(b2.wrong_guests(), [], "and nobody counts as wrong")


func test_check_finds_misplaced_guests():
	var m = G.for_date(DAY)
	var b = Board.new(m)
	b.place(0, m.solution[0])
	assert_eq(b.wrong_guests(), [], "one guest anywhere at the right table is fine")
	# put someone from the other table next to them
	var other := -1
	for g in 10:
		if m.table_of(m.solution[g]) != m.table_of(m.solution[0]):
			other = g
			break
	b.place(other, m.neighbor_seats(m.solution[0])[0])
	assert_eq(b.wrong_guests().size(), 1, "a guest at the wrong table is flagged")


func test_board_serialization():
	var m = G.for_date(DAY)
	var b = Board.new(m)
	b.place(3, 2)
	b.place(5, 7)
	b.hinted[5] = true
	var b2 = Board.new(m)
	b2.load_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq(b2.seat_of, b.seat_of, "seats restored")
	assert_true(b2.hinted.has(5), "hint marks restored")
	var b3 = Board.new(m)
	b3.load_dict({"seats": [0, 0, 0, -1, -1, -1, -1, -1, -1, -1]})
	assert_eq(b3.seated_count(), 1, "corrupt save: duplicate seats dropped")


func test_hints_walk_to_the_answer():
	for d in ["2026-10-19", "2026-10-21", "2026-10-22", "2026-10-24"]:
		var m = G.for_date(d)
		var b = Board.new(m)
		var moves := 0
		while not b.is_solved() and moves < 12:
			var h := Hints.next(m, b.seat_of)
			assert_eq(String(h.kind), "deduce", "%s: every hint comes from a deduction" % d)
			assert_true(String(h.text) != "", "explained")
			assert_true(not (h.clues as Array).is_empty() or h.uses_board, "with clues (or seated guests) to look at")
			assert_true(int(h.guest) >= 0 and b.seat_of[int(h.guest)] < 0, "about someone not yet seated")
			b.place(int(h.guest), int(h.seat))
			assert_eq(b.wrong_guests(), [], "%s: the hinted seat is right" % d)
			moves += 1
		assert_true(b.is_solved(), "%s: following hints solves the puzzle" % d)
		assert_true(moves <= 10, "one guest per hint")


func test_hint_spots_a_wrong_guest():
	var m = G.for_date(DAY)
	var b = Board.new(m)
	b.place(0, m.solution[0])
	var other := -1
	for g in 10:
		if m.table_of(m.solution[g]) != m.table_of(m.solution[0]):
			other = g
			break
	b.place(other, m.neighbor_seats(m.solution[0])[0])
	var h := Hints.next(m, b.seat_of)
	assert_eq(String(h.kind), "wrong", "misplaced guest found first")
	assert_true([0, other].has(int(h.guest)), "points at one of the two")


func test_share_text_is_spoiler_free():
	var m = G.for_date(DAY)
	var b = Board.new(m)
	for g in 10:
		b.place(g, m.solution[g])
	var url := "https://jprier.github.io/GameTests/seating-chart/"
	var t := Share.text(m, b.seat_of, {"seconds": 222, "mistakes": 0, "hints": 0, "hinted": []}, url)
	assert_true(t.begins_with("Seating Chart #%d" % m.number), "title line")
	assert_true(t.contains("3:42"), "time")
	assert_true(t.contains("✨ Flawless"), "flawless")
	assert_true(t.contains(url), "link")
	assert_false(t.contains("dev=1"), "no dev flag")
	assert_false(t.contains("?d="), "no day in the link")
	for gd in m.guests:
		assert_false(t.contains(String(gd.name)), "no guest names")
	assert_eq(t.count("🟩"), 10, "one square per seat")
	var t2 := Share.text(m, b.seat_of, {"seconds": 61, "mistakes": 2, "hints": 1, "hinted": [3]}, url)
	assert_eq(t2.count("🟨"), 1, "hinted seat marked")
	assert_true(t2.contains("💡 1 hint") and t2.contains("❌ 2 wrong checks"), "summary")
	assert_eq(Share.clock(3725), "1:02:05", "long times")
