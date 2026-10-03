extends Node2D
## X-Ray Shift: a daily airport-security game.
## Bags roll through the x-ray. Clear the clean ones, flag the ones with contraband, then tap the
## illegal items inside. Everyone gets the same ten bags each (UTC) day.

enum Screen { MENU, PLAY, END }
enum Phase { ENTER, SCAN, OPENING, OPEN, CLOSING, EXIT }

const GAME := "xray-shift"
const EPOCH := "2026-10-03"            # shift #1
const DEFAULT_URL := "https://jprier.github.io/GameTests/xray-shift/"
const BAGS := 10
const FIND_PTS := 100
const FALSE_ALARM_PTS := -100
const WRONG_PTS := -25
const TIME_PAR := 150.0                # seconds; every second under par is worth TIME_PTS
const TIME_PTS := 4

const BAG_HALF := Vector2(170, 104)    # bag outline, local units
const INNER := Vector2(150, 86)        # area items are packed into

const DUR := {Phase.ENTER: 0.6, Phase.OPENING: 0.8, Phase.CLOSING: 0.45, Phase.EXIT: 0.5}

const BAD_IDS := ["knife", "gun", "ammo", "explosive", "big_bottle", "hatchet"]
const LOOKALIKE := {"knife": "fork", "gun": "hair_dryer", "ammo": "batteries", "explosive": "power_bank",
	"big_bottle": "small_bottle", "hatchet": "umbrella"}
const LEGEND_NOTE := {
	"knife": "Any blade. Forks and spoons are fine.",
	"gun": "Solid blue metal. Hair dryers are mostly green plastic.",
	"ammo": "Pointed rounds. Flat-topped batteries are fine.",
	"explosive": "Sticks with wires and a timer. Power banks are fine.",
	"big_bottle": "Big bottles of liquid. Travel size is fine.",
	"hatchet": "A metal axe head on a handle. Umbrellas are fine.",
}
const BIG_IDS := ["laptop", "clothes", "book"]
const SMALL_OK := ["fork", "spoon", "hair_dryer", "batteries", "power_bank", "small_bottle", "phone", "shoe",
	"headphones", "keys", "umbrella", "toothbrush", "camera", "glasses", "watch"]

# x-ray false colour: blue = metal, orange = organic, green = plastic / inorganic
const XR := {
	"metal": Color(0.12, 0.26, 0.78, 0.74),
	"organic": Color(0.93, 0.5, 0.08, 0.58),
	"plastic": Color(0.16, 0.6, 0.26, 0.52),
	"fabric": Color(0.93, 0.56, 0.18, 0.15),
}

const C_BG := Color("12161c")
const C_PANEL := Color("1d242e")
const C_PANEL_HI := Color("283241")
const C_INK := Color("eef2f6")
const C_MUTED := Color("8a96a6")
const C_ACCENT := Color("ffc832")
const C_RED := Color("ff4d5a")
const C_GREEN := Color("35d07f")
const C_SCREEN := Color("e4e9ec")
const C_TABLE := Color("2a3340")
const C_BAGIN := Color("1f2a3d")

var CAT := {}                  # item id -> {name, bad, parts, half}

var today := ""
var date := ""
var puzzle_no := 1
var base_url := DEFAULT_URL
var dev_mode := false
var dev_open := false
var dev_reveal := false
var anim_speed := 1.0          # tests crank this up

var bags: Array = []           # [{items: [{id, pos, rot}], bad: [item index]}]
var results: Array = []        # [{flag, found: [], wrong: [], done}]
var elapsed := 0.0
var bag_i := 0
var screen := Screen.MENU
var phase := Phase.ENTER
var phase_t := 0.0
var close_hold := -1.0
var missed_flash: Array = []
var legend_open := false
var shake := 0.0
var popups: Array = []         # [{text, pos, color, t, size}]
var belt_off := 0.0
var demo_bag := {}

var font: Font
var buttons: Array = []
var col := Rect2()
var title_rect := Rect2()
var legend_rect := Rect2()
var mon := Rect2()
var ctrl := Rect2()
var open_cells: Array = []
var title_taps: Array = []
var press_t := -1.0
var press_pos := Vector2.ZERO
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""


func _ready() -> void:
	font = ThemeDB.fallback_font
	_build_catalog()
	_add_key_action("flag", [KEY_F, KEY_DOWN, KEY_X])
	_add_key_action("confirm", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT])
	_add_key_action("legend", [KEY_L, KEY_TAB])
	_add_key_action("back", [KEY_ESCAPE])
	_add_key_action("dev_toggle", [KEY_QUOTELEFT])
	demo_bag = {"items": _place(["clothes", "hair_dryer", "knife", "phone", "keys"], _rng_for("demo")), "bad": [2]}
	today = Time.get_date_string_from_system(true)
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_mode = OS.is_debug_build() or String(url.get("dev", "")) == "1"
	var want := today
	var d := String(url.get("day", ""))
	if _valid_date(d):
		want = d
	load_day(want)


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------------ item catalog

func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out


func _r(x: float, y: float, w: float, h: float, m: String, c: String) -> Dictionary:
	return {"t": "poly", "p": _pts([x, y, x + w, y, x + w, y + h, x, y + h]), "m": m, "c": Color(c)}


func _p(flat: Array, m: String, c: String) -> Dictionary:
	return {"t": "poly", "p": _pts(flat), "m": m, "c": Color(c)}


func _e(x: float, y: float, rx: float, ry: float, m: String, c: String) -> Dictionary:
	var p := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18.0
		p.append(Vector2(x + cos(a) * rx, y + sin(a) * ry))
	return {"t": "poly", "p": p, "m": m, "c": Color(c)}


func _c(x: float, y: float, r: float, m: String, c: String) -> Dictionary:
	return {"t": "circle", "o": Vector2(x, y), "r": r, "m": m, "c": Color(c)}


func _l(flat: Array, w: float, m: String, c: String) -> Dictionary:
	return {"t": "line", "p": _pts(flat), "w": w, "m": m, "c": Color(c)}


func _o(x: float, y: float, r: float, w: float, m: String, c: String) -> Dictionary:
	return {"t": "ring", "o": Vector2(x, y), "r": r, "w": w, "m": m, "c": Color(c)}


func _bottle(k: float) -> Array:
	var raw := [
		_p([-17, -26, -10, -34, 10, -34, 17, -26, 17, 40, -17, 40], "plastic", "cfe6f5"),
		_r(-15, -16, 30, 54, "organic", "4aa3df"),
		_r(-7, -44, 14, 11, "plastic", "cfe6f5"),
		_r(-8, -51, 16, 8, "plastic", "f2f2f2"),
	]
	var out: Array = []
	for part in raw:
		var q: Dictionary = part.duplicate()
		var pv := PackedVector2Array()
		for v in part.p:
			pv.append(v * k)
		q.p = pv
		out.append(q)
	return out


