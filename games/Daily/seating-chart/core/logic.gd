extends RefCounted
## Logical (human-style) solver.
##
## Instead of searching, it keeps the kind of notes a person keeps and only writes down things
## that follow from what is already known:
##   - which tables each guest could still be at,
##   - for each pair: do they share a table? (yes / no / unknown)
##   - for each pair: are they neighbours? (yes / no / unknown)
## Notes are bitmasks per guest, so reasoning is fast.
##
## Two ways to run it:
##   step mode  - one deduction at a time, easiest first, each recorded with its rule, level,
##                the facts it relied on and an English explanation. Used for hints and for the
##                difficulty rating.
##   bulk mode  - apply every deduction at once until nothing changes (no records). Used by the
##                generator to ask "can this be reasoned out within level X?" quickly.
## Both use the same rule code, so they always agree on what is deducible.
##
## Levels:
##   0  bookkeeping: a clue as written, neighbours share a table, etc.
##   1  direct: a table placement passed along a same/different-table link
##   2  counting and seating: a full table, chains of same-table links, both neighbours known,
##      only two people left who could be someone's neighbours, a row closing into a ring
##   3  indirect: two "different table" links with two tables, group sizes vs table size
##   4  what-if: assume one thing, follow levels 0-3 to a contradiction, conclude the opposite
## Every rule is sound, so if the notes pin down one complete seating, the puzzle has exactly
## one answer (tests cross-check this against the exhaustive solver).

const C = preload("res://core/constraints.gd")

const UNK := -1

static var _pop := PackedByteArray()

var m
var N := 0
var T := 0
var n := 0
var ALL := 0
var tab := PackedInt32Array()     # bitmask of tables each guest could still be at
var ay := PackedInt32Array()      # neighbours: yes
var an := PackedInt32Array()      # neighbours: no (includes self)
var sy := PackedInt32Array()      # same table: yes (includes self)
var sn := PackedInt32Array()      # same table: no
var prov: Dictionary = {}         # fact key -> step index that established it
var steps: Array = []
var contradiction := ""
var max_level := 4
var record_text := true
var _bulk := false
var _changed := false


func setup(model, clue_list: Array, level_cap: int = 4) -> void:
	m = model
	N = m.guest_count()
	T = m.tables
	n = m.seats
	ALL = (1 << N) - 1
	if _pop.size() < (1 << N):
		_pop.resize(1 << 16)
		for x in 1 << 16:
			_pop[x] = (x & 1) + _pop[x >> 1] if x > 0 else 0
	max_level = level_cap
	tab = PackedInt32Array()
	tab.resize(N)
	tab.fill((1 << T) - 1)
	ay = PackedInt32Array()
	ay.resize(N)
	ay.fill(0)
	sn = ay.duplicate()
	an = PackedInt32Array()
	sy = PackedInt32Array()
	for g in N:
		an.append(1 << g)
		sy.append(1 << g)
	prov = {}
	steps = []
	contradiction = ""
	for i in clue_list.size():
		_given_clue(clue_list[i], i)


## Step mode, as far as possible. Returns the solver (check .is_solved(), .steps ...).
static func run(model, clue_list: Array, level_cap: int = 4):
	var L = load("res://core/logic.gd").new()
	L.setup(model, clue_list, level_cap)
	L.solve()
	return L


## Bulk mode: can these clues be reasoned out completely within `level_cap`?
static func solvable(model, clue_list: Array, level_cap: int) -> bool:
	var L = load("res://core/logic.gd").new()
	L.record_text = false
	L.setup(model, clue_list, level_cap)
	L.propagate()
	return L.contradiction == "" and L.is_solved()


func solve() -> bool:
	while contradiction == "" and not is_solved():
		if step() < 0:
			break
	return contradiction == "" and is_solved()


## One deduction (step mode). Returns its step index, or -1 if stuck / contradiction.
func step() -> int:
	if contradiction != "":
		return -1
	var d = find_deduction()
	if d == null:
		return -1
	return apply_step(d)


## Bulk mode: apply everything deducible within max_level until nothing changes.
func propagate() -> void:
	_bulk = true
	var rt := record_text
	record_text = false
	while contradiction == "":
		_changed = false
		_bookkeeping()
		if contradiction == "" and max_level >= 1:
			_level1()
		if contradiction == "" and max_level >= 2:
			_level2()
		if contradiction == "" and max_level >= 3:
			_level3()
		if contradiction == "":
			contradiction = check()
		if contradiction != "" or is_solved():
			break
		if not _changed:
			if max_level >= 4 and _bulk_what_if():
				continue
			break
	_bulk = false
	record_text = rt


