extends SceneTree
## Audits the drink database as a deduction game and prints a report.
##   godot --headless --path . -s tools/analyze.gd
## Exit code 1 when the database has errors or indistinguishable drinks.

const DB = preload("res://core/db.gd")
const Schema = preload("res://core/schema.gd")
const Analysis = preload("res://core/analysis.gd")


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var bad := false
	print("Drinks: %d (%d allowed as answers)" % [DB.size(), DB.targets().size()])
	var errs := DB.validate()
	for e in errs:
		print("  ERROR ", e)
	bad = bad or not errs.is_empty()
	var dups := Analysis.duplicates()
	print("Indistinguishable groups: %d" % dups.size())
	for g in dups:
		print("  DUPLICATE ", g)
	bad = bad or not dups.is_empty()
	var near := Analysis.near_pairs(1)
	print("Pairs differing in one attribute: %d" % near.size())
	for p in near:
		print("  %-18s / %-18s  only %s" % [DB.name_of(p.a), DB.name_of(p.b), ", ".join(p.diff)])
	print("\nOpening guess a perfect player would make: %s" % Analysis.best_guess(DB.all()).name)
	print("\n%-18s %5s %5s %6s %6s %5s  %s" % ["Drink", "score", "steps", "avg1", "single", "crowd", "verdict"])
	var rows: Array = []
	for d in DB.all():
		var df := Analysis.difficulty(d)
		var el := Analysis.eligibility(d)
		rows.append([df.score, d, df, el])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	var counts := [0, 0, 0]
	for r in rows:
		var d: Dictionary = r[1]
		var df: Dictionary = r[2]
		var el: Dictionary = r[3]
		var verdict: String = Analysis.TIERS[df.tier] if el.ok else "not an answer: " + "; ".join(el.reasons)
		if el.ok:
			counts[df.tier] += 1
		print("%-18s %5d %5d %6.1f %6.2f %5d  %s" % [d.name, df.score, df.steps, df.avg_left, df.single, df.crowd, verdict])
	print("\nAnswer pools: Easy %d, Medium %d, Hard %d" % counts)
	print("Done in %d ms" % (Time.get_ticks_msec() - t0))
	quit(1 if bad else 0)