func _add(id: String, name: String, bad: bool, parts: Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for part in parts:
		var pad := 0.0
		var pts: Array = []
		match String(part.t):
			"poly", "line":
				pts = Array(part.p)
				pad = float(part.get("w", 0.0)) * 0.5
			"circle", "ring":
				pts = [part.o]
				pad = float(part.r) + float(part.get("w", 0.0)) * 0.5
		for v in pts:
			lo = Vector2(minf(lo.x, v.x - pad), minf(lo.y, v.y - pad))
			hi = Vector2(maxf(hi.x, v.x + pad), maxf(hi.y, v.y + pad))
	var mid := (lo + hi) * 0.5
	for part in parts:
		if part.has("p"):
			var pv := PackedVector2Array()
			for v in part.p:
				pv.append(v - mid)
			part.p = pv
		if part.has("o"):
			part.o = part.o - mid
	CAT[id] = {"name": name, "bad": bad, "parts": parts, "half": (hi - lo) * 0.5}


func _build_catalog() -> void:
	CAT.clear()
	# --- contraband
	_add("knife", "Knife", true, [
		_r(-52, -8, 40, 16, "organic", "7a4a26"),
		_p([-12, -8, 40, -8, 56, -1, 46, 5, -12, 5], "metal", "c9d1d9"),
		_c(-42, 0, 2.5, "metal", "c9d1d9"), _c(-24, 0, 2.5, "metal", "c9d1d9")])
	_add("gun", "Handgun", true, [
		_r(-44, -24, 84, 17, "metal", "1c1f23"),
		_r(-44, -28, 6, 4, "metal", "1c1f23"),
		_p([14, -8, 36, -8, 44, 26, 24, 28], "metal", "111316"),
		_l([16, -7, 16, 5, 6, 5, 1, -7], 3, "metal", "1c1f23"),
		_l([10, -7, 8, 1], 3, "metal", "1c1f23")])
	var ammo: Array = []
	for x in [-21, -7, 7, 21]:
		ammo.append(_r(x - 5, -2, 10, 20, "metal", "c8a03c"))
		ammo.append(_p([x - 5, -2, x - 3, -11, x, -15, x + 3, -11, x + 5, -2], "metal", "b5653a"))
	_add("ammo", "Ammunition", true, ammo)
	_add("explosive", "Explosives", true, [
		_r(-36, -22, 72, 13, "organic", "d23a2e"), _r(-36, -7, 72, 13, "organic", "d23a2e"),
		_r(-36, 8, 72, 13, "organic", "d23a2e"),
		_r(-21, -24, 6, 47, "plastic", "222222"), _r(15, -24, 6, 47, "plastic", "222222"),
		_r(-14, -38, 28, 14, "plastic", "1b1b1b"), _r(-10, -35, 20, 8, "metal", "7cff6b"),
		_l([-12, -24, -24, -32, -38, -40], 2.5, "metal", "e33b3b"),
		_l([8, -24, 26, -34, 40, -30], 2.5, "metal", "3b6fe3")])
	_add("big_bottle", "Big liquids", true, _bottle(1.0))
	_add("hatchet", "Hatchet", true, [
		_r(-52, -5, 86, 10, "organic", "9a6a3a"),
		_p([24, -10, 42, -25, 52, -23, 52, 19, 42, 21, 24, 8], "metal", "8d969e")])
	# --- allowed
	_add("small_bottle", "Travel bottle", false, _bottle(0.42))
	_add("hair_dryer", "Hair dryer", false, [
		_r(-38, -15, 56, 28, "plastic", "e889b5"), _c(20, -1, 16, "plastic", "e889b5"),
		_p([4, 10, 20, 10, 27, 42, 12, 44], "plastic", "d26f9f"),
		_l([-32, -6, -26, 5, -20, -6, -14, 5, -8, -6, -2, 5], 2, "metal", "c08040"),
		_l([20, 44, 30, 52, 44, 50], 2, "organic", "222222")])
	var batt: Array = []
	for x in [-17, 0, 17]:
		batt.append(_r(x - 6, -22, 12, 44, "metal", "3a3f46"))
		batt.append(_r(x - 3, -25, 6, 3, "metal", "b0b6bc"))
		batt.append(_r(x - 6, 10, 12, 12, "plastic", "e0b03a"))
	_add("batteries", "Batteries", false, batt)
	_add("fork", "Fork", false, [
		_r(-46, -3, 56, 6, "metal", "c9d1d9"), _r(8, -7, 10, 14, "metal", "c9d1d9"),
		_r(18, -7, 18, 2, "metal", "c9d1d9"), _r(18, -3, 18, 2, "metal", "c9d1d9"),
		_r(18, 1, 18, 2, "metal", "c9d1d9"), _r(18, 5, 18, 2, "metal", "c9d1d9")])
	_add("spoon", "Spoon", false, [
		_r(-44, -3, 52, 6, "metal", "c9d1d9"), _e(20, 0, 15, 9, "metal", "c9d1d9")])
	_add("power_bank", "Power bank", false, [
		_r(-28, -16, 56, 32, "plastic", "2b2b2b"),
		_r(-24, -12, 22, 24, "metal", "596069"), _r(2, -12, 22, 24, "metal", "596069"),
		_l([28, 0, 40, -14, 30, -30, 10, -28], 3, "metal", "eeeeee")])
	_add("laptop", "Laptop", false, [
		_r(-80, -52, 160, 104, "plastic", "aeb6bf"),
		_r(-62, -42, 70, 40, "metal", "2f7a46"),
		_r(-70, 14, 140, 28, "metal", "50565e"),
		_r(20, -38, 46, 22, "plastic", "8f98a2")])
	_add("phone", "Phone", false, [
		_r(-14, -28, 28, 56, "plastic", "1b1d22"), _r(-10, -16, 20, 30, "metal", "3c4a63")])
	_add("shoe", "Shoe", false, [
		_p([-40, 8, -40, -6, -20, -10, 0, -26, 18, -26, 22, -10, 40, 0, 40, 8], "organic", "8b5a2b"),
		_r(-42, 8, 84, 7, "organic", "3b2a1c")])
	_add("book", "Book", false, [
		_r(-36, -48, 72, 96, "organic", "2f4f8f"), _r(-30, -44, 60, 88, "organic", "f1ead8")])
	var band: Array = []
	for i in 13:
		var a := PI + PI * i / 12.0
		band.append_array([cos(a) * 30, sin(a) * 26])
	_add("headphones", "Headphones", false, [
		_l(band, 4, "plastic", "222222"), _c(-30, 6, 12, "plastic", "222222"), _c(30, 6, 12, "plastic", "222222"),
		_c(-30, 6, 5, "metal", "777777"), _c(30, 6, 5, "metal", "777777")])
	_add("keys", "Keys", false, [
		_o(0, -14, 9, 3, "metal", "b0b6bc"),
		_c(-7, 0, 6, "metal", "d4b04a"), _r(-9, 0, 5, 26, "metal", "d4b04a"),
		_c(8, -1, 6, "metal", "b0b6bc"), _r(6, -1, 5, 24, "metal", "b0b6bc")])
	_add("umbrella", "Umbrella", false, [
		_r(-78, -2, 148, 4, "metal", "777f88"),
		_p([-58, -9, 50, -5, 62, 0, 50, 5, -58, 9], "plastic", "24365e"),
		_l([-78, 0, -86, 2, -90, 10, -84, 16], 4, "plastic", "3a2a1c")])
	_add("toothbrush", "Toothbrush", false, [
		_r(-38, -3, 62, 6, "plastic", "4fb0e8"), _r(24, -5, 12, 10, "plastic", "f5f5f5")])
	_add("clothes", "Clothes", false, [
		_r(-62, -38, 124, 76, "fabric", "6a8caf"), _r(-56, -30, 112, 22, "fabric", "86a6c8"),
		_c(-30, 10, 3, "plastic", "eeeeee"), _c(-30, 24, 3, "plastic", "eeeeee")])
	_add("camera", "Camera", false, [
		_r(-30, -18, 60, 36, "plastic", "26282c"), _o(6, 0, 12, 5, "metal", "4b4f56"),
		_r(-26, -12, 10, 24, "metal", "4b4f56")])
	_add("glasses", "Glasses", false, [
		_o(-14, 0, 10, 3, "plastic", "3a2a1c"), _o(14, 0, 10, 3, "plastic", "3a2a1c"),
		_l([-4, -2, 4, -2], 2, "metal", "999999"), _l([-24, -2, -34, -6], 2, "metal", "999999"),
		_l([24, -2, 34, -6], 2, "metal", "999999")])
	_add("watch", "Watch", false, [
		_r(-6, -26, 12, 52, "organic", "5a3a1c"), _c(0, 0, 11, "metal", "c9d1d9"), _c(0, 0, 7, "plastic", "f5f5f5")])


# ------------------------------------------------------------------ dates & generation

func _valid_date(d: String) -> bool:
	if RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(d) == null:
		return false
	var t := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return Time.get_date_string_from_unix_time(t) == d


func day_number(d: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(EPOCH + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return int(round((b - a) / 86400.0)) + 1


func seed_for(d: String) -> int:
	return hash("%s-%s" % [GAME, d])


func _rng_for(d: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(d)
	return rng


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func generate(d: String) -> Array:
	var rng := _rng_for(d)
	var out: Array = []
	for attempt in 40:
		out = _try_bags(rng)
		if bags_valid(out):
			return out
	return out


func _try_bags(rng: RandomNumberGenerator) -> Array:
	var order: Array = range(BAGS)
	_shuffle(order, rng)
	var n_bad := rng.randi_range(4, 6)
	var bad_set := order.slice(0, n_bad)
	var deck: Array = []
	for k in 3:
		var part: Array = BAD_IDS.duplicate()
		_shuffle(part, rng)
		deck.append_array(part)
	var out: Array = []
	for i in BAGS:
		var contraband: Array = []
		if i in bad_set:
			var want := 2 if rng.randf() < 0.25 else 1
			while contraband.size() < want:
				var id: String = deck.pop_front()
				if id in contraband:
					deck.append(id)
				else:
					contraband.append(id)
		var smalls: Array = []
		if rng.randf() < 0.6:
			smalls.append(LOOKALIKE[BAD_IDS[rng.randi_range(0, BAD_IDS.size() - 1)]])
		var n_small := rng.randi_range(3, 5)
		while smalls.size() < n_small:
			var s: String = SMALL_OK[rng.randi_range(0, SMALL_OK.size() - 1)]
			if not s in smalls:
				smalls.append(s)
		var ids: Array = []
		if rng.randf() < 0.75:
			ids.append(BIG_IDS[rng.randi_range(0, BIG_IDS.size() - 1)])
		var rest: Array = smalls + contraband
		_shuffle(rest, rng)
		ids.append_array(rest)
		var items := _place(ids, rng)
		var bad: Array = []
		for k in items.size():
			if CAT[items[k].id].bad:
				bad.append(k)
		out.append({"items": items, "bad": bad})
	return out


func _extent(half: Vector2, rot: float) -> Vector2:
	var c := absf(cos(rot))
	var s := absf(sin(rot))
	return Vector2(c * half.x + s * half.y, s * half.x + c * half.y)


func _place(ids: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for id in ids:
		var half: Vector2 = CAT[id].half
		var big := String(id) in BIG_IDS
		var best_pos := Vector2.ZERO
		var best_rot := 0.0
		var best_score := INF
		for k in (2 if big else 14):
			var rot := rng.randf_range(-0.25, 0.25) if big else rng.randf_range(-PI, PI)
			var ex := _extent(half, rot)
			if ex.x > INNER.x or ex.y > INNER.y:
				rot = rng.randf_range(-0.15, 0.15)
				ex = _extent(half, rot)
			var pos := Vector2(rng.randf_range(-INNER.x + ex.x, INNER.x - ex.x),
				rng.randf_range(-INNER.y + ex.y, INNER.y - ex.y))
			var score := 0.0
			var ra := (half.x + half.y) * 0.45
			for q in out:
				var qh: Vector2 = CAT[q.id].half
				var w := 0.15 if String(q.id) in BIG_IDS else 1.0
				if CAT[id].bad and CAT[q.id].bad:
					w = 4.0
				elif CAT[id].bad or CAT[q.id].bad:
					w = 1.6
				score += maxf(0.0, ra + (qh.x + qh.y) * 0.45 - pos.distance_to(q.pos)) * w
			if score < best_score:
				best_score = score
				best_pos = pos
				best_rot = rot
		out.append({"id": id, "pos": best_pos, "rot": best_rot})
	return out


## Every day must be fair: enough contraband to find, some clean bags, no contraband stacked on contraband.
func bags_valid(bs: Array) -> bool:
	if bs.size() != BAGS:
		return false
	var total := 0
	var clean := 0
	for b in bs:
		var bad: Array = b.bad
		total += bad.size()
		if bad.is_empty():
			clean += 1
		for i in bad.size():
			var a: Dictionary = b.items[bad[i]]
			var ex := _extent(CAT[a.id].half, a.rot)
			if absf(a.pos.x) + ex.x > INNER.x + 0.5 or absf(a.pos.y) + ex.y > INNER.y + 0.5:
				return false
			for j in range(i + 1, bad.size()):
				if a.pos.distance_to(b.items[bad[j]].pos) < 40.0:
					return false
	return total >= 5 and clean >= 3


func load_day(d: String) -> void:
	date = d
	puzzle_no = day_number(d)
	bags = generate(d)
	results = []
	elapsed = 0.0
	_load_state()
	bag_i = 0
	for r in results:
		if r.done:
			bag_i += 1
	screen = Screen.END if finished() else Screen.MENU
	phase = Phase.ENTER
	phase_t = 0.0
	close_hold = -1.0
	missed_flash = []
	popups = []
	legend_open = false


# ------------------------------------------------------------------ rules

func finished() -> bool:
	if results.size() < BAGS:
		return false
	for r in results:
		if not r.done:
			return false
	return true


func bag_points(i: int) -> int:
	if i >= results.size():
		return 0
	var r: Dictionary = results[i]
	if not r.flag:
		return 0
	var p: int = r.found.size() * FIND_PTS + r.wrong.size() * WRONG_PTS
	if r.done and bags[i].bad.is_empty():
		p += FALSE_ALARM_PTS
	return p


func base_score() -> int:
	var s := 0
	for i in results.size():
		s += bag_points(i)
	return s


func time_bonus() -> int:
	if not finished():
		return 0
	return maxi(0, int(ceil(TIME_PAR - elapsed))) * TIME_PTS


func total_score() -> int:
	return base_score() + time_bonus()


func contraband_total() -> int:
	var n := 0
	for b in bags:
		n += b.bad.size()
	return n


func found_total() -> int:
	var n := 0
	for r in results:
		n += r.found.size()
	return n


func false_alarms() -> int:
	var n := 0
	for i in results.size():
		if results[i].flag and results[i].done and bags[i].bad.is_empty():
			n += 1
	return n


func wrong_total() -> int:
	var n := 0
	for r in results:
		n += r.wrong.size()
	return n


## 0 = perfect bag, 1 = partly right, 2 = mistake (missed bag or false alarm), -1 = not played yet.
func bag_mark(i: int) -> int:
	if i >= results.size() or not results[i].done:
		return -1
	var r: Dictionary = results[i]
	var bad: Array = bags[i].bad
	if bad.is_empty():
		return 2 if r.flag else 0
	if not r.flag:
		return 2
	return 0 if r.found.size() == bad.size() and r.wrong.is_empty() else 1


func start_shift() -> void:
	if finished():
		screen = Screen.END
		return
	screen = Screen.PLAY
	legend_open = false
	popups = []
	missed_flash = []
	close_hold = -1.0
	if bag_i < results.size() and results[bag_i].flag and not results[bag_i].done:
		phase = Phase.OPEN
		phase_t = 1.0
	else:
		phase = Phase.ENTER
		phase_t = 0.0


func flag_bag() -> void:
	if screen != Screen.PLAY or phase != Phase.SCAN:
		return
	results.append({"flag": true, "found": [], "wrong": [], "done": false})
	_save_state()
	_set_phase(Phase.OPENING)


func clear_bag() -> void:
	if screen != Screen.PLAY or phase != Phase.SCAN:
		return
	results.append({"flag": false, "found": [], "wrong": [], "done": true})
	var bad: Array = bags[bag_i].bad
	var c := _bag_center()
	if bad.is_empty():
		_popup("Clean", c + Vector2(0, -20), C_GREEN, 26)
	else:
		missed_flash = bad.duplicate()
		var names: Array = []
		for k in bad:
			names.append(CAT[bags[bag_i].items[k].id].name)
		_popup("Missed: " + ", ".join(names), c + Vector2(0, -20), C_RED, 22)
		shake = 0.35
	_save_state()
	_set_phase(Phase.EXIT)


func tap_item(i: int) -> void:
	if screen != Screen.PLAY or phase != Phase.OPEN or close_hold >= 0.0:
		return
	var b: Dictionary = bags[bag_i]
	if i < 0 or i >= b.items.size():
		return
	var r: Dictionary = results[bag_i]
	if i in r.found or i in r.wrong:
		return
	var at := _cell_center(i)
	if i in b.bad:
		r.found.append(i)
		_popup("+%d" % FIND_PTS, at, C_GREEN, 26)
		if r.found.size() == b.bad.size():
			r.done = true
			close_hold = 0.8
			_popup("Bag cleared!", mon.get_center() + Vector2(0, mon.size.y * 0.32), C_GREEN, 28)
	else:
		r.wrong.append(i)
		_popup("%d" % WRONG_PTS, at, C_RED, 24)
		shake = 0.3
	_save_state()


func done_bag() -> void:
	if screen != Screen.PLAY or phase != Phase.OPEN or close_hold >= 0.0:
		return
	var b: Dictionary = bags[bag_i]
	var r: Dictionary = results[bag_i]
	r.done = true
	var missing: Array = []
	for k in b.bad:
		if not k in r.found:
			missing.append(k)
	close_hold = 0.25
	if b.bad.is_empty():
		_popup("False alarm  %d" % FALSE_ALARM_PTS, mon.get_center(), C_RED, 30)
		shake = 0.45
		close_hold = 1.0
	elif not missing.is_empty():
		missed_flash = missing
		for k in missing:
			_popup("Missed!", _cell_center(k), C_RED, 22)
		shake = 0.3
		close_hold = 1.1
	_save_state()


func _set_phase(p: Phase) -> void:
	phase = p
	phase_t = 0.0


func _advance(delta: float) -> void:
	if screen != Screen.PLAY:
		return
	elapsed += delta
	if close_hold >= 0.0:
		close_hold -= delta * anim_speed
		if close_hold < 0.0:
			close_hold = -1.0
			missed_flash = []
			_set_phase(Phase.CLOSING)
		return
	if not DUR.has(phase):
		return
	var was_moving := phase == Phase.ENTER or phase == Phase.EXIT
	phase_t = minf(1.0, phase_t + delta * anim_speed / float(DUR[phase]))
	if was_moving:
		belt_off += delta * anim_speed * 260.0
	if phase_t < 1.0:
		return
	match phase:
		Phase.ENTER:
			_set_phase(Phase.SCAN)
		Phase.OPENING:
			_set_phase(Phase.OPEN)
		Phase.CLOSING:
			_set_phase(Phase.EXIT)
		Phase.EXIT:
			missed_flash = []
			bag_i += 1
			if bag_i >= BAGS:
				_finish()
			else:
				_set_phase(Phase.ENTER)


func _finish() -> void:
	screen = Screen.END
	_save_state()
	if OS.has_feature("web") and not dev_mode:
		var key := "gametests:%s:%s" % [GAME, date]
		var val := JSON.stringify({"result": "%s pts" % _num(total_score())})
		JavaScriptBridge.eval("try{localStorage.setItem(%s,%s)}catch(e){}" % [JSON.stringify(key), JSON.stringify(val)], true)


# ------------------------------------------------------------------ saving

func _save_path() -> String:
	return "user://%sxray_%s.json" % ["dev_" if dev_mode else "", date]


func _save_state() -> void:
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"results": results, "elapsed": elapsed}))
		f.close()
	_flush_storage()


func _load_state() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if not data is Dictionary:
		return
	elapsed = float(data.get("elapsed", 0.0))
	for r in data.get("results", []):
		if not r is Dictionary or results.size() >= BAGS:
			continue
		var n: int = bags[results.size()].items.size()
		var found: Array = []
		var wrong: Array = []
		for k in r.get("found", []):
			if int(k) >= 0 and int(k) < n:
				found.append(int(k))
		for k in r.get("wrong", []):
			if int(k) >= 0 and int(k) < n:
				wrong.append(int(k))
		results.append({"flag": bool(r.get("flag", false)), "found": found, "wrong": wrong, "done": bool(r.get("done", false))})
	# only the last record may be unfinished
	for i in range(results.size() - 1):
		results[i].done = true


func wipe_save() -> void:
	if FileAccess.file_exists(_save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))
	_flush_storage()


func _flush_storage() -> void:
	var f := FileAccess.open("user://.sync", FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


# ------------------------------------------------------------------ sharing

func share_link() -> String:
	return "%s?day=%s" % [base_url, date]


func _num(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]


func share_text() -> String:
	var marks := ""
	for i in BAGS:
		marks += ["⬜", "🟩", "🟨", "🟥"][bag_mark(i) + 1]
	var lines := PackedStringArray()
	lines.append("X-Ray Shift #%d · %s" % [puzzle_no, date])
	lines.append(marks)
	lines.append("%s pts · %d/%d contraband · ⏱ %s" % [_num(total_score()), found_total(), contraband_total(), clock(elapsed)])
	lines.append(share_link())
	return "\n".join(lines)


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__xrShare='pending';
			var done=function(r){if(window.__xrShare==='pending'){window.__xrShare=r;}};
			var ask=function(){try{window.prompt('Copy your result:',t);done('prompted');}catch(e){done('failed');}};
			var legacy=function(){
				var ok=false;
				try{
					var ta=document.createElement('textarea');
					ta.value=t;ta.setAttribute('readonly','');
					ta.style.cssText='position:fixed;top:0;left:0;opacity:0;';
					document.body.appendChild(ta);ta.select();
					ok=document.execCommand('copy');
					document.body.removeChild(ta);
					var c=document.querySelector('canvas');if(c){c.focus();}
				}catch(e){ok=false;}
				return ok;
			};
			var copy=function(){
				if(navigator.clipboard&&navigator.clipboard.writeText){
					setTimeout(function(){if(window.__xrShare==='pending'){if(legacy()){done('copied');}else{ask();}}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},function(){if(legacy()){done('copied');}else{ask();}});
				}else if(legacy()){done('copied');}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__xrCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__xrCopyNext=true;done('share_failed');}
				});
			}else{window.__xrCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied!")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__xrShare||''", true)
	if typeof(r) != TYPE_STRING or r == "pending" or r == "":
		return
	share_pending = false
	match r:
		"copied": _toast("Copied! Paste it anywhere")
		"shared": _toast("Shared!")
		"prompted", "cancelled": pass
		"share_failed": _toast("Couldn't share, tap again to copy")
		_: _toast("Couldn't share, try again")


