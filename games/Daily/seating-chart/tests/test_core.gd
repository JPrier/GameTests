extends GameTest
## Puzzle model, every constraint type, the exhaustive solver and the logic solver.

const Model = preload("res://core/model.gd")
const C = preload("res://core/constraints.gd")
const S = preload("res://core/solver.gd")
const L = preload("res://core/logic.gd")


## 10 guests A..J. Answer: Table 1 ring A B C D E, Table 2 ring F G H I J.
func _model():
	var m = Model.new()
	for i in 10:
		m.guests.append({"name": "ABCDEFGHIJ"[i], "desc": "", "color": i})
	var sol := PackedInt32Array()
	for g in 10:
		sol.append(g)
	m.solution = m.canonical(sol)
	return m


func _seating(pairs: Dictionary, m) -> PackedInt32Array:
	var s: PackedInt32Array = m.empty_seating()
	for g in pairs:
		s[g] = pairs[g]
	return s


# ------------------------------------------------------------------ model

func test_ring_geometry():
	var m = _model()
	assert_true(m.ring_adjacent(0, 1), "0-1 neighbours")
	assert_true(m.ring_adjacent(0, 4), "0-4 neighbours around the ring")
	assert_false(m.ring_adjacent(0, 2), "0-2 not neighbours")
	assert_false(m.ring_adjacent(4, 5), "different tables never neighbours")
	assert_eq(m.neighbor_seats(5), [6, 9], "seat 5 neighbours")


func test_canonical_ignores_turning_and_mirroring():
	var m = _model()
	var base: PackedInt32Array = m.solution
	# turn table 1 by two seats and mirror table 2
	var turned := PackedInt32Array([2, 3, 4, 0, 1, 5, 9, 8, 7, 6])
	assert_true(m.same_seating(base, turned), "rotations / mirror images are the same answer")
	var swapped := PackedInt32Array([1, 0, 2, 3, 4, 5, 6, 7, 8, 9])
	assert_false(m.same_seating(base, swapped), "swapping two guests is a different answer")
	var tables_swapped := PackedInt32Array([5, 6, 7, 8, 9, 0, 1, 2, 3, 4])
	assert_false(m.same_seating(base, tables_swapped), "tables are labelled")


func test_best_match_follows_rotation():
	var m = _model()
	var s := _seating({0: 2, 1: 3}, m)       # A and B seated, turned two seats
	var bm: Dictionary = m.best_match(s)
	assert_eq(bm.wrong, [], "turned but consistent placements are right")
	assert_eq(bm.target[2], 4, "C goes next to B in the turned frame")
	s = _seating({0: 0, 1: 2}, m)            # A and B not neighbours: one of them is wrong
	assert_eq(m.best_match(s).wrong.size(), 1, "one misplaced guest")


# ------------------------------------------------------------------ constraints

func _ev(c: Dictionary, m, s: PackedInt32Array) -> int:
	return C.eval(c, m, s, m.guest_at_from(s))


func test_adjacent():
	var m = _model()
	var c := C.make(C.ADJACENT, 0, 1)
	assert_eq(_ev(c, m, _seating({0: 0, 1: 1}, m)), C.TRUE, "side by side")
	assert_eq(_ev(c, m, _seating({0: 0, 1: 4}, m)), C.TRUE, "side by side across the ring seam")
	assert_eq(_ev(c, m, _seating({0: 0, 1: 2}, m)), C.FALSE, "same table, not neighbours")
	assert_eq(_ev(c, m, _seating({0: 0, 1: 5}, m)), C.FALSE, "different tables")
	assert_eq(_ev(c, m, _seating({0: 0}, m)), C.UNKNOWN, "one seated, neighbours free")
	assert_eq(_ev(c, m, _seating({0: 0, 2: 1, 3: 4}, m)), C.FALSE, "both neighbour seats taken by others")
	assert_eq(_ev(c, m, m.empty_seating()), C.UNKNOWN, "nobody seated")


