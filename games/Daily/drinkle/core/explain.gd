extends RefCounted
## Post-game explanations: the player's deduction path, and on a loss which clue would have told
## the remaining drinks apart.

const Schema = preload("res://core/schema.gd")
const DB = preload("res://core/db.gd")
const Cands = preload("res://core/candidates.gd")
const Hints = preload("res://core/hints.gd")
const Cmp = preload("res://core/compare.gd")


static func _lc(id: String, v) -> String:
	if id == "fruit" and v == "none":
		return "no fruit"
	var s := Schema.value_label(id, v)
	return s if id == "family" else s.to_lower()


## What a red cell rules out: the whole related group when the value has one (a red "lime"
## means no citrus at all), otherwise just the value.
static func _ruled_out(id: String, v) -> String:
	var g := Schema.group_of(id, v)
	if g != "" and id != "family":
		return Schema.group_label(id, g).to_lower()
	return _lc(id, v)


static func _arrow_note(id: String, guess_v, code: int) -> String:
	var lv := _lc(id, guess_v)
	if id == "sweet":
		return ("sweeter than " + lv) if code == Schema.HIGHER else ("less sweet than " + lv)
	if id == "strength":
		return ("stronger than " + lv) if code == Schema.HIGHER else ("lighter than " + lv)
	return ("more than " + lv) if code == Schema.HIGHER else ("less than " + lv)


## One line per guess: [{id, name, notes: [String], left: int, solved: bool}].
## notes say what that guess newly confirmed or ruled out; left is how many drinks still fit.
## facts carry "after": how many guesses had been made when the clue or hint revealed them.
static func path(history: Array, facts: Array = []) -> Array:
	var out: Array = []
	var ids := Schema.ids()
	for i in history.size():
		var h: Dictionary = history[i]
		var g := DB.get_drink(String(h.id))
		var fb: PackedInt32Array = h.fb
		var before := Hints.knowledge(history.slice(0, i), facts_upto(facts, i))
		var facts_now := facts_upto(facts, i + 1)
		var left := Cands.remaining(history.slice(0, i + 1), facts_now).size()
		if Cmp.all_exact(fb):
			out.append({"id": g.id, "name": g.name, "notes": ["solved"], "left": 1, "solved": true})
			continue
		var confirms: Array = []
		var outs: Array = []
		var others: Array = []
		for j in ids.size():
			var id: String = ids[j]
			var e: Dictionary = before[id]
			var v = g.get(id)
			match fb[j]:
				Schema.EXACT:
					if not e.exact:
						confirms.append(_lc(id, v))
				Schema.MISS:
					if Schema.kind(id) == "bool":
						if not e.exact:
							confirms.append(Schema.value_label(id, not v).to_lower())
					elif not e.exact and not e.out.has(v) and (id != "fruit" or v != "none"):
						var o := _ruled_out(id, v)
						if not outs.has(o):
							outs.append(o)
					elif id == "fruit" and v == "none" and not e.exact and e.group == "" and not e.out.has("none"):
						others.append("it has fruit")
				Schema.PARTIAL:
					if not e.exact and e.group == "":
						others.append("%s, not %s" % [Schema.group_label(id, Schema.group_of(id, v)).to_lower(), _lc(id, v)])
				Schema.HIGHER, Schema.LOWER:
					if not e.exact:
						others.append(_arrow_note(id, v, fb[j]))
		var notes: Array = []
		if not outs.is_empty():
			notes.append("ruled out " + _join(outs))
		if not confirms.is_empty():
			notes.append("confirmed " + _join(confirms))
		for o in others:
			if notes.size() >= 3:
				break
			notes.append(o)
		if notes.is_empty():
			notes.append("nothing new")
		out.append({"id": g.id, "name": g.name, "notes": notes, "left": left, "solved": false})
	return out


static func _join(items: Array) -> String:
	if items.size() <= 1:
		return "".join(items)
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + String(items[-1])


static func facts_upto(facts: Array, n: int) -> Array:
	var out: Array = []
	for f in facts:
		if int(f.get("after", 0)) <= n:
			out.append(f)
	return out


## For a lost game: {left: [names that still fit], text}. Says which attribute separates the
## answer from the drinks that were still possible.
static func loss(target: Dictionary, history: Array, facts: Array) -> Dictionary:
	var cands := Cands.remaining(history, facts)
	var others: Array = []
	for c in cands:
		if c.id != target.id:
			others.append(c)
	var names: Array = []
	for c in cands:
		names.append(c.name)
	if others.is_empty():
		return {"left": names, "text": "Only the %s fit everything you'd found. One more guess would have done it." % target.name}
	var best := ""
	var best_n := -1
	for id in Schema.ids():
		var n := 0
		for o in others:
			if o.get(id) != target.get(id):
				n += 1
		if n > best_n:
			best_n = n
			best = id
	var text := "%d drinks still fit your clues. " % cands.size()
	if best_n == others.size():
		text += "Testing the %s (it's %s) would have told them apart." % [Schema.label(best).to_lower(), _lc(best, target.get(best))]
	else:
		text += "Testing the %s (it's %s) would have ruled out %d of them." % [Schema.label(best).to_lower(), _lc(best, target.get(best)), best_n]
	return {"left": names, "text": text}