func _read_url() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var r = JavaScriptBridge.eval("""(function(){var p=new URLSearchParams(location.search);
		return JSON.stringify({day:p.get('day')||p.get('d')||'',dev:p.get('dev')||'',base:location.origin+location.pathname});})()""", true)
	if typeof(r) != TYPE_STRING:
		return {}
	var d = JSON.parse_string(r)
	return d if d is Dictionary else {}


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 2.2


func _popup(text: String, pos: Vector2, c: Color, size := 22) -> void:
	popups.append({"text": text, "pos": pos, "color": c, "t": 0.0, "size": size})


# ------------------------------------------------------------------ dev mode

func _date_add(d: String, days: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00") + days * 86400)


func dev_set_day(d: String) -> void:
	if not dev_mode or not _valid_date(d):
		return
	load_day(d)


func dev_shift(days: int) -> void:
	dev_set_day(_date_add(date, days))


func dev_random_day() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	dev_set_day(_date_add(EPOCH, rng.randi_range(-2000, 2000)))


func dev_reset() -> void:
	if not dev_mode:
		return
	wipe_save()
	load_day(date)


## Play every remaining bag perfectly (dev only) and jump to the end screen.
func dev_win() -> void:
	_dev_finish(true)


## Get every remaining bag wrong (dev only) and jump to the end screen.
func dev_lose() -> void:
	_dev_finish(false)


func _dev_finish(win: bool) -> void:
	if not dev_mode:
		return
	if results.size() > 0 and not results[-1].done:
		results.pop_back()
	while results.size() < BAGS:
		var b: Dictionary = bags[results.size()]
		var clean: bool = b.bad.is_empty()
		if win:
			results.append({"flag": not clean, "found": b.bad.duplicate(), "wrong": [], "done": true})
		else:
			results.append({"flag": clean, "found": [], "wrong": [], "done": true})
	elapsed = 60.0 if win else 240.0
	bag_i = BAGS
	dev_open = false
	_finish()


func _dev_tap() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	title_taps.append(now)
	while title_taps.size() > 0 and now - float(title_taps[0]) > 3.0:
		title_taps.pop_front()
	if title_taps.size() >= 5:
		title_taps.clear()
		if not dev_mode:
			enable_dev()
		else:
			dev_open = not dev_open


## Turn dev mode on mid-session (5 quick taps on the title). Dev progress is kept apart from real progress.
func enable_dev() -> void:
	if dev_mode:
		return
	dev_mode = true
	load_day(date)
	dev_open = true
	_toast("Dev mode on")


func get_agent_state() -> Dictionary:
	var state := "menu"
	if screen == Screen.PLAY:
		state = "playing"
	elif screen == Screen.END:
		state = "done"
	var answers: Array = []
	for b in bags:
		var names: Array = []
		for k in b.bad:
			names.append("%d:%s" % [k, b.items[k].id])
		answers.append(names)
	var cur_items: Array = []
	var cur_bad: Array = []
	if bag_i < bags.size():
		for it in bags[bag_i].items:
			cur_items.append(it.id)
		cur_bad = bags[bag_i].bad
	return {"day": date, "puzzle": puzzle_no, "seed": seed_for(date), "screen": Screen.keys()[screen],
		"state": state, "phase": Phase.keys()[phase], "bag": bag_i, "bags": BAGS, "score": base_score(),
		"total": total_score(), "time_bonus": time_bonus(), "elapsed": snappedf(elapsed, 0.01),
		"found": found_total(), "contraband": contraband_total(), "false_alarms": false_alarms(),
		"wrong": wrong_total(), "legend_open": legend_open, "dev_mode": dev_mode, "dev_open": dev_open,
		"current_items": cur_items, "current_bad": cur_bad, "answers": answers, "share_text": share_text()}


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	_advance(delta)
	shake = maxf(0.0, shake - delta)
	if toast_t > 0.0:
		toast_t -= delta
	for p in popups:
		p.t += delta
	popups = popups.filter(func(p): return p.t < 1.1)
	if share_pending:
		_poll_share()
	if press_t >= 0.0 and title_rect.has_point(press_pos) and Time.get_ticks_msec() / 1000.0 - press_t > 0.7:
		press_t = -1.0
		if dev_mode:
			dev_open = not dev_open
	_layout()
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouse or not ev.is_pressed() or ev.is_echo():
		return
	var key := ev as InputEventKey
	if ev.is_action_pressed("dev_toggle") and dev_mode:
		dev_open = not dev_open
	elif ev.is_action_pressed("back"):
		if dev_open:
			dev_open = false
		elif legend_open:
			legend_open = false
	elif ev.is_action_pressed("legend"):
		legend_open = not legend_open
	elif screen == Screen.MENU and ev.is_action_pressed("confirm"):
		start_shift()
	elif screen == Screen.PLAY:
		if phase == Phase.SCAN:
			if ev.is_action_pressed("flag"):
				flag_bag()
			elif ev.is_action_pressed("confirm"):
				clear_bag()
		elif phase == Phase.OPEN:
			if ev.is_action_pressed("confirm"):
				done_bag()
			elif key != null and key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
				tap_item(key.physical_keycode - KEY_1)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_on_press(make_input_local(ev).position)
		else:
			press_t = -1.0


func _on_press(p: Vector2) -> void:
	press_pos = p
	press_t = Time.get_ticks_msec() / 1000.0
	if title_rect.has_point(p):
		_dev_tap()
	for b in buttons:
		if b.rect.has_point(p):
			_do(String(b.id))
			return
	if dev_open:
		return
	if legend_open:
		legend_open = false
		return
	if legend_rect.has_point(p):
		legend_open = true
		return
	if screen == Screen.PLAY and phase == Phase.OPEN:
		for i in open_cells.size():
			if open_cells[i].has_point(p):
				tap_item(i)
				return


func _do(id: String) -> void:
	match id:
		"start": start_shift()
		"flag": flag_bag()
		"clear": clear_bag()
		"done": done_bag()
		"share": share()
		"legend_close": legend_open = false
		"dev_prev": dev_shift(-1)
		"dev_next": dev_shift(1)
		"dev_m30": dev_shift(-30)
		"dev_p30": dev_shift(30)
		"dev_today": dev_set_day(today)
		"dev_rand": dev_random_day()
		"dev_reset": dev_reset()
		"dev_reveal": dev_reveal = not dev_reveal
		"dev_win": dev_win()
		"dev_lose": dev_lose()
		"dev_close": dev_open = false


func _btn(id: String, r: Rect2, label: String, style := "") -> void:
	buttons.append({"id": id, "rect": r, "label": label, "style": style})


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 24.0, 560.0)
	col = Rect2((vs.x - w) * 0.5, 0, w, vs.y)
	title_rect = Rect2(col.position.x, 0, 220, 56)
	legend_rect = Rect2(col.position.x, 60, col.size.x, 74)
	ctrl = Rect2(col.position.x, vs.y - 92, col.size.x, 76)
	var top := legend_rect.end.y + 10
	mon = Rect2(col.position.x, top, col.size.x, maxf(220.0, ctrl.position.y - top - 52))
	mon.size.y = minf(mon.size.y, col.size.x * 1.1)
	buttons.clear()
	open_cells.clear()
	if dev_open:
		_layout_dev()
		return
	if legend_open:
		_btn("legend_close", Rect2(col.end.x - 44, legend_rect.position.y + 6, 38, 38), "X", "ghost")
		return
	match screen:
		Screen.MENU:
			mon.size.y = minf(mon.size.y, 250.0)
			_btn("start", ctrl, "Resume shift" if results.size() > 0 else "Start shift", "primary")
		Screen.PLAY:
			_layout_play()
		Screen.END:
			_btn("share", ctrl, "Share result", "primary")