func clone():
	var L = load("res://core/logic.gd").new()
	L.m = m
	L.N = N
	L.T = T
	L.n = n
	L.ALL = ALL
	L.tab = tab.duplicate()
	L.ay = ay.duplicate()
	L.an = an.duplicate()
	L.sy = sy.duplicate()
	L.sn = sn.duplicate()
	L.prov = prov.duplicate()
	L.steps = []
	L.contradiction = contradiction
	L.max_level = max_level
	L.record_text = record_text
	return L


# ------------------------------------------------------------------ bits

func pc(x: int) -> int:
	return _pop[x]


func _single(x: int) -> int:
	if x <= 0 or (x & (x - 1)) != 0:
		return -1
	var t := 0
	while x > 1:
		x >>= 1
		t += 1
	return t


func _list(x: int) -> Array:
	var out: Array = []
	var i := 0
	while x:
		if x & 1:
			out.append(i)
		x >>= 1
		i += 1
	return out


func _at_mask(t: int) -> int:           # guests certainly at table t
	var x := 0
	for g in N:
		if tab[g] == (1 << t):
			x |= 1 << g
	return x


func _may_mask(t: int) -> int:          # guests who could be at table t
	var x := 0
	for g in N:
		if (tab[g] >> t) & 1:
			x |= 1 << g
	return x


func _compat(g: int) -> int:            # guests who could share a table with g
	var x := 0
	for h in N:
		if tab[g] & tab[h]:
			x |= 1 << h
	return x


# ------------------------------------------------------------------ queries

func is_solved() -> bool:
	for g in N:
		if _single(tab[g]) < 0:
			return false
	for g in N:
		var mates := _at_mask(_single(tab[g]))
		if (mates & ~(ay[g] | an[g])) != 0:
			return false
	return true


func table_known(g: int) -> int:
	return _single(tab[g])


func get_adj(g: int, h: int) -> int:
	if (ay[g] >> h) & 1:
		return 1
	if (an[g] >> h) & 1:
		return 0
	return UNK


func get_same(g: int, h: int) -> int:
	if (sy[g] >> h) & 1:
		return 1
	if (sn[g] >> h) & 1:
		return 0
	return UNK


## The seating the notes describe (only meaningful once solved), in canonical form.
func solution() -> PackedInt32Array:
	var seat_of: PackedInt32Array = m.empty_seating()
	for t in T:
		var members := _list(_at_mask(t))
		if members.size() != n:
			return m.empty_seating()
		var ring: Array = [members[0]]
		var cur: int = members[0]
		while ring.size() < n:
			var nxt := -1
			for h in _list(ay[cur]):
				if not ring.has(h):
					nxt = h
					break
			if nxt < 0:
				return m.empty_seating()
			ring.append(nxt)
			cur = nxt
		for i in n:
			seat_of[ring[i]] = m.seat(t, i)
	return m.canonical(seat_of)


func summary() -> Dictionary:
	var by_level := [0, 0, 0, 0, 0]
	var top := 0
	for s in steps:
		var lv: int = s.level
		if s.rule == "clue" or s.rule == "board":
			continue
		by_level[lv] += 1
		top = maxi(top, lv)
	return {"solved": contradiction == "" and is_solved(), "max_level": top, "by_level": by_level,
		"steps": steps.size(), "contradiction": contradiction}


## Clue indices a step relies on, following its chain of reasons back to the clues.
func clue_chain(step_index: int) -> Array:
	var out: Array = []
	for i in step_chain(step_index):
		for c in steps[i].clues:
			if not out.has(c):
				out.append(c)
	out.sort()
	return out


## Step indices on the chain of reasons for a step (including itself), oldest first.
func step_chain(step_index: int) -> Array:
	var seen := {}
	var stack: Array = [step_index]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen.has(i) or i < 0 or i >= steps.size():
			continue
		seen[i] = true
		for dpi in steps[i].deps:
			stack.append(dpi)
	var out: Array = seen.keys()
	out.sort()
	return out


# ------------------------------------------------------------------ facts
# A fact is ["nt", g, t] (g isn't at table t), ["a", g, h, v] (neighbours yes/no) or
# ["s", g, h, v] (same table yes/no).

