extends Node2D
## Flightle: a real flight path with both airports hidden. Name the departure and
## arrival airports in 6 guesses; every miss reveals another clue.

enum Phase { PLAYING, WON, LOST }

const EPOCH := "2026-10-03"            # puzzle #1
const DEFAULT_URL := "https://jprier.github.io/GameTests/flightle/"
const DATA_PATH := "res://data/flightle.json"
const MAX_GUESSES := 6
const EARTH_KM := 6371.0
const CLUES := [
	{"id": "airline", "label": "AIRLINE"},
	{"id": "aircraft", "label": "AIRCRAFT"},
	{"id": "altitude", "label": "ALTITUDE PROFILE"},
	{"id": "distance", "label": "DISTANCE"},
	{"id": "departs", "label": "DEPARTS"},
]
const KEY_ROWS := ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
const NEAR_KM := 300.0
const MID_KM := 1500.0

const C_BG := Color("0b1220")
const C_CARD := Color("142036")
const C_CARD_HI := Color("1d2c49")
const C_LINE := Color(1, 1, 1, 0.08)
const C_INK := Color("eaf1fb")
const C_MUTED := Color("8796b0")
const C_DIM := Color("4c5a75")
const C_ACCENT := Color("ffb547")
const C_PATH := Color("4fd1ff")
const C_HIT := Color("34d399")
const C_NEAR := Color("fbbf24")
const C_MID := Color("fb923c")
const C_FAR := Color("5b6984")
const C_SWAP := Color("60a5fa")
const C_LAND := Color("1a2a45")
const C_LAND_EDGE := Color("2c4066")
const C_KEY := Color("22314f")
const C_BTN := Color("2a3b5e")

static var _data_cache: Dictionary = {}

var airports: Array = []
var ap_index: Dictionary = {}          # code -> index
var routes: Array = []
var land: Array = []                    # Array of PackedVector2Array (lon, lat)

var today := ""
var date := ""
var puzzle_no := 1
var base_url := DEFAULT_URL
var dev_mode := false
var dev_open := false
var dev_reveal := false

var route_i := 0
var route: Dictionary = {}
var guesses: Array = []                 # [[from_code, to_code], ...]
var phase := Phase.PLAYING
var slot := 0                           # 0 = from, 1 = to
var texts := ["", ""]
var picks := ["", ""]

# geometry of today's route
var path_pts: Array = []                # Array of Vector3 on the unit sphere
var center3 := Vector3.ZERO
var east3 := Vector3.ZERO
var north3 := Vector3.ZERO
var half_km := 0.0
var view_km := 1000.0                   # km from centre to the map edge (animated)

var font: Font
var buttons: Array = []
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""
var help_open := false
var anim_t := 0.0
var pop_t := 1.0                        # newest guess pop animation 0..1
var clue_flash := -1
var clue_flash_t := 0.0
var key_flash: Dictionary = {}
var title_rect := Rect2()
var press_t := -1.0
var title_taps: Array = []
var press_pos := Vector2.ZERO
var col := Rect2()
var map_rect := Rect2()
var clue_rect := Rect2()
var list_rect := Rect2()
var input_rect := Rect2()
var dev_date_edit: LineEdit
const ARCHIVE_ROWS := 7
var archive_open := false
var archive_page := 0
var archive_results: Dictionary = {}


func _ready() -> void:
	font = ThemeDB.fallback_font
	_add_key_action("confirm", [KEY_ENTER, KEY_KP_ENTER])
	_add_key_action("erase", [KEY_BACKSPACE])
	_add_key_action("switch_slot", [KEY_TAB])
	_add_key_action("dev_toggle", [KEY_QUOTELEFT])
	_add_key_action("back", [KEY_ESCAPE])
	_load_data()
	today = Time.get_date_string_from_system(true)
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_mode = OS.is_debug_build() or String(url.get("dev", "")) == "1"
	var want := today
	var d := String(url.get("day", ""))
	# Links always open today's flight; past days are picked in-game. Only dev mode honours ?day=.
	if dev_mode and _valid_date(d):
		want = d
	elif d != "":
		_clean_url()
	load_day(want)
	_layout()


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------------ data

func _load_data() -> void:
	if _data_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			var rings: Array = []
			for flat in parsed.get("land", []):
				var r := PackedVector2Array()
				for i in range(0, flat.size() - 1, 2):
					r.append(Vector2(float(flat[i]), float(flat[i + 1])))
				rings.append(r)
			parsed["land_rings"] = rings
			_data_cache = parsed
	airports = _data_cache.get("airports", [])
	routes = _data_cache.get("routes", [])
	land = _data_cache.get("land_rings", [])
	ap_index.clear()
	for i in airports.size():
		ap_index[String(airports[i].c)] = i


func airport(code: String) -> Dictionary:
	return airports[ap_index[code]] if ap_index.has(code) else {}


func ap_vec(code: String) -> Vector3:
	var a := airport(code)
	return latlon_vec(float(a.la), float(a.lo))


static func latlon_vec(la: float, lo: float) -> Vector3:
	var p := deg_to_rad(la)
	var l := deg_to_rad(lo)
	return Vector3(cos(p) * cos(l), cos(p) * sin(l), sin(p))


static func km_between(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.dot(b), -1.0, 1.0)) * EARTH_KM


func km_codes(a: String, b: String) -> float:
	return km_between(ap_vec(a), ap_vec(b))


## Initial great-circle bearing in degrees (0 = north, clockwise) from a to b.
func bearing(a: String, b: String) -> float:
	var A := airport(a)
	var B := airport(b)
	var p1 := deg_to_rad(float(A.la))
	var p2 := deg_to_rad(float(B.la))
	var dl := deg_to_rad(float(B.lo) - float(A.lo))
	var y := sin(dl) * cos(p2)
	var x := cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)


func route_valid(r: Dictionary) -> bool:
	var f := String(r.get("f", ""))
	var t := String(r.get("t", ""))
	return f != t and ap_index.has(f) and ap_index.has(t) and km_codes(f, t) >= 50.0 \
		and String(r.get("al", "")) != "" and String(r.get("ac", "")) != "" and String(r.get("dep", "")).length() == 5


# ------------------------------------------------------------------ days

