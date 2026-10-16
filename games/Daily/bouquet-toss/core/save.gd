extends RefCounted
## Local persistence (user://, which is IndexedDB on the web).
##   <prefix>day_<date>.json   that day's throws, result and practice count
##   <prefix>results.json      date -> short result label, for the past-days picker
##   <prefix>settings.json     sound on/off, tutorial seen
## Dev mode uses prefix "dev_" so testing never touches the player's real progress.

var prefix := ""


func _init(dev := false) -> void:
	prefix = "dev_" if dev else ""


func day_path(d: String) -> String:
	return "user://%sday_%s.json" % [prefix, d]


func results_path() -> String:
	return "user://%sresults.json" % prefix


static func read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		return null       # corrupt file: ignore it quietly
	return j.data


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


## Day state: {throws: [{a, p, o, acc}], done, result: {throws, accuracy, seconds, outcomes},
##             seconds, practice, aim: [a, p]}
func load_day(d: String) -> Dictionary:
	var data = read_json(day_path(d))
	if not data is Dictionary:
		return {}
	# Sanity: a corrupt or foreign file is ignored rather than trusted.
	if data.has("throws") and not data.throws is Array:
		return {}
	return data


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


func load_settings() -> Dictionary:
	var data = read_json("user://%ssettings.json" % prefix)
	return data if data is Dictionary else {}


func save_settings(s: Dictionary) -> void:
	write_json("user://%ssettings.json" % prefix, s)
