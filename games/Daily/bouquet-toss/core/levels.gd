extends RefCounted
## The level for a date: generate attempt 0, 1, 2... until the validator accepts one.
##
## core/attempts.json lists, for each upcoming date, which attempt was accepted and the
## validator's reference throw (made by tools/precompute.gd). A phone then builds just that one
## attempt and checks the reference throw still catches (one simulation) instead of searching.
## The level is identical either way; dates missing from the table search (and the game caches
## the result locally). Tests check the table against a fresh search.

const Gen = preload("res://core/generator.gd")
const V = preload("res://core/validator.gd")
const Daily = preload("res://core/daily.gd")
const L = preload("res://core/level.gd")
const P = preload("res://core/physics.gd")

const MAX_ATTEMPTS := 60
const TABLE_PATH := "res://core/attempts.json"

static var _table: Dictionary = {}
static var _table_loaded := false


static func attempt_table() -> Dictionary:
	if not _table_loaded:
		_table_loaded = true
		if FileAccess.file_exists(TABLE_PATH):
			var d = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
			if d is Dictionary and int(d.get("gen", -1)) == Gen.GEN_VERSION:
				_table = d.get("days", {})
	return _table


static func make_attempt(d: String, attempt: int) -> Dictionary:
	return Gen.make(d, Daily.day_number(d), Daily.seed_for(d, attempt), attempt, Daily.archetype_for(d))


## Searches from attempt 0. Returns the accepted level with "stats" and "solution" filled in.
static func search(d: String) -> Dictionary:
	var last: Dictionary = {}
	for attempt in MAX_ATTEMPTS:
		var lv := make_attempt(d, attempt)
		var st := V.evaluate(lv)
		if st.ok:
			return _finish(lv, st)
		last = lv
		last.stats = st
	# Never expected (the sweep tool checks this); fall back to the most solvable easy layout.
	for attempt in MAX_ATTEMPTS:
		var lv2 := Gen.make(d, Daily.day_number(d), Daily.seed_for(d, 1000 + attempt), 1000 + attempt, "open")
		var st2 := V.evaluate(lv2)
		if st2.solves > 0 and st2.robust > 0:
			return _finish(lv2, st2)
	return last


static func for_date(d: String) -> Dictionary:
	var lv := from_table(d)
	return lv if not lv.is_empty() else search(d)


## The level from the precomputed table, or {} when the date isn't listed (or the entry no
## longer matches the generator, which tests catch).
static func from_table(d: String) -> Dictionary:
	var t := attempt_table()
	if not t.has(d):
		return {}
	var e: Array = t[d]
	var lv := make_attempt(d, int(e[0]))
	if not L.geometry_errors(lv).is_empty():
		return {}
	if P.throw(lv, int(e[1]), int(e[2])).outcome != "catch":
		return {}
	lv.solution = {"a": int(e[1]), "p": int(e[2])}
	lv.stats = {}
	return lv


static func _finish(lv: Dictionary, st: Dictionary) -> Dictionary:
	lv.solution = st.solution
	lv.stats = {"rate": snappedf(float(st.rate), 0.0001), "solves": st.solves, "robust": st.robust,
		"routes": st.routes, "clusters": st.clusters}
	return lv
