class_name Events
extends RefCounted
## Random events that pop up while you play: a card with two choices and a timer. If you don't
## answer in time, the default (usually the risky one) happens. Money amounts are measured in
## seconds of your current gross income, so they always matter, and they're fixed when the card
## appears. Some outcomes are gambles.
##
## Outcome ops:
##   ["pay", secs]              lose secs of income in cash (can push you into the red)
##   ["gain", secs]             gain secs of income in cash
##   ["cash_frac", f]           lose a fraction of your cash
##   ["fx", kind, mult, secs]   timed effect: demand, kitchen, seating, income, food (+pts), wages
##   ["closed", secs]           the restaurant is closed (no restaurant revenue)

const TIMEOUT := 45.0
const MIN_GAP := 180.0
const MAX_GAP := 360.0

const LIST := [
	{"id": "inspection", "good": false, "title": "Health inspection", "text": "An inspector just walked in, clipboard first.",
		"choices": [{"label": "Deep clean first", "ops": [["pay", 90]]},
			{"label": "Wing it", "chance": 0.5, "ops": [], "else": [["closed", 60], ["pay", 120]], "note": "50% chance you're shut for a minute and fined"}],
		"default": 1},
	{"id": "freezer", "good": false, "title": "Freezer breakdown", "text": "The walk-in freezer is making a terrible noise.",
		"choices": [{"label": "Repair it now", "ops": [["pay", 120]]},
			{"label": "Limp along", "ops": [["fx", "kitchen", 0.5, 180]], "note": "The kitchen runs at half speed for 3 minutes"}],
		"default": 1},
	{"id": "review", "good": false, "title": "A bad review goes viral", "text": "\"Cold fries, rude waiter, 1 star.\" 40,000 likes.",
		"choices": [{"label": "Hire a PR firm", "ops": [["pay", 150]]},
			{"label": "Ride it out", "ops": [["fx", "demand", 0.6, 240]], "note": "40% fewer guests for 4 minutes"}],
		"default": 1},
	{"id": "critic", "good": true, "title": "A food critic is dining tonight", "text": "Table 6. The one pretending to read a book.",
		"choices": [{"label": "Roll out the red carpet", "ops": [["pay", 60]], "chance": 0.75, "win": [["fx", "demand", 2.0, 300]], "note": "75% chance of double the guests for 5 minutes"},
			{"label": "Business as usual", "chance": 0.35, "ops": [], "win": [["fx", "demand", 1.5, 180]], "note": "35% chance of 50% more guests for 3 minutes"}],
		"default": 1},
	{"id": "viral", "good": true, "title": "You went viral!", "text": "A customer's video of your kitchen hit the front page.",
		"choices": [{"label": "Ride the wave", "ops": [["fx", "demand", 2.5, 150]], "note": "2.5x the guests for 2.5 minutes"}],
		"default": 0},
	{"id": "supplier", "good": false, "title": "Supplier price hike", "text": "Your produce supplier doubled prices overnight.",
		"choices": [{"label": "Lock in a contract", "ops": [["pay", 200]]},
			{"label": "Pay market prices", "ops": [["fx", "food", 15.0, 300]], "note": "Food costs 15 points higher for 5 minutes"}],
		"default": 1},
	{"id": "walkout", "good": false, "title": "Staff walkout", "text": "The line cooks want a raise. Today.",
		"choices": [{"label": "Give raises", "ops": [["fx", "wages", 1.5, 600]], "note": "Running costs 50% higher for 10 minutes"},
			{"label": "Hold firm", "chance": 0.4, "ops": [], "else": [["fx", "kitchen", 0.3, 120]], "note": "60% chance the kitchen runs at 30% for 2 minutes"}],
		"default": 1},
	{"id": "pipe", "good": false, "title": "Burst pipe", "text": "There's water coming out of the ceiling. A lot of water.",
		"choices": [{"label": "Emergency plumber", "ops": [["pay", 180]]},
			{"label": "Close for repairs", "ops": [["closed", 90]], "note": "The restaurant is closed for 90 seconds"}],
		"default": 1},
	{"id": "lawsuit", "good": false, "title": "You're being sued", "text": "A customer says your soup was 'aggressively hot'.",
		"choices": [{"label": "Settle out of court", "ops": [["pay", 400]]},
			{"label": "Fight it", "chance": 0.5, "ops": [], "else": [["pay", 900]], "note": "50% chance you lose and pay 15 minutes of income"}],
		"default": 1},
	{"id": "audit", "good": false, "title": "Tax audit", "text": "The tax office would like to see your receipts. All of them.",
		"choices": [{"label": "Pay what they ask", "ops": [["cash_frac", 0.10]], "note": "Lose 10% of your cash"},
			{"label": "Hire an accountant", "ops": [["pay", 60]], "chance": 0.8, "win": [], "else": [["cash_frac", 0.15]], "note": "20% chance you still lose 15% of your cash"}],
		"default": 0},
	{"id": "investor", "good": true, "title": "An investor calls", "text": "Cash now, for a cut of your profits.",
		"choices": [{"label": "Take the money", "ops": [["gain", 600], ["fx", "income", 0.85, 600]], "note": "Get 10 minutes of income now, but earn 15% less for 10 minutes"},
			{"label": "Decline", "ops": []}],
		"default": 1},
	{"id": "celebrity", "good": true, "title": "Celebrity sighting", "text": "A movie star just ordered the special. Phones are out.",
		"choices": [{"label": "Pose for a photo", "ops": [["fx", "demand", 2.0, 180]], "note": "Double the guests for 3 minutes"}],
		"default": 0},
	{"id": "outage", "good": false, "title": "Power outage", "text": "The whole block just went dark.",
		"choices": [{"label": "Rent a generator", "ops": [["pay", 45]]},
			{"label": "Wait it out", "ops": [["closed", 45]], "note": "The restaurant is closed for 45 seconds"}],
		"default": 1},
	{"id": "gala", "good": true, "title": "Charity gala", "text": "Sponsor the city's biggest charity night?",
		"choices": [{"label": "Sponsor it", "ops": [["pay", 120], ["fx", "demand", 1.4, 600]], "note": "40% more guests for 10 minutes"},
			{"label": "Skip it", "ops": []}],
		"default": 1},
	{"id": "scare", "good": false, "title": "Food poisoning rumour", "text": "Someone online says your oysters made them sick.",
		"choices": [{"label": "Recall and refund", "ops": [["pay", 240]]},
			{"label": "Deny everything", "chance": 0.5, "ops": [], "else": [["fx", "demand", 0.4, 300], ["pay", 300]], "note": "50% chance of 60% fewer guests for 5 minutes, plus a 5-minute fine"}],
		"default": 1},
	{"id": "bus", "good": true, "title": "Tour bus!", "text": "Forty hungry tourists, all at once.",
		"choices": [{"label": "Open the doors", "ops": [["fx", "demand", 1.8, 120]], "note": "80% more guests for 2 minutes"}],
		"default": 0},
	{"id": "rival", "good": false, "title": "A rival opens across the street", "text": "Same menu. Lower prices. Bigger sign.",
		"choices": [{"label": "Start a price war", "ops": [["fx", "income", 0.8, 300]], "note": "All income 20% lower for 5 minutes"},
			{"label": "Ignore them", "ops": [["fx", "demand", 0.7, 420]], "note": "30% fewer guests for 7 minutes"}],
		"default": 1},
	{"id": "award", "good": true, "title": "Restaurant award", "text": "You've been shortlisted for Best New Restaurant.",
		"choices": [{"label": "Throw a party", "ops": [["pay", 90], ["fx", "income", 1.5, 300]], "note": "All income 50% higher for 5 minutes"},
			{"label": "Stay humble", "ops": [["fx", "demand", 1.2, 300]], "note": "20% more guests for 5 minutes"}],
		"default": 1},
]


