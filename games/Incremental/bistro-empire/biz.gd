class_name Biz
extends RefCounted
## Side businesses you run alongside the restaurant. Each has two builds (A and B) and a twist:
##
##   Food Truck   pick a spot; each spot's crowd changes every few minutes.
##   Bakery       ovens bake, counters sell; unsold stock goes stale, and a morning rush sells triple.
##   Catering     take contracts that tie up crew for a while and pay on completion.
##   Bar          huge margins, but crowds get rowdy; incidents close the bar (and cost fines in a
##                challenge). Happy hour trades risk for volume.
##   Hotel        set room rates per season; empty rooms earn nothing (and pay rent in a challenge).
##   Wholesale    warehouses fill with stock you sell on a moving market; trucks boost restaurant
##                income (or cut food costs empire-wide in a challenge).
##
## Scaling: every business is independent of the restaurant. Each has its own fixed prices and
## earnings (bigger for the ones that unlock later), and grows only through its own builds and
## upgrades, which go on forever (a milestone every 25 builds past 1,000, more extras past 400).
## Stars, Grit and Grit's empire bonus boost every business just as they boost the restaurant, so
## a business is as worth opening after your tenth sale as after your first. Restaurant upgrades
## don't touch businesses.
##
## Money is a log10 (see num.gd). The twists are computed in UNITS: one unit is what one A build
## earns per second before upgrades (unit_l), so counts stay small ordinary numbers and only the
## final amount becomes a log. step() simulates the twist in real time while the game runs;
## estimate() gives a steady-state rate for display, offline time and the balance bot.
##
## In challenge runs every business has running costs per build (fuel, wages, rent) and some
## have per-sale costs, so a badly run business can lose money; normal runs have none.

const UNIT_K := 4.0e-6            # one A build earns this share of the unlock earnings per second, before upgrades
const UNIT_SECS := 20.0           # the first A build costs this many seconds of its own earnings
const OPEN_K := 0.05              # opening costs this share of the unlock earnings
const MILESTONE_X := 2.0          # each milestone multiplies the business's income

const DEFS := [
	{"id": "truck", "name": "Food Truck", "unlock": 3.0e5, "a": "Truck", "as": "Trucks", "b": "Menu Item", "bs": "Menu Items",
		"b_cost": 10.0, "ga": 1.1, "gb": 1.1, "color": "ff8a3d",
		"blurb": "Park where the crowds are. Each spot's crowd changes every few minutes; moving takes 15s.",
		"a_desc": "+1 truck selling food", "b_desc": "+5% on every sale"},
	{"id": "bakery", "name": "Bakery", "unlock": 3.0e7, "a": "Oven", "as": "Ovens", "b": "Counter", "bs": "Counters",
		"b_cost": 2.0, "ga": 1.1, "gb": 1.06, "color": "e0c27a",
		"blurb": "Ovens bake, counters sell. Unsold bread goes stale; a morning rush every 4 minutes sells triple.",
		"a_desc": "+1 loaf/s baked", "b_desc": "+1.5 loaves/s sold"},
	{"id": "catering", "name": "Catering Co.", "unlock": 3.0e9, "a": "Crew", "as": "Crew", "b": "Van", "bs": "Vans",
		"b_cost": 25.0, "ga": 1.1, "gb": 1.3, "color": "6cc56b",
		"blurb": "Take contracts: weddings, galas, festivals. Crew is busy until the job ends, then it pays.",
		"a_desc": "+1 crew member", "b_desc": "+1 job at a time"},
	{"id": "bar", "name": "Cocktail Bar", "unlock": 3.0e11, "a": "Bartender", "as": "Bartenders", "b": "Bouncer", "bs": "Bouncers",
		"b_cost": 3.0, "ga": 1.1, "gb": 1.07, "color": "b58cff",
		"blurb": "Fat margins, rowdy crowds. When the rowdy meter fills there's an incident and a fine.",
		"a_desc": "+1 drink/s", "b_desc": "Keeps the peace"},
	{"id": "hotel", "name": "Boutique Hotel", "unlock": 3.0e13, "a": "Room", "as": "Rooms", "b": "Concierge", "bs": "Concierges",
		"b_cost": 2.5, "ga": 1.1, "gb": 1.07, "color": "5aa9e6",
		"blurb": "Set your room rate each season. Rent is due on every room, full or empty.",
		"a_desc": "+1 room (+rent)", "b_desc": "+more guests want to stay"},
	{"id": "wholesale", "name": "Wholesale Co.", "unlock": 3.0e15, "a": "Warehouse", "as": "Warehouses", "b": "Delivery Truck", "bs": "Delivery Trucks",
		"b_cost": 5.0, "ga": 1.1, "gb": 1.12, "color": "6ad1c0",
		"blurb": "Stock piles up; sell it when the market price is high. Trucks cut food costs across your empire.",
		"a_desc": "+1 crate/s", "b_desc": "-food costs everywhere"},
]
const N := 6