func _layout_play() -> void:
	var hw := (ctrl.size.x - 12) * 0.5
	if phase == Phase.SCAN or phase == Phase.ENTER or phase == Phase.EXIT:
		if phase == Phase.SCAN:
			_btn("clear", Rect2(ctrl.position.x, ctrl.position.y, hw, ctrl.size.y), "CLEAR", "clear")
			_btn("flag", Rect2(ctrl.position.x + hw + 12, ctrl.position.y, hw, ctrl.size.y), "FLAG", "flag")
	elif phase == Phase.OPEN and close_hold < 0.0:
		_btn("done", ctrl, "Done - close bag", "ghost_big")
	if phase in [Phase.OPENING, Phase.OPEN, Phase.CLOSING]:
		var n: int = bags[bag_i].items.size()
		for i in n:
			open_cells.append(_cell_rect(i, n))


func _scan_scale() -> float:
	return clampf(minf((mon.size.x - 16.0) / (BAG_HALF.x * 2.0 + 16.0), (mon.size.y - 60.0) / (BAG_HALF.y * 2.0 + 30.0)), 0.45, 1.7)


func _bag_center() -> Vector2:
	return mon.get_center() + Vector2(0, -8)


func _cell_rect(i: int, n: int) -> Rect2:
	var cols := 3
	var rows := int(ceil(n / float(cols)))
	var area := mon.grow(-14)
	area.position.y += 18
	area.size.y -= 18
	var cw := area.size.x / cols
	var ch := minf(area.size.y / rows, cw * 1.05)
	var oy := (area.size.y - ch * rows) * 0.5
	var row := i / cols
	var in_row := mini(cols, n - row * cols)
	var ox := (area.size.x - cw * in_row) * 0.5
	return Rect2(area.position.x + ox + (i % cols) * cw, area.position.y + oy + row * ch, cw, ch).grow(-4)


