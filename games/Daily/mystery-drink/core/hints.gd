extends RefCounted
## What the player knows, and help built only from the candidate set (never hand-written per
## puzzle).
##
##   knowledge(): per attribute, what the feedback so far pins down (for the "Known" strip)
##   clue(): an automatic clue after guesses 4 and 5: the most useful attribute still unknown
##   hint(level): 1 = which attribute to test next, 2 = a gentle fact, 3 = the most decisive fact
##
## Facts are {"attr", "value"} and are fed back into the candidate filter.

const Schema = preload("res://core/schema.gd")
const DB = preload("res://core/db.gd")
const Cands = preload("res://core/candidates.gd")

const CLUE_AFTER := [4, 5]      # wrong-guess counts that unlock an automatic clue


## attr -> {exact: bool, value, lo, hi (ordinals), group (category, "" if none), out: [values]}
static func knowledge(history: Array, facts: Array = []) -> Dictionary:
	var k := {}
	for id in Schema.ids():
		var a := Schema.attr(id)
		var e := {"exact": false, "value": null, "group": "", "out": []}
		if Schema.is_ordinal(id):
			e.lo = int(a.min)
			e.hi = int(a.min) + a.levels.size() - 1
		k[id] = e
	var ids := Schema.ids()
	for h in history:
		var g := DB.get_drink(String(h.id))
		if g.is_empty():
			continue
		var fb: PackedInt32Array = h.fb
		for i in ids.size():
			var id: String = ids[i]
			var e: Dictionary = k[id]
			var v = g.get(id)
			match fb[i]:
				Schema.EXACT:
					e.exact = true
					e.value = v
					if Schema.is_ordinal(id):
						e.lo = v
						e.hi = v
				Schema.HIGHER:
					e.lo = maxi(e.lo, int(v) + 1)
				Schema.LOWER:
					e.hi = mini(e.hi, int(v) - 1)
				Schema.PARTIAL:
					e.group = Schema.group_of(id, v)
					if not e.out.has(v):
						e.out.append(v)
				Schema.MISS:
					if Schema.kind(id) == "bool":
						e.exact = true
						e.value = not v
					elif not e.out.has(v):
						e.out.append(v)
	for f in facts:
		var e: Dictionary = k.get(String(f.attr), {})
		if e.is_empty():
			continue
		e.exact = true
		e.value = f.value
		if Schema.is_ordinal(String(f.attr)):
			e.lo = int(f.value)
			e.hi = int(f.value)
	for id in ids:
		var e: Dictionary = k[id]
		if Schema.is_ordinal(id) and not e.exact and e.lo == e.hi:
			e.exact = true
			e.value = e.lo
		if Schema.kind(id) == "category" and not e.exact:
			# only one value left that isn't ruled out (and fits a known group)?
			var left: Array = []
			for v in Schema.values(id):
				if e.out.has(v):
					continue
				if e.group != "" and Schema.group_of(id, v) != e.group:
					continue
				left.append(v)
			if left.size() == 1:
				e.exact = true
				e.value = left[0]
	return k


## Short text for the Known strip: "Rum", "Citrus?", "Sweet or more", "?".
static func known_text(id: String, e: Dictionary) -> String:
	if e.exact:
		return Schema.value_label(id, e.value)
	if Schema.is_ordinal(id):
		var a := Schema.attr(id)
		var lo_min := int(a.min)
		var hi_max: int = int(a.min) + a.levels.size() - 1
		if e.lo == lo_min and e.hi == hi_max:
			return "?"
		if e.lo == lo_min:
			return Schema.value_label(id, e.hi) + " or less"
		if e.hi == hi_max:
			return Schema.value_label(id, e.lo) + " or more"
		return Schema.value_label(id, e.lo) + " to " + Schema.value_label(id, e.hi)
	if e.group != "":
		return Schema.group_label(id, e.group) + "?"
	return "?"


