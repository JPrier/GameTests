extends SceneTree
## godot --headless --path . -s tools/calibrate.gd -- 2026-10-16 365
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var start := args[0] if args.size() > 0 else "2026-10-16"
	var days := int(args[1]) if args.size() > 1 else 200
	var t0 := Time.get_ticks_msec()
	var by := {}
	var fails := 0
	var attempts := 0
	var max_ms := 0
	for i in days:
		var d := PTDaily.date_add(start, i)
		var t1 := Time.get_ticks_msec()
		var p := PTGen.generate(d)
		max_ms = maxi(max_ms, Time.get_ticks_msec() - t1)
		if p.is_empty():
			fails += 1
			continue
		attempts += int(p.attempt)
		var cfg := PTDaily.config(d)
		var k := "%d %s" % [PTDaily.weekday(d), cfg.label]
		if not by.has(k):
			by[k] = {"n": 0, "match": 0, "scores": [], "clues": [], "friends": []}
		by[k].n += 1
		by[k].match += 1 if p.difficulty.label == cfg.label else 0
		by[k].scores.append(p.difficulty.score)
		by[k].clues.append(p.difficulty.clues)
		by[k].friends.append(p.friends.size())
	var keys := by.keys()
	keys.sort()
	for k in keys:
		var s: Array = by[k].scores
		s.sort()
		print("%s n=%d match=%d score[min %.1f med %.1f max %.1f] clues avg %.1f friends avg %.1f" % [k, by[k].n, by[k].match, s[0], s[s.size()/2], s[-1], _avg(by[k].clues), _avg(by[k].friends)])
	print("fails=%d avg attempt=%.1f total %d ms, worst day %d ms" % [fails, float(attempts)/days, Time.get_ticks_msec()-t0, max_ms])
	quit()

func _avg(a: Array) -> float:
	var t := 0.0
	for x in a: t += x
	return t / maxf(1, a.size())