func _valid_date(d: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return false
	if dev_mode:
		return true
	return d >= EPOCH and d <= today


func day_number(d: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(EPOCH + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return int(round((b - a) / 86400.0)) + 1


func seed_for(d: String) -> int:
	return hash("flightle:" + d)


func _cycle_perm(cycle: int) -> Array:
	var perm: Array = []
	for i in routes.size():
		perm.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("flightle:cycle:%d" % cycle)
	for i in range(perm.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = perm[i]
		perm[i] = perm[j]
		perm[j] = t
	return perm


## Every route is used once per cycle (no repeats), in a date-seeded order.
func route_index_for(d: String) -> int:
	var n := day_number(d) - 1
	var count := routes.size()
	var cycle := floori(float(n) / count)
	var pos := posmod(n, count)
	var perm := _cycle_perm(cycle)
	if pos <= 1 and count > 2:
		var prev_last = _cycle_perm(cycle - 1)[count - 1]
		if perm[0] == prev_last:
			var t = perm[0]
			perm[0] = perm[1]
			perm[1] = t
	var idx: int = perm[pos]
	# never serve a broken entry: walk forward deterministically to a valid one
	for k in count:
		if route_valid(routes[(idx + k) % count]):
			return (idx + k) % count
	return idx


func load_day(d: String) -> void:
	date = d
	puzzle_no = day_number(d)
	route_i = route_index_for(d)
	route = routes[route_i]
	_build_geometry()
	guesses = []
	_load_state()
	_recompute_phase()
	texts = ["", ""]
	picks = ["", ""]
	slot = 0 if not solved(0) else 1
	pop_t = 1.0
	clue_flash = -1
	view_km = _target_view_km()


func _build_geometry() -> void:
	var a := ap_vec(String(route.f))
	var b := ap_vec(String(route.t))
	path_pts = []
	var omega := acos(clampf(a.dot(b), -1.0, 1.0))
	for i in 65:
		var t := i / 64.0
		var p: Vector3
		if omega < 1e-6:
			p = a
		else:
			p = (a * sin((1.0 - t) * omega) + b * sin(t * omega)) / sin(omega)
		path_pts.append(p.normalized())
	center3 = path_pts[32]
	half_km = omega * EARTH_KM * 0.5
	var z := Vector3(0, 0, 1)
	east3 = z.cross(center3)
	if east3.length() < 1e-6:
		east3 = Vector3(0, 1, 0)
	east3 = east3.normalized()
	north3 = center3.cross(east3).normalized()


## Azimuthal equidistant projection around the route midpoint, in km (x east, y north).
func project_km(p: Vector3) -> Vector2:
	var ang := acos(clampf(p.dot(center3), -1.0, 1.0))
	var tang := p - center3 * p.dot(center3)
	var tl := tang.length()
	if tl < 1e-9:
		return Vector2.ZERO
	return Vector2(tang.dot(east3), tang.dot(north3)) / tl * ang * EARTH_KM


# ------------------------------------------------------------------ rules

func solved(end: int) -> bool:
	var want := String(route.f) if end == 0 else String(route.t)
	for g in guesses:
		if String(g[end]) == want:
			return true
	return false


func misses() -> int:
	var m := 0
	for i in guesses.size():
		if not (String(guesses[i][0]) == String(route.f) and String(guesses[i][1]) == String(route.t)):
			m += 1
	return m


func clues_revealed() -> int:
	if phase != Phase.PLAYING:
		return CLUES.size()
	return mini(misses(), CLUES.size())


func _recompute_phase() -> void:
	phase = Phase.PLAYING
	for g in guesses:
		if String(g[0]) == String(route.f) and String(g[1]) == String(route.t):
			phase = Phase.WON
			return
	if guesses.size() >= MAX_GUESSES:
		phase = Phase.LOST


## Feedback for one end of one guess: {kind: hit|swap|miss, km, bearing}.
func feedback(g: Array, end: int) -> Dictionary:
	var code := String(g[end])
	var want := String(route.f) if end == 0 else String(route.t)
	var other := String(route.t) if end == 0 else String(route.f)
	if code == want:
		return {"kind": "hit", "km": 0.0, "bearing": 0.0}
	if code == other:
		return {"kind": "swap", "km": km_codes(code, want), "bearing": bearing(code, want)}
	return {"kind": "miss", "km": km_codes(code, want), "bearing": bearing(code, want)}


func mark(fb: Dictionary) -> String:
	match String(fb.kind):
		"hit": return "🟩"
		"swap": return "🟦"
	var km := float(fb.km)
	if km < NEAR_KM:
		return "🟨"
	if km < MID_KM:
		return "🟧"
	return "⬛"


func mark_color(fb: Dictionary) -> Color:
	match String(fb.kind):
		"hit": return C_HIT
		"swap": return C_SWAP
	var km := float(fb.km)
	if km < NEAR_KM:
		return C_NEAR
	if km < MID_KM:
		return C_MID
	return C_FAR


static func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func suggestions(query: String, limit := 4) -> Array:
	var q := _norm(query)
	if q == "":
		return []
	var scored: Array = []
	for a in airports:
		var code := String(a.c)
		var city := _norm(String(a.city))
		var name := _norm(String(a.n))
		var s := -1
		if code == q:
			s = 0
		elif code.begins_with(q):
			s = 1
		elif city.begins_with(q):
			s = 2
		elif name.begins_with(q):
			s = 3
		elif q.length() >= 3 and city.contains(q):
			s = 4
		elif q.length() >= 3 and name.contains(q):
			s = 5
		if s >= 0:
			scored.append([s, code])
	scored.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and String(x[1]) < String(y[1])))
	var out: Array = []
	for i in mini(limit, scored.size()):
		out.append(String(scored[i][1]))
	return out


func current_suggestions() -> Array:
	if phase != Phase.PLAYING or solved(slot) or picks[slot] != "":
		return []
	return suggestions(texts[slot])


# ------------------------------------------------------------------ input actions

func type_text(s: String) -> void:
	for ch in s:
		type_char(ch)


func type_char(ch: String) -> void:
	if phase != Phase.PLAYING or solved(slot):
		return
	var c := ch.to_upper()
	if not ((c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
		return
	if picks[slot] != "":
		picks[slot] = ""
		texts[slot] = ""
	if String(texts[slot]).length() < 18:
		texts[slot] = String(texts[slot]) + c


func erase() -> void:
	if phase != Phase.PLAYING or solved(slot):
		return
	if picks[slot] != "":
		picks[slot] = ""
		return
	var t := String(texts[slot])
	if t.length() > 0:
		texts[slot] = t.substr(0, t.length() - 1)
	elif slot == 1 and not solved(0):
		slot = 0


func select_slot(i: int) -> void:
	if phase == Phase.PLAYING and not solved(i):
		slot = i


func choose(code: String, which := -1) -> void:
	var s := slot if which < 0 else which
	if phase != Phase.PLAYING or solved(s) or not ap_index.has(code):
		return
	picks[s] = code
	texts[s] = code
	var other := 1 - s
	if not solved(other) and picks[other] == "":
		slot = other


## Enter: complete the active slot from the top suggestion, or submit when both are set.
func confirm() -> void:
	if phase != Phase.PLAYING:
		return
	if not solved(slot) and picks[slot] == "":
		var sug := current_suggestions()
		if sug.size() > 0:
			choose(String(sug[0]))
			if ready_to_guess():
				submit()
		elif String(texts[slot]) != "":
			_toast("No airport matches \"%s\"" % texts[slot])
		return
	if ready_to_guess():
		submit()
	else:
		slot = 1 - slot if not solved(1 - slot) else slot


func pair_for_guess() -> Array:
	return [String(route.f) if solved(0) else String(picks[0]), String(route.t) if solved(1) else String(picks[1])]


func ready_to_guess() -> bool:
	if phase != Phase.PLAYING:
		return false
	var p := pair_for_guess()
	return String(p[0]) != "" and String(p[1]) != ""


func submit() -> bool:
	if not ready_to_guess():
		_toast("Pick both airports first")
		return false
	var p := pair_for_guess()
	if String(p[0]) == String(p[1]):
		_toast("Departure and arrival must differ")
		return false
	for g in guesses:
		if String(g[0]) == String(p[0]) and String(g[1]) == String(p[1]):
			_toast("You already tried that pair")
			return false
	var before := clues_revealed()
	guesses.append(p)
	_recompute_phase()
	picks = ["", ""]
	texts = ["", ""]
	slot = 0 if not solved(0) else 1
	pop_t = 0.0
	if phase == Phase.WON:
		_toast("Landed it!")
	elif phase == Phase.LOST:
		_toast("Out of guesses")
	else:
		var after := clues_revealed()
		if after > before:
			clue_flash = after - 1
			clue_flash_t = 1.0
			_toast("New clue: %s" % String(CLUES[after - 1].label).capitalize())
		elif solved(0) or solved(1):
			_toast("One end locked in")
	_save_state()
	return true


## Convenience for tests and agents: guess a full pair in one call.
func guess(f: String, t: String) -> bool:
	if not solved(0):
		choose(f, 0)
	if not solved(1):
		choose(t, 1)
	return submit()


# ------------------------------------------------------------------ altitude profile

## Points (minutes, feet) describing the modelled altitude profile.
func altitude_profile(r: Dictionary = route) -> Array:
	var total := float(r.min)
	var c0 := float(r.c0)
	var c1 := float(r.c1)
	var climb := c0 / 2200.0
	var desc := c1 / 2000.0
	if climb + desc > total * 0.9:
		var k := total * 0.9 / (climb + desc)
		climb *= k
		desc *= k
	var pts: Array = [Vector2(0, 0), Vector2(climb, c0)]
	var cruise_end := total - desc
	if c1 > c0:
		var steps := int(round((c1 - c0) / 2000.0))
		var span := cruise_end - climb
		for s in steps:
			var t := climb + span * (s + 1) / (steps + 1.0)
			var alt := c0 + (c1 - c0) * s / float(steps)
			pts.append(Vector2(t, alt))
			pts.append(Vector2(t + 4.0, c0 + (c1 - c0) * (s + 1) / float(steps)))
	pts.append(Vector2(cruise_end, c1))
	pts.append(Vector2(total, 0))
	return pts


func fl(ft: float) -> String:
	if ft < 18000:
		return "%s ft" % thousands(int(ft))
	return "FL%03d" % int(round(ft / 100.0))


func altitude_text() -> String:
	if int(route.c1) > int(route.c0):
		return "%s to %s" % [fl(route.c0), fl(route.c1)]
	return "Cruises at %s" % fl(route.c0)


func duration_text(m: int) -> String:
	if m < 60:
		return "%dm" % m
	return "%dh %02dm" % [m / 60, m % 60]


static func thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func clue_value(i: int) -> String:
	match String(CLUES[i].id):
		"airline": return String(route.al)
		"aircraft": return String(route.ac)
		"altitude": return altitude_text()
		"distance": return "%s km  ·  about %s" % [thousands(int(route.km)), duration_text(int(route.min))]
		"departs": return "%s local time" % String(route.dep)
	return ""


# ------------------------------------------------------------------ save

func _save_path() -> String:
	return "user://%sflightle_%s.json" % ["dev_" if dev_mode else "", date]


func _save_state() -> void:
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"route": "%s-%s" % [route.f, route.t], "guesses": guesses}))
		f.close()
	if phase != Phase.PLAYING:
		_mark_played()
	_flush_storage()


func _load_state() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if not data is Dictionary:
		return
	if String(data.get("route", "")) != "%s-%s" % [route.f, route.t]:
		return
	for g in data.get("guesses", []):
		if g is Array and g.size() == 2 and ap_index.has(String(g[0])) and ap_index.has(String(g[1])) \
				and guesses.size() < MAX_GUESSES:
			guesses.append([String(g[0]), String(g[1])])


func wipe_save() -> void:
	if FileAccess.file_exists(_save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))
	_flush_storage()