const SPOTS := ["Downtown", "Beach", "Stadium", "Night Market"]
const SPOT_PERIOD := 180.0
const MOVE_TIME := 15.0
const RUSH_PERIOD := 240.0
const RUSH_LEN := 30.0
const OFFER_PERIOD := 75.0
const JOB_NAMES := ["Wedding", "Corporate Gala", "Music Festival", "Birthday Party", "Film Set Lunch", "Charity Ball",
	"Tech Conference", "Graduation", "Sports Banquet", "Embassy Dinner", "Fashion Week", "Royal Reception"]
const SEASONS := ["Peak", "Shoulder", "Off-season", "Shoulder"]
const SEASON_MULT := [1.7, 1.0, 0.45, 1.0]
const SEASON_LEN := 240.0
const A_MILESTONES := [10, 25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300, 325, 350, 375, 400, 425, 450, 475, 500,
	525, 550, 575, 600, 625, 650, 675, 700, 725, 750, 775, 800, 825, 850, 875, 900, 925, 950, 975, 1000]
const B_MILESTONES := [5, 10, 25, 50, 100, 150]


# ------------------------------------------------------------------ state

static func blank(i: int) -> Dictionary:
	var s := {"open": false, "a": 0, "b": 0, "earned_l": Num.ZERO}
	match String(DEFS[i].id):
		"truck": s.merge({"spot": 0, "spots": [1.0, 1.0, 1.0, 1.0], "spot_t": 0.0, "move_t": 0.0})
		"bakery": s.merge({"stock": 0.0, "rush_t": 0.0})
		"catering": s.merge({"offers": [], "jobs": [], "offer_t": 0.0})
		"bar": s.merge({"happy": false, "rowdy": 0.0, "closed_t": 0.0, "incidents": 0})
		"hotel": s.merge({"rate": 1.0, "rate_auto": true, "season_t": 0.0})
		"wholesale": s.merge({"stock": 0.0, "mprice": 1.0, "auto_sell": true})
	return s


## A business's state from a save. Older saves priced catering contracts in plain money; those
## offers and jobs are dropped (new ones arrive within a minute).
static func load_state(i: int, d: Dictionary) -> Dictionary:
	var s := blank(i)
	for k in d:
		if s.has(k):
			s[k] = d[k]
	if d.has("earned") and not d.has("earned_l"):
		s.earned_l = Num.L(float(d.earned))
	if String(DEFS[i].id) == "catering":
		for list in ["offers", "jobs"]:
			var keep: Array = []
			for o in s[list]:
				if o is Dictionary and (o as Dictionary).has("pay_u"):
					keep.append(o)
			s[list] = keep
	return s


## Run earnings (log) needed before a business can be opened (keeps them arriving one by one).
static func unlock_at_l(i: int) -> float:
	return Econ.cp_l(Num.L(float(DEFS[i].unlock)))


## What one A build earns per second (before upgrades and prestige), as a log.
static func unit_l(i: int) -> float:
	return unlock_at_l(i) + Num.L(UNIT_K)


static func open_cost_l(i: int) -> float:
	return unlock_at_l(i) + Num.L(OPEN_K)


static func growth(i: int, which: String) -> float:
	return pow(float(DEFS[i]["g" + which]), Econ.COST_POW)


## Price of build number n (0-based) of A or B.
static func cost_at_l(i: int, which: String, n: int) -> float:
	var c0 := unit_l(i) + Num.L(UNIT_SECS * (1.0 if which == "a" else float(DEFS[i].b_cost)))
	return c0 + n * Num.L(growth(i, which))