static func fact_text(id: String, value) -> String:
	var v := Schema.value_label(id, value)
	match id:
		"family":
			return "It's in the %s family." % v
		"base":
			if Schema.group_of(id, value) == "free":
				return "It's alcohol-free, made with %s." % v.to_lower()
			return "Its base is %s." % v.to_lower()
		"fruit":
			return "No fruit goes into it." if value == "none" else "Its main fruit is %s." % v.to_lower()
		"bubbles":
			return "It's fizzy." if value else "It's still (no bubbles)."
		"sweet":
			return "Its sweetness is %s." % v.to_lower()
		"strength":
			return "It's alcohol-free." if int(value) == 0 else "Its strength is %s." % v.to_lower()
	return "%s: %s" % [Schema.label(id), v]


static func test_text(id: String) -> String:
	match id:
		"family": return "Try a guess that tests what kind of drink it is."
		"base": return "Try a guess that tests the base spirit."
		"fruit": return "Try a guess that tests which fruit goes in."
		"bubbles": return "Try testing whether it's fizzy."
		"sweet": return "Try testing how sweet it is."
		"strength": return "Try testing how strong it is."
	return "Try testing the %s." % Schema.label(id).to_lower()


static func unknown_attrs(history: Array, facts: Array) -> Array:
	var k := knowledge(history, facts)
	var out: Array = []
	for id in Schema.ids():
		if not k[id].exact:
			out.append(id)
	return out


## Candidates left if the target's value for `id` were revealed.
static func left_after_reveal(id: String, target: Dictionary, cands: Array) -> int:
	var n := 0
	for c in cands:
		if c.get(id) == target.get(id):
			n += 1
	return n


## {attr, value, text} for the most decisive unknown attribute, or {} when everything is known.
static func decisive_fact(target: Dictionary, history: Array, facts: Array) -> Dictionary:
	var cands := Cands.remaining(history, facts)
	var best := ""
	var best_n := 1 << 30
	for id in unknown_attrs(history, facts):
		var n := left_after_reveal(id, target, cands)
		if n < best_n:
			best_n = n
			best = id
	if best == "":
		return {}
	return {"attr": best, "value": target.get(best), "text": fact_text(best, target.get(best))}


## A gentle fact: the unknown attribute that narrows things the least but still narrows them.
static func gentle_fact(target: Dictionary, history: Array, facts: Array) -> Dictionary:
	var cands := Cands.remaining(history, facts)
	var best := ""
	var best_n := -1
	var fallback := ""
	for id in unknown_attrs(history, facts):
		var n := left_after_reveal(id, target, cands)
		if fallback == "":
			fallback = id
		if n < cands.size() and n > best_n:
			best_n = n
			best = id
	if best == "":
		best = fallback
	if best == "":
		return {}
	return {"attr": best, "value": target.get(best), "text": fact_text(best, target.get(best))}


## The unknown attribute whose values are spread most evenly over the candidates (the best
## thing to test next).
static func best_test(history: Array, facts: Array) -> String:
	var cands := Cands.remaining(history, facts)
	var best := ""
	var best_s := -1.0
	for id in unknown_attrs(history, facts):
		var counts := {}
		for c in cands:
			var v = str(c.get(id))
			counts[v] = int(counts.get(v, 0)) + 1
		var s := 0.0
		for v in counts:
			var p := float(counts[v]) / cands.size()
			s -= p * log(p)
		if s > best_s + 1e-9:
			best_s = s
			best = id
	return best


## The automatic clue owed after `wrong` wrong guesses, or {} if none is due.
static func clue(target: Dictionary, history: Array, facts: Array, wrong: int) -> Dictionary:
	if not CLUE_AFTER.has(wrong):
		return {}
	return decisive_fact(target, history, facts)


## Hint for a level (1-3): {level, text, fact ({} when the hint reveals no fact)}.
static func hint(level: int, target: Dictionary, history: Array, facts: Array) -> Dictionary:
	var cands := Cands.remaining(history, facts)
	if cands.size() <= 1:
		return {"level": level, "text": "Only one drink fits everything you know. Find it in the list!", "fact": {}}
	match level:
		1:
			var id := best_test(history, facts)
			if id == "":
				return {"level": 1, "text": "You know every attribute. Pick the drink that matches them all.", "fact": {}}
			return {"level": 1, "text": test_text(id), "fact": {}, "attr": id}
		2:
			var f := gentle_fact(target, history, facts)
			return {"level": 2, "text": f.get("text", ""), "fact": f}
	var f3 := decisive_fact(target, history, facts)
	return {"level": 3, "text": f3.get("text", ""), "fact": f3}
