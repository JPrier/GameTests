extends RefCounted
## Scoring. A day's result is the run up to the first catch:
##   1. fewest throws, 2. best accuracy (how close to the centre of the catch), 3. fastest time.
## Ratings are par-style and generous: 1 throw Perfect, 2 Great, 3 Good, 4-5 Nice, more = Caught.

const MIN_ACCURACY := 60


## 100% through the middle of the catch zone, 60% at its edge (never punishing).
static func accuracy(catch_d: float, catch_r: float) -> int:
	if catch_d < 0.0 or catch_r <= 0.0:
		return 0
	var t := clampf(catch_d / catch_r, 0.0, 1.0)
	return clampi(int(round(100.0 - float(100 - MIN_ACCURACY) * t)), MIN_ACCURACY, 100)


static func rating(throws: int) -> String:
	if throws <= 0:
		return ""
	match throws:
		1: return "Perfect"
		2: return "Great"
		3: return "Good"
		4, 5: return "Nice"
	return "Caught"


## Negative when a is better than b.
static func compare(a: Dictionary, b: Dictionary) -> int:
	var ta := int(a.get("throws", 999))
	var tb := int(b.get("throws", 999))
	if ta != tb:
		return -1 if ta < tb else 1
	var aa := int(a.get("accuracy", 0))
	var ab := int(b.get("accuracy", 0))
	if aa != ab:
		return -1 if aa > ab else 1
	var sa := float(a.get("seconds", 1e9))
	var sb := float(b.get("seconds", 1e9))
	if sa != sb:
		return -1 if sa < sb else 1
	return 0


static func better(a: Dictionary, b: Dictionary) -> bool:
	return compare(a, b) < 0


## Short label for the past-days list and the home page.
static func label(result: Dictionary) -> String:
	var t := int(result.get("throws", 0))
	return "%d throw%s · %d%%" % [t, "" if t == 1 else "s", int(result.get("accuracy", 0))]


static func clock(seconds: float) -> String:
	var s := maxi(int(seconds), 0)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## Player-facing words for how a throw ended.
static func outcome_text(outcome: String, hits: Array) -> String:
	match outcome:
		"catch": return "Caught it!"
		"splat": return "Splat! Right into the cake."
		"floor":
			return "Landed on the dance floor." if hits.size() <= 1 else "Bounced around and hit the floor."
		"rest":
			var last := String(hits[hits.size() - 1]) if not hits.is_empty() else ""
			match last:
				"table": return "Parked on a table."
				"balcony": return "Stuck on the balcony."
				"chair": return "Landed on a chair."
				"hedge": return "Lost in the hedge."
				"plant": return "Into the flowers."
			return "It came to rest."
		"fumble": return "Too fast! It bounced off their hands."
		"out": return "Gone with the wind!"
		"timeout": return "Still bouncing... try again."
	return ""
