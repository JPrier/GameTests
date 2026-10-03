class_name Biz
extends RefCounted
## Side businesses you run alongside the restaurant. Each has two builds (A and B) and a twist:
##
##   Food Truck   pick a spot; each spot's crowd changes every few minutes.
##   Bakery       ovens bake, counters sell; unsold stock goes stale, and a morning rush sells triple.
##   Catering     take contracts that tie up crew for a while and pay on completion.
##   Bar          huge margins, but crowds get rowdy; incidents cost fines. Happy hour trades risk for volume.
##   Hotel        set room rates per season; rent is paid on every room, full or empty.
##   Wholesale    warehouses fill with stock you sell on a moving market; trucks cut food costs empire-wide.
##
## Every business has running costs per build (fuel, wages, rent) that grow with its own upgrades,
## and some have per-sale costs, so a badly run business can lose money. Money is computed two ways: step() simulates the twist in real time while the
## game runs, estimate() gives a steady-state rate for display, offline time and the balance bot.

const REV_K := 2.0e-5             # revenue per unit per second, relative to the business's scale

const DEFS := [
	{"id": "truck", "name": "Food Truck", "unlock": 3.0e5, "a": "Truck", "as": "Trucks", "b": "Menu Item", "bs": "Menu Items",
		"a_cost": 0.002, "b_cost": 0.02, "ga": 1.15, "gb": 1.22, "color": "ff8a3d", "rev": 4.0,
		"blurb": "Park where the crowds are. Each spot's crowd changes every few minutes; moving takes 15s.",
		"a_desc": "+1 truck selling food", "b_desc": "+10% per sale"},
	{"id": "bakery", "name": "Bakery", "unlock": 3.0e7, "a": "Oven", "as": "Ovens", "b": "Counter", "bs": "Counters",
		"a_cost": 0.002, "b_cost": 0.004, "ga": 1.15, "gb": 1.16, "color": "e0c27a", "rev": 2.5,
		"blurb": "Ovens bake, counters sell. Unsold bread goes stale; a morning rush every 4 minutes sells triple.",
		"a_desc": "+1 loaf/s baked", "b_desc": "+1.5 loaves/s sold"},
	{"id": "catering", "name": "Catering Co.", "unlock": 3.0e9, "a": "Crew", "as": "Crew", "b": "Van", "bs": "Vans",
		"a_cost": 0.002, "b_cost": 0.05, "ga": 1.15, "gb": 1.6, "color": "6cc56b",
		"blurb": "Take contracts: weddings, galas, festivals. Crew is busy until the job ends, then it pays.",
		"a_desc": "+1 crew member", "b_desc": "+1 job at a time"},
	{"id": "bar", "name": "Cocktail Bar", "unlock": 3.0e11, "a": "Bartender", "as": "Bartenders", "b": "Bouncer", "bs": "Bouncers",
		"a_cost": 0.002, "b_cost": 0.006, "ga": 1.15, "gb": 1.17, "color": "b58cff",
		"blurb": "Fat margins, rowdy crowds. When the rowdy meter fills there's an incident and a fine.",
		"a_desc": "+1 drink/s", "b_desc": "Keeps the peace"},
	{"id": "hotel", "name": "Boutique Hotel", "unlock": 3.0e13, "a": "Room", "as": "Rooms", "b": "Concierge", "bs": "Concierges",
		"a_cost": 0.002, "b_cost": 0.005, "ga": 1.15, "gb": 1.17, "color": "5aa9e6",
		"blurb": "Set your room rate each season. Rent is due on every room, full or empty.",
		"a_desc": "+1 room (+rent)", "b_desc": "+more guests want to stay"},
	{"id": "wholesale", "name": "Wholesale Co.", "unlock": 3.0e15, "a": "Warehouse", "as": "Warehouses", "b": "Delivery Truck", "bs": "Delivery Trucks",
		"a_cost": 0.002, "b_cost": 0.01, "ga": 1.15, "gb": 1.2, "color": "6ad1c0",
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
const A_MILESTONES := [10, 25, 50, 75, 100, 150, 200, 250, 300, 400, 500, 600, 700, 850, 1000]
const B_MILESTONES := [5, 10, 25, 50, 100, 150]


# ------------------------------------------------------------------ state

static func blank(i: int) -> Dictionary:
	var s := {"open": false, "a": 0, "b": 0, "earned": 0.0}
	match String(DEFS[i].id):
		"truck": s.merge({"spot": 0, "spots": [1.0, 1.0, 1.0, 1.0], "spot_t": 0.0, "move_t": 0.0})
		"bakery": s.merge({"stock": 0.0, "rush_t": 0.0})
		"catering": s.merge({"offers": [], "jobs": [], "offer_t": 0.0})
		"bar": s.merge({"happy": false, "rowdy": 0.0, "closed_t": 0.0, "incidents": 0})
		"hotel": s.merge({"rate": 1.0, "rate_auto": true, "season_t": 0.0})
		"wholesale": s.merge({"stock": 0.0, "mprice": 1.0, "auto_sell": true})
	return s


## Scale of a business: everything is priced relative to cp(unlock).
static func scale(i: int) -> float:
	return Econ.cp(float(DEFS[i].unlock))


static func unit_rev(i: int) -> float:
	return scale(i) * REV_K * float(DEFS[i].get("rev", 1.0))


static func unlock_at(i: int) -> float:
	return scale(i)


static func open_cost(i: int) -> float:
	return Econ.cp(float(DEFS[i].unlock) * 0.25)


static func growth(i: int, which: String) -> float:
	return pow(float(DEFS[i]["g" + which]), Econ.COST_POW)


static func base_cost(i: int, which: String) -> float:
	return Econ.cp(float(DEFS[i].unlock) * float(DEFS[i][which + "_cost"]))


static func cost_at(i: int, which: String, n: int) -> float:
	return base_cost(i, which) * pow(growth(i, which), n)


static func cost_of(i: int, which: String, n: int, k: int) -> float:
	var g := growth(i, which)
	return cost_at(i, which, n) * (pow(g, k) - 1.0) / (g - 1.0)


static func invested(i: int, s: Dictionary) -> float:
	# the first of each build comes with opening
	return cost_of(i, "a", 1, maxi(0, int(s.a) - 1)) + cost_of(i, "b", 1, maxi(0, int(s.b) - 1)) + (open_cost(i) if s.open else 0.0)


## Running costs per second for the builds (not per-sale costs).
const RUN_A := {"truck": 0.35, "bakery": 0.0, "catering": 0.4, "bar": 0.2, "hotel": 0.0, "wholesale": 0.25}
const RUN_B := {"truck": 0.0, "bakery": 0.2, "catering": 0.0, "bar": 0.4, "hotel": 0.0, "wholesale": 0.3}


static func cost_mult(i: int, e) -> float:
	var a: Dictionary = e.agg()
	return float(a.biz[i]) * float(a.mul.biz) * float(a.upkeep) * e.effect_mult("wages")


static func upkeep(i: int, s: Dictionary, e) -> float:
	if not s.open:
		return 0.0
	var id: String = DEFS[i].id
	return (int(s.a) * float(RUN_A[id]) + int(s.b) * float(RUN_B[id])) * unit_rev(i) * cost_mult(i, e)


# ------------------------------------------------------------------ helpers

static func mult(i: int, e) -> float:
	var a: Dictionary = e.agg()
	return float(a.biz[i]) * float(a.mul.biz) * brand(e) * e.star_mult(a) * e.grit_mult(a) * float(a.mul.empire) * e.effect_mult("income")


## Franchising makes your name famous, which draws customers to every business you run.
static func brand(e) -> float:
	return 1.0 + 0.5 * log(e.franchise_mult(e.agg())) / log(10.0)


static func has_mgr(i: int, e) -> bool:
	return e.agg().flags.has("mgr_" + String(DEFS[i].id))


static func food_cost(e) -> float:
	return e.food_cost_pct()


static func truck_rev(i: int, s: Dictionary, e, spot_mult: float) -> float:
	var a: Dictionary = e.agg()
	return int(s.a) * unit_rev(i) * (1.0 + 0.1 * int(s.b)) * spot_mult * float(a.twist.truck) * mult(i, e)


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


static func hotel_demand(s: Dictionary, e, season: int, rate: float) -> float:
	return hotel_quality(s, e) * 4.0 * float(SEASON_MULT[season]) * pow(maxf(rate, 0.05), -1.6)


static func hotel_best_rate(i: int, s: Dictionary, e, season: int) -> float:
	if int(s.a) <= 0:
		return 1.0
	# demand exactly fills the rooms; any lower and you're giving rooms away
	return clampf(pow(hotel_quality(s, e) * 4.0 * float(SEASON_MULT[season]) / float(int(s.a)), 1.0 / 1.6), 0.2, 20.0)


static func season(s: Dictionary) -> int:
	return int(float(s.season_t) / SEASON_LEN) % SEASONS.size()


static func hotel_rev(i: int, s: Dictionary, e, sea: int, rate: float) -> Dictionary:
	var rooms := float(int(s.a))
	var occ := minf(rooms, hotel_demand(s, e, sea, rate))
	var m := mult(i, e)
	return {"rev": occ * rate * unit_rev(i) * 2.2 * m, "rent": rooms * unit_rev(i) * 0.6 * cost_mult(i, e), "occ": occ / maxf(rooms, 1.0)}


static func wholesale_cap(s: Dictionary) -> float:
	return int(s.a) * 240.0


static func wholesale_price(i: int, s: Dictionary, e) -> float:
	return unit_rev(i) * float(s.mprice) * float(e.agg().twist.wholesale) * mult(i, e)


## Percentage points knocked off food costs everywhere by delivery trucks.
static func food_cut(s: Dictionary) -> float:
	if not s.open:
		return 0.0
	return 15.0 * (1.0 - 1.0 / (1.0 + 0.08 * int(s.b)))


# ------------------------------------------------------------------ steady-state estimates

## {rev, cost} per second, the long-run average. offline=true assumes nobody is there to act.
static func estimate(i: int, s: Dictionary, e, offline := false) -> Dictionary:
	if not s.open:
		return {"rev": 0.0, "cost": 0.0}
	var a: Dictionary = e.agg()
	var up := upkeep(i, s, e)
	var mgr := has_mgr(i, e)
	var rev := 0.0
	var cost := up
	match String(DEFS[i].id):
		"truck":
			var sm := 1.0
			if mgr:
				sm = 1.6
			elif not offline:
				sm = float(s.spots[int(s.spot)]) if float(s.move_t) <= 0.0 else 0.0
			rev = truck_rev(i, s, e, sm)
		"bakery":
			var made := float(int(s.a))
			var sold := minf(made, bakery_sell_cap(s, e))
			var price := unit_rev(i) * mult(i, e)
			rev = sold * price
			cost += made * price * 0.35 * food_cost(e) / 25.0
		"catering":
			var util := minf(0.9, 0.35 + 0.12 * int(s.b) + (0.15 if mgr else 0.0))
			if offline and not mgr:
				util = 0.0
			rev = int(s.a) * unit_rev(i) * 1.6 * util * float(a.twist.catering) * mult(i, e)
		"bar":
			var m := bar_mix(s)
			var per := unit_rev(i) * 1.3 * float(m.price) * mult(i, e)
			var full := int(s.a) * float(m.vol) * per
			var inc := bar_incident_rate(s, e)
			var lost := clampf(inc * 10.0, 0.0, 1.0)   # closed 10s per incident
			rev = full * (1.0 - lost)
			cost += rev * 0.2 * food_cost(e) / 25.0 + inc * full * 30.0 * float(a.event_cost)
		"hotel":
			var tot := 0.0
			var rent := 0.0
			var seasons: Array = [0, 1, 2, 3] if (offline or mgr) else [season(s)]
			for sea in seasons:
				var r := hotel_best_rate(i, s, e, sea) if (mgr and bool(s.rate_auto)) or offline else float(s.rate)
				var h := hotel_rev(i, s, e, sea, r)
				tot += float(h.rev)
				rent = float(h.rent)
			rev = tot / seasons.size()
			cost += rent
		"wholesale":
			var pm := 1.35 if mgr else (0.85 if offline else 1.0)
			rev = int(s.a) * unit_rev(i) * pm * float(a.twist.wholesale) * mult(i, e)
	return {"rev": rev, "cost": cost}


# ------------------------------------------------------------------ real-time simulation

## Advances one business by dt seconds. Returns {rev, cost} money amounts for this step.
static func step(i: int, s: Dictionary, e, dt: float) -> Dictionary:
	if not s.open:
		return {"rev": 0.0, "cost": 0.0}
	var a: Dictionary = e.agg()
	var rng: RandomNumberGenerator = e.rng
	var cost := upkeep(i, s, e) * dt
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
				rev = truck_rev(i, s, e, float(s.spots[int(s.spot)])) * dt
		"bakery":
			s.rush_t = fmod(float(s.rush_t) + dt, RUSH_PERIOD)
			var rush := float(s.rush_t) < RUSH_LEN
			var price := unit_rev(i) * mult(i, e)
			var made := float(int(s.a)) * dt
			cost += made * price * 0.35 * food_cost(e) / 25.0
			var stock := float(s.stock) + made
			var cap := bakery_sell_cap(s, e) * (3.0 if rush else 1.0) * dt
			var sold := minf(stock, cap)
			stock -= sold
			# shelf holds a minute of selling (3 with a Head Baker); the rest goes stale, and
			# without a Head Baker everything on the shelf loses 1% a second
			var shelf := 180.0 if mgr else 60.0
			stock = minf(stock, bakery_sell_cap(s, e) * shelf) * (1.0 if mgr else pow(0.99, dt))
			s.stock = stock
			rev = sold * price
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
				rev += float(j.pay) * float(a.twist.catering) * mult(i, e)
			if mgr:
				auto_accept(i, s, e)
		"bar":
			var m := bar_mix(s)
			if float(s.closed_t) > 0.0:
				s.closed_t = maxf(0.0, float(s.closed_t) - dt)
			else:
				var per := unit_rev(i) * 1.3 * float(m.price) * mult(i, e)
				rev = int(s.a) * float(m.vol) * per * dt
				cost += rev * 0.2 * food_cost(e) / 25.0
				# meter fills at 100 per incident on average
				s.rowdy = float(s.rowdy) + bar_incident_rate(s, e) * 100.0 * dt * rng.randf_range(0.6, 1.4)
				if float(s.rowdy) >= 100.0:
					s.rowdy = 0.0
					s.closed_t = 10.0
					s.incidents = int(s.incidents) + 1
					var fine := int(s.a) * float(m.vol) * per * 30.0 * float(a.event_cost)
					cost += fine
					e.notify("Bar fight! Fined %s and closed 10s" % Econ.fmt_money(fine))
		"hotel":
			var before := season(s)
			s.season_t = fmod(float(s.season_t) + dt, SEASON_LEN * SEASONS.size())
			var sea := season(s)
			if mgr and bool(s.rate_auto) and (sea != before or float(s.rate) <= 0.0):
				s.rate = hotel_best_rate(i, s, e, sea)
			var h := hotel_rev(i, s, e, sea, float(s.rate))
			rev = float(h.rev) * dt
			cost += float(h.rent) * dt
		"wholesale":
			# mean-reverting random walk between 0.4x and 2.6x
			var m0 := float(s.mprice)
			m0 += (1.0 - m0) * 0.01 * dt + rng.randfn(0.0, 0.035) * sqrt(dt * 4.0)
			s.mprice = clampf(m0, 0.4, 2.6)
			s.stock = minf(float(s.stock) + int(s.a) * dt, wholesale_cap(s))
			if mgr and bool(s.auto_sell) and (float(s.mprice) >= 1.4 or float(s.stock) >= wholesale_cap(s) * 0.98):
				rev += sell_stock(i, s, e)
	return {"rev": rev, "cost": cost}


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


static func make_offers(i: int, s: Dictionary, e) -> Array:
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
			"pay": need * dur * unit_rev(i) * 1.6 * bonus, "bonus": bonus})
	return out