static func _pk(kind: String, g: int, h: int) -> String:
	return "%s:%d:%d" % [kind, mini(g, h), maxi(g, h)]


func _tab_keys(g: int) -> Array:
	var out: Array = []
	for t in T:
		if (tab[g] >> t) & 1 == 0:
			out.append("nt:%d:%d" % [g, t])
	return out


func _new_fact(f: Array) -> bool:
	match String(f[0]):
		"nt":
			return (tab[f[1]] >> f[2]) & 1 == 1
		"a":
			return get_adj(f[1], f[2]) != f[3]
		_:
			return get_same(f[1], f[2]) != f[3]


## Apply one fact. Returns true if it was new. Sets `contradiction` on conflict.
func _set_fact(f: Array, step_index: int) -> bool:
	var kind: String = f[0]
	var g: int = f[1]
	if kind == "nt":
		var t: int = f[2]
		if (tab[g] >> t) & 1 == 0:
			return false
		tab[g] &= ~(1 << t)
		if not _bulk:
			prov["nt:%d:%d" % [g, t]] = step_index
		if tab[g] == 0:
			contradiction = "%s would have no table left" % m.guest_name(g)
		return true
	var h: int = f[2]
	var v: int = f[3]
	var cur := get_adj(g, h) if kind == "a" else get_same(g, h)
	if cur == v:
		return false
	if cur != UNK:
		contradiction = "%s and %s would both %s and not" % [m.guest_name(g), m.guest_name(h),
			"sit side by side" if kind == "a" else "share a table"]
		return false
	if kind == "a":
		if v == 1:
			ay[g] |= 1 << h
			ay[h] |= 1 << g
		else:
			an[g] |= 1 << h
			an[h] |= 1 << g
	else:
		if v == 1:
			sy[g] |= 1 << h
			sy[h] |= 1 << g
		else:
			sn[g] |= 1 << h
			sn[h] |= 1 << g
	if not _bulk:
		prov[_pk(kind, g, h)] = step_index
	return true


func apply_step(d: Dictionary) -> int:
	var idx := steps.size()
	var deps: Array = []
	for k in d.get("uses", []):
		if prov.has(k):
			var p: int = prov[k]
			if p >= 0 and not deps.has(p):
				deps.append(p)
	steps.append({"rule": d.rule, "level": d.level, "facts": d.facts, "clues": d.get("clues", []),
		"deps": deps, "uses": d.get("uses", []), "text": d.get("text", "")})
	for f in d.facts:
		_set_fact(f, idx)
		if contradiction != "":
			break
	if contradiction == "":
		contradiction = check()
	return idx


## In step mode return the deduction; in bulk mode apply it and keep scanning (null).
func _emit(d: Dictionary):
	if not _bulk:
		return d
	for f in d.facts:
		if _set_fact(f, -1):
			_changed = true
		if contradiction != "":
			return d       # stop scanning; caller sees the contradiction
	return null


func _given_clue(c: Dictionary, i: int) -> void:
	var a: int = int(c.a)
	var facts: Array = []
	match String(c.type):
		C.ADJACENT:
			facts = [["a", a, int(c.b), 1]]
		C.NOT_ADJACENT:
			facts = [["a", a, int(c.b), 0]]
		C.SAME_TABLE:
			facts = [["s", a, int(c.b), 1]]
		C.DIFFERENT_TABLE:
			facts = [["s", a, int(c.b), 0]]
		C.AT_TABLE:
			for t in T:
				if t != int(c.t):
					facts.append(["nt", a, t])
	var fresh: Array = []
	for f in facts:
		if _new_fact(f):
			fresh.append(f)
	if fresh.is_empty():
		return
	apply_step({"rule": "clue", "level": 0, "facts": fresh, "clues": [i], "uses": [],
		"text": C.text(c, m) if record_text else ""})