func _cell_center(i: int) -> Vector2:
	if i < open_cells.size():
		return open_cells[i].get_center()
	return mon.get_center()


func _layout_dev() -> void:
	var x := col.position.x + 12
	var w := (col.size.x - 24 - 16) / 3.0
	var y := 236.0
	var rows := [
		[["dev_m30", "-30 d"], ["dev_prev", "< Day"], ["dev_next", "Day >"]],
		[["dev_p30", "+30 d"], ["dev_today", "Today"], ["dev_rand", "Random"]],
		[["dev_reset", "Reset day"], ["dev_reveal", "Hide answers" if dev_reveal else "Reveal"], ["dev_close", "Close"]],
		[["dev_win", "Instant win"], ["dev_lose", "Instant lose"]],
	]
	for row in rows:
		for k in row.size():
			_btn(row[k][0], Rect2(x + k * (w + 8), y, w, 44), row[k][1], "dev")
		y += 52


# ------------------------------------------------------------------ drawing

func _text(pos: Vector2, s: String, size: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, size, c)


func _center_text(cx: float, y: float, s: String, size: int, c: Color) -> void:
	draw_string(font, Vector2(cx - 400, y), s, HORIZONTAL_ALIGNMENT_CENTER, 800, size, c)


func _round_rect(r: Rect2, c: Color, radius := 10.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, r)


