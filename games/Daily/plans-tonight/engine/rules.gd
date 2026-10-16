class_name PTRules
extends RefCounted
## Constraint model + evaluator. A rule is plain data: {"type": String, "v": Variant}.
## Every check is a pure function of (plan, rule) so the same evaluator can later run on
## constraints typed in by a real friend group.
##
## A plan is plain data too:
##   {id, name, icon, activity, food ("" = no real food), price, start, end (minutes after
##    midnight), travel (minutes), setting ("indoor"/"outdoor"), noise ("quiet"/"lively"/"loud")}

const TYPES := [
	"max_price", "min_start", "max_start", "max_end", "min_end", "max_travel",
	"setting", "wants_food", "no_food_type", "no_activity", "not_loud", "not_quiet",
	"max_duration", "min_duration",
]

## Which card fact a rule talks about (used for the matching icon on rules and cards).
const TOPIC := {
	"max_price": "price", "min_start": "time", "max_start": "time", "max_end": "time",
	"min_end": "time", "max_travel": "travel", "setting": "setting", "wants_food": "food",
	"no_food_type": "food", "no_activity": "activity", "not_loud": "noise", "not_quiet": "noise",
	"max_duration": "time", "min_duration": "time",
}


static func duration(plan: Dictionary) -> int:
	return int(plan.end) - int(plan.start)


## The core question: does this plan satisfy this rule?
static func does(plan: Dictionary, rule: Dictionary) -> bool:
	var v = rule.get("v")
	match String(rule.type):
		"max_price": return int(plan.price) <= int(v)
		"min_start": return int(plan.start) >= int(v)
		"max_start": return int(plan.start) <= int(v)
		"max_end": return int(plan.end) <= int(v)
		"min_end": return int(plan.end) >= int(v)
		"max_travel": return int(plan.travel) <= int(v)
		"setting": return String(plan.setting) == String(v)
		"wants_food": return String(plan.food) != ""
		"no_food_type": return String(plan.food) != String(v)
		"no_activity": return String(plan.activity) != String(v)
		"not_loud": return String(plan.noise) != "loud"
		"not_quiet": return String(plan.noise) != "quiet"
		"max_duration": return duration(plan) <= int(v)
		"min_duration": return duration(plan) >= int(v)
	push_error("unknown rule type %s" % rule.type)
	return false


## A friend is happy with a plan when it passes every one of their rules.
static func friend_ok(plan: Dictionary, friend: Dictionary) -> bool:
	for r in friend.rules:
		if not does(plan, r):
			return false
	return true


## Rules (as indices into friend.rules) that the plan breaks.
static func broken(plan: Dictionary, friend: Dictionary) -> Array:
	var out: Array = []
	for i in friend.rules.size():
		if not does(plan, friend.rules[i]):
			out.append(i)
	return out


# ---------------------------------------------------------------- formatting

static func clock(m: int) -> String:
	m = posmod(m, 24 * 60)
	if m == 0:
		return "midnight"
	var h := int(m / 60)
	var mm := m % 60
	var suffix := "pm" if h >= 12 else "am"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	if mm == 0:
		return "%d%s" % [h12, suffix]
	return "%d:%02d%s" % [h12, mm, suffix]


## Card time range, e.g. "7:30–9:30pm" (suffix shown once when both ends share it).
static func time_range(plan: Dictionary) -> String:
	var a := clock(int(plan.start))
	var b := clock(int(plan.end))
	if a.ends_with("pm") and b.ends_with("pm"):
		a = a.substr(0, a.length() - 2)
	return "%s–%s" % [a, b]


static func hours(m: int) -> String:
	match m:
		60: return "1 hour"
		90: return "1½ hours"
		120: return "2 hours"
		150: return "2½ hours"
		180: return "3 hours"
		210: return "3½ hours"
		240: return "4 hours"
	return "%d min" % m


static func noise_label(n: String) -> String:
	match n:
		"quiet": return "Quiet"
		"lively": return "Lively"
		"loud": return "Loud"
	return n.capitalize()


static func a_an(word: String) -> String:
	var w := word.to_lower()
	return ("an " if w.length() > 0 and "aeiou".contains(w[0]) else "a ") + word


