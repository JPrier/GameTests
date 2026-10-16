extends RefCounted
## Progressive hints, worked out by the logic solver from the current board (nothing hard-coded).
##
## next(m, seat_of) returns what the next useful move is and why:
##   kind "wrong":  someone seated is in a spot that can't be right -> guest to move back
##   kind "deduce": a deduction (from the clues plus the correctly seated guests) that tells you
##                  where `guest` goes -> clue chain, explanation, seat
##   kind "place":  fallback with no explanation (never expected for a valid puzzle)
## The UI turns that into three levels: 1 highlight the clues, 2 explain, 3 make the move.

const L = preload("res://core/logic.gd")
const C = preload("res://core/constraints.gd")


static func next(m, seat_of: PackedInt32Array) -> Dictionary:
	var bm: Dictionary = m.best_match(seat_of)
	var target: PackedInt32Array = bm.target
	if not bm.wrong.is_empty():
		var g: int = bm.wrong[0]
		var related: Array = []
		var at: PackedInt32Array = m.guest_at_from(seat_of)
		for i in m.clues.size():
			var c: Dictionary = m.clues[i]
			if C.mentions(c, g) and C.eval(c, m, seat_of, at) == C.FALSE:
				related.append(i)
		return {"kind": "wrong", "guest": g, "seat": -1, "clues": related,
			"text": "%s can't stay in that seat." % m.guest_name(g),
			"nudge": "Someone is sitting in a seat that can't be right."}
	var correct: Array = []
	for g in seat_of.size():
		if seat_of[g] >= 0:
			correct.append(g)
	if correct.size() == seat_of.size():
		return {"kind": "done", "guest": -1, "seat": -1, "clues": [], "text": "Everyone is seated.", "nudge": "Everyone is seated."}
	var lg = L.new()
	lg.setup(m, m.clues, 4)
	lg.add_board_facts(seat_of, correct)
	var guard := 0
	var idx := -1
	var fresh_steps: int = lg.steps.size()  # clues as written can already place someone
	while lg.contradiction == "" and guard < 500:
		guard += 1
		if idx + 1 < fresh_steps:
			idx += 1
		else:
			idx = lg.step()
			if idx < 0:
				break
			fresh_steps = lg.steps.size()
		var s: Dictionary = lg.steps[idx]
		var g := _actionable(lg, s, seat_of)
		if g < 0:
			continue
		var chain: Array = []
		for i in lg.step_chain(idx):
			var st: Dictionary = lg.steps[i]
			if st.rule != "clue" and st.rule != "board" and st.level > 0:
				chain.append(String(st.text))
		var explain: Array = chain.slice(maxi(0, chain.size() - 3))
		var uses_board := false
		for i in lg.step_chain(idx):
			if lg.steps[i].rule == "board":
				uses_board = true
		return {"kind": "deduce", "guest": g, "seat": target[g], "clues": lg.clue_chain(idx), "uses_board": uses_board,
			"text": String(s.text), "chain": explain, "level": int(s.level), "rule": String(s.rule),
			"nudge": _nudge(lg.clue_chain(idx).size())}
	# fallback: first unseated guest
	for g in seat_of.size():
		if seat_of[g] < 0:
			return {"kind": "place", "guest": g, "seat": target[g], "clues": [],
				"text": "Try %s here." % m.guest_name(g), "nudge": "Try placing someone new."}
	return {"kind": "done", "guest": -1, "seat": -1, "clues": [], "text": "", "nudge": ""}


## The unseated guest a step lets you place, or -1. A step is actionable when it pins an
## unseated guest's table, or makes them a neighbour of someone already seated.
static func _actionable(lg, s: Dictionary, seat_of: PackedInt32Array) -> int:
	for f in s.facts:
		match String(f[0]):
			"nt":
				var g: int = f[1]
				if seat_of[g] < 0 and lg.table_known(g) >= 0:
					return g
			"a":
				if int(f[3]) != 1:
					continue
				var a: int = f[1]
				var b: int = f[2]
				if seat_of[a] >= 0 and seat_of[b] < 0:
					return b
				if seat_of[b] >= 0 and seat_of[a] < 0:
					return a
	return -1


static func _nudge(n_clues: int) -> String:
	if n_clues == 0:
		return "Look at who's already seated: it leaves only one option for someone."
	if n_clues == 1:
		return "Look closely at the highlighted clue."
	return "Look at the highlighted clues together."