func _draw_item(id: String, pos: Vector2, rot: float, sc: float, real := 0.0, alpha := 1.0) -> void:
	draw_set_transform(pos, rot, Vector2(sc, sc))
	for part in CAT[id].parts:
		var c: Color = XR[part.m].lerp(part.c, real)
		c.a *= alpha
		match String(part.t):
			"poly": draw_colored_polygon(part.p, c)
			"circle": draw_circle(part.o, part.r, c)
			"line": draw_polyline(part.p, c, part.w)
			"ring": draw_arc(part.o, part.r, 0, TAU, 28, c, part.w)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _icon_scale(id: String, r: Rect2) -> float:
	var h: Vector2 = CAT[id].half
	return maxf(minf(r.size.x / (h.x * 2.0), r.size.y / (h.y * 2.0)), minf(r.size.x / (h.y * 2.0), r.size.y / (h.x * 2.0)))


func _draw_icon(id: String, r: Rect2, real := 0.0, max_sc := INF) -> void:
	var h: Vector2 = CAT[id].half
	var rot := 0.0
	var sc := minf(r.size.x / (h.x * 2.0), r.size.y / (h.y * 2.0))
	var sc_rot := minf(r.size.x / (h.y * 2.0), r.size.y / (h.x * 2.0))
	if sc_rot > sc * 1.2:
		rot = -PI * 0.5
		sc = sc_rot
	_draw_item(id, r.get_center(), rot, minf(sc, max_sc), real)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), C_BG)
	_draw_header()
	match screen:
		Screen.MENU: _draw_menu()
		Screen.PLAY: _draw_play()
		Screen.END: _draw_end()
	_draw_legend_strip()
	for b in buttons:
		if not String(b.style) in ["dev"] and not String(b.id) == "legend_close":
			_draw_button(b)
	if legend_open:
		_draw_legend_panel()
	for p in popups:
		var k: float = p.t / 1.1
		var c: Color = p.color
		c.a = 1.0 - k * k
		var pos: Vector2 = p.pos + Vector2(0, -40.0 * k)
		var sz: int = p.size
		draw_string_outline(font, Vector2(pos.x - 300, pos.y), p.text, HORIZONTAL_ALIGNMENT_CENTER, 600, sz, 6, Color(0, 0, 0, c.a * 0.8))
		_center_text(pos.x, pos.y, p.text, sz, c)
	if dev_open:
		_draw_dev()
	if toast_t > 0.0:
		var a := clampf(toast_t * 3.0, 0.0, 1.0)
		var tw := font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 32
		var r := Rect2(col.get_center().x - tw * 0.5, ctrl.position.y - 52, tw, 38)
		_round_rect(r, Color(C_PANEL_HI, a), 19)
		_center_text(r.get_center().x, r.position.y + 25, toast, 16, Color(C_INK, a))