## Facts from guests already (correctly) seated on the board, used for hints.
func add_board_facts(seat_of: PackedInt32Array, guests: Array) -> void:
	var facts: Array = []
	for g in guests:
		var t: int = m.table_of(seat_of[g])
		for t2 in T:
			if t2 != t:
				facts.append(["nt", g, t2])
	for i in guests.size():
		for j in range(i + 1, guests.size()):
			var g: int = guests[i]
			var h: int = guests[j]
			if m.table_of(seat_of[g]) == m.table_of(seat_of[h]):
				facts.append(["s", g, h, 1])
				facts.append(["a", g, h, 1 if m.ring_adjacent(seat_of[g], seat_of[h]) else 0])
	var fresh: Array = []
	for f in facts:
		if _new_fact(f):
			fresh.append(f)
	if fresh.is_empty():
		return
	apply_step({"rule": "board", "level": 0, "facts": fresh, "clues": [], "uses": [],
		"text": "Guests already seated."})


# ------------------------------------------------------------------ consistency

## "" if the notes are consistent, otherwise a short reason (used in what-if explanations).
func check() -> String:
	for g in N:
		if tab[g] == 0:
			return "%s would have no table left" % m.guest_name(g)
	for t in T:
		var sure := pc(_at_mask(t))
		var could := pc(_may_mask(t))
		if sure > n:
			return "%s would have more than %d guests" % [m.table_name(t), n]
		if could < n:
			return "%s couldn't be filled" % m.table_name(t)
	for g in N:
		var me := 1 << g
		if (ay[g] & an[g]) or (sy[g] & sn[g]):
			return "%s's notes would contradict each other" % m.guest_name(g)
		if ay[g] & sn[g]:
			var h: int = _list(ay[g] & sn[g])[0]
			return "%s and %s would be neighbours at different tables" % [m.guest_name(g), m.guest_name(h)]
		if pc(ay[g]) > 2:
			return "%s would have three neighbours" % m.guest_name(g)
		var poss := _compat(g) & ~an[g] & ~sn[g] & ~me
		if pc(poss) < 2:
			return "%s couldn't get two neighbours" % m.guest_name(g)
		if pc(sy[g]) > n:
			return "%s, %s would all need one table" % [m.guest_name(g), _names(_list(sy[g] & ~me))]
		for h in _list(sy[g] & ~me):
			if (tab[g] & tab[h]) == 0:
				return "%s and %s would need the same table" % [m.guest_name(g), m.guest_name(h)]
			if sy[g] & sn[h]:
				var x: int = _list(sy[g] & sn[h])[0]
				return "%s would have to both join and avoid %s" % [m.guest_name(h), m.guest_name(x)]
		var tg := _single(tab[g])
		if tg >= 0 and (sn[g] & _at_mask(tg)):
			var y: int = _list(sn[g] & _at_mask(tg))[0]
			return "%s and %s would be at the same table" % [m.guest_name(g), m.guest_name(y)]
		if T == 2:
			for a in _list(sn[g]):
				if sn[a] & sn[g]:
					var c: int = _list(sn[a] & sn[g])[0]
					return "%s, %s and %s would need three different tables" % [m.guest_name(g), m.guest_name(a), m.guest_name(c)]
	for comp in _adj_components():
		if comp.cycle and comp.verts.size() < n:
			return "neighbours would close a circle of only %d" % comp.verts.size()
		if comp.verts.size() > n:
			return "a row of %d neighbours wouldn't fit at one table" % comp.verts.size()
	return ""


## Connected pieces of the "neighbours" graph: rows (with their two ends) or closed rings.
func _adj_components() -> Array:
	var seen := 0
	var out: Array = []
	for start in N:
		if (seen >> start) & 1 or ay[start] == 0:
			continue
		var comp := 0
		var frontier := 1 << start
		while frontier:
			comp |= frontier
			var nxt := 0
			for v in _list(frontier):
				nxt |= ay[v]
			frontier = nxt & ~comp
		seen |= comp
		var verts := _list(comp)
		var ends: Array = []
		for v in verts:
			if pc(ay[v]) <= 1:
				ends.append(v)
		out.append({"verts": verts, "ends": ends, "cycle": ends.is_empty()})
	return out


## A row of neighbours from one end, for explanations: [A, B, C].
func _path_order(comp: Dictionary) -> Array:
	if comp.ends.is_empty():
		return comp.verts
	var order: Array = [comp.ends[0]]
	var cur: int = comp.ends[0]
	while true:
		var nxt := -1
		for w in _list(ay[cur]):
			if not order.has(w):
				nxt = w
				break
		if nxt < 0:
			break
		order.append(nxt)
		cur = nxt
	return order


# ------------------------------------------------------------------ deductions

func _nm(g: int) -> String:
	return m.guest_name(g)