static func can_accept(s: Dictionary, k: int) -> bool:
	if k < 0 or k >= (s.offers as Array).size():
		return false
	var o: Dictionary = s.offers[k]
	return (s.jobs as Array).size() < catering_max_jobs(s) and int(s.a) - busy_crew(s) >= int(o.crew)


static func accept(s: Dictionary, k: int) -> bool:
	if not can_accept(s, k):
		return false
	var o: Dictionary = s.offers[k]
	(s.jobs as Array).append({"name": o.name, "crew": int(o.crew), "t": float(o.dur), "dur": float(o.dur), "pay": float(o.pay)})
	(s.offers as Array).remove_at(k)
	return true


static func auto_accept(i: int, s: Dictionary, e) -> void:
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


static func sell_stock(i: int, s: Dictionary, e) -> float:
	var v := float(s.stock) * wholesale_price(i, s, e) * 0.9
	s.stock = 0.0
	return v


# ------------------------------------------------------------------ upgrades

## Adds the upgrades for every business to the econ catalogue.
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
	var b_eff := {"truck": "twist", "bakery": "twist", "catering": "twist", "bar": "twist", "hotel": "twist", "wholesale": "twist"}
	var b_text := {"truck": "Crowds", "bakery": "Counter speed", "catering": "Contract pay", "bar": "Calm", "hotel": "Guest demand", "wholesale": "Sale price"}
	var mgr_names := {"truck": "Route Planner", "bakery": "Head Baker", "catering": "Events Manager",
		"bar": "Bar Manager", "hotel": "Revenue Manager", "wholesale": "Commodity Trader"}
	for i in N:
		var d: Dictionary = DEFS[i]
		var id: String = d.id
		var u := float(d.unlock)
		for mi in A_MILESTONES.size():
			var n: int = A_MILESTONES[mi]
			var x := 2.0 if mi < 2 else 1.25
			var c := u * float(d.a_cost) * pow(float(d.ga), n - 1) * 3.0
			e._add("bz_%s_a%d" % [id, n], "%s: %d %s" % [d.name, n, d.as], "business", c, [["biz", i, x]], ["biz", i, "a", n])
		for mi in B_MILESTONES.size():
			var n: int = B_MILESTONES[mi]
			var c := u * float(d.b_cost) * pow(float(d.gb), n - 1) * 3.0
			var eff: Array = [["twist", id, 1.25]]
			if id == "bar":
				eff = [["twist", id, 0.75]]
			e._add("bz_%s_b%d" % [id, n], "%s: %d %s" % [d.name, n, d.bs], "business", c, eff, ["biz", i, "b", n])
		e._add("bz_%s_mgr" % id, "%s: %s" % [d.name, mgr_names[id]], "business", u * 0.5, [["flag", "mgr_" + id]], ["biz", i, "open", 1])
		var names: Array = extra_names[id]
		for t in names.size():
			var c := u * 0.02 * pow(10.0, 1.6 * t)
			e._add("bz_%s_x%d" % [id, t], "%s: %s" % [d.name, names[t]], "business", c, [["biz", i, 1.25]], ["biz", i, "earn", c])
	# a few that help every business
	var all_names := ["Holding Company", "Shared Accounting", "Group Purchasing", "Executive Team", "Conglomerate",
		"Board of Directors", "Stock Listing", "Global Brand Portfolio", "Mega Corp", "Empire Holdings"]
	for t in all_names.size():
		e._add("bz_all_%d" % t, all_names[t], "business", pow(10.0, 9.0 + 4.0 * t), [["mul", "biz", 1.25]], ["bizopen", mini(t / 2 + 1, N)])