func _draw_header() -> void:
	var x := col.position.x
	_text(Vector2(x, 32), "X-RAY SHIFT", 24, C_ACCENT)
	_text(Vector2(x, 50), "Shift #%d  ·  %s%s" % [puzzle_no, date, "  ·  DEV" if dev_mode else ""], 12, C_MUTED)
	if screen == Screen.PLAY:
		var shown := base_score()
		_text(Vector2(col.end.x - 200, 30), _num(shown), 24, C_INK, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		_text(Vector2(col.end.x - 200, 50), "%s   bag %d/%d" % [clock(elapsed), mini(bag_i + 1, BAGS), BAGS], 13, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 200)


func _draw_legend_strip() -> void:
	var r := legend_rect
	_round_rect(r, Color("2a1d22"), 10)
	draw_rect(r.grow(-1), Color(C_RED, 0.35), false, 1.0)
	_text(Vector2(r.position.x + 10, r.position.y + 15), "CONTRABAND - flag bags with any of these", 11, Color("ff9aa2"))
	_text(Vector2(r.end.x - 70, r.position.y + 15), "tap: details", 10, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 60)
	var cw := (r.size.x - 8) / BAD_IDS.size()
	for i in BAD_IDS.size():
		var cell := Rect2(r.position.x + 4 + i * cw, r.position.y + 19, cw, 54)
		_round_rect(Rect2(cell.position.x + 3, cell.position.y + 1, cell.size.x - 6, 34), C_SCREEN, 6)
		_draw_icon(BAD_IDS[i], Rect2(cell.position.x + 7, cell.position.y + 4, cell.size.x - 14, 28))
		_center_text(cell.get_center().x, cell.position.y + 49, CAT[BAD_IDS[i]].name, 10, C_INK)


func _draw_legend_panel() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	var top := legend_rect.position.y
	var p := Rect2(col.position.x, top, col.size.x, minf(vs.y - top - 12, 620))
	_round_rect(p, C_PANEL, 12)
	_text(Vector2(p.position.x + 14, top + 30), "What to flag", 20, C_ACCENT)
	_draw_button({"id": "legend_close", "rect": Rect2(col.end.x - 44, top + 6, 38, 38), "label": "X", "style": "ghost"})
	var y := top + 48
	_text(Vector2(p.position.x + 14, y + 6), "X-ray colours:", 12, C_MUTED)
	var kx := p.position.x + 108
	for pair in [["metal", "metal"], ["organic", "organic"], ["plastic", "plastic"]]:
		var c: Color = XR[pair[0]]
		c.a = 1.0
		draw_rect(Rect2(kx, y - 4, 12, 12), c)
		_text(Vector2(kx + 16, y + 6), pair[1], 12, C_INK)
		kx += 76
	y += 18
	var rh := (p.end.y - y - 10) / BAD_IDS.size()
	rh = minf(rh, 84)
	for id in BAD_IDS:
		var row := Rect2(p.position.x + 10, y, p.size.x - 20, rh - 6)
		_round_rect(row, C_PANEL_HI, 8)
		var ic := Rect2(row.position.x + 6, row.position.y + 6, 62, row.size.y - 12)
		_round_rect(ic, C_SCREEN, 6)
		var ok: String = LOOKALIKE[id]
		var ic2 := Rect2(row.end.x - 54, row.position.y + 6, 48, row.size.y - 12)
		var shared := minf(_icon_scale(id, ic.grow(-4)), _icon_scale(ok, ic2.grow(-4)))
		_draw_icon(id, ic.grow(-4), 0.0, shared)
		_round_rect(ic2, Color(C_SCREEN, 0.75), 6)
		_draw_icon(ok, ic2.grow(-4), 0.0, shared)
		var tx := ic.end.x + 10
		var tw := ic2.position.x - tx - 8
		_text(Vector2(tx, row.position.y + 22), CAT[id].name, 16, Color("ff8f98"))
		draw_multiline_string(font, Vector2(tx, row.position.y + 38), LEGEND_NOTE[id], HORIZONTAL_ALIGNMENT_LEFT, tw, 11, 2, C_INK)
		_text(Vector2(tx, row.end.y - 8), "OK: " + CAT[ok].name, 11, C_GREEN, HORIZONTAL_ALIGNMENT_LEFT, tw)
		y += rh


func _draw_monitor_frame(label: String) -> void:
	# cover anything that slid past the monitor edges, then frame it
	var vs := get_viewport_rect().size
	draw_rect(Rect2(0, mon.position.y - 2, mon.position.x, mon.size.y + 4), C_BG)
	draw_rect(Rect2(mon.end.x, mon.position.y - 2, vs.x - mon.end.x, mon.size.y + 4), C_BG)
	draw_rect(mon.grow(2), Color("3a4656"), false, 4.0)
	if label != "":
		_text(mon.position + Vector2(8, 15), label, 11, Color(0.2, 0.25, 0.3, 0.8))


func _draw_bag_shell(c: Vector2, s: float, real: float) -> void:
	var r := Rect2(c - BAG_HALF * s, BAG_HALF * 2.0 * s)
	var fill: Color = XR.fabric.lerp(C_BAGIN, real)
	_round_rect(r, fill, 14 * s)
	var frame: Color = XR.metal.lerp(Color("44516a"), real)
	frame.a *= 0.55
	draw_rect(r.grow(-6 * s), frame, false, 2.0 * s)
	var hc: Color = XR.plastic.lerp(Color("111827"), real)
	draw_rect(Rect2(c.x - 34 * s, r.position.y - 14 * s, 68 * s, 12 * s), hc)
	for k in 22:
		var zx := r.position.x + 16 * s + k * (r.size.x - 32 * s) / 21.0
		draw_rect(Rect2(zx - 1.5 * s, r.position.y + 2 * s, 3 * s, 3 * s), Color(XR.metal, 0.6 * (1.0 - real)))


func _draw_scan_items(bag: Dictionary, c: Vector2, s: float, alpha := 1.0) -> void:
	for it in bag.items:
		_draw_item(it.id, c + it.pos * s, it.rot, s, 0.0, alpha)


func _ring(at: Vector2, rad: float, col_: Color, w := 3.0) -> void:
	draw_arc(at, rad, 0, TAU, 40, col_, w)


func _draw_menu() -> void:
	draw_rect(mon, C_SCREEN)
	var s := _scan_scale() * 0.9
	var c := mon.get_center() + Vector2(0, 4)
	_draw_bag_shell(c, s, 0.0)
	_draw_scan_items(demo_bag, c, s)
	var kn: Dictionary = demo_bag.items[2]
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0)
	_ring(c + kn.pos * s, 40 * s, Color(C_RED, pulse), 3)
	_text(mon.position + Vector2(8, 15), "TRAINING IMAGE", 11, Color(0.2, 0.25, 0.3, 0.8))
	_draw_monitor_frame("")
	var y := mon.end.y + 30
	var cx := col.get_center().x
	_center_text(cx, y, "Clear the clean bags. Flag the ones with contraband,", 15, C_INK)
	_center_text(cx, y + 20, "then tap every illegal item inside.", 15, C_INK)
	y += 52
	var lines := [["+%d" % FIND_PTS, "each contraband item you find", C_GREEN],
		["%d" % FALSE_ALARM_PTS, "flagging a clean bag", C_RED],
		["%d" % WRONG_PTS, "tapping a harmless item", C_RED],
		["+%d/s" % TIME_PTS, "time bonus under %s" % clock(TIME_PAR), C_ACCENT]]
	for l in lines:
		if y > ctrl.position.y - 12:
			break
		_text(Vector2(cx - 150, y), l[0], 15, l[2], HORIZONTAL_ALIGNMENT_RIGHT, 60)
		_text(Vector2(cx - 80, y), l[1], 14, C_MUTED)
		y += 21
	if y < ctrl.position.y - 16:
		_center_text(cx, y + 8, "%d bags · Keys: Space clear, F flag, 1-9 pick, L legend" % BAGS, 11, Color(C_MUTED, 0.8))


func _draw_play() -> void:
	var bag: Dictionary = bags[mini(bag_i, BAGS - 1)]
	var s := _scan_scale()
	var c := _bag_center()
	var opened := 0.0
	if phase == Phase.OPENING:
		opened = phase_t
	elif phase == Phase.OPEN:
		opened = 1.0
	elif phase == Phase.CLOSING:
		opened = 1.0 - phase_t
	var e_open := smoothstep(0.0, 1.0, opened)
	var sx := 0.0
	if phase == Phase.ENTER:
		var k := 1.0 - phase_t
		sx = -(mon.size.x * 0.5 + BAG_HALF.x * s + 10) * k * k
	elif phase == Phase.EXIT:
		sx = (mon.size.x * 0.5 + BAG_HALF.x * s + 10) * phase_t * phase_t
	var shk := Vector2(sin(Time.get_ticks_msec() / 18.0), cos(Time.get_ticks_msec() / 23.0)) * 6.0 * shake
	c += Vector2(sx, 0) + shk
	draw_rect(mon, C_SCREEN.lerp(C_TABLE, e_open))
	# belt
	var by := _bag_center().y + (BAG_HALF.y + 10) * s
	var belt_a := 1.0 - e_open
	draw_rect(Rect2(mon.position.x, by, mon.size.x, 10 * s), Color(0.35, 0.4, 0.45, 0.25 * belt_a))
	var step := 26.0 * s
	var off := fmod(belt_off * s, step)
	var bx := mon.position.x + off - step
	while bx < mon.end.x:
		draw_line(Vector2(bx, by), Vector2(bx, by + 10 * s), Color(0.2, 0.25, 0.3, 0.3 * belt_a), 2)
		bx += step
	if opened <= 0.0:
		_draw_bag_shell(c, s, 0.0)
		_draw_scan_items(bag, c, s)
		var show_red: Array = missed_flash.duplicate()
		if dev_reveal and phase != Phase.EXIT:
			show_red = bag.bad
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 120.0)
		for k in show_red:
			var it: Dictionary = bag.items[k]
			var h: Vector2 = CAT[it.id].half
			_ring(c + it.pos * s, maxf(h.x, h.y) * s + 8, Color(C_RED, pulse), 3)
		_draw_monitor_frame("XR-7   LANE 2   BAG %02d" % (bag_i + 1))
	else:
		_draw_open_bag(bag, c, s, opened)
		_draw_monitor_frame("")
	# bag progress
	var dy := mon.end.y + 10
	var dw := minf(28.0, (col.size.x - 9 * 6) / BAGS)
	var dx := col.get_center().x - (dw * BAGS + 6 * (BAGS - 1)) * 0.5
	for i in BAGS:
		var m := bag_mark(i)
		var cc := C_PANEL_HI
		if m == 0:
			cc = C_GREEN
		elif m == 1:
			cc = C_ACCENT
		elif m == 2:
			cc = C_RED
		var rr := Rect2(dx + i * (dw + 6), dy, dw, 10)
		_round_rect(rr, cc, 3)
		if i == bag_i and m < 0:
			draw_rect(rr.grow(2), C_INK, false, 1.5)
	if phase == Phase.SCAN:
		_center_text(col.get_center().x, ctrl.position.y - 7, "Anything illegal in this bag?", 13, C_MUTED)
	elif phase == Phase.OPEN and close_hold < 0.0:
		var r: Dictionary = results[bag_i]
		_center_text(col.get_center().x, ctrl.position.y - 7, "Tap the illegal items  ·  found %d" % r.found.size(), 13, C_ACCENT)