## Price of k builds starting at build n.
static func cost_of_l(i: int, which: String, n: int, k: int) -> float:
	return Num.geo(cost_at_l(i, which, n), growth(i, which), k)


## What the builds cost (used when selling a business off).
static func invested_l(i: int, s: Dictionary, _e = null) -> float:
	# the first of each build comes with opening
	return Num.sum([cost_of_l(i, "a", 1, maxi(0, int(s.a) - 1)), cost_of_l(i, "b", 1, maxi(0, int(s.b) - 1)),
		open_cost_l(i) if s.open else Num.ZERO])


## Running costs per second for the builds, in cost units (challenges only).
const RUN_A := {"truck": 0.35, "bakery": 0.0, "catering": 0.4, "bar": 0.2, "hotel": 0.0, "wholesale": 0.25}
const RUN_B := {"truck": 0.0, "bakery": 0.2, "catering": 0.0, "bar": 0.4, "hotel": 0.0, "wholesale": 0.3}


# ------------------------------------------------------------------ helpers

## log10 of this business's income multiplier: its own upgrades, every-business upgrades,
## prestige (stars, Grit, empire) and event effects. Nothing from the restaurant.
static func mult_l(i: int, e) -> float:
	var a: Dictionary = e.agg()
	return float(a.biz_l[i]) + float(a.lm.biz) + e.prestige_l(a) + e.effect_l("income")


## log10 of the money one revenue unit is worth per second right now.
static func rev_base_l(i: int, e) -> float:
	return unit_l(i) + mult_l(i, e)


## log10 of one cost unit (challenges): the unit, the business's upgrades and the square root of
## prestige, like the restaurant's running costs.
static func cost_base_l(i: int, e) -> float:
	var a: Dictionary = e.agg()
	return unit_l(i) + float(a.biz_l[i]) + float(a.lm.biz) + 0.5 * e.prestige_l(a) + Num.L(float(a.upkeep) * e.effect_mult("wages"))


static func upkeep_u(i: int, s: Dictionary) -> float:
	if not s.open:
		return 0.0
	var id: String = DEFS[i].id
	return int(s.a) * float(RUN_A[id]) + int(s.b) * float(RUN_B[id])


static func has_mgr(i: int, e) -> bool:
	return e.agg().flags.has("mgr_" + String(DEFS[i].id))


static func food_cost(e) -> float:
	return e.food_cost_pct()


static func truck_u(s: Dictionary, e, spot_mult: float) -> float:
	return int(s.a) * (1.0 + 0.05 * int(s.b)) * spot_mult * float(e.agg().twist.truck)


static func bakery_sell_cap(s: Dictionary, e) -> float:
	return 1.0 + 1.5 * int(s.b) * float(e.agg().twist.bakery)


static func catering_max_jobs(s: Dictionary) -> int:
	return 1 + int(s.b)


static func busy_crew(s: Dictionary) -> int:
	var n := 0
	for j in s.jobs:
		n += int(j.crew)
	return n


static func bar_mix(s: Dictionary) -> Dictionary:
	return {"vol": 1.8, "price": 0.7, "rowdy": 2.5} if s.happy else {"vol": 1.0, "price": 1.0, "rowdy": 1.0}


## Incidents per second at the bar.
static func bar_incident_rate(s: Dictionary, e) -> float:
	var m := bar_mix(s)
	var x := float(int(s.a)) * float(m.rowdy) / (2.0 + 3.0 * int(s.b))
	var calm := 0.6 if e.agg().flags.has("mgr_bar") else 1.0
	return 0.5 / 60.0 * x * float(e.agg().twist.bar) * calm


static func hotel_quality(s: Dictionary, e) -> float:
	return (2.0 + 1.5 * int(s.b)) * float(e.agg().twist.hotel)


static func hotel_demand(s: Dictionary, e, sea: int, rate: float) -> float:
	return hotel_quality(s, e) * 4.0 * float(SEASON_MULT[sea]) * pow(maxf(rate, 0.05), -1.6)