func _flush_storage() -> void:
	var f := FileAccess.open("user://.sync", FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


## Lets the GameTests home page show today's result (never from dev mode).
func _mark_played() -> void:
	if dev_mode:
		return
	_record_result(date, result_label())
	if not OS.has_feature("web"):
		return
	var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
		JSON.stringify("gametests:flightle:" + date), JSON.stringify(JSON.stringify({"result": result_label()}))]
	JavaScriptBridge.eval(js, true)


# ------------------------------------------------------------------ sharing

func result_label() -> String:
	return "%d/%d" % [guesses.size(), MAX_GUESSES] if phase == Phase.WON else "X/%d" % MAX_GUESSES


## Always the plain game URL, so an old share still opens on today's flight.
func share_link() -> String:
	return base_url


func share_text() -> String:
	var lines := PackedStringArray()
	var used := mini(misses(), CLUES.size())
	lines.append("Flightle #%d · %s" % [puzzle_no, date])
	lines.append("✈️ %s · %d clue%s" % [result_label(), used, "" if used == 1 else "s"])
	for g in guesses:
		lines.append(mark(feedback(g, 0)) + "➡️" + mark(feedback(g, 1)))
	lines.append(share_link())
	return "\n".join(lines)


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__flShare='pending';
			var done=function(r){if(window.__flShare==='pending'){window.__flShare=r;}};
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
					setTimeout(function(){if(window.__flShare==='pending'){if(legacy()){done('copied');}else{ask();}}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},function(){if(legacy()){done('copied');}else{ask();}});
				}else if(legacy()){done('copied');}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__flCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__flCopyNext=true;done('share_failed');}
				});
			}else{window.__flCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied!")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__flShare||''", true)
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


func next_puzzle_text() -> String:
	var s := 86400 - int(Time.get_unix_time_from_system()) % 86400
	return "Next flight in %dh %02dm" % [s / 3600, (s % 3600) / 60]


# ------------------------------------------------------------------ past days

## Drops ?day= (and anything else) from the address bar so a refresh stays on today.
func _clean_url() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{history.replaceState(null,'',location.pathname)}catch(e){}", true)


func archive_count() -> int:
	return maxi(1, day_number(today))


func archive_pages() -> int:
	return ceili(float(archive_count()) / ARCHIVE_ROWS)


## The days on one page of the picker, newest first (page 0 starts with today).
func archive_page_days(page: int) -> Array:
	var out: Array = []
	for i in range(page * ARCHIVE_ROWS, mini((page + 1) * ARCHIVE_ROWS, archive_count())):
		out.append(_date_add(today, -i))
	return out


func open_archive() -> void:
	archive_results = _add_unfinished(_load_results())
	var idx := clampi(day_number(today) - day_number(date), 0, archive_count() - 1)
	archive_page = int(idx / ARCHIVE_ROWS)
	archive_open = true
	help_open = false


func archive_shift(pages: int) -> void:
	archive_page = clampi(archive_page + pages, 0, archive_pages() - 1)


## Opens a past (or today's) flight from the picker.
func pick_day(d: String) -> void:
	archive_open = false
	if d < EPOCH or d > today:
		return
	if d != date:
		load_day(d)


func _results_path() -> String:
	return "user://flightle_results.json"


## date -> result label for every finished day (this device), including results only the
## home page knew about (localStorage).
func _load_results() -> Dictionary:
	var out: Dictionary = {}
	if FileAccess.file_exists(_results_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_results_path()))
		if data is Dictionary:
			out = data
	if OS.has_feature("web") and not dev_mode:
		var r = JavaScriptBridge.eval("""(function(){var o={},p='gametests:flightle:';try{for(var i=0;i<localStorage.length;i++){
			var k=localStorage.key(i);if(k&&k.indexOf(p)===0){try{o[k.substr(p.length)]=JSON.parse(localStorage.getItem(k)).result||'';}catch(e){}}}}catch(e){}
			return JSON.stringify(o);})()""", true)
		if typeof(r) == TYPE_STRING:
			var ls = JSON.parse_string(r)
			if ls is Dictionary:
				for k in ls:
					if not out.has(k):
						out[k] = ls[k]
	return out


## Days with a save but no recorded result (unfinished, or played before results were kept).
func _add_unfinished(out: Dictionary) -> Dictionary:
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	var re := RegEx.create_from_string("^flightle_(\\d{4}-\\d{2}-\\d{2})\\.json$")
	for f in dir.get_files():
		var m := re.search(f)
		if m and not out.has(m.get_string(1)):
			out[m.get_string(1)] = "In progress"
	return out


func _record_result(d: String, label: String) -> void:
	var all := {}
	if FileAccess.file_exists(_results_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_results_path()))
		if data is Dictionary:
			all = data
	all[d] = label
	var f := FileAccess.open(_results_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
		f.close()


func _pretty_date(d: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))
	var wd: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(t.weekday)]
	var mo: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(t.month) - 1]
	return "%s %s %d" % [wd, mo, int(t.day)]


# ------------------------------------------------------------------ dev mode

