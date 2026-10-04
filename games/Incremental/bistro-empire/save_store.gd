class_name SaveStore
extends RefCounted
## Belt-and-braces saving for Bistro Empire.
##
## Every save is written to two independent places:
##   1. user://bistro_empire.json  (Godot's file system; IndexedDB on the web, flushed asynchronously)
##   2. localStorage["bistro-empire:save"]  (web only; synchronous, so it survives the tab being killed)
## plus a rolling backup of each, refreshed at most every BACKUP_EVERY seconds, so a bad write
## can never take out every copy at once.
##
## Each copy is wrapped as {"game","v","t","sum","data"} where data is the game state as a JSON
## string and sum is its hash. A copy that fails to parse or whose hash doesn't match is ignored.
## On load the newest valid copy wins. Version-1 saves (a bare state dictionary) still load.
##
## IMPORTANT for future builds: user:// on the web is keyed by the project name, so never rename
## application/config/name in project.godot. The localStorage copies don't depend on it.

const GAME := "bistro-empire"
const VERSION := 2
const FILE := "user://bistro_empire.json"
const FILE_BAK := "user://bistro_empire.bak.json"
const LS_KEY := "bistro-empire:save"
const LS_BAK := "bistro-empire:backup"
const LS_PRE_IMPORT := "bistro-empire:before-import"
const BACKUP_EVERY := 120.0
const CODE_PREFIX := "BISTRO1:"

var web := OS.has_feature("web")
## Off the web there is no localStorage; tests (and desktop runs) emulate it with files.
var fake_ls_dir := "user://"
var last_backup_t := -1e9
var last_write_ok := false
var last_places := 0


# ------------------------------------------------------------------ wrapping

static func pack(state: Dictionary, t: int) -> String:
	var data := JSON.stringify(state)
	return JSON.stringify({"game": GAME, "v": VERSION, "t": t, "sum": str(data.hash()), "data": data})


## Returns {"state": Dictionary, "t": int} for a valid save text, or {} if it's unusable.
static func _parse(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


static func unpack(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var w = _parse(text)
	if not w is Dictionary:
		return {}
	if w.has("data"):
		if String(w.get("game", "")) != GAME:
			return {}
		var data := String(w.get("data", ""))
		if str(data.hash()) != String(w.get("sum", "")):
			return {}
		var s = _parse(data)
		if not s is Dictionary:
			return {}
		return {"state": s, "t": int(w.get("t", 0))}
	# version 1: the bare state dictionary with "t" inside it
	if w.has("cash") and w.has("reps"):
		return {"state": w, "t": int(w.get("t", 0))}
	return {}


# ------------------------------------------------------------------ export codes

static func encode_code(text: String) -> String:
	var raw := text.to_utf8_buffer()
	return CODE_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))