func _names(list: Array) -> String:
	var parts: Array = []
	for g in list:
		parts.append(_nm(g))
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + String(parts[-1])


func find_deduction():
	var d = _bookkeeping()
	if d == null and max_level >= 1:
		d = _level1()
	if d == null and max_level >= 2:
		d = _level2()
	if d == null and max_level >= 3:
		d = _level3()
	if d == null and max_level >= 4:
		d = _level4()
	return d


func _place_facts(g: int, t: int) -> Array:
	var facts: Array = []
	for t2 in T:
		if t2 != t and (tab[g] >> t2) & 1:
			facts.append(["nt", g, t2])
	return facts


func _bookkeeping():
	var rec := not _bulk
	for g in N:
		# neighbours share a table
		for h in _list(ay[g] & ~sy[g]):
			var r = _emit({"rule": "neighbours_share_table", "level": 0, "facts": [["s", g, h, 1]],
				"uses": [_pk("a", g, h)] if rec else [],
				"text": "%s sits next to %s, so they share a table." % [_nm(g), _nm(h)] if record_text else ""})
			if r != null:
				return r
		# different tables means not neighbours
		for h in _list(sn[g] & ~an[g]):
			var r2 = _emit({"rule": "apart_not_neighbours", "level": 0, "facts": [["a", g, h, 0]],
				"uses": [_pk("s", g, h)] if rec else [],
				"text": "%s and %s are at different tables, so they aren't neighbours." % [_nm(g), _nm(h)] if record_text else ""})
			if r2 != null:
				return r2
		# both tables known
		var tg := _single(tab[g])
		if tg < 0:
			continue
		var unknown := ALL & ~(sy[g] | sn[g])
		for h in _list(unknown):
			var th := _single(tab[h])
			if th < 0:
				continue
			var v := 1 if tg == th else 0
			var txt := ""
			if record_text:
				txt = ("%s and %s are both at %s." % [_nm(g), _nm(h), m.table_name(tg)]) if v == 1 \
					else ("%s is at %s and %s is at %s." % [_nm(g), m.table_name(tg), _nm(h), m.table_name(th)])
			var r3 = _emit({"rule": "tables_known", "level": 0, "facts": [["s", g, h, v]],
				"uses": (_tab_keys(g) + _tab_keys(h)) if rec else [], "text": txt})
			if r3 != null:
				return r3
	return null


func _level1():
	var rec := not _bulk
	for g in N:
		var tg := _single(tab[g])
		if tg < 0:
			continue
		for h in _list(sy[g] & ~(1 << g)):
			if tab[h] == (1 << tg):
				continue
			var r = _emit({"rule": "follow_same_table", "level": 1, "facts": _place_facts(h, tg),
				"uses": (_tab_keys(g) + [_pk("s", g, h)]) if rec else [],
				"text": "%s shares a table with %s, who is at %s, so %s is at %s too." % [_nm(h), _nm(g), m.table_name(tg), _nm(h), m.table_name(tg)] if record_text else ""})
			if r != null:
				return r
		for h in _list(sn[g]):
			if (tab[h] >> tg) & 1 == 0:
				continue
			var txt := ""
			if record_text:
				var rest: int = tab[h] & ~(1 << tg)
				if _single(rest) >= 0:
					txt = "%s can't share a table with %s, who is at %s, so %s is at %s." % [_nm(h), _nm(g), m.table_name(tg), _nm(h), m.table_name(_single(rest))]
				else:
					txt = "%s can't share a table with %s, so %s isn't at %s." % [_nm(h), _nm(g), _nm(h), m.table_name(tg)]
			var r2 = _emit({"rule": "follow_different_table", "level": 1, "facts": [["nt", h, tg]],
				"uses": (_tab_keys(g) + [_pk("s", g, h)]) if rec else [], "text": txt})
			if r2 != null:
				return r2
	return null