func test_not_adjacent():
	var m = _model()
	var c := C.make(C.NOT_ADJACENT, 0, 1)
	assert_eq(_ev(c, m, _seating({0: 0, 1: 1}, m)), C.FALSE, "side by side")
	assert_eq(_ev(c, m, _seating({0: 0, 1: 2}, m)), C.TRUE, "not neighbours")
	assert_eq(_ev(c, m, _seating({0: 0, 1: 7}, m)), C.TRUE, "different tables")
	assert_eq(_ev(c, m, _seating({0: 0}, m)), C.UNKNOWN, "one seated")
	assert_eq(_ev(c, m, _seating({0: 0, 2: 1, 3: 4}, m)), C.TRUE, "neighbours already filled by others")


func test_same_table():
	var m = _model()
	var c := C.make(C.SAME_TABLE, 0, 1)
	assert_eq(_ev(c, m, _seating({0: 0, 1: 3}, m)), C.TRUE, "same table")
	assert_eq(_ev(c, m, _seating({0: 0, 1: 6}, m)), C.FALSE, "different tables")
	assert_eq(_ev(c, m, _seating({0: 0}, m)), C.UNKNOWN, "one seated, room left")
	assert_eq(_ev(c, m, _seating({0: 0, 2: 1, 3: 2, 4: 3, 5: 4}, m)), C.FALSE, "A's table full without B")


func test_different_table():
	var m = _model()
	var c := C.make(C.DIFFERENT_TABLE, 0, 1)
	assert_eq(_ev(c, m, _seating({0: 0, 1: 6}, m)), C.TRUE, "apart")
	assert_eq(_ev(c, m, _seating({0: 0, 1: 2}, m)), C.FALSE, "together")
	assert_eq(_ev(c, m, _seating({0: 0}, m)), C.UNKNOWN, "one seated")
	assert_eq(_ev(c, m, _seating({0: 0, 2: 5, 3: 6, 4: 7, 5: 8, 6: 9}, m)), C.FALSE, "the other table is full")


func test_at_table():
	var m = _model()
	var c := C.make(C.AT_TABLE, 0, -1, 1)
	assert_eq(_ev(c, m, _seating({0: 7}, m)), C.TRUE, "at table 2")
	assert_eq(_ev(c, m, _seating({0: 2}, m)), C.FALSE, "at table 1")
	assert_eq(_ev(c, m, m.empty_seating()), C.UNKNOWN, "not seated")
	assert_eq(_ev(c, m, _seating({1: 5, 2: 6, 3: 7, 4: 8, 5: 9}, m)), C.FALSE, "table 2 full without A")