static func decode_code(code: String) -> String:
	code = code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	if not code.begins_with(CODE_PREFIX):
		return ""
	var raw := Marshalls.base64_to_raw(code.substr(CODE_PREFIX.length()))
	if raw.is_empty():
		return ""
	var out := raw.decompress_dynamic(32 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	return out.get_string_from_utf8()


# ------------------------------------------------------------------ storage primitives

func _file_write(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	# verify before swapping in, so a failed write never replaces a good save
	if FileAccess.get_file_as_string(tmp) != text:
		return false
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		var g := FileAccess.open(path, FileAccess.WRITE)
		if g == null:
			return false
		g.store_string(text)
		g.close()
	return true


func _file_read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _ls_set(key: String, text: String) -> bool:
	if web:
		var r = JavaScriptBridge.eval("(function(k,v){try{localStorage.setItem(k,v);return localStorage.getItem(k)===v?'ok':'bad';}catch(e){return 'err';}})(%s,%s)" % [JSON.stringify(key), JSON.stringify(text)], true)
		return r is String and r == "ok"
	return _file_write(fake_ls_dir + "ls_" + key.replace(":", "_") + ".txt", text)


func _ls_get(key: String) -> String:
	if web:
		var r = JavaScriptBridge.eval("(function(k){try{return localStorage.getItem(k)||'';}catch(e){return '';}})(%s)" % JSON.stringify(key), true)
		return r if r is String else ""
	return _file_read(fake_ls_dir + "ls_" + key.replace(":", "_") + ".txt")


func _ls_remove(key: String) -> void:
	if web:
		JavaScriptBridge.eval("(function(k){try{localStorage.removeItem(k);}catch(e){}})(%s)" % JSON.stringify(key), true)
	else:
		var p := fake_ls_dir + "ls_" + key.replace(":", "_") + ".txt"
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ------------------------------------------------------------------ public API

## Writes the state everywhere. Returns how many places took it (0-2).
func write(state: Dictionary, t: int, now: float) -> int:
	var text := pack(state, t)
	# refresh the rolling backups from the *current* good copies before overwriting them
	if now - last_backup_t >= BACKUP_EVERY:
		last_backup_t = now
		var cur := _file_read(FILE)
		if not unpack(cur).is_empty():
			_file_write(FILE_BAK, cur)
		var cur_ls := _ls_get(LS_KEY)
		if not unpack(cur_ls).is_empty():
			_ls_set(LS_BAK, cur_ls)
	var n := 0
	if _file_write(FILE, text):
		n += 1
	if _ls_set(LS_KEY, text):
		n += 1
	# a second tiny file write nudges the web build to flush to IndexedDB promptly
	var s := FileAccess.open("user://.sync", FileAccess.WRITE)
	if s:
		s.store_string(str(t))
		s.close()
	last_write_ok = n > 0
	last_places = n
	return n


## Every copy found, valid or not: [{src, text, ok, state, t}]
func candidates() -> Array:
	var out: Array = []
	for src in ["file", "local", "file_backup", "local_backup"]:
		var text := ""
		match src:
			"file": text = _file_read(FILE)
			"local": text = _ls_get(LS_KEY)
			"file_backup": text = _file_read(FILE_BAK)
			"local_backup": text = _ls_get(LS_BAK)
		if text == "":
			continue
		var u := unpack(text)
		out.append({"src": src, "text": text, "ok": not u.is_empty(), "state": u.get("state", {}), "t": int(u.get("t", 0))})
	return out


## The newest valid copy: {src, state, t} or {} when there is none.
func best() -> Dictionary:
	var pick := {}
	for c in candidates():
		if not c.ok:
			continue
		if pick.is_empty() or int(c.t) > int(pick.t) or (int(c.t) == int(pick.t) and _life_l(c.state) > _life_l(pick.state)):
			pick = c
	return pick


## Lifetime earnings of a saved state, as a log (older saves stored a plain number).
static func _life_l(st: Dictionary) -> float:
	if st.has("life_l"):
		return float(st.life_l)
	return Num.L(float(st.get("life_earned", 0.0)))


## True when something was saved but none of it can be read.
func all_corrupt() -> bool:
	var c := candidates()
	if c.is_empty():
		return false
	for x in c:
		if x.ok:
			return false
	return true


## Keeps unreadable copies aside instead of letting a new game overwrite them.
func quarantine(t: int) -> void:
	for c in candidates():
		if not c.ok:
			_file_write("user://bistro_empire.corrupt-%s-%d.json" % [c.src, t], String(c.text))


func keep_before_import(text: String) -> void:
	_ls_set(LS_PRE_IMPORT, text)
	_file_write("user://bistro_empire.before-import.json", text)


func erase_all() -> void:
	for p in [FILE, FILE_BAK]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_ls_remove(LS_KEY)
	_ls_remove(LS_BAK)
	last_backup_t = -1e9


## Ask the browser not to evict our storage under pressure (best effort, silently ignored if refused).
func request_persistence() -> void:
	if web:
		JavaScriptBridge.eval("try{if(navigator.storage&&navigator.storage.persist){navigator.storage.persist().then(function(p){window.__bePersist=p;});}}catch(e){}", true)


func persisted() -> String:
	if not web:
		return "n/a"
	var r = JavaScriptBridge.eval("(function(){return window.__bePersist===true?'yes':(window.__bePersist===false?'no':'?');})()", true)
	return r if r is String else "?"
