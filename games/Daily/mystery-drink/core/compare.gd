extends RefCounted
## compare(guess, target) -> one feedback code per attribute (Schema.EXACT ... LOWER).
## Pure and deterministic; the whole game, the candidate filter, hints and the analyser use it.
##
##   category: same value 🟩, same related group 🟨, otherwise 🟥
##   bool:     same 🟩, otherwise 🟥
##   ordinal:  same 🟩, otherwise an arrow pointing from the guess toward the mystery drink

const Schema = preload("res://core/schema.gd")


static func attr_feedback(id: String, guess_value, target_value) -> int:
	match Schema.kind(id):
		"ordinal":
			var g := int(guess_value)
			var t := int(target_value)
			if g == t:
				return Schema.EXACT
			return Schema.HIGHER if t > g else Schema.LOWER
		"category":
			if guess_value == target_value:
				return Schema.EXACT
			var gg := Schema.group_of(id, guess_value)
			if gg != "" and gg == Schema.group_of(id, target_value):
				return Schema.PARTIAL
			return Schema.MISS
	return Schema.EXACT if guess_value == target_value else Schema.MISS


static func compare(guess: Dictionary, target: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in Schema.ids():
		out.append(attr_feedback(id, guess.get(id), target.get(id)))
	return out


static func all_exact(fb: PackedInt32Array) -> bool:
	for c in fb:
		if c != Schema.EXACT:
			return false
	return true


## Compact string form, handy as a dictionary key: "=~x^v".
static func key(fb: PackedInt32Array) -> String:
	var s := ""
	for c in fb:
		s += "=~x^v"[c]
	return s


static func emoji_row(fb: PackedInt32Array) -> String:
	var s := ""
	for c in fb:
		s += Schema.code_emoji(c)
	return s
