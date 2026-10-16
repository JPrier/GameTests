extends RefCounted
## Local persistence (user://, which is IndexedDB on the web).
##   <prefix>day_<date>.json   board + timer + counters for one day
##   <prefix>results.json      date -> short result label, for the past-days picker
##   puzzle_v<N>_<date>.json   cached generated puzzle (same for everyone; skips regenerating)
## Dev mode uses prefix "dev_" so testing never touches the player's real progress.

const Gen = preload("res://core/generator.gd")   # cache key follows Gen.GEN_VERSION

var prefix := ""


func _init(dev := false) -> void:
	prefix = "dev_" if dev else ""


func day_path(d: String) -> String:
	return "user://%sday_%s.json" % [prefix, d]


func results_path() -> String:
	return "user://%sresults.json" % prefix


static func puzzle_path(d: String) -> String:
	return "user://puzzle_v%d_%s.json" % [Gen.GEN_VERSION, d]


static func read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
	flush()


static func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	flush()


## The web build syncs user:// to IndexedDB when a file is closed; touching a small file makes
## sure removals are written out too.
static func flush() -> void:
	var f := FileAccess.open("user://.sync", FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


func load_day(d: String) -> Dictionary:
	var data = read_json(day_path(d))
	return data if data is Dictionary else {}


func save_day(d: String, data: Dictionary) -> void:
	write_json(day_path(d), data)


func wipe_day(d: String) -> void:
	remove(day_path(d))
	var all := load_results()
	if all.has(d):
		all.erase(d)
		write_json(results_path(), all)


func load_results() -> Dictionary:
	var data = read_json(results_path())
	return data if data is Dictionary else {}


func record_result(d: String, label: String) -> void:
	var all := load_results()
	if String(all.get(d, "")) == label:
		return
	all[d] = label
	write_json(results_path(), all)


func wipe_all() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with(prefix + "day_") or f == prefix + "results.json":
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
	flush()


static func load_cached_puzzle(d: String):
	var data = read_json(puzzle_path(d))
	return data if data is Dictionary else null


static func cache_puzzle(d: String, data: Dictionary) -> void:
	write_json(puzzle_path(d), data)