static func hotel_best_rate(_i: int, s: Dictionary, e, sea: int) -> float:
	if int(s.a) <= 0:
		return 1.0
	# demand exactly fills the rooms; any lower and you're giving rooms away
	return clampf(pow(hotel_quality(s, e) * 4.0 * float(SEASON_MULT[sea]) / float(int(s.a)), 1.0 / 1.6), 0.2, 20.0)


static func season(s: Dictionary) -> int:
	return int(float(s.season_t) / SEASON_LEN) % SEASONS.size()


## Hotel takings in units: {rev, rent (cost units), occ}.
static func _hotel_u(s: Dictionary, e, sea: int, rate: float) -> Dictionary:
	var rooms := float(int(s.a))
	var occ := minf(rooms, hotel_demand(s, e, sea, rate))
	var full := occ / maxf(rooms, 1.0)
	var rev := occ * rate * 1.4
	if not e.costs_on():
		rev *= 0.6 + 0.4 * full   # no rent outside challenges, but a half-empty hotel loses its buzz
	return {"rev": rev, "rent": rooms * 0.6, "occ": full}


## Hotel takings as money: {rev_l, rent_l, occ}.
static func hotel_rev(i: int, s: Dictionary, e, sea: int, rate: float) -> Dictionary:
	var h := _hotel_u(s, e, sea, rate)
	return {"rev_l": Num.L(float(h.rev)) + rev_base_l(i, e), "rent_l": Num.L(float(h.rent)) + cost_base_l(i, e), "occ": h.occ}


static func wholesale_cap(s: Dictionary) -> float:
	return int(s.a) * 240.0


## What a crate sells for right now (log).
static func wholesale_price_l(i: int, s: Dictionary, e) -> float:
	return Num.L(float(s.mprice) * float(e.agg().twist.wholesale)) + rev_base_l(i, e)


## How long a bar fight shuts the bar. Normal runs have no fines, so the closure is longer.
static func bar_close_secs(e) -> float:
	return 10.0 if e.costs_on() else 30.0


## Normal runs: Delivery Trucks speed up the whole supply chain, boosting restaurant income by
## the same curve that cuts food costs in a challenge (up to +15%).
static func supply_boost(s: Dictionary) -> float:
	return food_cut(s) / 100.0


## Percentage points knocked off food costs everywhere by delivery trucks (challenges).
static func food_cut(s: Dictionary) -> float:
	if not s.open:
		return 0.0
	return 15.0 * (1.0 - 1.0 / (1.0 + 0.08 * int(s.b)))


# ------------------------------------------------------------------ steady-state estimates

## {rev_l, cost_l} per second, the long-run average. offline=true assumes nobody is there to act.
static func estimate(i: int, s: Dictionary, e, offline := false) -> Dictionary:
	if not s.open:
		return {"rev_l": Num.ZERO, "cost_l": Num.ZERO}
	var r := _raw_u(i, s, e, offline)
	var rb := rev_base_l(i, e)
	var cost := Num.ZERO
	if e.costs_on():   # businesses only have running costs in challenges
		cost = Num.add(Num.L(float(r.fixed)) + cost_base_l(i, e), Num.L(float(r.var)) + rb)
	return {"rev_l": Num.L(float(r.rev)) + rb, "cost_l": cost}


