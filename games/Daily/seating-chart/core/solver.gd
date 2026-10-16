extends RefCounted
## Exhaustive solver: the ground truth for "is this puzzle solvable, and is the answer unique?"
##
## Backtracking search that seats guests in id order, pruning as soon as any clue evaluates
## FALSE on the partial seating. Rotations and mirror images of a table are the same answer, so
## the search only builds canonical seatings (see model.canonical): a guest may start an empty
## table only in position 0, and the last position is only filled once position 1 is.
## That makes each distinct answer appear exactly once, so counting is exact.

const C = preload("res://core/constraints.gd")

var m
var clues: Array
var limit := 2
var found: Array = []        # canonical solutions found (up to `limit`)
var nodes := 0
var max_nodes := 2000000     # safety valve; `aborted` is set if hit

var aborted := false
var _seat_of := PackedInt32Array()
var _at := PackedInt32Array()
var _filled := PackedInt32Array()


static func count(model, clue_list: Array, lim: int = 2) -> int:
	var s = load("res://core/solver.gd").new()
	return s.run(model, clue_list, lim)


static func solutions(model, clue_list: Array, lim: int = 2) -> Array:
	var s = load("res://core/solver.gd").new()
	s.run(model, clue_list, lim)
	return s.found


func run(model, clue_list: Array, lim: int = 2) -> int:
	m = model
	clues = clue_list
	limit = lim
	found = []
	nodes = 0
	aborted = false
	_seat_of = m.empty_seating()
	_at = PackedInt32Array()
	_at.resize(m.seat_count())
	_at.fill(-1)
	_filled = PackedInt32Array()
	_filled.resize(m.tables)
	_filled.fill(0)
	_search(0)
	return found.size()


func _ok() -> bool:
	for c in clues:
		if C.eval(c, m, _seat_of, _at) == C.FALSE:
			return false
	return true


func _search(g: int) -> void:
	if found.size() >= limit or aborted:
		return
	nodes += 1
	if nodes > max_nodes:
		aborted = true
		return
	if g == m.guest_count():
		found.append(_seat_of.duplicate())
		return
	var n: int = m.seats
	for t in m.tables:
		if _filled[t] >= n:
			continue
		for p in n:
			var s: int = m.seat(t, p)
			if _at[s] >= 0:
				continue
			# symmetry breaking: lowest guest at a table takes position 0 ...
			if _filled[t] == 0 and p != 0:
				continue
			# ... and position 1 is filled before the last position (mirror images)
			if n > 2 and p == n - 1 and _at[m.seat(t, 1)] < 0:
				continue
			_seat_of[g] = s
			_at[s] = g
			_filled[t] += 1
			if _ok():
				_search(g + 1)
			_filled[t] -= 1
			_at[s] = -1
			_seat_of[g] = -1
			if found.size() >= limit or aborted:
				return
