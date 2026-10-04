extends Node2D
## Ticker Time: a daily stock-chart game with two modes.
##  - Guess the Year: five real one-year charts (ticker + company shown), name the year.
##  - Up or Down: start with $1,000; see a year of a stock's chart, bet on the next month.
## Everyone gets the same charts each day (seeded from the date). Drawn immediate-mode in _draw().

const EPOCH := "2026-10-02"            # puzzle #1
const DEFAULT_URL := "https://jprier.github.io/GameTests/ticker-time/"
const DATA_PATH := "res://data/stocks.json"
const ROUNDS := 5
const YEAR_MIN := 1995
const YEAR_MAX := 2025
const START_CASH := 1000.0
const LOOKBACK := 52                   # weeks of history shown in Up or Down
const AHEAD := 4                       # weeks until the bet settles (~1 month)
const STAKE_STEP := 0.05               # the bet slider moves in 5% steps
const STAKE_MIN := 0.05
const LEGACY_STAKES := [0.25, 0.5, 1.0]  # older saves stored an index into these
const YEAR_POINTS := [100, 80, 60, 45, 30, 20, 10]
const YEAR_BINS := [[1995, 2000], [2001, 2006], [2007, 2012], [2013, 2018], [2019, 2025]]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

const C_BG := Color("0f1724")
const C_CARD := Color("18233a")
const C_CARD_HI := Color("22304d")
const C_GRID := Color(1, 1, 1, 0.07)
const C_INK := Color("eef3fb")
const C_MUTED := Color("8b9ab3")
const C_ACCENT := Color("f5c451")
const C_LINE := Color("6aa8ff")
const C_UP := Color("2bd47d")
const C_DOWN := Color("ff5c6c")
const C_BTN := Color("26344f")
const C_BTN_ON := Color("3b5a8f")
const C_Q := Color(1, 1, 1, 0.05)

enum Screen { MENU, YEAR, UD, YEAR_END, UD_END }

static var _data_cache: Dictionary = {}

var stocks: Array = []
var w0_unix := 0
var nweeks := 0

var today := ""
var date := ""
var puzzle_no := 1
var base_url := DEFAULT_URL
var dev_mode := false
var dev_open := false
var dev_reveal := false

var year_rounds: Array = []    # [{stock, year}]
var ud_rounds: Array = []      # [{stock, end}]  end = global week index of the last week shown
var year_guesses: Array = []   # ints
var ud_bets: Array = []        # [{dir: 1|-1, frac: share of cash bet, 0.05..1}]

var screen := Screen.MENU
var year_i := 0
var ud_i := 0
var revealed := false
var cur_guess := 2010
var stake := 0.5
var reveal_t := 1.0
var bump_t := 0.0

var font: Font
var buttons: Array = []
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""
var slider_rect := Rect2()
var slider_drag := false
var title_rect := Rect2()
var title_taps: Array = []
var press_t := -1.0
var press_pos := Vector2.ZERO
var col := Rect2()
const ARCHIVE_ROWS := 7
var archive_open := false
var archive_page := 0
var archive_results: Dictionary = {}


func _ready() -> void:
	font = ThemeDB.fallback_font
	_add_key_action("left", [KEY_LEFT, KEY_A])
	_add_key_action("right", [KEY_RIGHT, KEY_D])
	_add_key_action("confirm", [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER])
	_add_key_action("bet_up", [KEY_UP, KEY_W])
	_add_key_action("bet_down", [KEY_DOWN, KEY_S])
	_add_key_action("back", [KEY_ESCAPE])
	_add_key_action("dev_toggle", [KEY_QUOTELEFT])
	_load_data()
	today = Time.get_date_string_from_system(true)
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_mode = OS.is_debug_build() or String(url.get("dev", "")) == "1"
	var want := today
	var d := String(url.get("day", ""))
	if d == "":
		d = String(url.get("d", ""))
	# Links always open today's game; past days are picked in-game. Only dev mode honours ?day=.
	if dev_mode and _valid_date(d):
		want = d
	elif d != "":
		_clean_url()
	load_day(want)


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
			_data_cache = parsed
	stocks = _data_cache.get("stocks", [])
	nweeks = int(_data_cache.get("nw", 0))
	w0_unix = Time.get_unix_time_from_datetime_string(String(_data_cache.get("w0", "1995-01-06")) + "T00:00:00")


func week_unix(g: int) -> int:
	return w0_unix + g * 7 * 86400


func week_date(g: int) -> Dictionary:
	return Time.get_date_dict_from_unix_time(week_unix(g))


## First global week whose Friday falls in `year`.
func first_week_of(year: int) -> int:
	var u := Time.get_unix_time_from_datetime_string("%04d-01-01T00:00:00" % year)
	return int(ceil(float(u - w0_unix) / (7.0 * 86400.0)))


func stock_first(si: int) -> int:
	return int(stocks[si].s)


func stock_last(si: int) -> int:
	return int(stocks[si].s) + stocks[si].c.size() - 1


func price(si: int, g: int) -> float:
	return float(stocks[si].c[g - int(stocks[si].s)])


func series(si: int, g0: int, g1: int) -> Array:
	var out: Array = []
	for g in range(g0, g1 + 1):
		out.append(price(si, g))
	return out


func _has_bad(si: int, g0: int, g1: int) -> bool:
	for b in stocks[si].get("b", []):
		var g := int(b) + int(stocks[si].s)
		if g >= g0 and g <= g1:
			return true
	return false


func year_range(year: int) -> Vector2i:
	return Vector2i(first_week_of(year), first_week_of(year + 1) - 1)


func has_full_year(si: int, year: int) -> bool:
	var r := year_range(year)
	return stock_first(si) <= r.x and stock_last(si) >= r.y and not _has_bad(si, r.x, r.y)


func ud_return(r: Dictionary) -> float:
	var e := int(r.end)
	return price(int(r.stock), e + AHEAD) / price(int(r.stock), e) - 1.0


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


func seed_for(mode: String, d: String) -> int:
	return hash("ticker-time:%s:%s" % [mode, d])


func load_day(d: String) -> void:
	date = d
	puzzle_no = day_number(d)
	generate(d)
	year_guesses = []
	ud_bets = []
	_load_state()
	screen = Screen.MENU
	revealed = false
	reveal_t = 1.0
	year_i = year_guesses.size()
	ud_i = ud_bets.size()
	cur_guess = 2010
	stake = 0.5


