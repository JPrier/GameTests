extends SceneTree
## Times level generation + validation for a run of dates.
##   godot --headless --path . -s tools/bench.gd -- [days=14] [start=2026-10-16]

const Levels = preload("res://core/levels.gd")
const V = preload("res://core/validator.gd")
const Daily = preload("res://core/daily.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 14
	var d: String = args[1] if args.size() > 1 else Daily.EPOCH
	var total := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		var lv := Levels.search(d)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		print("%s %-10s attempt %2d  rate %.3f robust %d routes %s  %.0f ms" % [d, lv.archetype, lv.attempt, lv.stats.rate, lv.stats.robust, ",".join(lv.stats.routes), ms])
		d = Daily.add_days(d, 1)
	print("avg %.0f ms" % (total / n))
	quit()