func _date_add(d: String, days: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00") + days * 86400)


func dev_set_day(d: String) -> void:
	if not dev_mode:
		return
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		_toast("Use YYYY-MM-DD")
		return
	load_day(d)


func dev_shift(days: int) -> void:
	dev_set_day(_date_add(date, days))


func dev_random_day() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	dev_set_day(_date_add(EPOCH, rng.randi_range(-1000, 2000)))


func dev_reset() -> void:
	if not dev_mode:
		return
	wipe_save()
	load_day(date)


func dev_win() -> void:
	if not dev_mode or phase != Phase.PLAYING:
		return
	guess(String(route.f), String(route.t))


func dev_lose() -> void:
	if not dev_mode:
		return
	# far-away decoys, distinct each time
	var decoys: Array = []
	for a in airports:
		var c := String(a.c)
		if c != String(route.f) and c != String(route.t):
			decoys.append(c)
	decoys.sort_custom(func(x, y): return km_codes(x, String(route.t)) > km_codes(y, String(route.t)))
	var i := 0
	while phase == Phase.PLAYING and i + 1 < decoys.size():
		if not guess(String(decoys[i]), String(decoys[i + 1])):
			pass
		i += 2


## 5 quick taps on the title turn dev mode on (same as the other GameTests games);
## once on, 5 taps toggle the panel. Dev progress is kept apart from real progress.
func _dev_tap() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	title_taps.append(now)
	while title_taps.size() > 0 and now - float(title_taps[0]) > 3.0:
		title_taps.pop_front()
	if title_taps.size() >= 5:
		title_taps.clear()
		press_t = -1.0
		if not dev_mode:
			enable_dev()
		else:
			dev_open = not dev_open


func enable_dev() -> void:
	if dev_mode:
		return
	dev_mode = true
	load_day(date)
	dev_open = true
	_toast("Dev mode on")


func _dev_apply_date() -> void:
	if dev_date_edit:
		dev_set_day(dev_date_edit.text.strip_edges())


func get_agent_state() -> Dictionary:
	var fb: Array = []
	for g in guesses:
		fb.append([mark(feedback(g, 0)), mark(feedback(g, 1))])
	return {"day": date, "puzzle": puzzle_no, "seed": seed_for(date), "route_index": route_i,
		"answer": "%s-%s" % [route.f, route.t], "state": ["playing", "won", "lost"][phase],
		"guesses": guesses, "feedback": fb, "misses": misses(), "clues_revealed": clues_revealed(),
		"slot": slot, "texts": texts, "picks": picks, "suggestions": current_suggestions(),
		"dev_mode": dev_mode, "dev_open": dev_open, "help_open": help_open, "share_text": share_text(),
		"archive_open": archive_open, "archive_page": archive_page, "today": today}


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	anim_t += delta
	pop_t = minf(1.0, pop_t + delta / 0.45)
	clue_flash_t = maxf(0.0, clue_flash_t - delta / 1.4)
	if toast_t > 0.0:
		toast_t -= delta
	for k in key_flash.keys():
		key_flash[k] = float(key_flash[k]) - delta * 5.0
		if float(key_flash[k]) <= 0.0:
			key_flash.erase(k)
	if share_pending:
		_poll_share()
	if press_t >= 0.0 and title_rect.has_point(press_pos) and Time.get_ticks_msec() / 1000.0 - press_t > 0.7:
		press_t = -1.0
		if dev_mode:
			dev_open = not dev_open
	var target := _target_view_km()
	view_km = lerpf(view_km, target, 1.0 - exp(-delta * 4.0))
	if absf(view_km - target) < target * 0.003:
		view_km = target
	_layout()
	_sync_dev_edit()
	queue_redraw()


## Guesses closer than this to the route midpoint are plotted; farther ones get an edge arrow.
func map_limit_km() -> float:
	return maxf(half_km * 2.4, 700.0)


func _target_view_km() -> float:
	var r := maxf(half_km * 1.25, 180.0)
	var limit := map_limit_km()
	for g in guesses:
		for e in 2:
			var d := km_between(ap_vec(String(g[e])), center3)
			if d <= limit:
				r = maxf(r, d * 1.12)
	if phase != Phase.PLAYING:
		r = maxf(r, half_km * 1.6 + 250.0)
	return r


func _unhandled_input(ev: InputEvent) -> void:
	var key := ev as InputEventKey
	if key == null or not key.pressed:
		return
	if dev_date_edit and dev_date_edit.has_focus():
		return
	if ev.is_action_pressed("dev_toggle") and dev_mode:
		dev_open = not dev_open
		return
	if ev.is_action_pressed("back"):
		dev_open = false
		help_open = false
		archive_open = false
		return
	if dev_open or help_open or archive_open:
		return
	if ev.is_action_pressed("erase", true):
		erase()
		_flash("DEL")
	elif ev.is_action_pressed("confirm"):
		if phase == Phase.PLAYING:
			confirm()
			_flash("ENTER")
		else:
			share()
	elif ev.is_action_pressed("switch_slot"):
		select_slot(1 - slot)
	elif key.unicode > 0 and not key.echo:
		var ch := String.chr(key.unicode)
		type_char(ch)
		_flash(ch.to_upper())


func _flash(id: String) -> void:
	key_flash["k_" + id] = 1.0


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			_on_press(p)
		else:
			press_t = -1.0


func _on_press(p: Vector2) -> void:
	press_pos = p
	press_t = Time.get_ticks_msec() / 1000.0
	if title_rect.has_point(p) and not dev_open:
		_dev_tap()
		return
	for b in buttons:
		if b.rect.has_point(p):
			if b.enabled:
				key_flash[String(b.id)] = 1.0
				_do(String(b.id))
			return
	if help_open:
		help_open = false


func _do(id: String) -> void:
	if id.begins_with("k_"):
		var k := id.substr(2)
		if k == "DEL":
			erase()
		elif k == "ENTER":
			confirm()
		else:
			type_char(k)
		return
	if id.begins_with("day_"):
		pick_day(id.substr(4))
		return
	if id.begins_with("sug_"):
		choose(id.substr(4))
		return
	match id:
		"slot0": select_slot(0)
		"slot1": select_slot(1)
		"go": submit()
		"share": share()
		"help": help_open = not help_open
		"archive": open_archive()
		"arch_newer": archive_shift(-1)
		"arch_older": archive_shift(1)
		"arch_close": archive_open = false
		"today": pick_day(today)
		"help_close": help_open = false
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
		"dev_go": _dev_apply_date()
		"dev_close": dev_open = false


func _btn(id: String, r: Rect2, label: String, style := "", enabled := true) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "style": style, "enabled": enabled})


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 24.0, 520.0)
	col = Rect2((vs.x - w) * 0.5, 0, w, vs.y)
	title_rect = Rect2(col.position.x, 0, 280, 52)
	buttons.clear()
	if dev_open:
		_layout_dev(vs)
		return
	if archive_open:
		_layout_archive(vs)
		return
	if help_open:
		_btn("help_close", _help_card(vs).grow(-0), "", "none")
		return
	_btn("help", Rect2(col.end.x - 36, 10, 36, 36), "?", "ghost")
	_btn("archive", Rect2(col.end.x - 80, 10, 36, 36), "", "ghost")
	var bottom := vs.y - 10.0
	if phase == Phase.PLAYING:
		var key_h := clampf((vs.y - 560.0) / 4.0, 36.0, 46.0)
		var kb_h := key_h * 3 + 12
		var top := bottom - kb_h - 6 - 34 - 6 - 44
		input_rect = Rect2(col.position.x, top, col.size.x, bottom - top)
		_layout_input(key_h)
	else:
		var h := 214.0
		input_rect = Rect2(col.position.x, bottom - h, col.size.x, h)
		var bw := input_rect.size.x - 28
		if date != today:
			bw = (bw - 10) * 0.5
			_btn("today", Rect2(input_rect.position.x + 24 + bw, input_rect.end.y - 60, bw, 46), "Today's flight", "accent")
		_btn("share", Rect2(input_rect.position.x + 14, input_rect.end.y - 60, bw, 46), "Share result", "accent")
	var rows := guesses.size()
	var row_h := 24.0
	list_rect = Rect2(col.position.x, input_rect.position.y - 8 - rows * row_h, col.size.x, rows * row_h)
	var clue_h := 38.0 * 2 + (58.0 if clues_revealed() > 2 else 38.0) + 12
	clue_rect = Rect2(col.position.x, list_rect.position.y - (8 if rows > 0 else 0) - clue_h, col.size.x, clue_h)
	var map_top := 78.0
	map_rect = Rect2(col.position.x, map_top, col.size.x, maxf(110.0, clue_rect.position.y - 8 - map_top))


