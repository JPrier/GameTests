extends SceneTree
## Bulk generation audit.
##   godot --headless --path . -s tools/sweep.gd -- [attempts=2000] [first-seed=1]
## Runs generator attempts across all tiers from arbitrary seeds and tallies why attempts were
## rejected (impossible, not deducible, trivial, too easy/hard for the tier ...). Every puzzle it
## accepts is then audited independently:
##   - every clue is well formed and true of the answer
##   - the exhaustive solver finds exactly one answer, and it is the stored one
##   - the logic solver reaches that answer within the tier's level cap
##   - no clue is redundant (dropping any one makes it unsolvable within the cap)
##   - the difficulty rating fits the tier
## Exits with code 1 if any audit fails.

const G = preload("res://core/generator.gd")
const S = preload("res://core/solver.gd")
const L = preload("res://core/logic.gd")
const C = preload("res://core/constraints.gd")
const D = preload("res://core/difficulty.gd")


static func audit(m) -> String:
	var cap := D.cap(m.tier)
	var has_table := false
	for c in m.clues:
		var bad := C.validate(c, m)
		if bad != "":
			return "broken clue: " + bad
		if not C.holds(c, m, m.solution):
			return "clue false of the answer: " + C.text(c, m)
		if String(c.type) == C.AT_TABLE:
			has_table = true
	if not has_table:
		return "no clue names a table"
	var sols := S.solutions(m, m.clues, 2)
	if sols.size() == 0:
		return "impossible"
	if sols.size() > 1:
		return "multiple solutions"
	if sols[0] != m.solution:
		return "stored answer is wrong"
	var lg = L.run(m, m.clues, cap)
	if not lg.is_solved() or lg.solution() != m.solution:
		return "not deducible within cap"
	for i in m.clues.size():
		var fewer: Array = m.clues.duplicate()
		fewer.remove_at(i)
		if L.solvable(m, fewer, cap):
			return "redundant clue: " + C.text(m.clues[i], m)
	var why := D.reject_reason(D.rate(m, m.clues, m.tier))
	if why != "":
		return "rating mismatch: " + why
	return ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 2000
	var first := int(args[1]) if args.size() > 1 else 1
	var verbose := args.size() > 2 and args[2] == "v"
	var only_tier := int(args[3]) if args.size() > 3 else -1
	var gen = G.new()
	var accepted := [0, 0, 0, 0]
	var tried := [0, 0, 0, 0]
	var rejects := {}
	var failures := 0
	var scores := [[], [], [], []]
	var t0 := Time.get_ticks_msec()
	for i in count:
		var tier := i % 4 if only_tier < 0 else only_tier
		var rng := RandomNumberGenerator.new()
		rng.seed = first + i
		tried[tier] += 1
		var ta := Time.get_ticks_msec()
		if verbose:
			printraw("seed %d tier %d ... " % [first + i, tier])
		var m = gen.attempt_puzzle(rng, tier)
		if verbose:
			print("%d ms" % (Time.get_ticks_msec() - ta))
		if m == null:
			var k := "%s: %s" % [D.tier_name(tier), gen.last_reject]
			rejects[k] = int(rejects.get(k, 0)) + 1
			continue
		accepted[tier] += 1
		scores[tier].append(int(m.rating.score))
		var problem := audit(m)
		if problem != "":
			failures += 1
			print("AUDIT FAIL seed=%d tier=%d: %s" % [first + i, tier, problem])
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("%d attempts in %.1f s (%.0f ms each)" % [count, secs, secs * 1000.0 / maxi(count, 1)])
	for t in 4:
		var sc: Array = scores[t]
		sc.sort()
		var med = sc[sc.size() / 2] if not sc.is_empty() else 0
		print("  %-6s accepted %4d / %4d  (%.0f%%)  score median %s range %s-%s" % [D.tier_name(t), accepted[t], tried[t],
			100.0 * accepted[t] / maxi(tried[t], 1), med, sc.min() if not sc.is_empty() else "-", sc.max() if not sc.is_empty() else "-"])
	var keys := rejects.keys()
	keys.sort()
	for k in keys:
		print("  rejected  %-50s %d" % [k, rejects[k]])
	print("audit failures: %d" % failures)
	quit(1 if failures > 0 else 0)