## The rule as a friend would say it. Always states the exact value it checks.
static func text(rule: Dictionary) -> String:
	var v = rule.get("v")
	match String(rule.type):
		"max_price": return "Won't spend more than $%d" % int(v)
		"min_start": return "Can't get there before %s" % clock(int(v))
		"max_start": return "Wants to get going by %s at the latest" % clock(int(v))
		"max_end": return "Has to head home by %s" % clock(int(v))
		"min_end": return "Refuses to call it a night before %s" % clock(int(v))
		"max_travel": return "Won't travel more than %d minutes" % int(v)
		"setting":
			return "Wants to be outdoors" if String(v) == "outdoor" else "Wants to stay indoors"
		"wants_food": return "Wants real food, not just drinks or snacks"
		"no_food_type": return "Won't eat %s" % food_word(String(v))
		"no_activity":
			if String(v) == "Dinner":
				return "Isn't in the mood for a sit-down dinner"
			return "Refuses to %s again" % String(ACTIVITY_VERB.get(String(v), "do " + String(v).to_lower()))
		"not_loud": return "Can't handle anywhere loud"
		"not_quiet": return "Refuses anywhere quiet"
		"max_duration": return "Can only stay out for %s, tops" % hours(int(v))
		"min_duration": return "Wants at least %s out" % hours(int(v))
	return String(rule.type)


## Why a specific plan breaks a rule, e.g. "$32, over the $30 limit".
static func reason(plan: Dictionary, rule: Dictionary) -> String:
	var v = rule.get("v")
	match String(rule.type):
		"max_price": return "$%d is over the $%d limit" % [int(plan.price), int(v)]
		"min_start": return "Starts at %s, before %s" % [clock(int(plan.start)), clock(int(v))]
		"max_start": return "Doesn't start until %s" % clock(int(plan.start))
		"max_end": return "Runs until %s, past %s" % [clock(int(plan.end)), clock(int(v))]
		"min_end": return "Ends at %s, too early" % clock(int(plan.end))
		"max_travel": return "%d min away, more than %d" % [int(plan.travel), int(v)]
		"setting": return "It's %s" % ("indoors" if String(plan.setting) == "indoor" else "outdoors")
		"wants_food": return "No real food there"
		"no_food_type": return "It's %s" % food_word(String(plan.food))
		"no_activity":
			if String(v) == "Dinner":
				return "It's a sit-down dinner"
			return "It's %s" % String(ACTIVITY_NOUN.get(String(plan.activity), String(plan.activity).to_lower()))
		"not_loud": return "Too loud to talk"
		"not_quiet": return "Too quiet"
		"max_duration": return "Runs %s" % hours(duration(plan))
		"min_duration": return "Only %s" % hours(duration(plan))
	return "Doesn't work"


const ACTIVITY_VERB := {
	"Bowling": "go bowling", "Movie": "see a movie", "Karaoke": "do karaoke", "Trivia night": "do trivia night",
	"Comedy show": "sit through a comedy show", "Escape room": "do an escape room", "Mini golf": "play mini golf",
	"Bar": "go to a bar", "Wine bar": "go to a wine bar", "Brewery": "go to a brewery",
	"Board games": "play board games", "Live music": "see live music", "Arcade": "go to an arcade",
	"Axe throwing": "go axe throwing", "Climbing": "go climbing", "Night market": "do a night market",
	"Picnic": "do a picnic", "Ice skating": "go ice skating", "Paint & sip": "do paint & sip",
}
const ACTIVITY_NOUN := {
	"Bowling": "bowling", "Movie": "a movie", "Karaoke": "karaoke", "Trivia night": "trivia night",
	"Comedy show": "a comedy show", "Escape room": "an escape room", "Mini golf": "mini golf", "Bar": "a bar",
	"Wine bar": "a wine bar", "Brewery": "a brewery", "Board games": "board games", "Live music": "live music",
	"Arcade": "an arcade", "Axe throwing": "axe throwing", "Climbing": "climbing", "Night market": "a night market",
	"Picnic": "a picnic", "Ice skating": "ice skating", "Paint & sip": "paint & sip",
}


static func food_word(f: String) -> String:
	return f if f == "BBQ" else f.to_lower()


# ---------------------------------------------------------------- contradictions

## True when no plan could ever satisfy both rules (regardless of the plans on offer).
## Used by the validator, and later to tell a real group which two people can't both be happy.
static func contradicts(a: Dictionary, b: Dictionary) -> bool:
	return _contra(a, b) or _contra(b, a)


static func _contra(a: Dictionary, b: Dictionary) -> bool:
	var ta := String(a.type)
	var tb := String(b.type)
	var va = a.get("v")
	var vb = b.get("v")
	match ta:
		"setting":
			return tb == "setting" and String(va) != String(vb)
		"min_start":
			if tb == "max_start":
				return int(va) > int(vb)
			if tb == "max_end":
				return int(vb) - int(va) < MIN_PLAN_MINUTES
		"min_end":
			if tb == "max_end":
				return int(va) > int(vb)
		"min_duration":
			if tb == "max_duration":
				return int(va) > int(vb)
			if tb == "max_end":
				return int(vb) - EARLIEST_START < int(va)
		"not_loud":
			return false
		"wants_food":
			return false
	return false


## Bounds the generator never goes outside; contradiction checks rely on them.
const MIN_PLAN_MINUTES := 60
const EARLIEST_START := 17 * 60
