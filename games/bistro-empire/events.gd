class_name Events
extends RefCounted
## Events pop up while you play as a card you must answer. Bad ones are drawn towards whatever
## you're running too hot (see RISK_TEXT), and the card says why. Money amounts are measured in
## seconds of your profit (at least a quarter of sales), fixed when the card appears, and
## insurance pays most of them. Some outcomes are gambles whose odds depend on the same risk.
##
## Outcome ops:
##   ["pay", secs]              lose secs of income in cash (can push you into the red)
##   ["gain", secs]             gain secs of income in cash
##   ["cash_frac", f]           lose a fraction of your cash
##   ["fx", kind, mult, secs]   timed effect: demand, kitchen, seating, income, food (+pts), wages
##   ["closed", secs]           the restaurant is closed (no restaurant revenue)

const TIMEOUT := 45.0            # kept for old saves; events now wait for an answer
const MIN_GAP := 180.0
const MAX_GAP := 360.0

## What makes trouble likely. Each bad event is tied to one, and the card says why it happened:
##   kitchen  cooks running flat out (served / kitchen capacity above 70%)
##   floor    a packed dining room (served / seats above 70%)
##   queue    guests turned away at the door
##   debt     how much of your credit line you've used
##   none     bad luck, nothing to do with you
const RISK_TEXT := {
	"kitchen": ["Your kitchen is running at %d%% of capacity.", "Kitchens under 70% busy rarely have this problem. Spare cooks are your insurance."],
	"floor": ["Your dining room is %d%% full.", "Rooms under 70% full rarely have this problem. Spare tables are your insurance."],
	"queue": ["You're turning away %d%% of the guests who come.", "Guests you can't seat complain. Add seats and cooks, or raise prices to shorten the queue."],
	"debt": ["You've used %d%% of your credit line.", "Banks get nervous above half your limit. Repay some debt to keep them calm."],
}