func _layout_input(key_h: float) -> void:
	var r := input_rect
	var go_w := 62.0
	var sw := (r.size.x - go_w - 8 - 22) * 0.5
	_btn("slot0", Rect2(r.position.x, r.position.y, sw, 44), "", "slot", not solved(0))
	_btn("slot1", Rect2(r.position.x + sw + 22, r.position.y, sw, 44), "", "slot", not solved(1))
	_btn("go", Rect2(r.end.x - go_w, r.position.y, go_w, 44), "GO", "primary", ready_to_guess())
	var sug := current_suggestions()
	var sy := r.position.y + 50
	if sug.size() > 0:
		var cw := (r.size.x - 6 * 3) / 4.0
		for i in sug.size():
			_btn("sug_" + String(sug[i]), Rect2(r.position.x + i * (cw + 6), sy, cw, 34), String(sug[i]), "chip")
	var ky := sy + 40
	var gap := 4.0
	var kw := (r.size.x - gap * 9) / 10.0
	for ri in KEY_ROWS.size():
		var row: String = KEY_ROWS[ri]
		var y := ky + ri * (key_h + 6)
		var x := r.position.x + (r.size.x - (row.length() * kw + (row.length() - 1) * gap)) * 0.5
		if ri == 2:
			var wide := kw * 1.5 + gap * 0.5
			_btn("k_ENTER", Rect2(r.position.x, y, wide, key_h), "ENTER", "key_wide")
			x = r.position.x + wide + gap
			for ch in row:
				_btn("k_" + ch, Rect2(x, y, kw, key_h), ch, "key")
				x += kw + gap
			_btn("k_DEL", Rect2(x, y, r.end.x - x, key_h), "DEL", "key_wide")
		else:
			for ch in row:
				_btn("k_" + ch, Rect2(x, y, kw, key_h), ch, "key")
				x += kw + gap


func _archive_card(vs: Vector2) -> Rect2:
	var w := minf(col.size.x, 420.0)
	return Rect2((vs.x - w) * 0.5, 64, w, 58 + ARCHIVE_ROWS * _archive_row_h(vs) + 70)


func _archive_row_h(vs: Vector2) -> float:
	return clampf((vs.y - 64 - 58 - 70 - 16) / ARCHIVE_ROWS, 40.0, 50.0)


func _layout_archive(vs: Vector2) -> void:
	var c := _archive_card(vs)
	var rh := _archive_row_h(vs)
	var days := archive_page_days(archive_page)
	for i in days.size():
		_btn("day_" + String(days[i]), Rect2(c.position.x + 12, c.position.y + 58 + i * rh, c.size.x - 24, rh - 6), "", "row")
	var bw := (c.size.x - 24 - 16) / 3.0
	var by := c.end.y - 58
	_btn("arch_newer", Rect2(c.position.x + 12, by, bw, 44), "< Newer", "", archive_page > 0)
	_btn("arch_close", Rect2(c.position.x + 20 + bw, by, bw, 44), "Close")
	_btn("arch_older", Rect2(c.position.x + 28 + bw * 2, by, bw, 44), "Older >", "", archive_page < archive_pages() - 1)


func _help_card(vs: Vector2) -> Rect2:
	var w := minf(col.size.x, 400.0)
	return Rect2((vs.x - w) * 0.5, 90, w, 360)


func _dev_card(vs: Vector2) -> Rect2:
	var w := minf(col.size.x, 420.0)
	return Rect2((vs.x - w) * 0.5, 60, w, 470)


func _layout_dev(vs: Vector2) -> void:
	var c := _dev_card(vs)
	var x := c.position.x + 12
	var w := (c.size.x - 24 - 16) / 3.0
	var y := c.position.y + 236
	var rows := [["dev_m30", "-30 d"], ["dev_prev", "< Day"], ["dev_next", "Day >"],
		["dev_p30", "+30 d"], ["dev_today", "Today"], ["dev_rand", "Random"],
		["dev_reset", "Reset day"], ["dev_reveal", "Hide answer" if dev_reveal else "Reveal"], ["dev_close", "Close"],
		["dev_win", "Instant win"], ["dev_lose", "Instant lose"]]
	for i in rows.size():
		_btn(rows[i][0], Rect2(x + (i % 3) * (w + 8), y + int(i / 3) * 52, w, 44), rows[i][1])
	_btn("dev_go", Rect2(c.end.x - 12 - 70, c.position.y + 184, 70, 38), "Go")


func _sync_dev_edit() -> void:
	if not dev_open:
		if dev_date_edit:
			dev_date_edit.queue_free()
			dev_date_edit = null
		return
	if dev_date_edit == null:
		dev_date_edit = LineEdit.new()
		dev_date_edit.placeholder_text = "YYYY-MM-DD"
		dev_date_edit.text = date
		dev_date_edit.text_submitted.connect(func(_t): _dev_apply_date())
		add_child(dev_date_edit)
	var c := _dev_card(get_viewport_rect().size)
	dev_date_edit.position = Vector2(c.position.x + 12, c.position.y + 184)
	dev_date_edit.size = Vector2(c.size.x - 24 - 80, 38)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var vs := get_viewport_rect().size
	if map_rect.size.x <= 0.0:
		_layout()
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	_draw_header()
	_draw_map()
	_draw_clues()
	_draw_guess_list()
	if phase == Phase.PLAYING:
		_draw_input()
	else:
		_draw_end()
	if dev_mode and not dev_open:
		_text(Vector2(map_rect.position.x + 12, map_rect.end.y - 10), "DEV · tap the title 5x, hold it, or press `", 10, Color(C_ACCENT, 0.8))
	if help_open:
		_draw_help(vs)
	if archive_open:
		_draw_archive(vs)
	if dev_open:
		_draw_dev(vs)
	if dev_reveal and dev_mode and not dev_open:
		_text(Vector2(col.position.x, 74), "answer %s - %s" % [route.f, route.t], 11, C_ACCENT)
	if toast_t > 0.0 and toast != "":
		var a := clampf(toast_t / 0.3, 0.0, 1.0)
		var tw := font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 32
		var ty := _dev_card(vs).end.y + 12 if dev_open else map_rect.position.y + 10
		var tr := Rect2((vs.x - tw) * 0.5, ty, tw, 34)
		draw_rect(tr, Color(C_ACCENT, 0.95 * a))
		_text(Vector2(tr.position.x, tr.position.y + 22), toast, 14, Color(C_BG, a), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)


func _text(pos: Vector2, s: String, size: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, size, c)


func _fit(s: String, size: int, width: float) -> String:
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return s
	var t := s
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		t = t.substr(0, t.length() - 1)
	return t + "…"


func _round_rect(r: Rect2, c: Color, rad := 8.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(rad))
	draw_style_box(sb, r)