func test_false_is_final():
	# For random partial seatings, a FALSE clue must stay FALSE however the rest are seated.
	var m = _model()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all_clues: Array = []
	for a in 10:
		for b in range(a + 1, 10):
			for t in [C.ADJACENT, C.NOT_ADJACENT, C.SAME_TABLE, C.DIFFERENT_TABLE]:
				all_clues.append(C.make(t, a, b))
		all_clues.append(C.make(C.AT_TABLE, a, -1, 0))
		all_clues.append(C.make(C.AT_TABLE, a, -1, 1))
	for trial in 60:
		var order: Array = range(10)
		for i in range(9, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		var full: PackedInt32Array = m.empty_seating()
		for i in 10:
			full[order[i]] = i
		var partial := full.duplicate()
		var hide := rng.randi_range(1, 9)
		for i in hide:
			partial[order[i]] = -1
		for c in all_clues:
			var p := _ev(c, m, partial)
			var f := _ev(c, m, full)
			assert_ne(f, C.UNKNOWN, "complete seating decides every clue")
			if p != C.UNKNOWN:
				assert_eq(p, f, "%s decided early must match the full seating" % C.key(c))


func test_clue_text_and_validation():
	var m = _model()
	assert_eq(C.text(C.make(C.ADJACENT, 0, 1, -1, 0), m), "A must sit next to B.", "text")
	assert_eq(C.text(C.make(C.AT_TABLE, 2, -1, 1, 0), m), "C sits at Table 2.", "table text")
	assert_eq(C.validate(C.make(C.ADJACENT, 0, 0), m), "clue about one guest twice", "self clue rejected")
	assert_eq(C.validate(C.make(C.AT_TABLE, 0, -1, 5), m), "bad table", "bad table rejected")
	assert_eq(C.validate({"type": "opposite", "a": 0, "b": 1}, m), "unknown clue type", "unknown type rejected")
	for t in C.TYPES:
		for v in C.variant_count(t):
			var c := C.make(t, 0, 1, 1, v)
			assert_false(C.text(c, m).contains("{"), "all placeholders filled: " + C.text(c, m))


# ------------------------------------------------------------------ solvers

func _full_clues(m) -> Array:
	var out: Array = []
	for a in 10:
		for b in range(a + 1, 10):
			out.append(C.make(C.ADJACENT if m.ring_adjacent(m.solution[a], m.solution[b]) else C.NOT_ADJACENT, a, b))
	out.append(C.make(C.AT_TABLE, 0, -1, 0))
	return out


func test_exhaustive_counts():
	var m = _model()
	assert_eq(S.count(m, [], 100000), 36288, "no clues: C(10,5) splits x 12 rings x 12 rings")
	var sols := S.solutions(m, _full_clues(m), 3)
	assert_eq(sols.size(), 1, "all neighbour facts + one table: unique")
	assert_eq(sols[0], m.solution, "and it's the answer")
	var contradictory := [C.make(C.ADJACENT, 0, 1), C.make(C.DIFFERENT_TABLE, 0, 1)]
	assert_eq(S.count(m, contradictory), 0, "contradictory clues: no answer")
	assert_eq(S.count(m, [C.make(C.AT_TABLE, 0, -1, 0)], 2), 2, "a weak clue leaves several answers")


func test_logic_solves_and_agrees():
	var m = _model()
	var lg = L.run(m, _full_clues(m), 4)
	assert_true(lg.is_solved(), "fully described puzzle is solvable by reasoning")
	assert_eq(lg.solution(), m.solution, "logic finds the answer")
	for s in lg.steps:
		assert_true(String(s.text) != "", "every step explained")
	assert_true(L.solvable(m, _full_clues(m), 2), "bulk mode agrees")


func test_logic_detects_contradiction():
	var m = _model()
	var lg = L.run(m, [C.make(C.SAME_TABLE, 0, 1), C.make(C.SAME_TABLE, 1, 2), C.make(C.DIFFERENT_TABLE, 0, 2)], 4)
	assert_ne(lg.contradiction, "", "transitivity contradiction found")


func test_logic_never_wrong_on_random_clue_sets():
	# Random true clue sets: whenever reasoning finishes, it must match the exhaustive answer,
	# and it must never "prove" something false (no contradiction from true clues).
	var m = _model()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var pool: Array = []
	for a in 10:
		for b in range(a + 1, 10):
			pool.append(C.make(C.ADJACENT if m.ring_adjacent(m.solution[a], m.solution[b]) else C.NOT_ADJACENT, a, b))
			pool.append(C.make(C.SAME_TABLE if m.table_of(m.solution[a]) == m.table_of(m.solution[b]) else C.DIFFERENT_TABLE, a, b))
	var solved := 0
	var unique := 0
	for trial in 40:
		var clues: Array = [C.make(C.AT_TABLE, rng.randi_range(0, 9), -1, 0)]
		clues[0].t = m.table_of(m.solution[clues[0].a])
		for k in rng.randi_range(10, 30):
			clues.append(pool[rng.randi_range(0, pool.size() - 1)])
		var lg = L.run(m, clues, 4)
		if S.count(m, clues, 2) == 1:
			unique += 1
		assert_eq(lg.contradiction, "", "true clues never contradict")
		if lg.is_solved():
			solved += 1
			assert_eq(lg.solution(), m.solution, "logic answer is the answer")
			assert_eq(S.count(m, clues, 2), 1, "logic-solved puzzles are unique")
		assert_eq(L.solvable(m, clues, 4), lg.is_solved(), "bulk and step modes agree")
	assert_gt(solved, 0, "some random sets are solvable")
	assert_eq(solved, unique, "reasoning (with what-ifs) finishes every uniquely solvable sample")