## A fresh event with money amounts fixed from the current gross income `r` (per second).
static func make(rng: RandomNumberGenerator, r: float, luck: float, cost_mult: float, has_cash: bool) -> Dictionary:
	var good_p := clampf(0.35 + luck, 0.0, 0.9)
	var want_good := rng.randf() < good_p
	var pool: Array = []
	for ev in LIST:
		if bool(ev.good) == want_good:
			pool.append(ev)
	var src: Dictionary = pool[rng.randi() % pool.size()]
	var ev: Dictionary = src.duplicate(true)
	ev["r"] = r
	ev["cost_mult"] = cost_mult
	ev["t"] = TIMEOUT
	return ev


static func op_amount(ev: Dictionary, op: Array, cash: float) -> float:
	match String(op[0]):
		"pay": return float(op[1]) * float(ev.r) * float(ev.cost_mult)
		"gain": return float(op[1]) * float(ev.r)
		"cash_frac": return maxf(0.0, cash) * float(op[1]) * float(ev.cost_mult)
	return 0.0


## The price shown on a choice button (upfront costs only).
static func upfront(ev: Dictionary, choice: Dictionary, cash: float) -> float:
	var tot := 0.0
	for op in choice.ops:
		if String(op[0]) == "pay" or String(op[0]) == "cash_frac":
			tot += op_amount(ev, op, cash)
	return tot


## Applies a choice to the econ. Returns a short line describing what happened.
static func resolve(e, ev: Dictionary, idx: int) -> String:
	var choices: Array = ev.choices
	idx = clampi(idx, 0, choices.size() - 1)
	var ch: Dictionary = choices[idx]
	var ops: Array = (ch.ops as Array).duplicate()
	var line := ""
	if ch.has("chance"):
		var hit: bool = e.rng.randf() < float(ch.chance)
		if hit:
			ops.append_array(ch.get("win", []))
			line = "Lucky!"
		else:
			ops.append_array(ch.get("else", []))
			line = "Unlucky."
	for op in ops:
		match String(op[0]):
			"pay", "cash_frac":
				e.cash -= op_amount(ev, op, e.cash)
			"gain":
				var g := op_amount(ev, op, e.cash)
				e.cash += g
			"fx":
				e.add_effect(String(op[1]), float(op[2]), float(op[3]), String(ev.title))
			"closed":
				e.add_effect("closed", 0.0, float(op[1]), String(ev.title))
	return line
