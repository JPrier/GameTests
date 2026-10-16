extends RefCounted
## remaining(history, facts) -> the drinks that still fit everything revealed so far.
## Never shown to the player during a game; used for hints, clues, analysis and the end screen.
##
##   history: Array of {"id": guessed drink id, "fb": PackedInt32Array feedback}
##   facts:   Array of {"attr": attribute id, "value": the mystery drink's value} (from clues/hints)

const DB = preload("res://core/db.gd")
const Cmp = preload("res://core/compare.gd")


static func fits(d: Dictionary, history: Array, facts: Array = []) -> bool:
	for h in history:
		var g := DB.get_drink(String(h.id))
		if g.is_empty():
			continue
		var fb: PackedInt32Array = h.fb
		if Cmp.all_exact(fb):
			if d.id != g.id:
				return false
			continue
		if d.id == g.id:
			return false      # a wrong guess is ruled out even if another drink shares its profile
		if Cmp.compare(g, d) != fb:
			return false
	for f in facts:
		if d.get(String(f.attr)) != f.value:
			return false
	return true


static func remaining(history: Array, facts: Array = [], pool: Array = []) -> Array:
	if pool.is_empty():
		pool = DB.all()
	var out: Array = []
	for d in pool:
		if fits(d, history, facts):
			out.append(d)
	return out


static func ids(drinks: Array) -> Array:
	var out: Array = []
	for d in drinks:
		out.append(d.id)
	return out


## The history entry for guessing `guess_id` against `target`.
static func entry(guess_id: String, target: Dictionary) -> Dictionary:
	return {"id": guess_id, "fb": Cmp.compare(DB.get_drink(guess_id), target)}