func generate(d: String) -> void:
	year_rounds = generate_year_rounds(d)
	ud_rounds = generate_ud_rounds(d)


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func generate_year_rounds(d: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for("year", d)
	var bins := YEAR_BINS.duplicate()
	_shuffle(bins, rng)
	var used := {}
	var out: Array = []
	for b in bins:
		for attempt in 400:
			var y := rng.randi_range(int(b[0]), int(b[1]))
			var si := rng.randi_range(0, stocks.size() - 1)
			if used.has(si) or not has_full_year(si, y):
				continue
			var r := year_range(y)
			var vals := series(si, r.x, r.y)
			var lo: float = vals.min()
			var hi: float = vals.max()
			if (hi - lo) / ((hi + lo) * 0.5) < 0.12:
				continue   # too flat to read
			used[si] = true
			out.append({"stock": si, "year": y})
			break
	return out


func generate_ud_rounds(d: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for("ud", d)
	var gmax := nweeks - 2   # last complete week
	var used := {}
	var out: Array = []
	var attempts := 0
	while out.size() < ROUNDS and attempts < 5000:
		attempts += 1
		var si := rng.randi_range(0, stocks.size() - 1)
		if used.has(si):
			continue
		var lo := stock_first(si) + LOOKBACK - 1
		var hi := mini(stock_last(si), gmax) - AHEAD
		if hi < lo:
			continue
		var e := rng.randi_range(lo, hi)
		if _has_bad(si, e - LOOKBACK + 1, e + AHEAD):
			continue
		var r := {"stock": si, "end": e}
		var ret := ud_return(r)
		if absf(ret) < 0.01:
			continue   # a coin flip on a flat line isn't fun
		if out.size() == ROUNDS - 1:
			# make sure the day isn't all ups or all downs
			var ups := 0
			for o in out:
				if ud_return(o) > 0:
					ups += 1
			if (ups == ROUNDS - 1 and ret > 0) or (ups == 0 and ret < 0):
				continue
		used[si] = true
		out.append(r)
	return out


# ------------------------------------------------------------------ scoring

func year_points(guess: int, actual: int) -> int:
	var dist := absi(guess - actual)
	return YEAR_POINTS[dist] if dist < YEAR_POINTS.size() else 0


func year_score() -> int:
	var t := 0
	for i in year_guesses.size():
		t += year_points(int(year_guesses[i]), int(year_rounds[i].year))
	return t


func year_mark(i: int) -> String:
	var dist := absi(int(year_guesses[i]) - int(year_rounds[i].year))
	if dist == 0:
		return "🟩"
	if dist <= 2:
		return "🟨"
	if dist <= 5:
		return "🟧"
	return "🟥"


func year_mark_color(i: int) -> Color:
	var dist := absi(int(year_guesses[i]) - int(year_rounds[i].year))
	if dist == 0:
		return C_UP
	if dist <= 2:
		return C_ACCENT
	if dist <= 5:
		return Color("ff9d4d")
	return C_DOWN


## Replays the bets so far and returns per-round results plus the running cash.
func ud_results() -> Array:
	var cash := START_CASH
	var out: Array = []
	for i in ud_bets.size():
		var bet: Dictionary = ud_bets[i]
		var ret := ud_return(ud_rounds[i])
		var amount := snappedf(cash * float(bet.frac), 0.01)
		var pnl := maxf(-amount, amount * ret * int(bet.dir))
		pnl = snappedf(pnl, 0.01)
		var before := cash
		cash = snappedf(cash + pnl, 0.01)
		out.append({"ret": ret, "amount": amount, "pnl": pnl, "before": before, "after": cash,
			"right": (ret > 0) == (int(bet.dir) > 0)})
	return out


func cash() -> float:
	var r := ud_results()
	return START_CASH if r.is_empty() else float(r[-1].after)


func best_possible_cash() -> float:
	var c := START_CASH
	for r in ud_rounds:
		c = snappedf(c * (1.0 + absf(ud_return(r))), 0.01)
	return c


func year_done() -> bool:
	return year_guesses.size() >= year_rounds.size()


func ud_done() -> bool:
	return ud_bets.size() >= ud_rounds.size()


# ------------------------------------------------------------------ actions

func open_mode(mode: Screen) -> void:
	revealed = false
	reveal_t = 1.0
	if mode == Screen.YEAR:
		year_i = year_guesses.size()
		screen = Screen.YEAR_END if year_done() else Screen.YEAR
	elif mode == Screen.UD:
		ud_i = ud_bets.size()
		screen = Screen.UD_END if ud_done() else Screen.UD
	else:
		screen = mode


func set_guess(y: int) -> void:
	var c := clampi(y, YEAR_MIN, YEAR_MAX)
	if c != cur_guess:
		bump_t = 1.0
	cur_guess = c


func lock_guess() -> void:
	if screen != Screen.YEAR or revealed or year_done():
		return
	year_guesses.append(cur_guess)
	revealed = true
	reveal_t = 0.0
	_save_state()


func place_bet(dir: int) -> void:
	if screen != Screen.UD or revealed or ud_done():
		return
	ud_bets.append({"dir": dir, "frac": stake})
	revealed = true
	reveal_t = 0.0
	_save_state()


func set_stake(frac: float) -> void:
	var f := clampf(snappedf(frac, STAKE_STEP), STAKE_MIN, 1.0)
	if not is_equal_approx(f, stake):
		bump_t = 1.0
	stake = f


func stake_label(frac: float) -> String:
	return "all in" if frac >= 0.999 else "%d%%" % int(round(frac * 100.0))


func next_round() -> void:
	if not revealed:
		return
	revealed = false
	reveal_t = 1.0
	if screen == Screen.YEAR:
		year_i += 1
		if year_done():
			screen = Screen.YEAR_END
			_mark_played()
	elif screen == Screen.UD:
		ud_i += 1
		if ud_done():
			screen = Screen.UD_END
			_mark_played()


# ------------------------------------------------------------------ saving

func _save_path() -> String:
	return "user://%sticker_%s.json" % ["dev_" if dev_mode else "", date]


func _save_state() -> void:
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"year": year_guesses, "ud": ud_bets}))
		f.close()
	_flush_storage()


func _load_state() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if not data is Dictionary:
		return
	for g in data.get("year", []):
		if year_guesses.size() < year_rounds.size():
			year_guesses.append(int(g))
	for b in data.get("ud", []):
		if b is Dictionary and ud_bets.size() < ud_rounds.size():
			var frac := float(b.get("frac", -1.0))
			if frac < 0.0:
				frac = float(LEGACY_STAKES[clampi(int(b.get("stake", 1)), 0, LEGACY_STAKES.size() - 1)])
			ud_bets.append({"dir": 1 if int(b.get("dir", 1)) > 0 else -1, "frac": clampf(frac, STAKE_MIN, 1.0)})


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

## Always the plain game URL, so an old share still opens on today's game.
func share_link() -> String:
	return base_url


func result_label() -> String:
	var parts: Array = []
	if year_done():
		parts.append("%d pts" % year_score())
	if ud_done():
		parts.append(money(cash()))
	return " · ".join(parts)


## Remembers the day's result for the past-days picker and the GameTests home page (never in dev mode).
func _mark_played() -> void:
	if dev_mode or result_label() == "":
		return
	_record_result(date, result_label())
	if OS.has_feature("web"):
		var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
			JSON.stringify("gametests:ticker-time:" + date), JSON.stringify(JSON.stringify({"result": result_label()}))]
		JavaScriptBridge.eval(js, true)


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


func archive_shift(pages: int) -> void:
	archive_page = clampi(archive_page + pages, 0, archive_pages() - 1)


## Opens a past (or today's) game from the picker, on its menu.
func pick_day(d: String) -> void:
	archive_open = false
	if d < EPOCH or d > today:
		return
	if d != date:
		load_day(d)
	screen = Screen.MENU


func _results_path() -> String:
	return "user://ticker_results.json"


func _load_results() -> Dictionary:
	var out: Dictionary = {}
	if FileAccess.file_exists(_results_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_results_path()))
		if data is Dictionary:
			out = data
	return out


## Days with a save but no recorded result (unfinished, or played before results were kept).
func _add_unfinished(out: Dictionary) -> Dictionary:
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	var re := RegEx.create_from_string("^ticker_(\\d{4}-\\d{2}-\\d{2})\\.json$")
	for f in dir.get_files():
		var m := re.search(f)
		if m and not out.has(m.get_string(1)):
			var data = JSON.parse_string(FileAccess.get_file_as_string("user://" + f))
			var done: bool = data is Dictionary and (data.get("year", []).size() >= ROUNDS or data.get("ud", []).size() >= ROUNDS)
			out[m.get_string(1)] = "Played" if done else "In progress"
	return out