func _outline_rect(r: Rect2, c: Color, rad := 8.0, wdt := 2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = c
	sb.set_border_width_all(wdt)
	sb.set_corner_radius_all(int(rad))
	draw_style_box(sb, r)


func _draw_header() -> void:
	var x := col.position.x
	_draw_plane(Vector2(x + 12, 28), deg_to_rad(45.0), 11.0, C_ACCENT)
	_text(Vector2(x + 30, 37), "FLIGHTLE", 26, C_INK)
	var tw := font.get_string_size("FLIGHTLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var sub := "#%d · %s" % [puzzle_no, date]
	if x + 38 + tw + font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > col.end.x - 88:
		sub = "#%d" % puzzle_no
	_text(Vector2(x + 38 + tw, 37), sub, 13, C_MUTED)
	var goal := "Name both airports of this flight · %d tries" % MAX_GUESSES
	if phase == Phase.PLAYING and guesses.size() > 0:
		goal = "Guess %d of %d · each miss unlocks a clue" % [guesses.size() + 1, MAX_GUESSES]
	elif phase != Phase.PLAYING:
		goal = "Today's flight, revealed" if date == today else "Past flight, revealed"
	if date != today and phase == Phase.PLAYING:
		goal = "Past flight · %s" % _pretty_date(date)
	_text(Vector2(x, 66), goal, 14, C_ACCENT if date != today and phase == Phase.PLAYING else C_MUTED)
	for b in buttons:
		if String(b.id) == "help":
			_outline_rect(b.rect, C_DIM, 18.0, 2)
			_text(Vector2(b.rect.position.x, b.rect.position.y + 25), "?", 18, C_INK, HORIZONTAL_ALIGNMENT_CENTER, b.rect.size.x)
		elif String(b.id) == "archive":
			_outline_rect(b.rect, C_DIM, 18.0, 2)
			_draw_calendar(b.rect.get_center(), C_INK)


func _to_screen(km: Vector2, scale: float) -> Vector2:
	return map_rect.get_center() + Vector2(km.x, -km.y) * scale


func _draw_map() -> void:
	var r := map_rect
	_round_rect(r, C_CARD, 12.0)
	var scale := (minf(r.size.x, r.size.y) * 0.5 - 22.0) / maxf(view_km, 1.0)
	var done := phase != Phase.PLAYING
	# faint radar rings; no geography until the end
	var cc := r.get_center()
	for i in range(1, 4):
		draw_arc(cc, minf(r.size.x, r.size.y) * 0.5 * i / 3.3, 0, TAU, 64, C_LINE, 1.0, true)
	if done:
		_draw_land(scale)
	# route
	var pts := PackedVector2Array()
	for p in path_pts:
		pts.append(_to_screen(project_km(p), scale))
	draw_polyline(pts, Color(C_PATH, 0.25), 3.0, true)
	var cycle := 7.0
	var t := fmod(anim_t, cycle) / (cycle - 1.2)
	t = clampf(t, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var n := int(t * 64.0)
	if n >= 1:
		var trail := pts.slice(0, n + 1)
		draw_polyline(trail, C_PATH, 3.0, true)
	var a := pts[0]
	var b := pts[64]
	draw_circle(a, 6.0, C_PATH)
	draw_circle(a, 3.0, C_CARD)
	draw_arc(b, 7.0, 0, TAU, 24, C_PATH, 2.5, true)
	draw_circle(b, 2.5, C_PATH)
	var i0 := clampi(int(t * 63.0), 0, 63)
	var pos := pts[i0].lerp(pts[i0 + 1], t * 63.0 - i0)
	var dir := (pts[i0 + 1] - pts[i0])
	_draw_plane(pos, dir.angle() + PI * 0.5 if dir.length() > 0.01 else 0.0, 9.0, C_ACCENT)
	var dep_label := "DEP"
	var arr_label := "ARR"
	if done or solved(0) or dev_reveal:
		dep_label = String(route.f)
	if done or solved(1) or dev_reveal:
		arr_label = String(route.t)
	_label_at(a, dep_label, C_PATH, b)
	_label_at(b, arr_label, C_PATH, a)
	# guesses
	var limit := map_limit_km()
	for gi in guesses.size():
		var g: Array = guesses[gi]
		var newest := gi == guesses.size() - 1
		for e in 2:
			var code := String(g[e])
			if code == String(route.f) or code == String(route.t):
				continue
			var fb := feedback(g, e)
			var col_c := mark_color(fb)
			var v := ap_vec(code)
			var kp := project_km(v)
			var sp := _to_screen(kp, scale)
			var inner := r.grow(-14).abs()
			var rad := 4.5 * (1.0 + (1.0 - pop_t) * 1.2 if newest else 1.0)
			if km_between(v, center3) <= limit and inner.has_point(sp):
				draw_circle(sp, rad, col_c)
				_text(sp + Vector2(7, 4), code, 10, Color(col_c, 0.9))
			else:
				# edge arrow pointing the way to the far-away guess
				var d := (sp - cc).normalized()
				var edge := _ray_to_rect(cc, d, inner)
				_draw_arrow(edge, d.angle(), 7.0, col_c)
				_text(edge - d * 16 + Vector2(-10, 4), code, 9, Color(col_c, 0.85))
	# compass + scale
	_text(Vector2(r.position.x + 12, r.position.y + 20), "N", 11, C_MUTED)
	_draw_arrow(Vector2(r.position.x + 16, r.position.y + 28), -PI * 0.5, 5.0, C_MUTED)
	if done or clues_revealed() >= 4 or guesses.size() > 0:
		var km_step := _nice_step(view_km * 0.4)
		var px := km_step * scale
		var y := r.end.y - 14
		var x0 := r.end.x - 14 - px
		draw_line(Vector2(x0, y), Vector2(x0 + px, y), C_MUTED, 2.0)
		draw_line(Vector2(x0, y - 4), Vector2(x0, y + 1), C_MUTED, 2.0)
		draw_line(Vector2(x0 + px, y - 4), Vector2(x0 + px, y + 1), C_MUTED, 2.0)
		_text(Vector2(x0 + px * 0.5 - 40, y - 7), "%s km" % thousands(int(km_step)), 10, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, 80)


func _nice_step(v: float) -> float:
	var p := pow(10.0, floor(log(maxf(v, 1.0)) / log(10.0)))
	for m: float in [5.0, 2.0, 1.0]:
		if m * p <= v:
			return m * p
	return p


func _ray_to_rect(o: Vector2, d: Vector2, r: Rect2) -> Vector2:
	var tx := INF
	var ty := INF
	if absf(d.x) > 1e-6:
		tx = ((r.end.x if d.x > 0 else r.position.x) - o.x) / d.x
	if absf(d.y) > 1e-6:
		ty = ((r.end.y if d.y > 0 else r.position.y) - o.y) / d.y
	return o + d * minf(tx, ty)


func _label_at(p: Vector2, s: String, c: Color, away_from: Vector2) -> void:
	var d := (p - away_from).normalized()
	if d.length() < 0.1:
		d = Vector2(0, -1)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var q := p + d * 16.0 + Vector2(-w * 0.5, 4)
	q.x = clampf(q.x, map_rect.position.x + 4, map_rect.end.x - w - 4)
	q.y = clampf(q.y, map_rect.position.y + 14, map_rect.end.y - 4)
	_text(q, s, 12, c)


var _land_key := ""
var _land_polys: Array = []
var _land_lines: Array = []


func _draw_land(scale: float) -> void:
	var key := "%s|%.4f|%s" % [date, scale, map_rect]
	if key != _land_key:
		_land_key = key
		_build_land(scale)
	for poly in _land_polys:
		draw_colored_polygon(poly, C_LAND)
	for line in _land_lines:
		draw_polyline(line, C_LAND_EDGE, 1.0, true)


func _build_land(scale: float) -> void:
	_land_polys = []
	_land_lines = []
	var lim := PI * 0.48
	var box := map_rect.grow(-2)
	var clip := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	for ring in land:
		var runs: Array = []
		var seg := PackedVector2Array()
		var all_in := true
		for ll in ring:
			var v := latlon_vec(ll.y, ll.x)
			if acos(clampf(v.dot(center3), -1.0, 1.0)) > lim:
				all_in = false
				if seg.size() >= 2:
					runs.append(seg)
				seg = PackedVector2Array()
				continue
			seg.append(_to_screen(project_km(v), scale))
		if all_in and seg.size() >= 3:
			for piece in Geometry2D.intersect_polygons(seg, clip):
				if piece.size() >= 3:
					if not Geometry2D.triangulate_polygon(piece).is_empty():
						_land_polys.append(piece)
			seg.append(seg[0])
		if seg.size() >= 2:
			runs.append(seg)
		for run in runs:
			for line in Geometry2D.intersect_polyline_with_polygon(run, clip):
				if line.size() >= 2:
					_land_lines.append(line)


func _draw_plane(p: Vector2, ang: float, s: float, c: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -1.0), Vector2(0.18, -0.35), Vector2(1.0, 0.15), Vector2(1.0, 0.32),
		Vector2(0.18, 0.12), Vector2(0.14, 0.7), Vector2(0.42, 0.92), Vector2(0.42, 1.0), Vector2(0, 0.9),
		Vector2(-0.42, 1.0), Vector2(-0.42, 0.92), Vector2(-0.14, 0.7), Vector2(-0.18, 0.12), Vector2(-1.0, 0.32),
		Vector2(-1.0, 0.15), Vector2(-0.18, -0.35)])
	var out := PackedVector2Array()
	for q in pts:
		out.append(p + (q * s).rotated(ang))
	draw_colored_polygon(out, c)


func _draw_arrow(p: Vector2, ang: float, s: float, c: Color) -> void:
	var pts := PackedVector2Array([Vector2(s, 0), Vector2(-s * 0.7, s * 0.65), Vector2(-s * 0.35, 0), Vector2(-s * 0.7, -s * 0.65)])
	var out := PackedVector2Array()
	for q in pts:
		out.append(p + q.rotated(ang))
	draw_colored_polygon(out, c)


func _draw_check(p: Vector2, s: float, c: Color) -> void:
	draw_polyline(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(-s * 0.3, s * 0.7), p + Vector2(s, -s * 0.7)]), c, 2.5, true)