func _level2():
	var rec := not _bulk
	# a full table pushes everyone else away; exactly n candidates fill it
	for t in T:
		var sure := _at_mask(t)
		var could := _may_mask(t)
		if pc(sure) == n and could != sure:
			var facts: Array = []
			var uses: Array = []
			var moved := _list(could & ~sure)
			for g in moved:
				facts.append(["nt", g, t])
			if rec:
				for g in _list(sure):
					uses += _tab_keys(g)
			var txt := ""
			if record_text:
				txt = "%s is full (%s), so %s %s elsewhere." % [m.table_name(t), _names(_list(sure)), _names(moved), "sits" if moved.size() == 1 else "sit"]
			var r = _emit({"rule": "table_full", "level": 2, "facts": facts, "uses": uses, "text": txt})
			if r != null:
				return r
		if pc(could) == n and could != sure:
			var facts2: Array = []
			var uses2: Array = []
			for g in _list(could & ~sure):
				facts2 += _place_facts(g, t)
			if rec:
				for g in _list(ALL & ~could):
					uses2.append("nt:%d:%d" % [g, t])
			var txt2 := ""
			if record_text:
				txt2 = "Only %s can still sit at %s, and it needs %d guests, so they all do." % [_names(_list(could)), m.table_name(t), n]
			var r2 = _emit({"rule": "table_exact", "level": 2, "facts": facts2, "uses": uses2, "text": txt2})
			if r2 != null:
				return r2
	# chains of same-table links
	for b in N:
		for a in _list(sy[b] & ~(1 << b)):
			var newy := sy[b] & ~sy[a] & ~sn[a]
			for c in _list(newy):
				var r3 = _emit({"rule": "same_table_chain", "level": 2, "facts": [["s", a, c, 1]],
					"uses": [_pk("s", a, b), _pk("s", b, c)] if rec else [],
					"text": "%s shares a table with %s, and %s with %s, so %s and %s share a table." % [_nm(a), _nm(b), _nm(b), _nm(c), _nm(a), _nm(c)] if record_text else ""})
				if r3 != null:
					return r3
			var newn := sn[b] & ~sy[a] & ~sn[a]
			for c in _list(newn):
				var r4 = _emit({"rule": "same_table_chain", "level": 2, "facts": [["s", a, c, 0]],
					"uses": [_pk("s", a, b), _pk("s", b, c)] if rec else [],
					"text": "%s shares a table with %s, who can't share with %s, so %s and %s are apart too." % [_nm(a), _nm(b), _nm(c), _nm(a), _nm(c)] if record_text else ""})
				if r4 != null:
					return r4
	# both neighbours known
	for g in N:
		if pc(ay[g]) == 2:
			var unk := ALL & ~(ay[g] | an[g])
			if unk:
				var nb := _list(ay[g])
				var facts5: Array = []
				for h in _list(unk):
					facts5.append(["a", g, h, 0])
				var r5 = _emit({"rule": "both_neighbours_known", "level": 2, "facts": facts5,
					"uses": [_pk("a", g, nb[0]), _pk("a", g, nb[1])] if rec else [],
					"text": "%s already sits between %s and %s, so %s isn't next to anyone else." % [_nm(g), _nm(nb[0]), _nm(nb[1]), _nm(g)] if record_text else ""})
				if r5 != null:
					return r5
	# the two neighbours of one guest aren't neighbours of each other
	if n > 3:
		for b in N:
			if pc(ay[b]) != 2:
				continue
			var ac := _list(ay[b])
			var a: int = ac[0]
			var c: int = ac[1]
			if get_adj(a, c) != UNK:
				continue
			var r6 = _emit({"rule": "no_triangle", "level": 2, "facts": [["a", a, c, 0]],
				"uses": [_pk("a", a, b), _pk("a", b, c)] if rec else [],
				"text": "%s sits between %s and %s, so %s and %s are on either side of %s and can't be neighbours." % [_nm(b), _nm(a), _nm(c), _nm(a), _nm(c), _nm(b)] if record_text else ""})
			if r6 != null:
				return r6
	# only two people can still be someone's neighbours
	for g in N:
		var me := 1 << g
		var cand := _compat(g) & ~an[g] & ~sn[g] & ~me
		if pc(cand) == 2 and (cand & ~ay[g]) != 0:
			var facts7: Array = []
			for h in _list(cand & ~ay[g]):
				facts7.append(["a", g, h, 1])
			var uses7: Array = []
			if rec:
				for h in _list(ALL & ~cand & ~me):
					uses7.append(_pk("a", g, h))
					uses7.append(_pk("s", g, h))
					uses7 += _tab_keys(h)
				uses7 += _tab_keys(g)
			var r7 = _emit({"rule": "only_two_neighbours", "level": 2, "facts": facts7, "uses": uses7,
				"text": "Everyone has two neighbours, and only %s can still sit next to %s, so they both do." % [_names(_list(cand)), _nm(g)] if record_text else ""})
			if r7 != null:
				return r7
	# rows of neighbours: a row as long as a table closes; a shorter row can't
	for comp in _adj_components():
		if comp.cycle:
			continue
		var size: int = comp.verts.size()
		if size < 4 or comp.ends.size() != 2:
			continue      # (a branching row is caught as a contradiction by check())
		var e1: int = comp.ends[0]
		var e2: int = comp.ends[1]
		if get_adj(e1, e2) != UNK:
			continue
		var order := _path_order(comp)
		var uses8: Array = []
		if rec:
			for i in order.size() - 1:
				uses8.append(_pk("a", order[i], order[i + 1]))
		if size == n:
			var r8 = _emit({"rule": "ring_closes", "level": 2, "facts": [["a", e1, e2, 1]], "uses": uses8,
				"text": "%s sit in a row of %d, a whole table, so %s and %s meet around the far side." % [_names(order), n, _nm(e1), _nm(e2)] if record_text else ""})
			if r8 != null:
				return r8
		elif size < n:
			var r9 = _emit({"rule": "ring_too_short", "level": 2, "facts": [["a", e1, e2, 0]], "uses": uses8,
				"text": "%s sit in a row; %s and %s at the ends can't also be neighbours, or the circle would have only %d seats." % [_names(order), _nm(e1), _nm(e2), size] if record_text else ""})
			if r9 != null:
				return r9
	return null


