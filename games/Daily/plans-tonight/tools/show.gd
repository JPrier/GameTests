extends SceneTree
func _init() -> void:
	for d in OS.get_cmdline_user_args():
		var p := PTGen.generate(d)
		print("\n=== %s #%d %s %s (%s) attempt %d" % [d, PTDaily.day_number(d), PTDaily.pretty(d), p.difficulty.label, p.difficulty.score, p.attempt])
		for f in p.friends:
			print("%s — %s" % [f.name, f.flavor])
			for r in f.rules:
				print("   • ", PTRules.text(r))
		for pl in p.plans:
			print("%s %-18s $%d  %s  %d min  %s  %s  %s  %s" % ["★" if pl.id == p.target else " ", pl.name, pl.price, PTRules.time_range(pl), pl.travel, pl.setting, pl.noise, pl.activity, pl.food if pl.food != "" else "no food"])
			if pl.id != p.target:
				for fi in p.friends.size():
					for ri in PTRules.broken(pl, p.friends[fi]):
						print("      ✗ %s: %s" % [p.friends[fi].name, PTRules.reason(pl, p.friends[fi].rules[ri])])
	quit()
