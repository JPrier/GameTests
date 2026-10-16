class_name PTShare
extends RefCounted
## Spoiler-free result text. One row per guess, one square per friend
## (🟩 happy with that plan, 🟥 vetoed it), so it never says which plan won.

const URL := "https://jprier.github.io/GameTests/plans-tonight/"


static func clock(seconds: int) -> String:
	seconds = maxi(0, seconds)
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func row(p: Dictionary, plan_id: int) -> String:
	var s := ""
	for f in p.friends:
		s += "🟩" if PTRules.friend_ok(p.plans[plan_id], f) else "🟥"
	return s


## guesses: plan ids in order (the last one is the answer when solved).
static func text(p: Dictionary, puzzle_no: int, guesses: Array, hints: int, seconds: int, url := URL) -> String:
	var lines := PackedStringArray()
	lines.append("Plans Tonight? #%d" % puzzle_no)
	var stats := "🍻 %d/%d · ⏱️ %s" % [guesses.size(), p.plans.size(), clock(seconds)]
	if hints > 0:
		stats += " · 💡%d" % hints
	lines.append(stats)
	for g in guesses:
		lines.append(row(p, int(g)))
	lines.append(url)
	return "\n".join(lines)


## Short result for the GameTests home page and the past-days list, e.g. "2/6".
static func label(p: Dictionary, guesses: Array) -> String:
	return "%d/%d" % [guesses.size(), p.plans.size()]
