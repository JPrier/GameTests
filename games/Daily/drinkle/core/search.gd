extends RefCounted
## Autocomplete over drink names and aliases. Forgiving about case, accents, punctuation,
## "&" vs "and", word order and one typo per word.
##
##   "moj" -> Mojito, "gin t" -> Gin & Tonic, "g&t" -> Gin & Tonic, "marg" -> Margarita,
##   "espresso" -> Espresso Martini, "pina" -> Piña Colada, "margerita" -> Margarita

const DB = preload("res://core/db.gd")

const ACCENTS := {"á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "é": "e", "è": "e", "ê": "e",
	"ë": "e", "í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u", "ñ": "n", "ç": "c", "ø": "o", "å": "a"}

static var _keys: Array = []      # [{id, text, tokens, compact, alias}]


static func normalize(s: String) -> String:
	s = s.to_lower().strip_edges()
	var out := ""
	for ch in s:
		if ACCENTS.has(ch):
			out += ACCENTS[ch]
		elif ch == "&" or ch == "+":
			out += " and "
		elif ch == "'" or ch == "’" or ch == "." or ch == "´":
			pass                         # "dark 'n' stormy" -> "dark n stormy"
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		else:
			out += " "
	var parts := out.split(" ", false)
	return " ".join(parts)


static func tokens(s: String) -> PackedStringArray:
	return normalize(s).split(" ", false)


static func _ensure() -> void:
	if not _keys.is_empty():
		return
	for d in DB.all():
		var texts: Array = [d.name]
		texts.append_array(d.aliases)
		for i in texts.size():
			var n := normalize(String(texts[i]))
			if n == "":
				continue
			_keys.append({"id": d.id, "text": n, "tokens": n.split(" ", false),
				"compact": n.replace(" ", ""), "alias": i > 0})


## Exact name/alias match (after normalising) -> id, else "".
static func resolve(text: String) -> String:
	_ensure()
	var n := normalize(text)
	if n == "":
		return ""
	for k in _keys:
		if k.text == n or k.compact == n.replace(" ", ""):
			return k.id
	return ""


static func _lev_le1(a: String, b: String) -> bool:
	## true when a and b are within one edit (insert, delete, substitute, or swap of neighbours)
	if a == b:
		return true
	var la := a.length()
	var lb := b.length()
	if absi(la - lb) > 1:
		return false
	if la == lb:
		var diffs: Array = []
		for i in la:
			if a[i] != b[i]:
				diffs.append(i)
				if diffs.size() > 2:
					return false
		if diffs.size() == 1:
			return true
		return diffs.size() == 2 and diffs[1] == diffs[0] + 1 and a[diffs[0]] == b[diffs[1]] and a[diffs[1]] == b[diffs[0]]
	var s := a if la < lb else b
	var l := b if la < lb else a
	var i := 0
	var j := 0
	var skipped := false
	while i < s.length() and j < l.length():
		if s[i] == l[j]:
			i += 1
			j += 1
		elif skipped:
			return false
		else:
			skipped = true
			j += 1
	return true


## How well query token q matches key token k: 3 exact, 2 prefix, 1 typo-tolerant prefix (only
## for 5+ letters, so short prefixes like "marg" stay precise), 0 no.
static func _tok_score(q: String, k: String) -> int:
	if q == k:
		return 3
	if k.begins_with(q):
		return 2
	if q.length() >= 5:
		if _lev_le1(q, k.substr(0, q.length())) or _lev_le1(q, k.substr(0, q.length() + 1)) \
				or _lev_le1(q, k.substr(0, maxi(1, q.length() - 1))) or _lev_le1(q, k):
			return 1
	return 0


## Score for one key, or -1 when it doesn't match. Every query token must match a different
## key token (any order); matching from the first word and exact words score higher.
static func _key_score(qt: PackedStringArray, qcompact: String, k: Dictionary) -> int:
	var used := {}
	var total := 0
	for qi in qt.size():
		var best := 0
		var best_j := -1
		for j in k.tokens.size():
			if used.has(j):
				continue
			var sc := _tok_score(qt[qi], k.tokens[j])
			if sc > best:
				best = sc
				best_j = j
		if best == 0:
			total = -1
			break
		used[best_j] = true
		total += best * 10
		if qi == 0 and best_j == 0:
			total += 15
	if total < 0:
		# "pinacolada", "gnt": the query typed without spaces
		if qcompact.length() >= 3 and k.compact.begins_with(qcompact):
			return 25
		return -1
	if k.text == " ".join(qt):
		total += 100
	if not k.alias:
		total += 20         # a drink's own name beats an alias ("sour": Whiskey Sour before "sour apple martini")
	return total


## Ranked matches for the query: Array of drink ids (best first, each once).
static func search(query: String, limit: int = 0) -> Array:
	_ensure()
	var qt := tokens(query)
	if qt.is_empty():
		return []
	var qcompact := "".join(qt)
	var best := {}
	for k in _keys:
		var sc := _key_score(qt, qcompact, k)
		if sc >= 0 and sc > int(best.get(k.id, -1)):
			best[k.id] = sc
	var ids: Array = best.keys()
	ids.sort_custom(func(a, b):
		if best[a] != best[b]:
			return best[a] > best[b]
		var fa: int = DB.get_drink(a).fame
		var fb: int = DB.get_drink(b).fame
		if fa != fb:
			return fa < fb
		return DB.name_of(a) < DB.name_of(b))
	if limit > 0 and ids.size() > limit:
		ids.resize(limit)
	return ids


## Every drink A-Z by name (the browse list when nothing is typed).
static func alphabetical() -> Array:
	var ids: Array = []
	for d in DB.all():
		ids.append(d.id)
	ids.sort_custom(func(a, b): return normalize(DB.name_of(a)) < normalize(DB.name_of(b)))
	return ids
