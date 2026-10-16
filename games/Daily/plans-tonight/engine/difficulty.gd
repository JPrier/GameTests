class_name PTDifficulty
extends RefCounted
## Difficulty comes from how much deduction a puzzle takes, not from obscure rules:
## more plans, more clues, more "near misses" (wrong plans only one clue rules out),
## clues that each rule out little, and clues that need a bit of arithmetic (durations).

const COMPLEXITY := {
	"max_duration": 2.0, "min_duration": 2.0, "min_start": 1.4, "max_start": 1.4, "max_end": 1.4,
	"min_end": 1.4, "max_price": 1.2, "max_travel": 1.2,
}
## Score bands, calibrated against thousands of generated days (see tests/test_fuzz.gd).
const EASY_MAX := 11.5
const MEDIUM_MAX := 15.0
const LABELS := ["Easy", "Medium", "Hard"]


static func rank(label: String) -> int:
	return maxi(0, LABELS.find(label))


static func analyse(p: Dictionary) -> Dictionary:
	var ds := PTValidate.decoys(p)
	var rs := PTValidate.all_rules(p)
	var kills := PTValidate.kill_counts(p)
	var near := 0
	for d in kills:
		if kills[d] == 1:
			near += 1
	var elim_sum := 0.0
	var max_e := 0
	var comp := 0.0
	for e in rs:
		var n := PTValidate.elim(p, e[2]).size()
		elim_sum += n
		max_e = maxi(max_e, n)
		comp += float(COMPLEXITY.get(e[2].type, 1.0))
	var m := maxi(1, rs.size())
	var avg := elim_sum / m / maxf(1.0, ds.size())
	comp /= m
	var score: float = p.plans.size() * 1.0 + rs.size() * 0.5 + near * 0.6 + (1.0 - avg) * 2.5 + (comp - 1.0) * 2.0
	var label := "Easy" if score < EASY_MAX else ("Medium" if score < MEDIUM_MAX else "Hard")
	return {"score": snappedf(score, 0.01), "label": label, "near": near, "clues": rs.size(),
		"avg_elim": snappedf(avg, 0.01), "max_elim": max_e}
