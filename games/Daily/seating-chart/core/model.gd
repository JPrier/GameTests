extends RefCounted
## Puzzle model: guests, round tables with fixed seats, and the clue list.
##
## Seats are numbered `table * seats + position`; positions run clockwise around a table.
## A seating is a PackedInt32Array `seat_of` (guest -> seat, -1 = not seated).
##
## Round tables have no head seat, so rotating or mirroring a table gives the "same" seating:
## everybody keeps the same neighbours. Solutions are therefore compared up to those
## symmetries (see `canonical`). Tables themselves are labelled (Table 1, Table 2) and are not
## interchangeable; every puzzle carries at least one clue that names a table.

var tables := 2
var seats := 5                       # seats per table
var guests: Array = []               # [{name: String, desc: String, color: int}]
var clues: Array = []                # constraint dictionaries (see constraints.gd)
var solution := PackedInt32Array()   # canonical seat of each guest

# daily metadata (filled in by the generator)
var date := ""
var number := 0
var tier := 0
var seed_value := 0
var attempts := 0
var rating: Dictionary = {}


func guest_count() -> int:
	return tables * seats


func seat_count() -> int:
	return tables * seats


func table_of(s: int) -> int:
	return s / seats


func pos_of(s: int) -> int:
	return s % seats


func seat(t: int, p: int) -> int:
	return t * seats + posmod(p, seats)


## The two seats either side of `s` at its table.
func neighbor_seats(s: int) -> Array:
	var t := table_of(s)
	var p := pos_of(s)
	return [seat(t, p + 1), seat(t, p - 1)]


func ring_adjacent(s1: int, s2: int) -> bool:
	if s1 < 0 or s2 < 0 or s1 == s2 or table_of(s1) != table_of(s2):
		return false
	var d := posmod(pos_of(s1) - pos_of(s2), seats)
	return d == 1 or d == seats - 1


## seat -> guest (or -1) for a seating.
func guest_at_from(seat_of: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(seat_count())
	out.fill(-1)
	for g in seat_of.size():
		if seat_of[g] >= 0:
			out[seat_of[g]] = g
	return out


func empty_seating() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(guest_count())
	out.fill(-1)
	return out


func is_complete(seat_of: PackedInt32Array) -> bool:
	for s in seat_of:
		if s < 0:
			return false
	return true


## Position in the ring after applying dihedral transform `k` (0..2n-1):
## k < n rotates by k; k >= n mirrors, then rotates by k - n.
func transform_pos(p: int, k: int) -> int:
	if k < seats:
		return posmod(p + k, seats)
	return posmod(-p + (k - seats), seats)


## The canonical form of a complete seating: at each table the lowest-numbered guest sits at
## position 0, and the guest at position 1 is lower-numbered than the one at the last position.
## Two seatings are equivalent (same neighbours, same tables) iff their canonical forms match.
func canonical(seat_of: PackedInt32Array) -> PackedInt32Array:
	var out := seat_of.duplicate()
	var at := guest_at_from(seat_of)
	for t in tables:
		var ring: Array = []
		for p in seats:
			ring.append(at[seat(t, p)])
		if ring.has(-1):
			continue
		var lo := 0
		for p in seats:
			if ring[p] < ring[lo]:
				lo = p
		var fwd: Array = []
		for i in seats:
			fwd.append(ring[posmod(lo + i, seats)])
		if fwd[1] > fwd[seats - 1]:
			var rev: Array = [fwd[0]]
			for i in range(seats - 1, 0, -1):
				rev.append(fwd[i])
			fwd = rev
		for i in seats:
			out[fwd[i]] = seat(t, i)
	return out


func same_seating(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	return canonical(a) == canonical(b)


## For a (possibly partial) board, the solution seat each guest should have, picking per table
## the rotation/mirror of the solution that agrees with the most seated guests.
## Returns {target: PackedInt32Array guest->seat, wrong: Array of seated guests not on target}.
func best_match(seat_of: PackedInt32Array) -> Dictionary:
	var target := solution.duplicate()
	for t in tables:
		var best_k := 0
		var best_hits := -1
		for k in seats * 2:
			var hits := 0
			for g in guest_count():
				var s: int = solution[g]
				if table_of(s) != t:
					continue
				if seat_of[g] == seat(t, transform_pos(pos_of(s), k)):
					hits += 1
			if hits > best_hits:
				best_hits = hits
				best_k = k
		for g in guest_count():
			var s: int = solution[g]
			if table_of(s) == t:
				target[g] = seat(t, transform_pos(pos_of(s), best_k))
	var wrong: Array = []
	for g in guest_count():
		if seat_of[g] >= 0 and seat_of[g] != target[g]:
			wrong.append(g)
	return {"target": target, "wrong": wrong}


func guest_name(g: int) -> String:
	if g >= 0 and g < guests.size():
		return String(guests[g].name)
	return "?"


func table_name(t: int) -> String:
	return "Table %d" % (t + 1)


# ------------------------------------------------------------------ serialization

func to_dict() -> Dictionary:
	var sol: Array = []
	for s in solution:
		sol.append(s)
	return {
		"v": 1, "tables": tables, "seats": seats, "guests": guests.duplicate(true),
		"clues": clues.duplicate(true), "solution": sol, "date": date, "number": number,
		"tier": tier, "seed": seed_value, "attempts": attempts, "rating": rating.duplicate(true),
	}


static func from_dict(d: Dictionary):
	var m = load("res://core/model.gd").new()
	m.tables = int(d.get("tables", 2))
	m.seats = int(d.get("seats", 5))
	m.guests = []
	for g in d.get("guests", []):
		m.guests.append({"name": String(g.get("name", "")), "desc": String(g.get("desc", "")), "color": int(g.get("color", 0))})
	m.clues = []
	for c in d.get("clues", []):
		m.clues.append(_ints(c))
	m.solution = PackedInt32Array()
	for s in d.get("solution", []):
		m.solution.append(int(s))
	m.date = String(d.get("date", ""))
	m.number = int(d.get("number", 0))
	m.tier = int(d.get("tier", 0))
	m.seed_value = int(d.get("seed", 0))
	m.attempts = int(d.get("attempts", 0))
	m.rating = _ints(d.get("rating", {}))
	return m


## JSON brings numbers back as floats; turn whole numbers back into ints (recursively).
static func _ints(v):
	if typeof(v) == TYPE_FLOAT and v == floor(v):
		return int(v)
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(_ints(x))
		return out
	if v is Dictionary:
		var out2 := {}
		for k in v:
			out2[k] = _ints(v[k])
		return out2
	return v