## Steady-state rates in units: rev and var (revenue units), fixed (cost units).
static func _raw_u(i: int, s: Dictionary, e, offline: bool) -> Dictionary:
	var a: Dictionary = e.agg()
	var up := upkeep_u(i, s)
	var mgr := has_mgr(i, e)
	var rev := 0.0
	var cost := 0.0
	match String(DEFS[i].id):
		"truck":
			var sm := 1.0
			if mgr:
				sm = 1.6
			elif not offline:
				sm = float(s.spots[int(s.spot)]) if float(s.move_t) <= 0.0 else 0.0
			rev = truck_u(s, e, sm)
		"bakery":
			var made := float(int(s.a))
			var sold := minf(made, bakery_sell_cap(s, e))
			rev = sold
			cost += made * 0.35 * food_cost(e) / 25.0
		"catering":
			var util := minf(0.9, 0.35 + 0.12 * int(s.b) + (0.15 if mgr else 0.0))
			if offline and not mgr:
				util = 0.0
			rev = int(s.a) * 1.6 * util * float(a.twist.catering)
		"bar":
			var m := bar_mix(s)
			var full := int(s.a) * float(m.vol) * 1.3 * float(m.price)
			var inc := bar_incident_rate(s, e)
			var lost := clampf(inc * bar_close_secs(e), 0.0, 1.0)   # closed after each incident
			rev = full * (1.0 - lost)
			cost += rev * 0.2 * food_cost(e) / 25.0 + inc * full * 30.0 * float(a.event_cost)
		"hotel":
			var tot := 0.0
			var rent := 0.0
			var seasons: Array = [0, 1, 2, 3] if (offline or mgr) else [season(s)]
			for sea in seasons:
				var r := hotel_best_rate(i, s, e, sea) if (mgr and bool(s.rate_auto)) or offline else float(s.rate)
				var h := _hotel_u(s, e, sea, r)
				tot += float(h.rev)
				rent = float(h.rent)
			rev = tot / seasons.size()
			up += rent
		"wholesale":
			var pm := 1.35 if mgr else (0.85 if offline else 1.0)
			rev = int(s.a) * pm * float(a.twist.wholesale)
	return {"rev": rev, "fixed": up, "var": cost}


# ------------------------------------------------------------------ real-time simulation

## Advances one business by dt seconds. Returns {rev_l, cost_l}: money for this step.
static func step(i: int, s: Dictionary, e, dt: float) -> Dictionary:
	if not s.open:
		return {"rev_l": Num.ZERO, "cost_l": Num.ZERO}
	var a: Dictionary = e.agg()
	var rng: RandomNumberGenerator = e.rng
	var fixed := upkeep_u(i, s) * dt
	var cost := 0.0
	var rev := 0.0
	var mgr := has_mgr(i, e)
	match String(DEFS[i].id):
		"truck":
			s.spot_t = float(s.spot_t) - dt
			if float(s.spot_t) <= 0.0:
				s.spot_t = SPOT_PERIOD
				var spots: Array = []
				for k in SPOTS.size():
					spots.append(snappedf(rng.randf_range(0.3, 2.4), 0.05))
				s.spots = spots
				if mgr:
					move_truck(s, best_spot(s), true)
			if float(s.move_t) > 0.0:
				s.move_t = maxf(0.0, float(s.move_t) - dt)
			else:
				rev = truck_u(s, e, float(s.spots[int(s.spot)])) * dt
		"bakery":
			s.rush_t = fmod(float(s.rush_t) + dt, RUSH_PERIOD)
			var rush := float(s.rush_t) < RUSH_LEN
			var made := float(int(s.a)) * dt
			cost += made * 0.35 * food_cost(e) / 25.0
			var stock := float(s.stock) + made
			var cap := bakery_sell_cap(s, e) * (3.0 if rush else 1.0) * dt
			var sold := minf(stock, cap)
			stock -= sold
			# shelf holds a minute of selling (3 with a Head Baker); the rest goes stale, and
			# without a Head Baker everything on the shelf loses 1% a second
			var shelf := 180.0 if mgr else 60.0
			stock = minf(stock, bakery_sell_cap(s, e) * shelf) * (1.0 if mgr else pow(0.99, dt))
			s.stock = stock
			rev = sold
		"catering":
			s.offer_t = float(s.offer_t) - dt
			if float(s.offer_t) <= 0.0 or (s.offers as Array).is_empty():
				s.offer_t = OFFER_PERIOD
				s.offers = make_offers(i, s, e)
			var done: Array = []
			for j in s.jobs:
				j.t = float(j.t) - dt
				if float(j.t) <= 0.0:
					done.append(j)
			for j in done:
				(s.jobs as Array).erase(j)
				rev += float(j.pay_u) * float(a.twist.catering)
			if mgr:
				auto_accept(i, s, e)
		"bar":
			var m := bar_mix(s)
			if float(s.closed_t) > 0.0:
				s.closed_t = maxf(0.0, float(s.closed_t) - dt)
			else:
				var full := int(s.a) * float(m.vol) * 1.3 * float(m.price)
				rev = full * dt
				cost += rev * 0.2 * food_cost(e) / 25.0
				# meter fills at 100 per incident on average
				s.rowdy = float(s.rowdy) + bar_incident_rate(s, e) * 100.0 * dt * rng.randf_range(0.6, 1.4)
				if float(s.rowdy) >= 100.0:
					s.rowdy = 0.0
					s.closed_t = bar_close_secs(e)
					s.incidents = int(s.incidents) + 1
					var fine := full * 30.0 * float(a.event_cost)
					cost += fine
					e.notify(("Bar fight! Fined %s and closed 10s" % Num.fmt_money(Num.L(fine) + rev_base_l(i, e))) if e.costs_on() else "Bar fight! Closed for 30s")
		"hotel":
			var before := season(s)
			s.season_t = fmod(float(s.season_t) + dt, SEASON_LEN * SEASONS.size())
			var sea := season(s)
			if mgr and bool(s.rate_auto) and (sea != before or float(s.rate) <= 0.0):
				s.rate = hotel_best_rate(i, s, e, sea)
			var h := _hotel_u(s, e, sea, float(s.rate))
			rev = float(h.rev) * dt
			fixed += float(h.rent) * dt
		"wholesale":
			# mean-reverting random walk between 0.4x and 2.6x
			var m0 := float(s.mprice)
			m0 += (1.0 - m0) * 0.01 * dt + rng.randfn(0.0, 0.035) * sqrt(dt * 4.0)
			s.mprice = clampf(m0, 0.4, 2.6)
			s.stock = minf(float(s.stock) + int(s.a) * dt, wholesale_cap(s))
			if mgr and bool(s.auto_sell) and (float(s.mprice) >= 1.4 or float(s.stock) >= wholesale_cap(s) * 0.98):
				rev += _sell_u(s, e)
	var rb := rev_base_l(i, e)
	var cl := Num.ZERO
	if e.costs_on():
		cl = Num.add(Num.L(fixed) + cost_base_l(i, e), Num.L(cost) + rb)
	return {"rev_l": Num.L(rev) + rb, "cost_l": cl}


