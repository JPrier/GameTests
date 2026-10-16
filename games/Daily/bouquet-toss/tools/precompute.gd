extends SceneTree
## Writes core/attempts.json: for each date, the accepted generator attempt and the
## validator's reference throw, so phones skip the search (see core/levels.gd).
##   godot --headless --path . -s tools/precompute.gd -- [days=420] [start=EPOCH]
## Rerun (and bump Gen.GEN_VERSION) whenever the generator, validator or physics change.

const Levels = preload("res://core/levels.gd")
const Gen = preload("res://core/generator.gd")
const Daily = preload("res://core/daily.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 420
	var d: String = args[1] if args.size() > 1 else Daily.EPOCH
	var days := {}
	var t0 := Time.get_ticks_msec()
	for i in n:
		var lv := Levels.search(d)
		if int(lv.attempt) >= 1000:
			push_error("%s needed the fallback layout" % d)
		days[d] = [int(lv.attempt), int(lv.solution.a), int(lv.solution.p)]
		if i % 25 == 0:
			print("%d/%d %s (%.0f s)" % [i, n, d, (Time.get_ticks_msec() - t0) / 1000.0])
		d = Daily.add_days(d, 1)
	var out := {"gen": Gen.GEN_VERSION, "start": Daily.EPOCH, "days": days}
	var f := FileAccess.open("res://core/attempts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", false))
	f.close()
	print("wrote %d days in %.0f s" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