func _draw_open_bag(bag: Dictionary, c: Vector2, s: float, opened: float) -> void:
	var e := smoothstep(0.0, 1.0, clampf(opened / 0.45, 0.0, 1.0))
	# bag shell grows from its scan size to fill the monitor, and its zipper opens
	var r0 := Rect2(c - BAG_HALF * s, BAG_HALF * 2.0 * s)
	var r1 := mon.grow(-6)
	var r := Rect2(r0.position.lerp(r1.position, e), r0.size.lerp(r1.size, e))
	_round_rect(r, XR.fabric.lerp(C_BAGIN, e), 14)
	var zip_k := clampf(opened / 0.4, 0.0, 1.0)
	var zx := r.position.x + 10 + (r.size.x - 20) * zip_k
	draw_line(Vector2(r.position.x + 10, r.position.y + 6), Vector2(zx, r.position.y + 6), Color("0c111a"), 6)
	draw_line(Vector2(zx, r.position.y + 6), Vector2(r.end.x - 10, r.position.y + 6), Color("9aa4b2", 1.0 - e * 0.5), 3)
	draw_rect(Rect2(zx - 5, r.position.y, 10, 14), Color("c9d1d9"))
	if e > 0.5:
		_text(r.position + Vector2(12, 26), "OPENED FOR INSPECTION", 11, Color(C_MUTED, (e - 0.5) * 2.0))
	var res: Dictionary = results[bag_i] if bag_i < results.size() else {"found": [], "wrong": []}
	var n: int = bag.items.size()
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 110.0)
	for i in n:
		var it: Dictionary = bag.items[i]
		var cell: Rect2 = open_cells[i] if i < open_cells.size() else _cell_rect(i, n)
		var h: Vector2 = CAT[it.id].half
		var fit := minf(cell.size.x * 0.82 / (h.x * 2.0), cell.size.y * 0.7 / (h.y * 2.0))
		var fit_r := minf(cell.size.x * 0.82 / (h.y * 2.0), cell.size.y * 0.7 / (h.x * 2.0))
		var trot := 0.0
		if fit_r > fit * 1.15:
			fit = fit_r
			trot = -PI * 0.5
		fit = minf(fit, 2.2)
		var k := smoothstep(0.0, 1.0, clampf((opened - 0.3 - i * 0.035) / 0.5, 0.0, 1.0))
		var tc := cell.get_center() + Vector2(0, -6)
		if k > 0.0:
			var ca := Color(Color("4a5a75"), 0.75 * k)
			if i in res.found:
				ca = Color(C_GREEN, 0.28 * k)
			elif i in res.wrong:
				ca = Color(C_RED, 0.22 * k)
			_round_rect(cell, ca, 8)
		var pos: Vector2 = (c + it.pos * s).lerp(tc, k)
		_draw_item(it.id, pos, lerp_angle(float(it.rot), trot, k), lerpf(s, fit, k), k)
		if k >= 1.0:
			if i in res.found or i in res.wrong or i in missed_flash:
				_center_text(cell.get_center().x, cell.end.y - 6, CAT[it.id].name, 11, Color(C_INK, 0.85))
			if i in res.found:
				draw_rect(cell, C_GREEN, false, 3.0)
				draw_polyline(_pts([cell.end.x - 26, cell.position.y + 14, cell.end.x - 19, cell.position.y + 21, cell.end.x - 8, cell.position.y + 8]), C_GREEN, 4)
			elif i in res.wrong:
				draw_rect(cell, C_RED, false, 2.0)
				var q := Vector2(cell.end.x - 16, cell.position.y + 14)
				draw_line(q + Vector2(-6, -6), q + Vector2(6, 6), C_RED, 3)
				draw_line(q + Vector2(-6, 6), q + Vector2(6, -6), C_RED, 3)
			if i in missed_flash or (dev_reveal and i in bag.bad and not i in res.found):
				draw_rect(cell.grow(1), Color(C_RED, pulse), false, 4.0)


func _draw_end() -> void:
	var cx := col.get_center().x
	var top := legend_rect.end.y + 14
	var card := Rect2(col.position.x, top, col.size.x, ctrl.position.y - top - 14)
	_round_rect(card, C_PANEL, 12)
	var y := top + 34
	_center_text(cx, y, "SHIFT COMPLETE", 16, C_MUTED)
	y += 54
	_center_text(cx, y, _num(total_score()), 52, C_ACCENT)
	y += 22
	_center_text(cx, y, "points", 13, C_MUTED)
	y += 30
	var dw := minf(28.0, (col.size.x - 40 - 9 * 6) / BAGS)
	var dx := cx - (dw * BAGS + 6 * (BAGS - 1)) * 0.5
	for i in BAGS:
		var m := bag_mark(i)
		var cc: Color = [C_PANEL_HI, C_GREEN, C_ACCENT, C_RED][m + 1]
		_round_rect(Rect2(dx + i * (dw + 6), y, dw, dw), cc, 5)
	y += dw + 30
	var rows := [
		["Contraband found  %d/%d" % [found_total(), contraband_total()], found_total() * FIND_PTS, C_GREEN],
		["False alarms  %d" % false_alarms(), false_alarms() * FALSE_ALARM_PTS, C_RED],
		["Harmless items tapped  %d" % wrong_total(), wrong_total() * WRONG_PTS, C_RED],
		["Time  %s" % clock(elapsed), time_bonus(), C_ACCENT],
	]
	var lx := card.position.x + 22
	var rx := card.end.x - 22
	for row in rows:
		if y > card.end.y - 40:
			break
		_text(Vector2(lx, y), row[0], 15, C_INK)
		var v: int = row[1]
		_text(Vector2(rx - 120, y), ("+" if v > 0 else "") + _num(v), 15, row[2] if v != 0 else C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 120)
		y += 28
	var left := 86400 - int(Time.get_unix_time_from_system()) % 86400
	if y < card.end.y - 16:
		var nxt := "Next shift in %d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60] if date == today else "Today's shift: open without ?day="
		_center_text(cx, card.end.y - 16, nxt, 12, C_MUTED)


func _draw_button(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var style := String(b.style)
	var bg := C_PANEL_HI
	var fg := C_INK
	var size := 18
	match style:
		"primary":
			bg = C_ACCENT
			fg = Color("1a1300")
			size = 20
		"clear":
			bg = Color("1f7a4c")
			size = 24
		"flag":
			bg = Color("b8323e")
			size = 24
		"ghost_big":
			bg = C_PANEL_HI
			size = 20
		"ghost":
			bg = Color(C_PANEL_HI, 0.8)
			size = 16
		"dev":
			bg = Color("3a2f55")
			size = 14
	_round_rect(r, bg, 10)
	var ty := r.position.y + r.size.y * 0.5 + size * 0.35
	if style == "clear" or style == "flag":
		ty -= 7
		var hint := "Space" if style == "clear" else "F"
		_center_text(r.get_center().x, r.end.y - 10, hint, 11, Color(1, 1, 1, 0.55))
	_center_text(r.get_center().x, ty, String(b.label), size, fg)


func _draw_dev() -> void:
	var p := Rect2(col.position.x, 62, col.size.x, 460)
	_round_rect(p, Color("161226", 0.97), 12)
	draw_rect(p, Color("8a6cff"), false, 1.5)
	var x := p.position.x + 12
	_text(Vector2(x, p.position.y + 24), "DEV  ·  %s  ·  #%d" % [date, puzzle_no], 16, Color("c8b8ff"))
	_text(Vector2(x, p.position.y + 44), "seed %d  ·  %s/%s  ·  bag %d" % [seed_for(date), Screen.keys()[screen], Phase.keys()[phase], bag_i + 1], 12, C_MUTED)
	var line := ""
	for i in bags.size():
		var names: Array = []
		for k in bags[i].bad:
			names.append(String(bags[i].items[k].id))
		line += "%d:%s  " % [i + 1, "-" if names.is_empty() else "+".join(names)]
	draw_multiline_string(font, Vector2(x, p.position.y + 66), line, HORIZONTAL_ALIGNMENT_LEFT, p.size.x - 24, 11, 6, C_INK)
	_text(Vector2(x, p.position.y + 150), "score %d  ·  time %s  ·  contraband %d" % [base_score(), clock(elapsed), contraband_total()], 12, C_MUTED)
	for b in buttons:
		if String(b.style) == "dev":
			_draw_button(b)