# ------------------------------------------------------------------ twist actions

static func best_spot(s: Dictionary) -> int:
	var b := 0
	for k in SPOTS.size():
		if float(s.spots[k]) > float(s.spots[b]):
			b = k
	return b


static func move_truck(s: Dictionary, k: int, instant := false) -> bool:
	if k == int(s.spot) or k < 0 or k >= SPOTS.size():
		return false
	s.spot = k
	s.move_t = 3.0 if instant else MOVE_TIME
	return true


## Three contracts. Pay is in units (pay_u): crew x seconds x 1.6 x a bonus.
static func make_offers(_i: int, s: Dictionary, e) -> Array:
	var rng: RandomNumberGenerator = e.rng
	var out: Array = []
	var crew := maxi(1, int(s.a))
	for k in 3:
		var frac := rng.randf_range(0.15, 0.8)
		var need := maxi(1, int(round(crew * frac)))
		var dur := snappedf(rng.randf_range(30.0, 150.0), 5.0)
		# short jobs and big jobs pay a premium
		var bonus := rng.randf_range(0.8, 1.6) * (1.0 + 30.0 / dur * 0.3) * (1.0 + frac * 0.4)
		out.append({"name": JOB_NAMES[rng.randi() % JOB_NAMES.size()], "crew": need, "dur": dur,
			"pay_u": need * dur * 1.6 * bonus, "bonus": bonus})
	return out


## What a contract pays (log), at today's multipliers.
static func pay_l(i: int, o: Dictionary, e) -> float:
	return Num.L(float(o.pay_u) * float(e.agg().twist.catering)) + rev_base_l(i, e)


static func can_accept(s: Dictionary, k: int) -> bool:
	if k < 0 or k >= (s.offers as Array).size():
		return false
	var o: Dictionary = s.offers[k]
	return (s.jobs as Array).size() < catering_max_jobs(s) and int(s.a) - busy_crew(s) >= int(o.crew)


static func accept(s: Dictionary, k: int) -> bool:
	if not can_accept(s, k):
		return false
	var o: Dictionary = s.offers[k]
	(s.jobs as Array).append({"name": o.name, "crew": int(o.crew), "t": float(o.dur), "dur": float(o.dur), "pay_u": float(o.pay_u)})
	(s.offers as Array).remove_at(k)
	return true


