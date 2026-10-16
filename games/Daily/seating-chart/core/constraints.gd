extends RefCounted
## Structured clue definitions. Every clue is a plain Dictionary so the solver, the generator,
## hints, saving and the UI all read the same thing:
##
##   {type: "adjacent",        a: guest, b: guest}   a sits directly beside b
##   {type: "not_adjacent",    a: guest, b: guest}   a does not sit directly beside b
##   {type: "same_table",      a: guest, b: guest}   a and b sit at the same table
##   {type: "different_table", a: guest, b: guest}   a and b sit at different tables
##   {type: "at_table",        a: guest, t: table}   a sits at table t
##
## plus `v`, a phrasing variant used only for the text.
##
## `eval` works on partial seatings and returns TRUE, FALSE or UNKNOWN. FALSE is final: once a
## clue is FALSE no way of seating the remaining guests can make it TRUE, so solvers may prune
## on it and the UI can flag it as broken.

const ADJACENT := "adjacent"
const NOT_ADJACENT := "not_adjacent"
const SAME_TABLE := "same_table"
const DIFFERENT_TABLE := "different_table"
const AT_TABLE := "at_table"
const TYPES := [ADJACENT, NOT_ADJACENT, SAME_TABLE, DIFFERENT_TABLE, AT_TABLE]

const TRUE := 1
const FALSE := 0
const UNKNOWN := -1


static func make(type: String, a: int, b: int = -1, t: int = -1, v: int = 0) -> Dictionary:
	var c := {"type": type, "a": a, "v": v}
	if type == AT_TABLE:
		c["t"] = t
	else:
		c["b"] = b
	return c


## Guests a clue mentions.
static func guests_of(c: Dictionary) -> Array:
	if String(c.type) == AT_TABLE:
		return [int(c.a)]
	return [int(c.a), int(c.b)]


static func mentions(c: Dictionary, g: int) -> bool:
	return guests_of(c).has(g)


## Identity of a clue ignoring phrasing and argument order (for de-duplication).
static func key(c: Dictionary) -> String:
	if String(c.type) == AT_TABLE:
		return "%s:%d:%d" % [c.type, c.a, c.t]
	return "%s:%d:%d" % [c.type, mini(int(c.a), int(c.b)), maxi(int(c.a), int(c.b))]


## "" when the clue is well formed for the model, otherwise what's wrong with it.
static func validate(c: Dictionary, m) -> String:
	if not c.has("type") or not TYPES.has(String(c.type)):
		return "unknown clue type"
	var n: int = m.guest_count()
	if not c.has("a") or int(c.a) < 0 or int(c.a) >= n:
		return "bad guest a"
	if String(c.type) == AT_TABLE:
		if not c.has("t") or int(c.t) < 0 or int(c.t) >= m.tables:
			return "bad table"
	else:
		if not c.has("b") or int(c.b) < 0 or int(c.b) >= n:
			return "bad guest b"
		if int(c.a) == int(c.b):
			return "clue about one guest twice"
	return ""


static func _table_filled(m, at: PackedInt32Array, t: int) -> int:
	var k := 0
	for p in m.seats:
		if at[m.seat(t, p)] >= 0:
			k += 1
	return k


## TRUE / FALSE / UNKNOWN for a (partial) seating. `at` is the matching seat -> guest array.
static func eval(c: Dictionary, m, seat_of: PackedInt32Array, at: PackedInt32Array) -> int:
	var type := String(c.type)
	var sa: int = seat_of[int(c.a)]
	if type == AT_TABLE:
		var t: int = int(c.t)
		if sa >= 0:
			return TRUE if m.table_of(sa) == t else FALSE
		return FALSE if _table_filled(m, at, t) >= m.seats else UNKNOWN
	var sb: int = seat_of[int(c.b)]
	match type:
		ADJACENT:
			if sa >= 0 and sb >= 0:
				return TRUE if m.ring_adjacent(sa, sb) else FALSE
			if sa < 0 and sb < 0:
				return UNKNOWN
			var s := sa if sa >= 0 else sb
			for ns in m.neighbor_seats(s):
				if at[ns] < 0:
					return UNKNOWN
			return FALSE          # both neighbour seats taken by someone else
		NOT_ADJACENT:
			if sa >= 0 and sb >= 0:
				return FALSE if m.ring_adjacent(sa, sb) else TRUE
			if sa < 0 and sb < 0:
				return UNKNOWN
			var s2 := sa if sa >= 0 else sb
			for ns in m.neighbor_seats(s2):
				if at[ns] < 0:
					return UNKNOWN
			return TRUE           # both neighbour seats taken by someone else
		SAME_TABLE:
			if sa >= 0 and sb >= 0:
				return TRUE if m.table_of(sa) == m.table_of(sb) else FALSE
			if sa < 0 and sb < 0:
				return UNKNOWN
			var s3 := sa if sa >= 0 else sb
			return FALSE if _table_filled(m, at, m.table_of(s3)) >= m.seats else UNKNOWN
		DIFFERENT_TABLE:
			if sa >= 0 and sb >= 0:
				return TRUE if m.table_of(sa) != m.table_of(sb) else FALSE
			if sa < 0 and sb < 0:
				return UNKNOWN
			var s4 := sa if sa >= 0 else sb
			var mine: int = m.table_of(s4)
			for t2 in m.tables:
				if t2 != mine and _table_filled(m, at, t2) < m.seats:
					return UNKNOWN
			return FALSE          # every other table is full
	return UNKNOWN


## Is the clue true of a complete seating?
static func holds(c: Dictionary, m, seat_of: PackedInt32Array) -> bool:
	return eval(c, m, seat_of, m.guest_at_from(seat_of)) == TRUE


# ------------------------------------------------------------------ text

const PHRASES := {
	ADJACENT: [
		"{a} must sit next to {b}.",
		"{a} and {b} insist on sitting side by side.",
		"{a} refuses to sit anywhere but beside {b}.",
		"Seat {a} right next to {b}.",
	],
	NOT_ADJACENT: [
		"{a} can't sit next to {b}.",
		"Do not seat {a} beside {b}.",
		"{a} and {b} must not be neighbours.",
		"Keep {a} out of elbow range of {b}.",
	],
	SAME_TABLE: [
		"{a} and {b} sit at the same table.",
		"{a} must share a table with {b}.",
		"{a} and {b} are inseparable: same table.",
		"Put {a} at {b}'s table.",
	],
	DIFFERENT_TABLE: [
		"{a} and {b} sit at different tables.",
		"Keep {a} and {b} at separate tables.",
		"{a} won't share a table with {b}.",
		"{a} and {b} can't share a table.",
	],
	AT_TABLE: [
		"{a} sits at {t}.",
		"{a} has been promised a seat at {t}.",
		"{a} must be at {t}.",
		"{a} is seated at {t}.",
	],
}


static func variant_count(type: String) -> int:
	return PHRASES[type].size()


static func text(c: Dictionary, m) -> String:
	var opts: Array = PHRASES[String(c.type)]
	var s: String = opts[posmod(int(c.get("v", 0)), opts.size())]
	s = s.replace("{a}", m.guest_name(int(c.a)))
	if c.has("b"):
		s = s.replace("{b}", m.guest_name(int(c.b)))
	if c.has("t"):
		s = s.replace("{t}", m.table_name(int(c.t)))
	return s
