extends RefCounted
## The player's board: who sits where, with undo, reset and checking. No UI in here.

const C = preload("res://core/constraints.gd")

var m
var seat_of := PackedInt32Array()
var history: Array = []              # previous seat_of arrays (undo stack)
var hinted: Dictionary = {}          # guest -> true if a hint seated them
const MAX_HISTORY := 200


func _init(model = null) -> void:
	if model != null:
		setup(model)


func setup(model) -> void:
	m = model
	seat_of = m.empty_seating()
	history = []
	hinted = {}


func guest_at() -> PackedInt32Array:
	return m.guest_at_from(seat_of)


func occupant(s: int) -> int:
	for g in seat_of.size():
		if seat_of[g] == s:
			return g
	return -1


func seated_count() -> int:
	var k := 0
	for s in seat_of:
		if s >= 0:
			k += 1
	return k


func _push() -> void:
	history.append(seat_of.duplicate())
	if history.size() > MAX_HISTORY:
		history.pop_front()


## Put guest g in seat s. Whoever was there moves to g's old seat (or back to the tray).
## Returns false if nothing changed.
func place(g: int, s: int) -> bool:
	if g < 0 or g >= seat_of.size() or s < 0 or s >= m.seat_count():
		return false
	if seat_of[g] == s:
		return false
	_push()
	var other := occupant(s)
	if other >= 0:
		seat_of[other] = seat_of[g]
		hinted.erase(other)
	seat_of[g] = s
	hinted.erase(g)
	return true


## Send guest g back to the tray.
func unseat(g: int) -> bool:
	if g < 0 or g >= seat_of.size() or seat_of[g] < 0:
		return false
	_push()
	seat_of[g] = -1
	hinted.erase(g)
	return true


func undo() -> bool:
	if history.is_empty():
		return false
	seat_of = history.pop_back()
	for g in hinted.keys():
		if seat_of[g] < 0:
			hinted.erase(g)
	return true


## Clear every seat. Undo brings the board back.
func reset() -> bool:
	if seated_count() == 0:
		return false
	_push()
	seat_of = m.empty_seating()
	hinted = {}
	return true


## TRUE / FALSE / UNKNOWN for each clue on the current board.
func clue_states() -> Array:
	var at := guest_at()
	var out: Array = []
	for c in m.clues:
		out.append(C.eval(c, m, seat_of, at))
	return out


func broken_clues() -> Array:
	var out: Array = []
	var st := clue_states()
	for i in st.size():
		if st[i] == C.FALSE:
			out.append(i)
	return out


func is_complete() -> bool:
	return m.is_complete(seat_of)


## Every seat filled and every clue holds. (With a unique puzzle this is the answer.)
func is_solved() -> bool:
	if not is_complete():
		return false
	for st in clue_states():
		if st != C.TRUE:
			return false
	return true


## Seated guests that aren't where the answer has them (allowing for turning or mirroring a table).
func wrong_guests() -> Array:
	return m.best_match(seat_of).wrong


func to_dict() -> Dictionary:
	var arr: Array = []
	for s in seat_of:
		arr.append(s)
	return {"seats": arr, "hinted": hinted.keys()}


func load_dict(d: Dictionary) -> void:
	seat_of = m.empty_seating()
	var arr: Array = d.get("seats", [])
	if arr.size() == seat_of.size():
		var used := {}
		for g in arr.size():
			var s := int(arr[g])
			if s >= 0 and s < m.seat_count() and not used.has(s):
				seat_of[g] = s
				used[s] = true
	hinted = {}
	for g in d.get("hinted", []):
		if int(g) >= 0 and int(g) < seat_of.size() and seat_of[int(g)] >= 0:
			hinted[int(g)] = true
	history = []