static func auto_accept(_i: int, s: Dictionary, _e) -> void:
	var tries := 3
	while tries > 0:
		tries -= 1
		var best := -1
		var best_v := 0.0
		for k in (s.offers as Array).size():
			if can_accept(s, k):
				var o: Dictionary = s.offers[k]
				var v := float(o.bonus)
				if v > best_v:
					best_v = v
					best = k
		if best < 0:
			return
		accept(s, best)


static func _sell_u(s: Dictionary, e) -> float:
	var v := float(s.stock) * float(s.mprice) * float(e.agg().twist.wholesale) * 0.9
	s.stock = 0.0
	return v


## Sells all stock now. Returns the money (log); the caller adds it as earnings.
static func sell_stock_l(i: int, s: Dictionary, e) -> float:
	return Num.L(_sell_u(s, e)) + rev_base_l(i, e)


# ------------------------------------------------------------------ upgrades

## Adds the upgrades for every business to the econ catalogue, and their infinite lines.
static func add_upgrades(e) -> void:
	var extra_names := {
		"truck": ["Fresh Paint Job", "Social Media Map", "Secret Sauce", "Late-Night Run", "Truck Rally", "Festival Pass",
			"Food Truck Award", "Gourmet Fusion", "Fleet Wrap", "Street Food Legend", "TV Food Tour", "Truck Empire",
			"Night Market King", "City Permit Deal", "Influencer Stops", "Mobile Ordering", "Signature Truck", "Rolling Icon"],
		"bakery": ["Sourdough Starter", "Butter Croissants", "Wedding Cakes", "Bread Subscriptions", "Rustic Loaves",
			"French Pastry Chef", "Baguette Battle Win", "Pie Contest Ribbon", "Cake Decorating", "Gluten-Free Line",
			"Artisan Flour Mill", "Cronut Craze", "Bake-Off Champion", "Royal Warrant", "Sugar Sculpture",
			"Viennoiserie", "Bread Museum", "Patisserie Legend"],
		"catering": ["Polished Silverware", "Ice Sculptures", "Champagne Tower", "Event Planner", "Celebrity Clients",
			"Wedding Expo Booth", "Food Stations", "Live Carving", "Corporate Retainer", "Destination Weddings",
			"Royal Wedding", "Presidential Dinner", "Award Show Contract", "Gala Season", "Black Tie Brand",
			"Global Events Arm", "Mile-High Catering", "Legendary Feasts"],
		"bar": ["Craft Bitters", "Speakeasy Door", "Live DJ", "Signature Cocktail", "Rooftop Bar", "Mixology Award",
			"Velvet Rope", "Bottle Service", "Smoked Old Fashioned", "Bar of the Year", "Secret Menu Drinks",
			"Jazz Nights", "Celebrity Mixologist", "World's 50 Best", "Private Label Gin", "Molecular Cocktails",
			"Legendary Pour", "Golden Shaker"],
		"hotel": ["Fluffy Towels", "Room Service", "Spa Treatments", "Rooftop Pool", "Michelin Concierge", "Butler Service",
			"Penthouse Suite", "Travel Award", "Infinity Pool", "Private Island Tours", "Five Stars", "Celebrity Suite",
			"Helipad", "Underwater Suite", "Seven Stars", "Space Window Suite", "Royal Patronage", "Hotel Legend"],
		"wholesale": ["Barcode Scanners", "Pallet Jacks", "Forklift Fleet", "Cold Chain", "Bulk Contracts", "Import License",
			"Trading Desk", "Futures Contracts", "Auto Warehouse", "Global Sourcing", "Commodity Index", "Port Terminal",
			"Cargo Airline", "Market Maker", "Robot Warehouse", "Supply Monopoly", "World Pantry", "Trade Empire"],
	}
	var mgr_names := {"truck": "Route Planner", "bakery": "Head Baker", "catering": "Events Manager",
		"bar": "Bar Manager", "hotel": "Revenue Manager", "wholesale": "Commodity Trader"}
	var x_at := [5, 15, 30, 45, 60, 80, 100, 120, 140, 160, 180, 200, 230, 260, 290, 320, 360, 400]
	for i in N:
		var d: Dictionary = DEFS[i]
		var id: String = d.id
		var akeys: Array = []
		for mi in A_MILESTONES.size():
			var n: int = A_MILESTONES[mi]
			e._add("bz_%s_a%d" % [id, n], "%s: %d %s" % [d.name, n, d.as], "business", Num.ZERO, [["biz", i, MILESTONE_X]], ["biz", i, "a", n],
				{"cost_l": Num.L(3.0) + cost_at_l(i, "a", n - 1), "biz": i})
			akeys.append("bz_%s_a%d" % [id, n])
		var ii: int = i
		var dd: Dictionary = d
		e._track("bz_%s_a" % id, akeys, func(mi: int) -> Dictionary:
			var n: int = 1000 + 25 * (mi - A_MILESTONES.size() + 1)
			return {"name": "%s: %s %s" % [dd.name, Econ.fmt_count(n), dd.as], "cat": "business", "eff": [["biz", ii, MILESTONE_X]],
				"cost_l": Num.L(3.0) + cost_at_l(ii, "a", n - 1), "req": ["biz", ii, "a", n], "biz": ii})
		for mi in B_MILESTONES.size():
			var n: int = B_MILESTONES[mi]
			var eff: Array = [["twist", id, 1.25]]
			if id == "bar":
				eff = [["twist", id, 0.75]]
			e._add("bz_%s_b%d" % [id, n], "%s: %d %s" % [d.name, n, d.bs], "business", Num.ZERO, eff, ["biz", i, "b", n],
				{"cost_l": Num.L(3.0) + cost_at_l(i, "b", n - 1), "biz": i})
		e._add("bz_%s_mgr" % id, "%s: %s" % [d.name, mgr_names[id]], "business", Num.ZERO, [["flag", "mgr_" + id]], ["biz", i, "open", 1],
			{"cost_l": open_cost_l(i) + Num.L(3.0), "biz": i})
		e._add("bz_%s_auto" % id, "%s: Expansion Manager" % d.name, "business", Num.ZERO, [["flag", "auto_" + id]], ["biz", i, "a", 25],
			{"cost_l": open_cost_l(i) + Num.L(30.0), "biz": i})
		var names: Array = extra_names[id]
		var xkeys: Array = []
		for t in names.size():
			e._add("bz_%s_x%d" % [id, t], "%s: %s" % [d.name, names[t]], "business", Num.ZERO, [["biz", i, 1.3]], ["biz", i, "a", x_at[t]],
				{"cost_l": Num.L(10.0) + cost_at_l(i, "a", x_at[t]), "biz": i})
			xkeys.append("bz_%s_x%d" % [id, t])
		var nm: Array = names
		e._track("bz_%s_x" % id, xkeys, func(t: int) -> Dictionary:
			var at: int = 400 + 50 * (t - nm.size() + 1)
			return {"name": "%s: %s %s" % [dd.name, nm[t % nm.size()], Econ.roman(t / nm.size() + 1)], "cat": "business",
				"eff": [["biz", ii, 1.3]], "cost_l": Num.L(10.0) + cost_at_l(ii, "a", at), "req": ["biz", ii, "a", at], "biz": ii})
	# a few that help every business, then forever
	var all_names := ["Holding Company", "Shared Accounting", "Group Purchasing", "Executive Team", "Conglomerate",
		"Board of Directors", "Stock Listing", "Global Brand Portfolio", "Mega Corp", "Empire Holdings"]
	var all_cost := func(t: int) -> float:
		return open_cost_l(0) + Num.L(30.0) + 1.2 * t
	var allkeys: Array = []
	for t in all_names.size():
		e._add("bz_all_%d" % t, all_names[t], "business", Num.ZERO, [["mul", "biz", 1.25]], ["bizopen", mini(t / 2 + 1, N)],
			{"cost_l": all_cost.call(t)})
		allkeys.append("bz_all_%d" % t)
	e._track("bz_all", allkeys, func(t: int) -> Dictionary:
		var c: float = all_cost.call(t)
		return {"name": "%s %s" % [all_names[t % all_names.size()], Econ.roman(t / all_names.size() + 1)], "cat": "business",
			"eff": [["mul", "biz", 1.25]], "cost_l": c, "req": ["earn", c + Num.L(0.08)]})