func _level3():
	var rec := not _bulk
	# with two tables, two people apart from the same person share the other table
	if T == 2:
		for b in N:
			var apart := _list(sn[b])
			for i in apart.size():
				for j in range(i + 1, apart.size()):
					var a: int = apart[i]
					var c: int = apart[j]
					if get_same(a, c) != UNK:
						continue
					var r = _emit({"rule": "two_apart", "level": 3, "facts": [["s", a, c, 1]],
						"uses": [_pk("s", a, b), _pk("s", b, c)] if rec else [],
						"text": "There are only two tables. %s and %s both avoid %s's table, so they share the other one." % [_nm(a), _nm(c), _nm(b)] if record_text else ""})
					if r != null:
						return r
	# a group that fills a table keeps everyone else out
	for g in N:
		var grp := sy[g]
		if pc(grp) != n or g != _list(grp)[0]:
			continue
		var facts: Array = []
		var out := 0
		for x in _list(grp):
			var unk := ALL & ~grp & ~sn[x]
			for h in _list(unk):
				facts.append(["s", x, h, 0])
				out |= 1 << h
		if facts.is_empty():
			continue
		var uses: Array = []
		if rec:
			for x in _list(grp & ~(1 << g)):
				uses.append(_pk("s", g, x))
		var r2 = _emit({"rule": "group_fills_table", "level": 3, "facts": facts, "uses": uses,
			"text": "%s fill a whole table together, so %s can't join them." % [_names(_list(grp)), _names(_list(out))] if record_text else ""})
		if r2 != null:
			return r2
	# two groups too big to merge
	for a in N:
		var unk2 := ALL & ~(sy[a] | sn[a]) & ~((1 << (a + 1)) - 1)
		for b in _list(unk2):
			if pc(sy[a] | sy[b]) <= n:
				continue
			var uses3: Array = []
			if rec:
				for x in _list(sy[a] & ~(1 << a)):
					uses3.append(_pk("s", a, x))
				for x in _list(sy[b] & ~(1 << b)):
					uses3.append(_pk("s", b, x))
			var r3 = _emit({"rule": "groups_too_big", "level": 3, "facts": [["s", a, b, 0]], "uses": uses3,
				"text": "%s and %s are two groups that add up to %d, more than a table seats, so %s and %s sit apart." % [_names(_list(sy[a])), _names(_list(sy[b])), pc(sy[a] | sy[b]), _nm(a), _nm(b)] if record_text else ""})
			if r3 != null:
				return r3
	# a group can't fit at a table that's nearly full
	for g in N:
		if _single(tab[g]) >= 0:
			continue
		var grp2 := sy[g]
		for t in T:
			if (tab[g] >> t) & 1 == 0:
				continue
			var there := _at_mask(t) & ~grp2
			if pc(there) + pc(grp2) <= n:
				continue
			var uses4: Array = []
			if rec:
				for h in _list(there):
					uses4 += _tab_keys(h)
				for x in _list(grp2 & ~(1 << g)):
					uses4.append(_pk("s", g, x))
			var txt := ""
			if record_text:
				var who := _nm(g) if pc(grp2) == 1 else "%s and %s" % [_nm(g), _names(_list(grp2 & ~(1 << g)))]
				txt = "%s already has %s, so there's no room for %s there: %s isn't at %s." % [m.table_name(t), _names(_list(there)), who, _nm(g), m.table_name(t)]
			var r4 = _emit({"rule": "group_wont_fit", "level": 3, "facts": [["nt", g, t]], "uses": uses4, "text": txt})
			if r4 != null:
				return r4
	return null


