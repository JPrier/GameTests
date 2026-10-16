class_name PTSave
extends RefCounted
## Turns a day's progress into JSON-safe data and back. A save only restores onto the exact
## puzzle it was made for (checked with a signature), so a generator change can't corrupt it.

const VERSION := 1


static func signature(p: Dictionary) -> String:
	var core := {"plans": p.plans, "target": p.target, "rules": []}
	for f in p.friends:
		core.rules.append(f.rules)
	return str(hash(JSON.stringify(core)))


static func fresh() -> Dictionary:
	return {"guesses": [], "hints": 0, "hint_plan": -1, "hint_conflict": {}, "crossed": [],
		"seconds": 0.0, "done": false}


static func encode(p: Dictionary, st: Dictionary) -> Dictionary:
	return {
		"v": VERSION, "sig": signature(p), "guesses": st.guesses, "hints": st.hints,
		"hint_plan": st.hint_plan, "hint_conflict": st.hint_conflict, "crossed": st.crossed,
		"seconds": snappedf(float(st.seconds), 0.1), "done": st.done,
	}


## Returns a clean state, or fresh() if the data doesn't belong to this puzzle.
static func decode(p: Dictionary, data) -> Dictionary:
	var st := fresh()
	if not data is Dictionary or int(data.get("v", 0)) != VERSION or String(data.get("sig", "")) != signature(p):
		return st
	var n: int = p.plans.size()
	for g in data.get("guesses", []):
		var id := int(g)
		if id >= 0 and id < n and not st.guesses.has(id) and not st.done:
			st.guesses.append(id)
			if id == int(p.target):
				st.done = true
	st.hints = clampi(int(data.get("hints", 0)), 0, PTHints.MAX)
	var hp := int(data.get("hint_plan", -1))
	st.hint_plan = hp if hp >= 0 and hp < n and hp != int(p.target) else -1
	var hc = data.get("hint_conflict", {})
	if hc is Dictionary and hc.has("plan") and hc.has("friend") and hc.has("rule"):
		var cp := int(hc.plan)
		var cf := int(hc.friend)
		var cr := int(hc.rule)
		if cp >= 0 and cp < n and cf >= 0 and cf < p.friends.size() and cr >= 0 \
				and cr < p.friends[cf].rules.size() and not PTRules.does(p.plans[cp], p.friends[cf].rules[cr]):
			st.hint_conflict = {"plan": cp, "friend": cf, "rule": cr}
	for c in data.get("crossed", []):
		var id := int(c)
		if id >= 0 and id < n and not st.crossed.has(id):
			st.crossed.append(id)
	st.seconds = maxf(0.0, float(data.get("seconds", 0.0)))
	return st
