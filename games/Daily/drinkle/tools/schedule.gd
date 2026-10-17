extends SceneTree
## Pins daily answers in data/schedule.json so past puzzles never change when drinks are added.
##   godot --headless --path . -s tools/schedule.gd -- [days=1100] [keep_before=YYYY-MM-DD]
## Dates before keep_before keep the answer already in the file (default: two days after today,
## so every time zone's "today" is covered while the change is reviewed and deployed). Every
## later date, up to puzzle #1 + days, is recomputed from the current database and tier pools.
## The rotation salt is the first one that never repeats an answer within MIN_GAP days, counting
## the kept dates too. Also records the tier pools and each drink's difficulty so phones never
## run the analyser.

const DB = preload("res://core/db.gd")
const Analysis = preload("res://core/analysis.gd")
const Daily = preload("res://core/daily.gd")

const OUT := "res://data/schedule.json"
const MIN_GAP := 14


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 1100
	var keep_before := String(args[1]) if args.size() > 1 else Daily.add_days(Daily.today_local(), 2)
	var old := {}
	var old_doc := {}
	if FileAccess.file_exists(OUT):
		var data = JSON.parse_string(FileAccess.get_file_as_string(OUT))
		if data is Dictionary:
			old_doc = data
			if data.get("days") is Dictionary:
				old = data.days
	# a later run never un-pins what an earlier run pinned
	var prev_pin := String(old_doc.get("pinned_before", Daily.EPOCH))
	if prev_pin > keep_before:
		keep_before = prev_pin
	Analysis.clear_cache()
	var pools := Analysis.tier_pools()
	var diff := {}
	for d in DB.all():
		var df := Analysis.difficulty(d)
		diff[d.id] = {"score": df.score, "tier": df.tier}
	var kept := {}
	for i in days:
		var d := Daily.add_days(Daily.EPOCH, i)
		if d < keep_before and old.has(d) and DB.has(String(old[d])):
			kept[d] = String(old[d])
	var salt := -1
	var out_days := {}
	for s in 200:
		out_days = _build(days, kept, pools, s)
		if _min_gap(out_days, days) >= MIN_GAP:
			salt = s
			break
	if salt < 0:
		push_error("no rotation salt avoids repeats within %d days" % MIN_GAP)
		quit(1)
		return
	var changed := 0
	for d in out_days:
		if old.has(d) and String(old[d]) != out_days[d]:
			changed += 1
	var doc := {
		"about": "Pinned daily answers (tools/schedule.gd). Dates before pinned_before never change.",
		"fingerprint": DB.fingerprint(),
		"pinned_before": keep_before,
		"salt": salt,
		"pools": pools,
		"difficulty": diff,
		"days": out_days,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t", false))
	f.close()
	print("schedule: %d days from %s, kept %d before %s, changed %d later, salt %d, pools %d/%d/%d" % [
		days, Daily.EPOCH, kept.size(), keep_before, changed, salt, pools[0].size(), pools[1].size(), pools[2].size()])
	quit()


func _build(days: int, kept: Dictionary, pools: Array, salt: int) -> Dictionary:
	Daily.reset_cache()
	Daily._schedule_loaded = true
	Daily._file = {"salt": salt}
	Daily._pools = pools
	var out := {}
	for i in days:
		var d := Daily.add_days(Daily.EPOCH, i)
		out[d] = kept[d] if kept.has(d) else Daily.computed_target(d)
	return out


func _min_gap(sched: Dictionary, days: int) -> int:
	var last := {}
	var best := 1 << 30
	for i in days:
		var id: String = sched[Daily.add_days(Daily.EPOCH, i)]
		if last.has(id):
			best = mini(best, i - int(last[id]))
		last[id] = i
	return best
