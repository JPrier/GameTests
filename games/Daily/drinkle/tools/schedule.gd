extends SceneTree
## Pins daily answers in data/schedule.json so past puzzles never change when drinks are added.
##   godot --headless --path . -s tools/schedule.gd -- [days=1100] [keep_before=YYYY-MM-DD]
## Dates before keep_before (default: today) keep the answer already in the file; every later
## date (up to puzzle #1 + days) is recomputed with the current database and tier pools.
## Also records the tier pools and each answer's difficulty so phones never run the analyser.

const DB = preload("res://core/db.gd")
const Analysis = preload("res://core/analysis.gd")
const Daily = preload("res://core/daily.gd")

const OUT := "res://data/schedule.json"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 1100
	var keep_before := String(args[1]) if args.size() > 1 else Daily.today_local()
	var old := {}
	if FileAccess.file_exists(OUT):
		var data = JSON.parse_string(FileAccess.get_file_as_string(OUT))
		if data is Dictionary and data.get("days") is Dictionary:
			old = data.days
	# compute pools fresh (ignore any pinned pools)
	var pools := Analysis.tier_pools()
	Daily.reset_cache()
	Daily._pools = pools
	Daily._schedule = {}
	Daily._schedule_loaded = true
	var diff := {}
	for t in pools.size():
		for id in pools[t]:
			var df := Analysis.difficulty(DB.get_drink(id))
			diff[id] = {"score": df.score, "tier": df.tier}
	var out_days := {}
	var kept := 0
	var changed := 0
	for i in days:
		var d := Daily.add_days(Daily.EPOCH, i)
		if d < keep_before and old.has(d) and DB.has(String(old[d])):
			out_days[d] = String(old[d])
			kept += 1
		else:
			out_days[d] = Daily.computed_target(d)
			if old.has(d) and String(old[d]) != out_days[d]:
				changed += 1
	var doc := {
		"about": "Pinned daily answers (tools/schedule.gd). Past dates must never change.",
		"fingerprint": DB.fingerprint(),
		"pools": pools,
		"difficulty": diff,
		"days": out_days,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t", false))
	f.close()
	print("schedule: %d days from %s, kept %d pinned, changed %d future, pools %d/%d/%d" % [
		days, Daily.EPOCH, kept, changed, pools[0].size(), pools[1].size(), pools[2].size()])
	quit()
