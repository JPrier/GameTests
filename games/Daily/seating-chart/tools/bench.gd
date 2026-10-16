extends SceneTree
## godot --headless --path . -s tools/bench.gd -- [days] [start-date]
## Generates puzzles for a run of dates and prints timing, tiers and reject reasons.

const G = preload("res://core/generator.gd")
const Daily = preload("res://core/daily.gd")
const D = preload("res://core/difficulty.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 14
	var start := String(args[1]) if args.size() > 1 else "2026-10-12"
	var total_ms := 0
	var worst := 0
	var rejects := {}
	for i in days:
		var d := Daily.add_days(start, i)
		var t0 := Time.get_ticks_msec()
		var gen = G.new()
		var m = gen.generate(d, Daily.tier_for(d))
		var ms := Time.get_ticks_msec() - t0
		total_ms += ms
		worst = maxi(worst, ms)
		for k in gen.stats:
			rejects[k] = int(rejects.get(k, 0)) + int(gen.stats[k])
		if m == null:
			print("%s FAILED" % d)
			continue
		print("%s %-6s tier=%d attempts=%3d clues=%2d at=%d levels=%s score=%d  %d ms" % [
			d, D.tier_name(m.tier), m.tier, m.attempts, m.clues.size(), m.rating.at_table,
			str(m.rating.by_level), m.rating.score, ms])
	print("avg %d ms, worst %d ms" % [total_ms / maxi(days, 1), worst])
	print("rejects: ", rejects)
	quit()