func _draw_clues() -> void:
	var r := clue_rect
	var revealed := clues_revealed()
	var hw := (r.size.x - 6) * 0.5
	var alt_h := 58.0 if revealed > 2 else 38.0
	var rects := [Rect2(r.position.x, r.position.y, hw, 38), Rect2(r.position.x + hw + 6, r.position.y, hw, 38),
		Rect2(r.position.x, r.position.y + 44, r.size.x, alt_h),
		Rect2(r.position.x, r.position.y + 50 + alt_h, hw, 38), Rect2(r.position.x + hw + 6, r.position.y + 50 + alt_h, hw, 38)]
	for i in CLUES.size():
		var cr: Rect2 = rects[i]
		var open := i < revealed
		var bg := C_CARD
		if open and i == clue_flash and clue_flash_t > 0.0:
			bg = C_CARD.lerp(C_ACCENT.darkened(0.45), clue_flash_t)
		_round_rect(cr, bg if open else C_BG.lerp(C_CARD, 0.45), 8.0)
		if not open:
			_outline_rect(cr, C_LINE, 8.0, 1)
		_text(Vector2(cr.position.x + 10, cr.position.y + 14), String(CLUES[i].label), 9, C_MUTED if open else C_DIM)
		if not open:
			_text(Vector2(cr.position.x + 10, cr.position.y + 31), "unlocks after miss %d" % (i + 1), 12, C_DIM)
			continue
		if String(CLUES[i].id) == "altitude":
			_text(Vector2(cr.position.x + 10, cr.position.y + 31), _fit(altitude_text(), 13, cr.size.x * 0.5 - 14), 13, C_INK)
			_draw_profile(Rect2(cr.position.x + cr.size.x * 0.5, cr.position.y + 8, cr.size.x * 0.5 - 10, cr.size.y - 16))
		else:
			_text(Vector2(cr.position.x + 10, cr.position.y + 31), _fit(clue_value(i), 14, cr.size.x - 20), 14, C_INK)


func _draw_profile(r: Rect2) -> void:
	var pts := altitude_profile()
	var tmax := float(route.min)
	var amax := 42000.0
	var line := PackedVector2Array()
	var fill := PackedVector2Array()
	for p in pts:
		line.append(Vector2(r.position.x + p.x / tmax * r.size.x, r.end.y - p.y / amax * r.size.y))
	fill = line.duplicate()
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), C_LINE, 1.0)
	for k: float in [10000.0, 20000.0, 30000.0, 40000.0]:
		var y := r.end.y - k / amax * r.size.y
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.04), 1.0)
	if fill.size() >= 3 and not Geometry2D.triangulate_polygon(fill).is_empty():
		draw_colored_polygon(fill, Color(C_PATH, 0.12))
	draw_polyline(line, C_PATH, 2.0, true)