const LIST := [
	{"id": "inspection", "good": false, "risk": "kitchen", "title": "Health inspection", "text": "An inspector just walked in, clipboard first.",
		"choices": [{"label": "Deep clean first", "ops": [["pay", 90]]},
			{"label": "Wing it", "fail": [0.1, 0.8], "ops": [], "else": [["closed", 60], ["pay", 120]], "note": "%d%% chance you're shut for a minute and fined"}],
		"default": 1},
	{"id": "freezer", "good": false, "risk": "kitchen", "title": "Freezer breakdown", "text": "The walk-in freezer is making a terrible noise.",
		"choices": [{"label": "Repair it now", "ops": [["pay", 120]]},
			{"label": "Limp along", "ops": [["fx", "kitchen", 0.5, 180]], "note": "The kitchen runs at half speed for 3 minutes"}],
		"default": 1},
	{"id": "review", "good": false, "risk": "queue", "title": "A bad review goes viral", "text": "\"Cold fries, rude waiter, 1 star.\" 40,000 likes.",
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
	{"id": "supplier", "good": false, "risk": "none", "title": "Supplier price hike", "text": "Your produce supplier doubled prices overnight.",
		"choices": [{"label": "Lock in a contract", "ops": [["pay", 200]]},
			{"label": "Pay market prices", "ops": [["fx", "food", 15.0, 300]], "note": "Food costs 15 points higher for 5 minutes"}],
		"default": 1},
	{"id": "walkout", "good": false, "risk": "kitchen", "title": "Staff walkout", "text": "The line cooks want a raise. Today.",
		"choices": [{"label": "Give raises", "ops": [["fx", "wages", 1.5, 600]], "note": "Running costs 50% higher for 10 minutes"},
			{"label": "Hold firm", "fail": [0.15, 0.7], "ops": [], "else": [["fx", "kitchen", 0.3, 120]], "note": "%d%% chance the kitchen runs at 30% for 2 minutes"}],
		"default": 1},
	{"id": "pipe", "good": false, "risk": "none", "title": "Burst pipe", "text": "There's water coming out of the ceiling. A lot of water.",
		"choices": [{"label": "Emergency plumber", "ops": [["pay", 180]]},
			{"label": "Close for repairs", "ops": [["closed", 90]], "note": "The restaurant is closed for 90 seconds"}],
		"default": 1},
	{"id": "lawsuit", "good": false, "risk": "floor", "title": "You're being sued", "text": "A customer slipped between two tables in your packed dining room.",
		"choices": [{"label": "Settle out of court", "ops": [["pay", 400]]},
			{"label": "Fight it", "fail": [0.15, 0.7], "ops": [], "else": [["pay", 900]], "note": "%d%% chance you lose and pay 15 minutes of income"}],
		"default": 1},
	{"id": "audit", "good": false, "risk": "none", "title": "Tax audit", "text": "The tax office would like to see your receipts. All of them.",
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
	{"id": "outage", "good": false, "risk": "none", "title": "Power outage", "text": "The whole block just went dark.",
		"choices": [{"label": "Rent a generator", "ops": [["pay", 45]]},
			{"label": "Wait it out", "ops": [["closed", 45]], "note": "The restaurant is closed for 45 seconds"}],
		"default": 1},
	{"id": "gala", "good": true, "title": "Charity gala", "text": "Sponsor the city's biggest charity night?",
		"choices": [{"label": "Sponsor it", "ops": [["pay", 120], ["fx", "demand", 1.4, 600]], "note": "40% more guests for 10 minutes"},
			{"label": "Skip it", "ops": []}],
		"default": 1},
	{"id": "scare", "good": false, "risk": "kitchen", "title": "Food poisoning rumour", "text": "Someone online says a rushed plate made them sick.",
		"choices": [{"label": "Recall and refund", "ops": [["pay", 240]]},
			{"label": "Deny everything", "fail": [0.15, 0.7], "ops": [], "else": [["fx", "demand", 0.4, 300], ["pay", 300]], "note": "%d%% chance of 60% fewer guests for 5 minutes, plus a 5-minute fine"}],
		"default": 1},
	{"id": "bus", "good": true, "title": "Tour bus!", "text": "Forty hungry tourists, all at once.",
		"choices": [{"label": "Open the doors", "ops": [["fx", "demand", 1.8, 120]], "note": "80% more guests for 2 minutes"}],
		"default": 0},
	{"id": "rival", "good": false, "risk": "none", "title": "A rival opens across the street", "text": "Same menu. Lower prices. Bigger sign.",
		"choices": [{"label": "Start a price war", "ops": [["fx", "income", 0.8, 300]], "note": "All income 20% lower for 5 minutes"},
			{"label": "Ignore them", "ops": [["fx", "demand", 0.7, 420]], "note": "30% fewer guests for 7 minutes"}],
		"default": 1},
	{"id": "crowd", "good": false, "risk": "floor", "title": "Fire marshal", "text": "Someone reported your dining room as over capacity.",
		"choices": [{"label": "Turn guests away tonight", "ops": [["fx", "seating", 0.6, 240]], "note": "40% fewer seats for 4 minutes"},
			{"label": "Argue the count", "fail": [0.15, 0.7], "ops": [], "else": [["closed", 90], ["pay", 180]], "note": "%d%% chance you're shut for 90 seconds and fined"}]},
	{"id": "angry", "good": false, "risk": "queue", "title": "The queue turns ugly", "text": "Guests who've waited an hour are filming the line.",
		"choices": [{"label": "Free drinks for the line", "ops": [["pay", 90]]},
			{"label": "Let them leave", "ops": [["fx", "demand", 0.7, 300]], "note": "30% fewer guests for 5 minutes"}]},
	{"id": "bank", "good": false, "risk": "debt", "title": "The bank wants a word", "text": "Your loan officer has \"concerns\" about your exposure.",
		"choices": [{"label": "Pay a penalty fee", "ops": [["pay", 120]]},
			{"label": "Accept a rate hike", "ops": [["fx", "rate", 2.0, 600]], "note": "Loan interest doubles for 10 minutes"}]},
	{"id": "passed", "good": true, "title": "Inspection: spotless", "text": "The inspector found your kitchen calm and clean, and said so online.",
		"choices": [{"label": "Frame the certificate", "ops": [["fx", "demand", 1.3, 240]], "note": "30% more guests for 4 minutes"}]},
	{"id": "award", "good": true, "title": "Restaurant award", "text": "You've been shortlisted for Best New Restaurant.",
		"choices": [{"label": "Throw a party", "ops": [["pay", 90], ["fx", "income", 1.5, 300]], "note": "All income 50% higher for 5 minutes"},
			{"label": "Stay humble", "ops": [["fx", "demand", 1.2, 300]], "note": "20% more guests for 5 minutes"}],
		"default": 1},
]


## How risky the restaurant is right now, 0 (safe) to 1 (asking for it), plus the raw figures.
static func risks(e) -> Dictionary:
	var saved: Array = e.effects
	e.effects = []
	var inf: Dictionary = e.income_info(e.agg())
	e.effects = saved
	var lim: float = e.credit_limit()
	var du: float = e.debt / lim if lim > 0.0 else 0.0
	var raw := {"kitchen": float(inf.kstrain), "floor": float(inf.fstrain), "queue": float(inf.queue), "debt": du}
	var r := {"none": 0.0,
		"kitchen": clampf((float(raw.kitchen) - 0.7) / 0.22, 0.0, 1.0),
		"floor": clampf((float(raw.floor) - 0.7) / 0.22, 0.0, 1.0),
		"queue": clampf(float(raw.queue) / 0.3, 0.0, 1.0),
		"debt": clampf((du - 0.4) / 0.6, 0.0, 1.0)}
	return {"r": r, "raw": raw}


## Seconds until the next event: a riskier restaurant gets into trouble sooner.
static func next_gap(rng: RandomNumberGenerator, rk: Dictionary) -> float:
	var worst := 0.0
	for k in rk.r:
		worst = maxf(worst, float(rk.r[k]))
	return rng.randf_range(MIN_GAP, MAX_GAP) * (1.0 - 0.45 * worst)


## A fresh event with money amounts fixed from the current gross income `r` (per second).
## Bad events are drawn towards whatever you're running too hot; a calm, well-run restaurant
## mostly gets good news. `cmods` is the concept's risk table, `cover` the insured share of bills.
static func make(rng: RandomNumberGenerator, r: float, luck: float, cost_mult: float, rk: Dictionary,
		cmods: Dictionary = {}, cover := 0.0, only := "", soft := false) -> Dictionary:
	var rr: Dictionary = rk.r
	var worst := 0.0
	for k in rr:
		worst = maxf(worst, float(rr[k]) * float(cmods.get(k, 1.0)))
	worst = minf(worst, 1.0)
	var good_p := clampf(0.2 + 0.4 * (1.0 - worst) + luck, 0.05, 0.9)
	var want_good := rng.randf() < good_p
	var pool: Array = []
	var weights: Array = []
	var tot := 0.0
	for ev in LIST:
		if only != "":
			if String(ev.id) != only:
				continue
		elif bool(ev.good) != want_good:
			continue
		var w := 1.0
		if String(ev.get("risk", "")) == "debt" and float((rk.raw as Dictionary).get("debt", 0.0)) <= 0.0 and only == "":
			continue   # no loans, no nervous banker
		if not bool(ev.good):
			var key := String(ev.get("risk", "none"))
			w = 0.5 if key == "none" else 0.1 + 3.0 * float(rr.get(key, 0.0)) * float(cmods.get(key, 1.0))
		elif String(ev.id) == "passed":
			w = 1.5 if float(rr.kitchen) <= 0.0 else 0.0
		pool.append(ev)
		weights.append(w)
		tot += w
	if pool.is_empty():
		return {}
	var pick := rng.randf() * tot
	var src: Dictionary = pool[pool.size() - 1]
	for i in pool.size():
		pick -= float(weights[i])
		if pick <= 0.0:
			src = pool[i]
			break
	var ev: Dictionary = src.duplicate(true)
	var key := String(ev.get("risk", "none"))
	var lvl := float(rr.get(key, 0.0)) * float(cmods.get(key, 1.0))
	lvl = minf(lvl, 1.0)
	var stakes := float(cmods.get("stakes", 1.0)) if key in ["floor", "queue"] or String(ev.id) == "critic" else 1.0
	ev["r"] = r
	ev["cost_mult"] = cost_mult * stakes
	ev["cover"] = cover
	ev["soft"] = soft   # normal runs: a bill never takes you below $0
	ev["t"] = TIMEOUT
	ev["level"] = lvl
	if RISK_TEXT.has(key) and not bool(ev.good):
		var raw := float((rk.raw as Dictionary).get(key, 0.0))
		ev["why"] = String(RISK_TEXT[key][0]) % int(round(raw * 100.0))
		ev["fix"] = String(RISK_TEXT[key][1])
	for ch in ev.choices:
		if ch.has("fail"):
			var f: Array = ch.fail
			var fp := clampf(float(f[0]) + float(f[1]) * lvl, 0.05, 0.95)
			ch["chance"] = 1.0 - fp
			ch["note"] = String(ch.note).replace("%d%%", "%d%%" % int(round(fp * 100.0)))
	return ev


static func op_amount(ev: Dictionary, op: Array, cash: float) -> float:
	match String(op[0]):
		"pay":
			var amt := float(op[1]) * float(ev.r) * float(ev.cost_mult) * (1.0 - float(ev.get("cover", 0.0)))
			return minf(amt, maxf(cash, 0.0)) if bool(ev.get("soft", false)) else amt
		"gain": return float(op[1]) * float(ev.r)
		"cash_frac": return maxf(0.0, cash) * float(op[1]) * float(ev.cost_mult) * (1.0 - float(ev.get("cover", 0.0)))
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