func _record_result(d: String, label: String) -> void:
	var all := _load_results()
	all[d] = label
	var f := FileAccess.open(_results_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
		f.close()


func _short_date(d: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))
	var wd: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(t.weekday)]
	return "%s %s %d" % [wd, MONTHS[int(t.month) - 1], int(t.day)]


func money(v: float, sign := false) -> String:
	var neg := v < 0
	var cents := int(round(absf(v) * 100.0))
	var whole := str(cents / 100)
	var out := ""
	while whole.length() > 3:
		out = "," + whole.substr(whole.length() - 3) + out
		whole = whole.substr(0, whole.length() - 3)
	out = whole + out
	var s := "$%s.%02d" % [out, cents % 100]
	if neg:
		return "-" + s
	return ("+" + s) if sign else s


func pct(v: float, sign := true) -> String:
	var s := "%.1f%%" % (absf(v) * 100.0)
	if v < 0:
		return "-" + s
	return ("+" + s) if sign else s


func share_text() -> String:
	var lines := PackedStringArray()
	lines.append("Ticker Time #%d · %s" % [puzzle_no, date])
	if year_guesses.size() > 0:
		var marks := ""
		for i in year_guesses.size():
			marks += year_mark(i)
		lines.append("📅 Guess the Year: %d/%d %s" % [year_score(), ROUNDS * 100, marks])
	if ud_bets.size() > 0:
		var marks := ""
		for r in ud_results():
			marks += "🟢" if r.right else "🔴"
		var c := cash()
		lines.append("📈 Up or Down: %s (%s) %s" % [money(c), pct(c / START_CASH - 1.0), marks])
	lines.append(share_link())
	return "\n".join(lines)


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__ttShare='pending';
			var done=function(r){if(window.__ttShare==='pending'){window.__ttShare=r;}};
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
					setTimeout(function(){if(window.__ttShare==='pending'){if(legacy()){done('copied');}else{ask();}}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},function(){if(legacy()){done('copied');}else{ask();}});
				}else if(legacy()){done('copied');}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__ttCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__ttCopyNext=true;done('share_failed');}
				});
			}else{window.__ttCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied!")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__ttShare||''", true)
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
		return JSON.stringify({day:p.get('day')||'',d:p.get('d')||'',dev:p.get('dev')||'',base:location.origin+location.pathname});})()""", true)
	if typeof(r) != TYPE_STRING:
		return {}
	var d = JSON.parse_string(r)
	return d if d is Dictionary else {}


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 2.2


# ------------------------------------------------------------------ dev mode

func _date_add(d: String, days: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00") + days * 86400)


func dev_set_day(d: String) -> void:
	if not dev_mode:
		return
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return
	load_day(d)


func dev_shift(days: int) -> void:
	dev_set_day(_date_add(date, days))


func dev_random_day() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	dev_set_day(_date_add(EPOCH, rng.randi_range(-3000, 3000)))


func dev_reset() -> void:
	if not dev_mode:
		return
	wipe_save()
	load_day(date)


## Finish the current mode (or both, from the menu) with perfect answers.
func dev_win() -> void:
	_dev_finish(true)


## Finish the current mode (or both, from the menu) with the worst answers.
func dev_lose() -> void:
	_dev_finish(false)


func _dev_finish(win: bool) -> void:
	if not dev_mode:
		return
	var do_year := screen in [Screen.MENU, Screen.YEAR, Screen.YEAR_END]
	var do_ud := screen in [Screen.MENU, Screen.UD, Screen.UD_END]
	if do_year:
		while year_guesses.size() < year_rounds.size():
			var y := int(year_rounds[year_guesses.size()].year)
			year_guesses.append(y if win else (YEAR_MIN if y - YEAR_MIN > YEAR_MAX - y else YEAR_MAX))
	if do_ud:
		while ud_bets.size() < ud_rounds.size():
			var up := ud_return(ud_rounds[ud_bets.size()]) > 0
			ud_bets.append({"dir": (1 if up else -1) * (1 if win else -1), "frac": 1.0})
	_save_state()
	revealed = false
	if screen == Screen.MENU:
		return
	open_mode(Screen.YEAR if do_year else Screen.UD)


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
	var back := screen
	load_day(date)
	if back != Screen.MENU:
		open_mode(Screen.YEAR if back in [Screen.YEAR, Screen.YEAR_END] else Screen.UD)
	dev_open = true
	_toast("Dev mode on")


func get_agent_state() -> Dictionary:
	var state := "menu"
	if screen == Screen.YEAR or screen == Screen.UD:
		state = "playing"
	elif screen == Screen.YEAR_END or screen == Screen.UD_END:
		state = "done"
	var ya: Array = []
	for r in year_rounds:
		ya.append("%s %d" % [stocks[int(r.stock)].t, int(r.year)])
	var ua: Array = []
	for r in ud_rounds:
		ua.append("%s %s" % [stocks[int(r.stock)].t, pct(ud_return(r))])
	return {"day": date, "puzzle": puzzle_no, "seed_year": seed_for("year", date), "seed_ud": seed_for("ud", date),
		"screen": Screen.keys()[screen], "state": state, "round_year": year_i, "round_ud": ud_i, "revealed": revealed,
		"guess": cur_guess, "stake": stake, "year_score": year_score(), "year_done": year_done(),
		"cash": cash(), "ud_done": ud_done(), "dev_mode": dev_mode, "dev_open": dev_open,
		"year_answers": ya, "ud_answers": ua, "share_text": share_text(),
		"archive_open": archive_open, "archive_page": archive_page, "today": today}


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if reveal_t < 1.0:
		reveal_t = minf(1.0, reveal_t + delta / 0.9)
	bump_t = maxf(0.0, bump_t - delta * 6.0)
	if toast_t > 0.0:
		toast_t -= delta
	if share_pending:
		_poll_share()
	if press_t >= 0.0 and title_rect.has_point(press_pos) and Time.get_ticks_msec() / 1000.0 - press_t > 0.7:
		press_t = -1.0
		if dev_mode:
			dev_open = not dev_open
	_layout()
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	var key := ev as InputEventKey
	if key == null or not key.pressed:
		return
	if key.echo and not (ev.is_action("left") or ev.is_action("right")):
		return
	if ev.is_action_pressed("dev_toggle", true) and dev_mode:
		dev_open = not dev_open
	elif ev.is_action_pressed("back"):
		if dev_open:
			dev_open = false
		elif archive_open:
			archive_open = false
		else:
			screen = Screen.MENU
	elif archive_open:
		return
	elif screen == Screen.YEAR and not revealed:
		if ev.is_action_pressed("left", true):
			set_guess(cur_guess - 1)
		elif ev.is_action_pressed("right", true):
			set_guess(cur_guess + 1)
		elif ev.is_action_pressed("confirm"):
			lock_guess()
	elif screen == Screen.UD and not revealed:
		if ev.is_action_pressed("bet_up"):
			place_bet(1)
		elif ev.is_action_pressed("bet_down"):
			place_bet(-1)
		elif ev.is_action_pressed("left", true):
			set_stake(stake - STAKE_STEP)
		elif ev.is_action_pressed("right", true):
			set_stake(stake + STAKE_STEP)
		elif key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_3:
			set_stake(float(LEGACY_STAKES[key.physical_keycode - KEY_1]))
	elif revealed and ev.is_action_pressed("confirm"):
		next_round()
	elif screen == Screen.MENU and ev.is_action_pressed("confirm"):
		open_mode(Screen.YEAR if not year_done() else Screen.UD)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			_on_press(p)
		else:
			slider_drag = false
			press_t = -1.0
	elif ev is InputEventMouseMotion and slider_drag:
		_slider_to(make_input_local(ev).position.x)


func _on_press(p: Vector2) -> void:
	press_pos = p
	press_t = Time.get_ticks_msec() / 1000.0
	if title_rect.has_point(p):
		_dev_tap()
	for b in buttons:
		if b.rect.has_point(p):
			if b.enabled:
				_do(String(b.id))
			return
	if dev_open or archive_open:
		return
	if (screen == Screen.YEAR or screen == Screen.UD) and not revealed and slider_rect.grow_individual(12, 18, 12, 18).has_point(p):
		slider_drag = true
		_slider_to(p.x)


func _slider_to(x: float) -> void:
	var t := clampf((x - slider_rect.position.x) / slider_rect.size.x, 0.0, 1.0)
	if screen == Screen.UD:
		set_stake(STAKE_MIN + t * (1.0 - STAKE_MIN))
	else:
		set_guess(YEAR_MIN + int(round(t * (YEAR_MAX - YEAR_MIN))))


func _do(id: String) -> void:
	if id.begins_with("day_"):
		pick_day(id.substr(4))
		return
	match id:
		"archive": open_archive()
		"arch_newer": archive_shift(-1)
		"arch_older": archive_shift(1)
		"arch_close": archive_open = false
		"today": pick_day(today)
		"menu": screen = Screen.MENU
		"play_year": open_mode(Screen.YEAR)
		"play_ud": open_mode(Screen.UD)
		"minus": set_guess(cur_guess - 1)
		"plus": set_guess(cur_guess + 1)
		"lock": lock_guess()
		"next": next_round()
		"up": place_bet(1)
		"down": place_bet(-1)
		"stake_minus": set_stake(stake - STAKE_STEP)
		"stake_plus": set_stake(stake + STAKE_STEP)
		"share": share()
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


func _btn(id: String, r: Rect2, label: String, style := "", enabled := true) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "style": style, "enabled": enabled})


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 24.0, 560.0)
	col = Rect2((vs.x - w) * 0.5, 0, w, vs.y)
	title_rect = Rect2(col.position.x, 0, 260, 66)
	buttons.clear()
	slider_rect = Rect2()
	if dev_open:
		_layout_dev(vs)
		return
	if archive_open:
		_layout_archive(vs)
		return
	match screen:
		Screen.MENU: _layout_menu(vs)
		Screen.YEAR: _layout_year(vs)
		Screen.UD: _layout_ud(vs)
		Screen.YEAR_END, Screen.UD_END: _layout_end(vs)
	if screen != Screen.MENU:
		_btn("menu", Rect2(col.end.x - 74, 12, 74, 36), "Menu", "ghost")


func _menu_cards(vs: Vector2) -> Array:
	var top := 150.0
	var h := clampf((vs.y - top - 150.0) * 0.5, 160.0, 200.0)
	top += maxf(0.0, (vs.y - (top + h * 2 + 16 + 62 + 40)) * 0.15)
	return [Rect2(col.position.x, top, col.size.x, h), Rect2(col.position.x, top + h + 16, col.size.x, h)]


func _layout_menu(vs: Vector2) -> void:
	var cards := _menu_cards(vs)
	var a: Rect2 = cards[0]
	var b: Rect2 = cards[1]
	_btn("play_year", Rect2(a.position.x + 16, a.end.y - 62, a.size.x - 32, 46),
		"See results" if year_done() else ("Continue" if year_guesses.size() > 0 else "Play"), "primary")
	_btn("play_ud", Rect2(b.position.x + 16, b.end.y - 62, b.size.x - 32, 46),
		"See results" if ud_done() else ("Continue" if ud_bets.size() > 0 else "Play"), "primary")
	_btn("archive", Rect2(col.end.x - 44, 12, 44, 42), "", "icon")
	if date != today:
		var hw := (col.size.x - 12) * 0.5
		_btn("share", Rect2(col.position.x, b.end.y + 16, hw, 46), "Share results", "accent", year_done() or ud_done())
		_btn("today", Rect2(col.position.x + hw + 12, b.end.y + 16, hw, 46), "Today's game", "primary")
	elif year_done() or ud_done():
		_btn("share", Rect2(col.position.x, b.end.y + 16, col.size.x, 46), "Share today's results", "accent")


func _archive_row_h(vs: Vector2) -> float:
	return clampf((vs.y - 64 - 58 - 70 - 16) / ARCHIVE_ROWS, 40.0, 50.0)


func _archive_card(vs: Vector2) -> Rect2:
	var w := minf(col.size.x, 440.0)
	return Rect2((vs.x - w) * 0.5, 64, w, 58 + ARCHIVE_ROWS * _archive_row_h(vs) + 70)


func _layout_archive(vs: Vector2) -> void:
	var c := _archive_card(vs)
	var rh := _archive_row_h(vs)
	var days := archive_page_days(archive_page)
	for i in days.size():
		_btn("day_" + String(days[i]), Rect2(c.position.x + 12, c.position.y + 58 + i * rh, c.size.x - 24, rh - 6), "", "arch_row")
	var bw := (c.size.x - 24 - 16) / 3.0
	var by := c.end.y - 58
	_btn("arch_newer", Rect2(c.position.x + 12, by, bw, 44), "< Newer", "", archive_page > 0)
	_btn("arch_close", Rect2(c.position.x + 20 + bw, by, bw, 44), "Close")
	_btn("arch_older", Rect2(c.position.x + 28 + bw * 2, by, bw, 44), "Older >", "", archive_page < archive_pages() - 1)


func _content_rects(vs: Vector2, bottom_h: float) -> Dictionary:
	var top := 60.0
	var info := Rect2(col.position.x, top + 28, col.size.x, 74)
	var bottom := Rect2(col.position.x, vs.y - bottom_h - 12, col.size.x, bottom_h)
	var chart := Rect2(col.position.x, info.end.y + 10, col.size.x, maxf(140.0, bottom.position.y - info.end.y - 22))
	chart.size.y = minf(chart.size.y, 460.0)
	# centre a short chart between info and controls
	var spare := bottom.position.y - 12 - chart.end.y
	if spare > 0:
		chart.position.y += spare * 0.25
	return {"progress": Rect2(col.position.x, top, col.size.x, 24), "info": info, "chart": chart, "bottom": bottom}


func _layout_year(vs: Vector2) -> void:
	var r := _content_rects(vs, 200.0)
	var b: Rect2 = r.bottom
	if revealed:
		_btn("next", Rect2(b.position.x, b.end.y - 54, b.size.x, 54),
			"See results" if year_i >= ROUNDS - 1 else "Next chart", "primary")
		return
	slider_rect = Rect2(b.position.x + 64, b.position.y + 100, b.size.x - 128, 8)
	_btn("minus", Rect2(b.position.x, b.position.y + 80, 48, 48), "-")
	_btn("plus", Rect2(b.end.x - 48, b.position.y + 80, 48, 48), "+")
	_btn("lock", Rect2(b.position.x, b.end.y - 54, b.size.x, 54), "Lock in %d" % cur_guess, "primary")


func _layout_ud(vs: Vector2) -> void:
	var r := _content_rects(vs, 200.0)
	var b: Rect2 = r.bottom
	if revealed:
		_btn("next", Rect2(b.position.x, b.end.y - 54, b.size.x, 54),
			"See results" if ud_i >= ROUNDS - 1 else "Next stock", "primary")
		return
	slider_rect = Rect2(b.position.x + 60, b.position.y + 60, b.size.x - 120, 8)
	_btn("stake_minus", Rect2(b.position.x, b.position.y + 40, 44, 44), "-")
	_btn("stake_plus", Rect2(b.end.x - 44, b.position.y + 40, 44, 44), "+")
	var hw := (b.size.x - 12) * 0.5
	_btn("down", Rect2(b.position.x, b.end.y - 70, hw, 70), "Down", "down")
	_btn("up", Rect2(b.position.x + hw + 12, b.end.y - 70, hw, 70), "Up", "up")


func _layout_end(vs: Vector2) -> void:
	var y := vs.y - 12
	var other_done := ud_done() if screen == Screen.YEAR_END else year_done()
	var other_id := "play_ud" if screen == Screen.YEAR_END else "play_year"
	var other_label := ("Up or Down" if screen == Screen.YEAR_END else "Guess the Year") + (" results" if other_done else "")
	var hw := (col.size.x - 12) * 0.5
	_btn("share", Rect2(col.position.x, y - 54, hw, 54), "Share", "accent")
	_btn(other_id, Rect2(col.position.x + hw + 12, y - 54, hw, 54), other_label, "primary")


func _dev_card(vs: Vector2) -> Rect2:
	var w := minf(col.size.x, 420.0)
	return Rect2((vs.x - w) * 0.5, 64, w, 440)


func _layout_dev(vs: Vector2) -> void:
	var c := _dev_card(vs)
	var x := c.position.x + 12
	var w := (c.size.x - 24 - 16) / 3.0
	var y := c.position.y + 210
	var rows := [["dev_m30", "-30 d"], ["dev_prev", "< Day"], ["dev_next", "Day >"],
		["dev_p30", "+30 d"], ["dev_today", "Today"], ["dev_rand", "Random"],
		["dev_reset", "Reset day"], ["dev_reveal", "Hide answers" if dev_reveal else "Reveal"], ["dev_close", "Close"],
		["dev_win", "Instant win"], ["dev_lose", "Instant lose"]]
	for i in rows.size():
		_btn(rows[i][0], Rect2(x + (i % 3) * (w + 8), y + int(i / 3) * 52, w, 44), rows[i][1])


# ------------------------------------------------------------------ drawing

func _text(pos: Vector2, s: String, size: int, color := C_INK, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, size, color)


func _text_c(r: Rect2, y: float, s: String, size: int, color := C_INK) -> void:
	draw_string(font, Vector2(r.position.x, y), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, color)


func _round_rect(r: Rect2, color: Color, radius := 12.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	_draw_header()
	match screen:
		Screen.MENU: _draw_menu(vs)
		Screen.YEAR: _draw_year(vs)
		Screen.UD: _draw_ud(vs)
		Screen.YEAR_END: _draw_year_end(vs)
		Screen.UD_END: _draw_ud_end(vs)
	if dev_open:
		_draw_dev(vs)
	if archive_open:
		_draw_archive(vs)
	for b in buttons:
		if String(b.style) == "icon":
			_round_rect(b.rect, Color(1, 1, 1, 0.06), 12)
			_draw_calendar(b.rect.get_center(), C_INK)
		elif String(b.style) != "arch_row":
			_draw_button(b)
	if toast_t > 0.0 and toast != "":
		var a := clampf(toast_t / 0.3, 0.0, 1.0)
		var tw := font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 36
		var tr := Rect2((vs.x - tw) * 0.5, vs.y * 0.42, tw, 44)
		_round_rect(tr, Color(0.05, 0.08, 0.13, 0.92 * a), 22)
		_text_c(tr, tr.position.y + 29, toast, 18, Color(C_INK, a))


func _draw_header() -> void:
	var x := col.position.x
	draw_rect(Rect2(x, 22, 6, 18), C_UP)
	draw_rect(Rect2(x + 9, 16, 6, 24), C_DOWN)
	draw_rect(Rect2(x + 18, 12, 6, 28), C_ACCENT)
	_text(Vector2(x + 34, 38), "TICKER TIME", 24, C_INK)
	if screen == Screen.MENU:
		var sub := "#%d · %s%s" % [puzzle_no, _pretty_date(date), "  [dev]" if dev_mode else ""]
		_text(Vector2(x + 34, 56), sub, 14, C_MUTED)
		if date != today:
			var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			_text(Vector2(x + 34 + sw + 8, 56), "PAST DAY", 14, C_ACCENT)


## Small calendar glyph for the past-days button.
func _draw_calendar(c: Vector2, col_: Color) -> void:
	var r := Rect2(c.x - 9, c.y - 8, 18, 17)
	draw_rect(r, col_, false, 1.8)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5), col_)
	draw_line(Vector2(c.x - 4.5, c.y - 11), Vector2(c.x - 4.5, c.y - 6), col_, 1.8)
	draw_line(Vector2(c.x + 4.5, c.y - 11), Vector2(c.x + 4.5, c.y - 6), col_, 1.8)
	for i in 3:
		draw_rect(Rect2(c.x - 6.5 + i * 4.5, c.y + 1.5, 3, 3), col_)


func _draw_archive(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	var c := _archive_card(vs)
	_round_rect(c, C_CARD_HI, 16)
	_text(Vector2(c.position.x + 18, c.position.y + 34), "Past days", 20, C_INK)
	_text(Vector2(c.position.x, c.position.y + 34), "Page %d of %d" % [archive_page + 1, archive_pages()], 12, C_MUTED,
		HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 18)
	for b in buttons:
		var id := String(b.id)
		if not id.begins_with("day_"):
			continue
		var d := id.substr(4)
		var r: Rect2 = b.rect
		_round_rect(r, C_CARD, 10)
		if d == date:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = C_ACCENT
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(10)
			draw_style_box(sb, r)
		var mid := r.position.y + r.size.y * 0.5 + 6
		_text(Vector2(r.position.x + 12, mid), "#%d" % day_number(d), 16, C_ACCENT)
		_text(Vector2(r.position.x + 64, mid), "Today" if d == today else _short_date(d), 15, C_INK)
		var res := String(archive_results.get(d, ""))
		_text(Vector2(r.position.x, mid), res if res != "" else "Not played", 14 if res != "" else 12,
			C_UP if res != "" else C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12)


func _pretty_date(d: String) -> String:
	var p := d.split("-")
	if p.size() != 3:
		return d
	return "%s %d, %s" % [MONTHS[clampi(int(p[1]) - 1, 0, 11)], int(p[2]), p[0]]


func _draw_button(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var style := String(b.style)
	var bg := C_BTN
	var fg := C_INK
	match style:
		"primary": bg = Color("2f6fdc")
		"accent": bg = C_ACCENT; fg = Color("1a1405")
		"on": bg = C_BTN_ON
		"ghost": bg = Color(1, 1, 1, 0.06); fg = C_MUTED
		"up": bg = C_UP; fg = Color("06240f")
		"down": bg = C_DOWN; fg = Color("2b0509")
	if not b.enabled:
		bg = Color(bg, 0.35)
		fg = Color(fg, 0.45)
	_round_rect(r, bg, 12)
	var size := 20 if r.size.y >= 50 else 17
	if style == "up" or style == "down":
		var cx := r.get_center().x - 34
		var cy := r.get_center().y
		var s := 11.0
		var tri: PackedVector2Array
		if style == "up":
			tri = PackedVector2Array([Vector2(cx, cy - s), Vector2(cx + s, cy + s * 0.7), Vector2(cx - s, cy + s * 0.7)])
		else:
			tri = PackedVector2Array([Vector2(cx, cy + s), Vector2(cx + s, cy - s * 0.7), Vector2(cx - s, cy - s * 0.7)])
		draw_colored_polygon(tri, fg)
		_text(Vector2(cx + 20, cy + 9), String(b.label).to_upper(), 24, fg)
		return
	if String(b.label) == "-" or String(b.label) == "+":
		var c := r.get_center()
		draw_line(c - Vector2(9, 0), c + Vector2(9, 0), fg, 3)
		if String(b.label) == "+":
			draw_line(c - Vector2(0, 9), c + Vector2(0, 9), fg, 3)
		return
	_text_c(r, r.get_center().y + size * 0.36, String(b.label), size, fg)


func _draw_menu(vs: Vector2) -> void:
	var x := col.position.x
	var cards := _menu_cards(vs)
	var ty: float = cards[0].position.y - 50
	_text(Vector2(x, ty), "Real stock charts, 1995 to today.", 17, C_MUTED)
	_text(Vector2(x, ty + 24), "A new game every day, the same for everyone.", 17, C_MUTED)
	var a: Rect2 = cards[0]
	var b: Rect2 = cards[1]
	_round_rect(a, C_CARD, 16)
	_round_rect(b, C_CARD, 16)
	_text(a.position + Vector2(18, 38), "Guess the Year", 24)
	_text(a.position + Vector2(18, 66), "5 charts. Name the year each one shows.", 16, C_MUTED)
	var status := "%d / %d points" % [year_score(), ROUNDS * 100] if year_guesses.size() > 0 else "Closest year wins the most points"
	_text(a.position + Vector2(18, 94), status, 16, C_ACCENT if year_guesses.size() > 0 else C_MUTED)
	_draw_progress_dots(Rect2(a.end.x - 112, a.position.y + 22, 96, 20), year_guesses.size(), true)
	_draw_walk(Rect2(a.end.x - 150, a.position.y + 50, 132, 48), 7, C_UP)
	_text(b.position + Vector2(18, 38), "Up or Down", 24)
	_text(b.position + Vector2(18, 66), "Start with $1,000. Bet on the next month.", 16, C_MUTED)
	var c := cash()
	var st2 := "%s (%s)" % [money(c), pct(c / START_CASH - 1.0)] if ud_bets.size() > 0 else "5 stocks. Slide your bet, call the move."
	_text(b.position + Vector2(18, 94), st2, 16, (C_UP if c >= START_CASH else C_DOWN) if ud_bets.size() > 0 else C_MUTED)
	_draw_progress_dots(Rect2(b.end.x - 112, b.position.y + 22, 96, 20), ud_bets.size(), false)
	_draw_walk(Rect2(b.end.x - 150, b.position.y + 50, 132, 48), 11, C_LINE)
	_text_c(Rect2(0, 0, vs.x, 0), vs.y - 14, "Weekly closes, split-adjusted. Not investment advice.", 12, Color(C_MUTED, 0.7))


## A decorative random-walk line (not real data).
func _draw_walk(r: Rect2, seed_v: int, color: Color) -> void:
	if col.size.x < 500:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var vals: Array = []
	var v := 0.0
	for i in 40:
		v += rng.randfn(0.06, 0.5)
		vals.append(v)
	var lo: float = vals.min()
	var hi: float = vals.max()
	var pts := PackedVector2Array()
	for i in vals.size():
		pts.append(Vector2(r.position.x + r.size.x * i / 39.0, r.end.y - (float(vals[i]) - lo) / (hi - lo) * r.size.y))
	draw_polyline(pts, Color(color, 0.35), 2.0, true)


func _draw_progress_dots(r: Rect2, done: int, year_mode: bool, current := -1) -> void:
	var step := r.size.x / ROUNDS
	for i in ROUNDS:
		var c := Vector2(r.position.x + step * (i + 0.5), r.get_center().y)
		var color := Color(1, 1, 1, 0.12)
		if i < done:
			if year_mode:
				color = year_mark_color(i)
			else:
				color = C_UP if ud_results()[i].right else C_DOWN
		draw_circle(c, 6.0, color)
		if i == current:
			draw_arc(c, 9.0, 0, TAU, 24, C_INK, 1.5, true)


func _draw_year(vs: Vector2) -> void:
	if year_i >= year_rounds.size():
		return
	var r := _content_rects(vs, 200.0)
	var rnd: Dictionary = year_rounds[year_i]
	var si := int(rnd.stock)
	var actual := int(rnd.year)
	var pr: Rect2 = r.progress
	_text(pr.position + Vector2(0, 18), "GUESS THE YEAR  %d/%d" % [year_i + 1, ROUNDS], 15, C_MUTED)
	_draw_progress_dots(Rect2(pr.end.x - 200, pr.position.y + 2, 96, 20), year_guesses.size(), true, year_i)
	_text(Vector2(pr.end.x - 90, pr.position.y + 18), "%d pts" % year_score(), 15, C_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, 90)
	var info: Rect2 = r.info
	_text(info.position + Vector2(0, 38), String(stocks[si].t), 36, C_INK)
	_text(info.position + Vector2(0, 66), String(stocks[si].n), 18, C_MUTED)
	var yr := year_range(actual)
	var vals := series(si, yr.x, yr.y)
	var labels: Array = []
	for m in 12:
		var mu := Time.get_unix_time_from_datetime_string("%04d-%02d-15T00:00:00" % [actual, m + 1])
		labels.append([(mu - week_unix(yr.x)) / (week_unix(yr.y) - week_unix(yr.x) + 0.0), MONTHS[m].substr(0, 1) if r.chart.size.x < 420 else MONTHS[m]])
	var col_line := C_UP if vals[-1] >= vals[0] else C_DOWN
	_draw_chart(r.chart, vals, [], labels, col_line, 1.0)
	if revealed or dev_reveal:
		_text(r.chart.position + Vector2(16, 40), "%d" % actual, 30, Color(C_ACCENT, 0.9 if revealed else 0.45))
	var b: Rect2 = r.bottom
	if revealed:
		var g := int(year_guesses[year_i])
		var pts := year_points(g, actual)
		var t := ease(reveal_t, 0.4)
		var c := year_mark_color(year_i)
		_round_rect(Rect2(b.position.x, b.position.y, b.size.x, 120), C_CARD, 14)
		_text_c(b, b.position.y + 48, "It was %d" % actual, 30, C_INK)
		var diff := absi(g - actual)
		var what := "Exact!" if diff == 0 else ("You said %d, off by %d year%s" % [g, diff, "" if diff == 1 else "s"])
		_text_c(b, b.position.y + 78, what, 17, C_MUTED)
		_text_c(b, b.position.y + 108, "+%d points" % int(round(pts * t)), 20, c)
	else:
		var s := 1.0 + bump_t * 0.08
		_text_c(b, b.position.y + 50, "%d" % cur_guess, int(48 * s), C_ACCENT)
		_text_c(b, b.position.y + 72, "drag, tap or use arrow keys", 13, C_MUTED)
		var sr := slider_rect
		_round_rect(sr, Color(1, 1, 1, 0.12), 4)
		for y in range(YEAR_MIN, YEAR_MAX + 1, 5):
			var tx := sr.position.x + sr.size.x * (y - YEAR_MIN) / float(YEAR_MAX - YEAR_MIN)
			draw_line(Vector2(tx, sr.end.y + 4), Vector2(tx, sr.end.y + 9), C_MUTED, 1)
			if (y - YEAR_MIN) % 10 == 0 or y == YEAR_MAX:
				_text(Vector2(tx - 30, sr.end.y + 24), str(y), 12, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, 60)
		var kx := sr.position.x + sr.size.x * (cur_guess - YEAR_MIN) / float(YEAR_MAX - YEAR_MIN)
		draw_circle(Vector2(kx, sr.get_center().y), 13, C_ACCENT)
		draw_circle(Vector2(kx, sr.get_center().y), 5, C_BG)


func _draw_ud(vs: Vector2) -> void:
	if ud_i >= ud_rounds.size():
		return
	var r := _content_rects(vs, 200.0)
	var rnd: Dictionary = ud_rounds[ud_i]
	var si := int(rnd.stock)
	var e := int(rnd.end)
	var results := ud_results()
	var shown_cash := START_CASH if ud_i == 0 else float(results[ud_i - 1].after)
	var pr: Rect2 = r.progress
	_text(pr.position + Vector2(0, 18), "UP OR DOWN  %d/%d" % [ud_i + 1, ROUNDS], 15, C_MUTED)
	_draw_progress_dots(Rect2(pr.end.x - 220, pr.position.y + 2, 96, 20), ud_bets.size(), false, ud_i)
	var res: Dictionary = {}
	if revealed:
		res = results[ud_i]
		shown_cash = lerpf(float(res.before), float(res.after), ease(reveal_t, 0.4))
	_text(Vector2(pr.end.x - 110, pr.position.y + 18), money(shown_cash), 16, C_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, 110)
	var info: Rect2 = r.info
	_text(info.position + Vector2(0, 38), String(stocks[si].t), 36, C_INK)
	if revealed or dev_reveal:
		var d0 := week_date(e - LOOKBACK + 1)
		var d1 := week_date(e + AHEAD)
		_text(info.position + Vector2(0, 66), "%s · %s %d to %s %d" % [stocks[si].n, MONTHS[int(d0.month) - 1], int(d0.year),
			MONTHS[int(d1.month) - 1], int(d1.year)], 16, C_MUTED)
	else:
		_text(info.position + Vector2(0, 66), "%s · last 12 months" % stocks[si].n, 16, C_MUTED)
	var hist := series(si, e - LOOKBACK + 1, e)
	var fut: Array = []
	if revealed or dev_reveal:
		fut = series(si, e, e + AHEAD)
	var labels := [[0.0, "12 mo ago"], [0.5, "6 mo"], [1.0, "now"]]
	_draw_chart(r.chart, hist, fut, labels, C_LINE, ease(reveal_t, 0.5) if revealed else 1.0)
	var b: Rect2 = r.bottom
	if revealed:
		var ret := float(res.ret)
		var up := ret > 0
		_round_rect(Rect2(b.position.x, b.position.y, b.size.x, 120), C_CARD, 14)
		var bet: Dictionary = ud_bets[ud_i]
		_text_c(b, b.position.y + 44, "%s %s in a month" % [("Up" if up else "Down"), pct(absf(ret), false)], 28, C_UP if up else C_DOWN)
		_text_c(b, b.position.y + 74, "You bet %s %s" % [money(float(res.amount)), "up" if int(bet.dir) > 0 else "down"], 17, C_MUTED)
		var pnl := float(res.pnl) * ease(reveal_t, 0.4)
		_text_c(b, b.position.y + 106, ("You made %s" if res.pnl >= 0 else "You lost %s") % money(absf(pnl)), 20,
			C_UP if float(res.pnl) >= 0 else C_DOWN)
	else:
		var amt := snappedf(shown_cash * stake, 0.01)
		var sz := int(22 * (1.0 + bump_t * 0.06))
		_text(b.position + Vector2(0, 26), "Bet %s" % money(amt), sz, C_ACCENT)
		_text(Vector2(b.end.x - 200, b.position.y + 26), "%s of %s" % [stake_label(stake), money(shown_cash)], 15, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		var sr := slider_rect
		var kx := sr.position.x + sr.size.x * (stake - STAKE_MIN) / (1.0 - STAKE_MIN)
		_round_rect(sr, Color(1, 1, 1, 0.12), 4)
		_round_rect(Rect2(sr.position, Vector2(kx - sr.position.x, sr.size.y)), Color(C_ACCENT, 0.55), 4)
		for f in [0.25, 0.5, 0.75, 1.0]:
			var tx: float = sr.position.x + sr.size.x * (float(f) - STAKE_MIN) / (1.0 - STAKE_MIN)
			draw_line(Vector2(tx, sr.end.y + 4), Vector2(tx, sr.end.y + 9), C_MUTED, 1)
			_text(Vector2(tx - 30, sr.end.y + 24), stake_label(float(f)), 12, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, 60)
		draw_circle(Vector2(kx, sr.get_center().y), 13, C_ACCENT)
		draw_circle(Vector2(kx, sr.get_center().y), 5, C_BG)


## values: main series; future: continuation (first point == last of values); labels: [[t 0..1, text]]
func _draw_chart(r: Rect2, values: Array, future: Array, labels: Array, line_color: Color, grow: float) -> void:
	_round_rect(r, C_CARD, 14)
	var plot := Rect2(r.position.x + 14, r.position.y + 16, r.size.x - 70, r.size.y - 44)
	var n_future := AHEAD if screen == Screen.UD else 0
	var nh := float(maxi(1, values.size() - 1))
	var hist_w := plot.size.x * (0.8 if n_future > 0 else 1.0)
	var lo: float = values.min()
	var hi: float = values.max()
	if not future.is_empty():
		lo = minf(lo, future.min())
		hi = maxf(hi, future.max())
	if hi - lo < hi * 0.02:
		hi += hi * 0.01
		lo -= hi * 0.01
	var pad := (hi - lo) * 0.08
	lo -= pad
	hi += pad
	var ticks := _nice_ticks(lo, hi)
	for v in ticks:
		var y := plot.end.y - (float(v) - lo) / (hi - lo) * plot.size.y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), C_GRID, 1)
		_text(Vector2(plot.end.x + 6, y + 5), _price_label(float(v)), 12, C_MUTED)
	for l in labels:
		var t := float(l[0])
		var x := plot.position.x + t * hist_w
		if t < -0.001 or t > 1.001:
			continue
		if t < 0.05:
			_text(Vector2(plot.position.x, r.end.y - 10), String(l[1]), 12, C_MUTED)
		elif t > 0.95 and n_future > 0:
			_text(Vector2(x - 84, r.end.y - 10), String(l[1]), 12, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 80)
		else:
			_text(Vector2(x - 40, r.end.y - 10), String(l[1]), 12, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, 80)
	var to_pt := func(i: float, v: float) -> Vector2:
		var x := plot.position.x + minf(i, nh) / nh * hist_w
		if i > nh:
			x += (i - nh) / float(AHEAD) * (plot.size.x - hist_w)
		return Vector2(x, plot.end.y - (v - lo) / (hi - lo) * plot.size.y)
	# question zone for the hidden month
	if n_future > 0:
		var qx: float = to_pt.call(float(values.size() - 1), lo).x
		var qr := Rect2(qx, plot.position.y, plot.end.x - qx, plot.size.y)
		draw_rect(qr, C_Q)
		draw_dashed_line(Vector2(qx, plot.position.y), Vector2(qx, plot.end.y), Color(1, 1, 1, 0.25), 1.5, 5)
		if future.is_empty():
			_text_c(qr, qr.get_center().y + 14, "?", 40, Color(1, 1, 1, 0.3))
		_text_c(qr, r.end.y - 10, "+1 month", 12, C_MUTED)
	var pts := PackedVector2Array()
	for i in values.size():
		pts.append(to_pt.call(float(i), float(values[i])))
	var fill := pts.duplicate()
	fill.append(Vector2(pts[-1].x, plot.end.y))
	fill.append(Vector2(pts[0].x, plot.end.y))
	draw_colored_polygon(fill, Color(line_color, 0.12))
	draw_polyline(pts, line_color, 2.5, true)
	if not future.is_empty():
		var up: bool = float(future[-1]) >= float(future[0])
		var fc := C_UP if up else C_DOWN
		var steps := (future.size() - 1) * grow
		var fp := PackedVector2Array()
		for i in future.size():
			if i > steps + 0.001:
				var a: Vector2 = to_pt.call(values.size() - 1 + i - 1.0, float(future[i - 1]))
				var b: Vector2 = to_pt.call(values.size() - 1 + float(i), float(future[i]))
				fp.append(a.lerp(b, steps - (i - 1)))
				break
			fp.append(to_pt.call(values.size() - 1 + float(i), float(future[i])))
		if fp.size() >= 2:
			draw_polyline(fp, fc, 3.5, true)
			draw_circle(fp[-1], 5, fc)
		var base_y: float = to_pt.call(0.0, float(future[0])).y
		draw_dashed_line(Vector2(pts[-1].x, base_y), Vector2(plot.end.x, base_y), Color(1, 1, 1, 0.3), 1, 4)
	draw_circle(pts[-1], 4.5, line_color)


func _nice_ticks(lo: float, hi: float) -> Array:
	var span := hi - lo
	var raw := span / 4.0
	var mag := pow(10.0, floorf(log(raw) / log(10.0)))
	var step := mag
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= m * mag:
			step = m * mag
			break
	var out: Array = []
	var v := ceilf(lo / step) * step
	while v <= hi:
		out.append(v)
		v += step
	return out


func _price_label(v: float) -> String:
	if v >= 1000:
		return "$%.1fk" % (v / 1000.0) if fmod(v, 1000.0) != 0 else "$%dk" % int(v / 1000.0)
	if v >= 10:
		return "$%d" % int(round(v))
	if v >= 1:
		return "$%.1f" % v
	return "$%.2f" % v


func _draw_year_end(vs: Vector2) -> void:
	var x := col.position.x
	_text(Vector2(x, 92), "GUESS THE YEAR · #%d" % puzzle_no, 15, C_MUTED)
	_text(Vector2(x, 140), "%d" % year_score(), 52, C_ACCENT)
	_text(Vector2(x + font.get_string_size("%d" % year_score(), HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x + 10, 140),
		"/ %d points" % (ROUNDS * 100), 20, C_MUTED)
	var y := 170.0
	var rh := minf(64.0, (vs.y - y - 90) / ROUNDS)
	for i in year_rounds.size():
		var rr := Rect2(x, y + i * rh, col.size.x, rh - 8)
		_round_rect(rr, C_CARD, 12)
		var rnd: Dictionary = year_rounds[i]
		var si := int(rnd.stock)
		draw_circle(Vector2(rr.position.x + 20, rr.get_center().y), 7, year_mark_color(i) if i < year_guesses.size() else C_GRID)
		_text(Vector2(rr.position.x + 38, rr.get_center().y - 2), String(stocks[si].t), 18)
		_text(Vector2(rr.position.x + 38, rr.get_center().y + 17), String(stocks[si].n), 13, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x * 0.45)
		_draw_spark(Rect2(rr.position.x + rr.size.x * 0.5, rr.position.y + 8, rr.size.x * 0.18, rr.size.y - 16), si, year_range(int(rnd.year)))
		if i < year_guesses.size():
			_text(Vector2(rr.end.x - 154, rr.get_center().y - 2), "%d" % int(rnd.year), 18, C_INK, HORIZONTAL_ALIGNMENT_RIGHT, 140)
			_text(Vector2(rr.end.x - 154, rr.get_center().y + 17), "you %d · +%d" % [int(year_guesses[i]), year_points(int(year_guesses[i]), int(rnd.year))],
				13, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 140)


func _draw_spark(r: Rect2, si: int, rng: Vector2i) -> void:
	var vals := series(si, rng.x, rng.y)
	var lo: float = vals.min()
	var hi: float = maxf(vals.max(), lo + 0.0001)
	var pts := PackedVector2Array()
	for i in vals.size():
		pts.append(Vector2(r.position.x + r.size.x * i / float(vals.size() - 1), r.end.y - (float(vals[i]) - lo) / (hi - lo) * r.size.y))
	draw_polyline(pts, C_UP if vals[-1] >= vals[0] else C_DOWN, 1.5, true)


func _draw_ud_end(vs: Vector2) -> void:
	var x := col.position.x
	var c := cash()
	_text(Vector2(x, 92), "UP OR DOWN · #%d" % puzzle_no, 15, C_MUTED)
	_text(Vector2(x, 140), money(c), 48, C_UP if c >= START_CASH else C_DOWN)
	_text(Vector2(x, 166), "%s from $1,000 · perfect calls all-in: %s" % [pct(c / START_CASH - 1.0), money(best_possible_cash())], 14, C_MUTED)
	var y := 182.0
	var rh := minf(64.0, (vs.y - y - 90) / ROUNDS)
	var results := ud_results()
	for i in ud_rounds.size():
		var rr := Rect2(x, y + i * rh, col.size.x, rh - 8)
		_round_rect(rr, C_CARD, 12)
		var rnd: Dictionary = ud_rounds[i]
		var si := int(rnd.stock)
		var e := int(rnd.end)
		var d1 := week_date(e)
		var ret := ud_return(rnd)
		var right: bool = i < results.size() and results[i].right
		draw_circle(Vector2(rr.position.x + 20, rr.get_center().y), 7, (C_UP if right else C_DOWN) if i < results.size() else C_GRID)
		_text(Vector2(rr.position.x + 38, rr.get_center().y - 2), "%s  %s" % [stocks[si].t, pct(ret)], 18)
		_text(Vector2(rr.position.x + 38, rr.get_center().y + 17), "%s · %s %d" % [stocks[si].n, MONTHS[int(d1.month) - 1], int(d1.year)],
			13, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x * 0.6)
		if i < results.size():
			var res: Dictionary = results[i]
			_text(Vector2(rr.end.x - 154, rr.get_center().y - 2), money(float(res.pnl), true), 18, C_UP if float(res.pnl) >= 0 else C_DOWN, HORIZONTAL_ALIGNMENT_RIGHT, 140)
			_text(Vector2(rr.end.x - 154, rr.get_center().y + 17), "%s · %s" % ["up" if int(ud_bets[i].dir) > 0 else "down", stake_label(float(ud_bets[i].frac))],
				13, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 140)


func _draw_dev(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var c := _dev_card(vs)
	_round_rect(c, Color("101a2c"), 14)
	draw_rect(c, C_ACCENT, false, 1.0)
	var x := c.position.x + 14
	var y := c.position.y + 28
	_text(Vector2(x, y), "DEV  %s  #%d" % [date, puzzle_no], 18, C_ACCENT)
	y += 22
	_text(Vector2(x, y), "seeds  year %d  ud %d" % [seed_for("year", date), seed_for("ud", date)], 12, C_MUTED)
	y += 18
	_text(Vector2(x, y), "screen %s  year %d/%d  ud %d/%d  cash %s" % [Screen.keys()[screen], year_guesses.size(), ROUNDS,
		ud_bets.size(), ROUNDS, money(cash())], 12, C_MUTED)
	y += 22
	var ya := PackedStringArray()
	for r in year_rounds:
		ya.append("%s %d" % [stocks[int(r.stock)].t, int(r.year)])
	_text(Vector2(x, y), "Year: " + ", ".join(ya), 12, C_INK, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 28)
	y += 18
	var ua := PackedStringArray()
	for r in ud_rounds:
		ua.append("%s %s" % [stocks[int(r.stock)].t, pct(ud_return(r))])
	_text(Vector2(x, y), "U/D: " + ", ".join(ua.slice(0, 3)), 12, C_INK, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 28)
	y += 18
	_text(Vector2(x, y), "     " + ", ".join(ua.slice(3)), 12, C_INK, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 28)
	y += 18
	_text(Vector2(x, y), "dev saves are separate from real progress", 12, C_MUTED)