func _draw_guess_list() -> void:
	var r := list_rect
	for i in guesses.size():
		var g: Array = guesses[i]
		var y := r.position.y + i * 24.0
		var newest := i == guesses.size() - 1
		var row := Rect2(r.position.x, y + 1, r.size.x, 22)
		var bg := C_CARD
		if newest and pop_t < 1.0:
			bg = C_CARD_HI.lerp(C_CARD, pop_t)
		_round_rect(row, bg, 6.0)
		_text(Vector2(row.position.x + 8, y + 17), str(i + 1), 12, C_DIM)
		var half := (row.size.x - 30) * 0.5
		for e in 2:
			var fb := feedback(g, e)
			var x := row.position.x + 26 + e * half
			var c := mark_color(fb)
			draw_rect(Rect2(x, y + 6, 10, 10), c)
			_text(Vector2(x + 16, y + 17), String(g[e]), 13, C_INK)
			var info_x := x + 54
			match String(fb.kind):
				"hit":
					_draw_check(Vector2(info_x + 8, y + 12), 6.0, C_HIT)
				_:
					var km := int(round(float(fb.km)))
					var txt := ("other end · " if String(fb.kind) == "swap" else "") + "%s km" % thousands(km)
					_text(Vector2(info_x, y + 17), _fit(txt, 12, half - 80), 12, c if String(fb.kind) == "swap" else C_MUTED)
					var tw := font.get_string_size(_fit(txt, 12, half - 80), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
					_draw_arrow(Vector2(info_x + tw + 12, y + 11), deg_to_rad(float(fb.bearing)) - PI * 0.5, 7.5, C_INK)
			if e == 0:
				_draw_arrow(Vector2(row.position.x + 26 + half - 8, y + 12), 0.0, 4.0, C_DIM)


func _draw_input() -> void:
	for b in buttons:
		var r: Rect2 = b.rect
		var id := String(b.id)
		var flash := float(key_flash.get(id, 0.0))
		match String(b.style):
			"slot":
				var i := 0 if id == "slot0" else 1
				var lock := solved(i)
				_round_rect(r, C_CARD, 8.0)
				if lock:
					_outline_rect(r, C_HIT, 8.0, 2)
				elif slot == i:
					_outline_rect(r, C_ACCENT, 8.0, 2)
				_text(Vector2(r.position.x + 9, r.position.y + 13), "FROM" if i == 0 else "TO", 9, C_MUTED)
				var main := ""
				var sub := ""
				var color := C_INK
				if lock:
					main = String(route.f) if i == 0 else String(route.t)
					sub = String(airport(main).city)
					color = C_HIT
				elif picks[i] != "":
					main = String(picks[i])
					sub = String(airport(main).city)
				elif String(texts[i]) != "":
					main = String(texts[i])
				if main == "":
					_text(Vector2(r.position.x + 9, r.position.y + 34), "city or code", 13, C_DIM)
				else:
					_text(Vector2(r.position.x + 9, r.position.y + 35), main, 16, color)
					var mw := font.get_string_size(main, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
					if sub != "":
						_text(Vector2(r.position.x + 15 + mw, r.position.y + 34), _fit(sub, 11, r.size.x - mw - 24), 11, C_MUTED)
				if slot == i and not lock and picks[i] == "" and fmod(anim_t, 1.0) < 0.55:
					var cx := r.position.x + 10 + (font.get_string_size(main, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x if main != "" else 0.0)
					draw_line(Vector2(cx, r.position.y + 20), Vector2(cx, r.position.y + 38), C_ACCENT, 2.0)
				if i == 0:
					_draw_plane(Vector2(r.end.x + 11, r.get_center().y), PI * 0.5, 7.0, C_DIM)
			"primary":
				var c := C_ACCENT if b.enabled else C_BTN
				if flash > 0.0:
					c = c.lightened(0.3 * flash)
				_round_rect(r, c, 8.0)
				_text(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 6), String(b.label), 16,
					C_BG if b.enabled else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			"chip":
				var code := String(b.label)
				_round_rect(r, C_CARD_HI.lightened(0.15 * flash), 17.0)
				var city := String(airport(code).city)
				_text(Vector2(r.position.x + 9, r.position.y + 22), code, 13, C_ACCENT)
				_text(Vector2(r.position.x + 44, r.position.y + 22), _fit(city, 11, r.size.x - 50), 11, C_INK)
			"key", "key_wide":
				var kc := C_KEY.lerp(C_ACCENT, 0.55 * flash)
				_round_rect(r, kc, 6.0)
				if id == "k_DEL":
					_draw_arrow(r.get_center(), PI, 8.0, C_INK)
					draw_line(r.get_center() + Vector2(-2, 0), r.get_center() + Vector2(10, 0), C_INK, 3.0)
				else:
					var fs := 11 if String(b.style) == "key_wide" else 17
					_text(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), String(b.label), fs, C_INK,
						HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if current_suggestions().is_empty():
		var hint := ""
		if not solved(slot) and picks[slot] == "" and String(texts[slot]) != "":
			hint = "No match. Try a city name or 3-letter code"
		elif ready_to_guess():
			hint = "Tap GO or press Enter"
		elif not solved(slot) and picks[slot] == "":
			hint = "Type the %s city or airport code" % ("departure" if slot == 0 else "arrival")
		if hint != "":
			_text(Vector2(input_rect.position.x, input_rect.position.y + 72), hint, 13, C_MUTED,
				HORIZONTAL_ALIGNMENT_CENTER, input_rect.size.x)


func _draw_end() -> void:
	var r := input_rect
	_round_rect(r, C_CARD, 12.0)
	var won := phase == Phase.WON
	var head := "Landed it in %d/%d!" % [guesses.size(), MAX_GUESSES] if won else "Missed it. The flight was:"
	_text(Vector2(r.position.x + 14, r.position.y + 28), head, 18, C_HIT if won else C_MID)
	var f := airport(String(route.f))
	var t := airport(String(route.t))
	var fw := font.get_string_size(String(route.f), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_text(Vector2(r.position.x + 14, r.position.y + 56), String(route.f), 20, C_INK)
	_draw_plane(Vector2(r.position.x + 30 + fw, r.position.y + 49), PI * 0.5, 8.0, C_ACCENT)
	_text(Vector2(r.position.x + 46 + fw, r.position.y + 56), String(route.t), 20, C_INK)
	_text(Vector2(r.position.x + 14, r.position.y + 76),
		_fit("%s to %s" % [f.city, t.city], 13, r.size.x - 28), 13, C_MUTED)
	_text(Vector2(r.position.x + 14, r.position.y + 98),
		_fit("%s · %s" % [route.al, route.ac], 13, r.size.x - 28), 13, C_INK)
	_text(Vector2(r.position.x + 14, r.position.y + 117),
		_fit("%s km · about %s · departs %s" % [thousands(int(route.km)), duration_text(int(route.min)), route.dep], 13, r.size.x - 28), 13, C_MUTED)
	_text(Vector2(r.position.x, r.end.y - 68), next_puzzle_text(), 12, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for b in buttons:
		if String(b.id) == "share" or String(b.id) == "today":
			var c := C_ACCENT if String(b.id) == "share" else C_BTN
			c = c.lightened(0.3 * float(key_flash.get(String(b.id), 0.0)))
			_round_rect(b.rect, c, 10.0)
			_text(Vector2(b.rect.position.x, b.rect.position.y + 29), String(b.label), 17,
				C_BG if String(b.id) == "share" else C_INK, HORIZONTAL_ALIGNMENT_CENTER, b.rect.size.x)


## Small calendar glyph for the past-days button.
func _draw_calendar(c: Vector2, col_: Color) -> void:
	var r := Rect2(c.x - 8, c.y - 7, 16, 15)
	draw_rect(r, col_, false, 1.6)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 4), col_)
	draw_line(Vector2(c.x - 4, c.y - 10), Vector2(c.x - 4, c.y - 5), col_, 1.6)
	draw_line(Vector2(c.x + 4, c.y - 10), Vector2(c.x + 4, c.y - 5), col_, 1.6)
	for i in 3:
		draw_rect(Rect2(c.x - 5.5 + i * 4, c.y + 1, 2.5, 2.5), col_)


func _draw_archive(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	var c := _archive_card(vs)
	_round_rect(c, C_CARD_HI, 14.0)
	_text(Vector2(c.position.x + 18, c.position.y + 34), "Past flights", 20, C_INK)
	var pg := "Page %d of %d" % [archive_page + 1, archive_pages()]
	_text(Vector2(c.position.x, c.position.y + 34), pg, 12, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 18)
	for b in buttons:
		var id := String(b.id)
		var hl := float(key_flash.get(id, 0.0))
		if id.begins_with("day_"):
			var d := id.substr(4)
			var r: Rect2 = b.rect
			_round_rect(r, C_CARD.lightened(0.15 * hl), 8.0)
			if d == date:
				_outline_rect(r, C_ACCENT, 8.0, 2)
			var mid := r.position.y + r.size.y * 0.5 + 6
			_text(Vector2(r.position.x + 12, mid), "#%d" % day_number(d), 16, C_ACCENT)
			var name := "Today" if d == today else _pretty_date(d)
			_text(Vector2(r.position.x + 64, mid), name, 15, C_INK)
			var res := String(archive_results.get(d, ""))
			var rc := C_DIM
			if res.begins_with("X"):
				rc = C_MID
			elif res != "":
				rc = C_HIT
			_text(Vector2(r.position.x, mid), res if res != "" else "Not played", 14 if res != "" else 12, rc,
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12)
		elif id.begins_with("arch_"):
			var en: bool = b.enabled
			_round_rect(b.rect, (C_BTN if en else C_CARD).lightened(0.25 * hl), 8.0)
			_text(Vector2(b.rect.position.x, b.rect.position.y + b.rect.size.y * 0.5 + 5), String(b.label), 14,
				C_INK if en else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, b.rect.size.x)


func _draw_help(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	var c := _help_card(vs)
	_round_rect(c, C_CARD_HI, 14.0)
	var x := c.position.x + 18
	var y := c.position.y + 36
	_text(Vector2(x, y), "How to play", 20, C_INK)
	var lines := [
		"A real flight route is drawn with the airports",
		"hidden. The plane flies from DEP to ARR, north up.",
		"",
		"Guess both airports: type a city or 3-letter code.",
		"Each end gets its distance and a direction arrow",
		"toward the real airport. A correct end locks in.",
		"",
		"Every miss unlocks a clue: airline, aircraft,",
		"altitude profile, distance, departure time.",
		"",
		"Green = right · yellow < 300 km · orange < 1,500 km",
		"Blue = right airport, wrong end.",
		"A new flight every day at 00:00 UTC.",
	]
	for i in lines.size():
		_text(Vector2(x, y + 30 + i * 20), String(lines[i]), 13, C_MUTED if String(lines[i]) != "" else C_MUTED)
	_text(Vector2(c.position.x, c.end.y - 14), "Tap anywhere to close", 11, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)


func _draw_dev(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var c := _dev_card(vs)
	_round_rect(c, C_CARD_HI, 12.0)
	var x := c.position.x + 14
	var y := c.position.y + 28
	_text(Vector2(x, y), "Dev mode", 18, C_ACCENT)
	var info := [
		"day %s · puzzle #%d · today %s" % [date, puzzle_no, today],
		"seed %d · route %d/%d" % [seed_for(date), route_i, routes.size()],
		"state %s · guesses %d · clues %d" % [["playing", "won", "lost"][phase], guesses.size(), clues_revealed()],
		"answer: %s - %s" % [route.f, route.t] if dev_reveal else "answer: (hidden)",
		"%s · %s · %s km · %s" % [route.al, route.ac, thousands(int(route.km)), route.dep] if dev_reveal else "",
		"progress saved separately (dev_*)",
	]
	for i in info.size():
		_text(Vector2(x, y + 24 + i * 19), _fit(String(info[i]), 12, c.size.x - 28), 12, C_INK if i < 3 else C_MUTED)
	_text(Vector2(x, c.position.y + 178), "Jump to date", 10, C_MUTED)
	for b in buttons:
		_round_rect(b.rect, C_BTN.lightened(0.25 * float(key_flash.get(String(b.id), 0.0))), 8.0)
		_text(Vector2(b.rect.position.x, b.rect.position.y + b.rect.size.y * 0.5 + 5), String(b.label), 13, C_INK,
			HORIZONTAL_ALIGNMENT_CENTER, b.rect.size.x)