# ------------------------------------------------------------------ what-if

## The assumptions a person would try: "suppose X sat at Table N", and "suppose X sat / didn't
## sit next to Y" for two people already known to share a table.
func _trial_candidates() -> Array:
	var out: Array = []
	for g in N:
		if _single(tab[g]) >= 0:
			continue
		for t in _list(tab[g]):
			var rest: int = tab[g] & ~(1 << t)
			out.append({"assume": _place_facts(g, t), "opposite": [["nt", g, t]],
				"desc": "%s sat at %s" % [_nm(g), m.table_name(t)],
				"conclusion": ("%s is at %s" % [_nm(g), m.table_name(_single(rest))]) if _single(rest) >= 0 else ("%s isn't at %s" % [_nm(g), m.table_name(t)])})
	# neighbour what-ifs only between people already known to share a table
	for g in N:
		for h in _list(sy[g] & ~(ay[g] | an[g]) & ~((1 << (g + 1)) - 1)):
			out.append({"assume": [["a", g, h, 1]], "opposite": [["a", g, h, 0]],
				"desc": "%s sat next to %s" % [_nm(g), _nm(h)],
				"conclusion": "%s and %s aren't neighbours" % [_nm(g), _nm(h)]})
			out.append({"assume": [["a", g, h, 0]], "opposite": [["a", g, h, 1]],
				"desc": "%s didn't sit next to %s" % [_nm(g), _nm(h)],
				"conclusion": "%s sits next to %s" % [_nm(g), _nm(h)]})
	return out


## Runs an assumption through levels 0-3 in bulk. Returns the sub-solver.
func _try(assume: Array):
	var sub = clone()
	sub.max_level = 3
	sub.record_text = false
	sub._bulk = true
	for f in assume:
		sub._set_fact(f, -1)
		if sub.contradiction != "":
			break
	sub._bulk = false
	if sub.contradiction == "":
		sub.propagate()
	return sub


## Bulk what-if: find any assumption that breaks and record the opposite. True if one did.
func _bulk_what_if() -> bool:
	for cand in _trial_candidates():
		var sub = _try(cand.assume)
		if sub.contradiction != "":
			for f in cand.opposite:
				_set_fact(f, -1)
			_changed = true
			return true
	return false


## Step-mode what-if: picks the assumption that breaks in the fewest deductions, and explains it.
func _level4():
	var best = null
	var best_len := 1 << 30
	for cand in _trial_candidates():
		var quick = _try(cand.assume)
		if quick.contradiction == "":
			continue
		# replay in step mode to measure and explain the chain
		var sub = clone()
		sub.max_level = 3
		sub.record_text = record_text
		sub.steps = []
		for f in cand.assume:
			sub._set_fact(f, -1)
			if sub.contradiction != "":
				break
		if sub.contradiction == "":
			sub.contradiction = sub.check()
		var guard := 0
		while sub.contradiction == "" and guard < 300:
			guard += 1
			if sub.step() < 0:
				break
		if sub.contradiction == "":
			continue
		var length: int = sub.steps.size()
		if length >= best_len:
			continue
		best_len = length
		var uses: Array = []
		for s in sub.steps:
			for k in s.uses:
				if prov.has(k) and not uses.has(k):
					uses.append(k)
		var txt := ""
		if record_text:
			var chain: Array = []
			for s in sub.steps:
				if s.level > 0 and chain.size() < 3:
					chain.append(s.text)
			txt = "Suppose %s. " % cand.desc
			if not chain.is_empty():
				txt += "Then " + " ".join(chain) + " "
			txt += "But then %s. So %s." % [sub.contradiction, cand.conclusion]
		best = {"rule": "what_if", "level": 4, "facts": cand.opposite, "uses": uses, "text": txt}
		if best_len <= 2:
			break
	return best
