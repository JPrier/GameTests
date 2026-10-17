extends SceneTree
## Writes core/attempts.json: for each date, each of its throws' accepted generator attempt
## and the validator's reference throw, so phones skip the search (see core/levels.gd).
##   godot --headless --path . -s tools/precompute.gd -- [days=400] [start=EPOCH] [out=res://core/attempts.json]
## Long runs can be split into shards (different start/out) and merged: entries are
## independent per date. Any existing days in `out` are kept unless recomputed.
## Rerun (and bump Gen.GEN_VERSION) whenever the generator, validator or physics change.

const Levels = preload("res://core/levels.gd")
const Gen = preload("res://core/generator.gd")
const Daily = preload("res://core/daily.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 400
	var d: String = args[1] if args.size() > 1 else Daily.EPOCH
	var out_path: String = args[2] if args.size() > 2 else "res://core/attempts.json"
	var days := {}
	var t0 := Time.get_ticks_msec()
	for i in n:
		var row: Array = []
		for hole in Daily.HOLES:
			var lv := Levels.search(d, hole)
			if int(lv.attempt) >= 1000:
				push_error("%s throw %d needed the fallback layout" % [d, hole + 1])
			row.append([int(lv.attempt), int(lv.solution.a), int(lv.solution.p)])
		days[d] = row
		if i % 10 == 0:
			print("%d/%d %s (%.0f s)" % [i, n, d, (Time.get_ticks_msec() - t0) / 1000.0])
		d = Daily.add_days(d, 1)
	var existing := {}
	if FileAccess.file_exists(out_path):
		var old = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		if old is Dictionary and int(old.get("gen", -1)) == Gen.GEN_VERSION:
			existing = old.get("days", {})
	existing.merge(days, true)
	var keys := existing.keys()
	keys.sort()
	var ordered := {}
	for k in keys:
		ordered[k] = existing[k]
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"gen": Gen.GEN_VERSION, "start": Daily.EPOCH, "days": ordered}, "", false))
	f.close()
	print("wrote %d days in %.0f s" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
