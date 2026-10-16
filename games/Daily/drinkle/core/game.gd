extends RefCounted
## One day's game, without UI: guesses, feedback, clues, hints, win/loss, save round trip.

const Schema = preload("res://core/schema.gd")
const DB = preload("res://core/db.gd")
const Cmp = preload("res://core/compare.gd")
const Cands = preload("res://core/candidates.gd")
const Hints = preload("res://core/hints.gd")

const MAX_GUESSES := 6
const MAX_HINTS := 3

var date := ""
var target: Dictionary = {}
var guesses: Array = []          # drink ids, in order
var facts: Array = []            # [{attr, value, after, source: "clue"|"hint"}]
var hint_texts: Array = []       # [{level, text}]
var hints_used := 0
var finished := false
var won := false


func _init(d: String = "", target_drink: Dictionary = {}) -> void:
	date = d
	target = target_drink


func history() -> Array:
	var out: Array = []
	for id in guesses:
		out.append(Cands.entry(id, target))
	return out


func feedback(i: int) -> PackedInt32Array:
	return Cmp.compare(DB.get_drink(guesses[i]), target)


func wrong_count() -> int:
	return guesses.size() - (1 if won else 0)


func guesses_left() -> int:
	return MAX_GUESSES - guesses.size()


func fact_list() -> Array:
	return facts


## Validates and records a guess. Returns {ok, error, solved, clue ({} or the revealed fact)}.
func guess(id: String) -> Dictionary:
	if finished:
		return {"ok": false, "error": "finished"}
	if not DB.has(id):
		return {"ok": false, "error": "unknown"}
	if guesses.has(id):
		return {"ok": false, "error": "repeat"}
	guesses.append(id)
	var clue := {}
	if id == target.id:
		won = true
		finished = true
	elif guesses.size() >= MAX_GUESSES:
		finished = true
	else:
		var c := Hints.clue(target, history(), facts, wrong_count())
		if not c.is_empty():
			clue = _add_fact(c, "clue")
	return {"ok": true, "error": "", "solved": won, "clue": clue}


func _add_fact(f: Dictionary, source: String) -> Dictionary:
	for e in facts:
		if e.attr == f.attr:
			return {}
	var entry := {"attr": f.attr, "value": f.value, "after": guesses.size(), "source": source, "text": f.get("text", "")}
	facts.append(entry)
	return entry


func can_hint() -> bool:
	return not finished and hints_used < MAX_HINTS


## Uses the next hint level. Returns {level, text, fact} or {} when none is available.
func use_hint() -> Dictionary:
	if not can_hint():
		return {}
	var h := Hints.hint(hints_used + 1, target, history(), facts)
	hints_used += 1
	if not h.get("fact", {}).is_empty():
		_add_fact(h.fact, "hint")
	hint_texts.append({"level": h.level, "text": h.text})
	return h


func remaining() -> Array:
	return Cands.remaining(history(), facts)


func knowledge() -> Dictionary:
	return Hints.knowledge(history(), facts)


## Gives up: the game ends as a loss (used by dev "lose" and tests).
func give_up() -> void:
	finished = true
	won = false


func result_label() -> String:
	if not finished:
		return "In progress" if not guesses.is_empty() else ""
	return ("%d/%d" % [guesses.size(), MAX_GUESSES]) if won else ("X/%d" % MAX_GUESSES)


func to_dict() -> Dictionary:
	var fs: Array = []
	for f in facts:
		fs.append({"attr": f.attr, "value": f.value, "after": f.after, "source": f.source, "text": f.get("text", "")})
	return {"date": date, "target": target.get("id", ""), "guesses": guesses.duplicate(), "facts": fs,
		"hints": hints_used, "hint_texts": hint_texts.duplicate(true), "finished": finished, "won": won}


## Restores saved progress. Ignores a save made for a different answer (e.g. after a schedule
## change) and drops anything malformed.
func load_dict(d: Dictionary) -> bool:
	if String(d.get("target", "")) != String(target.get("id", "")):
		return false
	guesses = []
	for id in d.get("guesses", []):
		var s := String(id)
		if DB.has(s) and not guesses.has(s) and guesses.size() < MAX_GUESSES:
			guesses.append(s)
	facts = []
	for f in d.get("facts", []):
		if not (f is Dictionary) or Schema.attr(String(f.get("attr", ""))).is_empty():
			continue
		var attr := String(f.attr)
		var v = f.get("value")
		if Schema.is_ordinal(attr):
			v = int(v)
		if not Schema.valid_value(attr, v) or v != target.get(attr):
			continue
		facts.append({"attr": attr, "value": v, "after": int(f.get("after", 0)), "source": String(f.get("source", "hint")), "text": String(f.get("text", ""))})
	hints_used = clampi(int(d.get("hints", 0)), 0, MAX_HINTS)
	hint_texts = d.get("hint_texts", []) if d.get("hint_texts") is Array else []
	won = guesses.has(target.get("id", ""))
	if won:
		guesses = guesses.slice(0, guesses.find(target.id) + 1)
	finished = won or guesses.size() >= MAX_GUESSES or bool(d.get("finished", false))
	return true
