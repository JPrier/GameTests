extends RefCounted
## Difficulty tiers and the rating of a puzzle from its logical solve.
##
## A puzzle's difficulty comes from the hardest kind of reasoning it needs (see logic.gd
## levels) and how often, not from its size: every MVP puzzle has 10 guests at 2 tables of 5.

const L = preload("res://core/logic.gd")

const NAMES := ["Easy", "Medium", "Tricky", "Hard"]

## cap: the hardest logic level the puzzle may need.
## weights: how often each clue type is drawn while building the clue set.
## max_at: most "X sits at Table N" clues (direct placements).
const TIERS := [
	{"cap": 2, "max_at": 4, "weights": {"adjacent": 5, "not_adjacent": 2, "same_table": 3, "different_table": 3, "at_table": 4}},
	{"cap": 3, "max_at": 3, "weights": {"adjacent": 4, "not_adjacent": 3, "same_table": 3, "different_table": 3, "at_table": 2}},
	{"cap": 3, "max_at": 2, "weights": {"adjacent": 3, "not_adjacent": 3, "same_table": 3, "different_table": 6, "at_table": 1}},
	{"cap": 4, "max_at": 1, "weights": {"adjacent": 3, "not_adjacent": 5, "same_table": 3, "different_table": 5, "at_table": 0}},
]

const LEVEL_WEIGHT := [0, 1, 2, 4, 10]
const MIN_CLUES := 6
const MAX_CLUES := 18


static func tier_name(t: int) -> String:
	return NAMES[clampi(t, 0, NAMES.size() - 1)]


static func cap(t: int) -> int:
	return int(TIERS[t].cap)


## Full rating of a clue set: logic summary at the tier cap plus whether it falls to one level
## less (too easy for the tier). score = weighted sum of deductions.
static func rate(m, clues: Array, tier: int) -> Dictionary:
	var c := cap(tier)
	var full = L.run(m, clues, 4)
	var s: Dictionary = full.summary()
	var score := 0
	for lv in 5:
		score += LEVEL_WEIGHT[lv] * int(s.by_level[lv])
	var easier := false
	if c > 1:
		easier = L.solvable(m, clues, c - 1)
	var at_count := 0
	for cl in clues:
		if String(cl.type) == "at_table":
			at_count += 1
	return {"solved": s.solved, "max_level": s.max_level, "by_level": s.by_level, "score": score,
		"falls_to_lower": easier, "clues": clues.size(), "at_table": at_count, "tier": tier}


## Why a rated puzzle doesn't fit its tier ("" = it fits).
static func reject_reason(r: Dictionary) -> String:
	var tier: int = r.tier
	var bl: Array = r.by_level
	if not r.solved:
		return "not logically solvable"
	if int(r.clues) < MIN_CLUES:
		return "trivial: too few clues"
	if int(r.clues) > MAX_CLUES:
		return "too many clues"
	if int(r.max_level) > cap(tier):
		return "too hard for tier"
	if int(r.at_table) > int(TIERS[tier].max_at):
		return "too many direct placements"
	match tier:
		0:
			if int(bl[1]) + int(bl[2]) < 3:
				return "trivial: nothing to deduce"
		1:
			if r.falls_to_lower:
				return "too easy for tier"
			if int(bl[3]) < 1 or int(bl[3]) > 6:
				return "wrong amount of indirect reasoning"
		2:
			if r.falls_to_lower:
				return "too easy for tier"
			if int(bl[3]) < 2:
				return "not enough overlapping reasoning"
		3:
			if r.falls_to_lower:
				return "too easy for tier"
			if int(bl[4]) < 1 or int(bl[4]) > 3:
				return "wrong amount of what-if reasoning"
	return ""
