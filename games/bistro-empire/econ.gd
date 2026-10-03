class_name Econ
extends RefCounted
## Bistro Empire economy: game state and rules only, no rendering.
##
## Income = served customers/s x ticket x price x multipliers.
##   served = min(demand x price^-elasticity, min(seating, kitchen))
## so the three volume stats bottleneck each other, and price turns surplus
## demand into money up to a price ceiling. Franchises, ventures and stars
## multiply the flagship on top.
##
## Money out: food costs (a % of restaurant revenue), upkeep on everything you've built,
## loan interest, and random events. If cash stays below zero past the deadline the whole
## empire goes bankrupt: the run resets and you earn Grit, a second prestige currency.
## Side businesses (biz.gd) earn alongside the restaurant.

const STATS := ["demand", "seating", "kitchen", "ticket"]
const STAT_NAME := {"demand": "Demand", "seating": "Seating", "kitchen": "Kitchen", "ticket": "Ticket",
	"global": "Restaurant income", "tap": "Serve tap", "royalty": "Franchise royalties", "ceiling": "Price ceiling",
	"biz": "All business income", "empire": "All income"}
const REPS := ["ads", "tables", "cooks", "recipes"]
const REP_NAME := {"ads": "Ad Campaign", "tables": "Table", "cooks": "Line Cook", "recipes": "Recipe"}
const REP_PLURAL := {"ads": "Ad Campaigns", "tables": "Tables", "cooks": "Line Cooks", "recipes": "Recipes"}
const REP_STAT := {"ads": "demand", "tables": "seating", "cooks": "kitchen", "recipes": "ticket"}
const STAT_REP := {"demand": "ads", "seating": "tables", "kitchen": "cooks", "ticket": "recipes"}
const REP_COST := {"ads": 12.0, "tables": 8.0, "cooks": 10.0, "recipes": 20.0}
const REP_GROWTH := {"ads": 1.15, "tables": 1.14, "cooks": 1.15, "recipes": 1.17}
const REP_ADD := {"ads": 0.5, "tables": 0.4, "cooks": 0.4, "recipes": 0.5}
const BASE := {"demand": 1.2, "seating": 1.0, "kitchen": 1.0, "ticket": 4.0}
const MILESTONES := [25, 50, 100, 150, 200, 250, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1750, 2000]
const PRICE_MIN := 0.25
const MAX_MONEY := 1.0e300
## Every cash price is raised to this power. Larger = slower growth per order of magnitude.
const COST_POW := 1.2
const STAR_BASE := 0.02
const OFFLINE_BASE := 0.25
const OFFLINE_HOURS_BASE := 2.0
const CITY_GROWTH := 1.8
const FOOD_BASE := 25.0           # % of a plate's base value spent on ingredients
const RENT_K := 0.1              # per idle seat, as a share of a plate's base value
const WAGE_K := 0.1              # per idle kitchen slot
const MARKETING_K := 0.05         # per guest turned away (ads that brought people you can't serve)
const CREDIT_SECS := 600.0        # credit limit = this many seconds of gross income
const INTEREST_BASE := 0.005 / 60.0  # 0.5% per minute at low borrowing
const DEADLINE_BASE := 300.0      # seconds you can stay in the red
const GRIT_BASE := 0.01           # +1% all income per unspent Grit
const STAR_COEF := 25.0
const VENT_GROWTH := 1.5

const CONCEPTS := ["diner", "fastfood", "fine", "cafe"]
const CONCEPT := {
	"diner": {"name": "Diner", "blurb": "Balanced and forgiving. Cheap tables, +25% all income.",
		"mult": {"global": 1.25}, "elastic": 2.0, "ceiling": 3.0, "rep_cost": {"tables": 0.75}, "unlock": 0, "color": "f5c451"},
	"fastfood": {"name": "Fast Food", "blurb": "Huge volume, tiny bills. Guests flee high prices.",
		"mult": {"kitchen": 3.0, "seating": 2.5, "demand": 4.0, "ticket": 0.5}, "elastic": 2.4, "ceiling": 2.2,
		"rep_cost": {"ads": 0.7, "cooks": 0.8}, "unlock": 0, "color": "ff7a45"},
	"fine": {"name": "Fine Dining", "blurb": "Few seats, enormous bills. Prices barely scare guests.",
		"mult": {"ticket": 2.5, "seating": 0.4, "demand": 0.5}, "elastic": 1.7, "ceiling": 4.0,
		"rep_cost": {"recipes": 0.7}, "unlock": 1, "color": "c58bff"},
	"cafe": {"name": "Café", "blurb": "Hands-on. SERVE taps are worth far more, and earn % of income.",
		"mult": {"tap": 10.0, "global": 0.9}, "tappct": 0.03, "elastic": 2.0, "ceiling": 3.0,
		"rep_cost": {"recipes": 0.85}, "unlock": 2, "color": "6ad1c0"},
}

const CITY_NAMES := ["Maple Falls", "Riverton", "Cedar Grove", "Port Haven", "Brookfield", "Austin", "Denver",
	"Reykjavik", "Seattle", "Chicago", "Toronto", "Mexico City", "Dublin", "London", "Paris", "Berlin", "Rome",
	"Madrid", "Istanbul", "Dubai", "Mumbai", "Singapore", "Seoul", "Tokyo", "Sydney", "Sao Paulo", "New York",
	"Orbital Station", "Lunar Base", "Mars Colony"]
const VENTURES := [
	{"name": "Street Food Brand", "stat": "demand"},
	{"name": "Family Farm", "stat": "ticket"},
	{"name": "Furniture Workshop", "stat": "seating"},
	{"name": "Culinary School", "stat": "kitchen"},
	{"name": "Delivery App", "stat": "demand"},
	{"name": "Cooking Show", "stat": "royalty"},
	{"name": "Frozen Food Line", "stat": "ticket"},
	{"name": "Global Spice Co.", "stat": "global"},
]
const VENT_RATE := 0.02
const VENT_MILESTONES := [5, 10, 25, 50, 75, 100, 125, 150, 200, 250, 300, 400]
const CITY_MILESTONES := [1, 5, 10, 15, 20, 30, 40, 50]
const CITY_MS_MULT := [1.5, 1.25, 1.25, 1.5, 1.25, 1.25, 1.5, 2.0]
const CITY_MS_NAME := ["Grand Opening", "Local Supplier", "Neighbourhood Favourite", "City Billboard",
	"Regional HQ", "City Icon", "Landmark Status", "Capital of Flavour"]

var NC: int = CITY_NAMES.size()
var NV: int = VENTURES.size()
var city_cost: Array = []
var city_yield: Array = []
var vent_cost: Array = []

# ---------------------------------------------------------------- upgrade catalogue
var run_upgrade_count := 0
var upgrades: Array = []          # [{id, name, cat, cost, star, req, eff, excl, concept, legacy}]
var by_key: Dictionary = {}

# ---------------------------------------------------------------- state
var cash := 0.0
var run_earned := 0.0
var life_earned := 0.0
var stars := 0.0                  # unspent
var stars_earned := 0.0           # ever
var prestiges := 0
var concept := "diner"
var reps := {"ads": 0, "tables": 0, "cooks": 0, "recipes": 0}
var owned := {}                   # run upgrades id -> true
var legacy := {}                  # legacy upgrades id -> true
var cities: Array = []
var vents: Array = []
var price := 1.0
var price_auto := true            # only honoured once the auto-price flag is owned
var auto_on := {}                 # automation key -> bool (player toggles)
var run_time := 0.0
var play_time := 0.0
var taps := 0
var best_income := 0.0
var concept_chosen := false
var biz: Array = []               # side businesses, see biz.gd
var debt := 0.0
var grit := 0.0                   # unspent
var grit_earned := 0.0
var bankruptcies := 0
var red_t := 0.0                  # seconds spent with cash below zero
var effects: Array = []           # [{kind, mult, t, dur, src}] timed effects from events
var event: Dictionary = {}        # the event card waiting for an answer
var event_t := Events.MIN_GAP     # seconds of active play until the next event
var peak_gross := 0.0             # best gross income per second this run
var events_on := true
var last_bankrupt: Dictionary = {}
var notes: Array = []             # short messages for the UI to show
var rng := RandomNumberGenerator.new()

var _agg: Dictionary = {}
var _dirty := true


func _init() -> void:
	rng.randomize()
	for i in NC:
		city_cost.append(5.0e6 * ladder(0.0, 2.4, 3.4, i, NC))
		city_yield.append(pow(4.0, i))
	for i in NV:
		vent_cost.append(1.0e9 * ladder(0.0, 10.0, 10.0, i, NV))
	_build_catalogue()
	for u in upgrades:
		if not u.legacy:
			run_upgrade_count += 1
	reset_run_state()


# ================================================================= catalogue

static func cp(c: float) -> float:
	return pow(c, COST_POW)


## Cost exponent (log10) for tier t of n, with the step widening from s0 to s1 decades.
static func ladder(start: float, s0: float, s1: float, t: int, n: int) -> float:
	var k := (s1 - s0) / maxf(1.0, float(n - 1))
	return pow(10.0, start + s0 * t + k * t * t * 0.5)


static func roman(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var s := ""
	for i in vals.size():
		while n >= vals[i]:
			s += syms[i]
			n -= vals[i]
	return s


func _add(key: String, name: String, cat: String, cost: float, eff: Array, req: Array = [], extra: Dictionary = {}) -> Dictionary:
	var u := {"id": upgrades.size(), "key": key, "name": name, "cat": cat, "cost": cp(cost) if cost > 0.0 else 0.0, "eff": eff,
		"req": req, "excl": -1, "concept": "", "legacy": false, "star": 0.0}
	for k in extra:
		u[k] = extra[k]
	if req.is_empty() and not u.legacy:
		u.req = ["earn", float(u.cost) * 0.08]
	upgrades.append(u)
	by_key[key] = u.id
	return u


func _build_catalogue() -> void:
	upgrades.clear()
	by_key.clear()
	# ---- 1. stat tiers: 60 each for demand, seating, kitchen; 60 dishes for ticket
	var nouns := {
		"demand": ["Hand-Drawn Sign", "Flyers", "Loyalty Cards", "Radio Spot", "Newspaper Ad", "Billboard",
			"Food Blogger Visit", "Social Media Page", "Happy Hour", "Influencer Deal", "TV Commercial", "Mascot",
			"Viral Video", "Celebrity Endorsement", "Stadium Sponsorship", "Blimp Ad", "Award Nomination",
			"Festival Booth", "Brand Jingle", "Documentary"],
		"seating": ["Extra Chairs", "Booth Seating", "Patio", "Bar Counter", "Faster Bussing", "Reservation Book",
			"Host Stand", "Second Floor", "Rooftop Terrace", "Turnover Training", "Waitlist App",
			"Private Dining Room", "Heated Patio", "Banquet Hall", "Express Lane", "Pager System",
			"Tablet Ordering", "Garden Courtyard", "Mezzanine", "Grand Ballroom"],
		"kitchen": ["Sharper Knives", "Cast Iron Pans", "Second Fryer", "Prep Station", "Walk-in Fridge",
			"Convection Oven", "Mise en Place", "Sous Chef", "Dish Machine", "Flat-Top Grill", "Pressure Cooker",
			"Expo Window", "Kitchen Display", "Combi Oven", "Blast Chiller", "Pastry Station", "Tandoor",
			"Wood-Fired Oven", "Robot Prep Arm", "Molecular Lab"],
	}
	var eras := ["", "Pro ", "Galactic "]
	var dishes := ["Grilled Cheese", "Fries", "Milkshakes", "Burgers", "Hot Dogs", "Pancakes", "Club Sandwich",
		"Chili", "Fried Chicken", "Mac & Cheese", "Tacos", "Caesar Salad", "Pizza", "BBQ Ribs", "Fish & Chips",
		"Pad Thai", "Ramen", "Pho", "Burritos", "Gyros", "Dumplings", "Curry", "Lasagna", "Paella", "Sushi",
		"Poke Bowls", "Bibimbap", "Shakshuka", "Risotto", "Steak Frites", "Crab Cakes", "Lobster Roll",
		"Duck Confit", "Beef Wellington", "Bouillabaisse", "Oysters", "Wagyu Steak", "Truffle Pasta",
		"Caviar Blini", "Omakase", "Tasting Menu", "Peking Duck", "King Crab", "Chocolate Souffle",
		"Creme Brulee", "Tiramisu", "Baklava", "Mochi", "Churros", "Cheesecake", "Gelato Bar",
		"Craft Cocktails", "Wine Pairing", "Sommelier Picks", "Chef's Table", "Saffron Rice",
		"Golden Dessert", "Zero-G Noodles", "Moon Cheese Plate", "Martian Chili"]
	var stat_off := {"demand": 0.0, "seating": 0.15, "kitchen": 0.3, "ticket": 0.55}
	for i in 60:
		for s in ["seating", "kitchen", "demand", "ticket"]:
			var nm: String
			if s == "ticket":
				nm = "Menu: " + dishes[i]
			else:
				nm = eras[i / 20] + nouns[s][i % 20]
			var x := 1.5 if i % 5 != 4 else 2.0
			var c := ladder(1.8 + float(stat_off[s]), 1.6, 1.6, i, 60)
			_add("t_%s_%d" % [s, i], nm, s, c, [["mul", s, x]])
	# ---- 2. global ambience: 60
	var amb := ["Fresh Paint", "Potted Plants", "Soft Lighting", "Background Jazz", "Spotless Restrooms",
		"Uniforms", "Logo Redesign", "Local Art", "Fireplace", "Live Pianist", "Aquarium", "Chandelier",
		"Open Kitchen", "Inspector Visit", "Signature Scent", "Hand-Thrown Plates", "Marble Bar",
		"Indoor Waterfall", "Gold Leaf Ceiling", "Zero-G Lounge"]
	var amb_era := ["", "Refined ", "Legendary "]
	for i in 60:
		var x := 1.3 if i % 4 != 3 else 1.6
		_add("g_%d" % i, amb_era[i / 20] + amb[i % 20], "global", ladder(2.5, 1.7, 1.7, i, 60), [["mul", "global", x]])
	# ---- 3. repeatable milestones: 4 x 21
	for r in REPS:
		for mi in MILESTONES.size():
			var n: int = MILESTONES[mi]
			var x := 2.0 if (mi < 2 or mi % 4 == 3) else 1.5
			var c := float(REP_COST[r]) * pow(float(REP_GROWTH[r]), n - 1) * 4.0
			_add("m_%s_%d" % [r, n], "%d %s" % [n, REP_PLURAL[r]], REP_STAT[r], c, [["mul", REP_STAT[r], x]], ["rep", r, n])
	# ---- 4. synergies: 12 pairs x 5 tiers
	var syn_names := {
		"ads>seating": "Reservations by Ad", "ads>kitchen": "Hype-Driven Hiring", "ads>ticket": "Premium Branding",
		"tables>demand": "Busy Window Effect", "tables>kitchen": "Pass-Through Counters", "tables>ticket": "Tableside Service",
		"cooks>demand": "Open Kitchen Show", "cooks>seating": "Runners from the Line", "cooks>ticket": "Chef's Specials",
		"recipes>demand": "Menu Buzz", "recipes>seating": "Shared Platters", "recipes>kitchen": "Streamlined Recipes",
	}
	var syn_v := [0.002, 0.004, 0.006, 0.008, 0.01]
	var p := 0
	for pair in syn_names:
		var parts: PackedStringArray = String(pair).split(">")
		for t in 5:
			var c := pow(10.0, 5.0 + 25.0 * t + 2.0 * p)
			_add("s_%s_%s_%d" % [parts[0], parts[1], t], "%s %s" % [syn_names[pair], roman(t + 1)], parts[1], c,
				[["syn", parts[0], parts[1], syn_v[t]]])
		p += 1
	# ---- 5. cost reductions: 4 x 10
	var cr_names := {"ads": "Bulk Ad Buys", "tables": "Flat-Pack Tables", "cooks": "Staffing Agency", "recipes": "Test Kitchen"}
	var ri := 0
	for r in REPS:
		for t in 10:
			_add("c_%s_%d" % [r, t], "%s %s" % [cr_names[r], roman(t + 1)], "cost", pow(10.0, 3.0 + 10.0 * t + 0.4 * ri),
				[["cost", r, 0.7]])
		ri += 1
	# ---- 6. serve tap: 40
	var tap_names := ["Quick Hands", "Rush Bell", "Hustle Shoes", "Double Plating"]
	for t in 40:
		var eff: Array
		if t % 2 == 0:
			eff = [["mul", "tap", 3.0]]
		else:
			eff = [["tappct", 0.005]]
		_add("tap_%d" % t, "%s %s" % [tap_names[t % 4], roman(t / 4 + 1)], "tap", ladder(1.3, 2.4, 2.4, t, 40), eff)
	# ---- 7. brand / price ceiling: 25
	var brand := ["Price Tags", "Word of Mouth", "Regulars", "Loyalty Program", "Signature Sauce", "Brand Story",
		"Cult Following", "Secret Menu", "Glowing Reviews", "Waiting List", "Members' Club", "Household Name"]
	for t in 25:
		var nm: String = brand[t % 12] + ("" if t < 12 else " " + roman(t / 12 + 1))
		_add("b_%d" % t, nm, "ceiling", ladder(2.6, 4.0, 4.0, t, 25), [["mul", "ceiling", 1.25 if t > 0 else 1.0]] if t > 0 else [["flag", "price"]])
	# ---- 8. automation + offline: 6 + 10
	_add("a_price", "Floor Manager", "auto", 2.5e3, [["flag", "auto_price"]])
	_add("a_ads", "Marketing Manager", "auto", 5.0e4, [["flag", "auto_ads"]])
	_add("a_tables", "Front-of-House Manager", "auto", 8.0e4, [["flag", "auto_tables"]])
	_add("a_cooks", "Head Chef", "auto", 1.2e5, [["flag", "auto_cooks"]])
	_add("a_recipes", "Menu Developer", "auto", 2.0e5, [["flag", "auto_recipes"]])
	_add("a_upg", "Operations Director", "auto", 1.0e9, [["flag", "auto_upg"]])
	for t in 10:
		_add("o_%d" % t, "Night Shift %s" % roman(t + 1), "offline", pow(10.0, 4.0 + 5.0 * t), [["offline", 0.075], ["offhours", 1.0]])
	# ---- 9. franchise royalties: 50 + cost 10
	var roy := ["Franchise Manual", "Training Program", "Regional Manager", "Supply Contract", "Brand Standards",
		"Mystery Shoppers", "Central Kitchen", "Logistics Hub", "Franchise Awards", "Owner Summit",
		"Point-of-Sale Network", "Shared Marketing Fund", "Quality Audits", "Franchisee Bonus", "Master Franchise",
		"Distribution Centre", "Brand Bible", "Area Developers", "Franchise TV Spot", "Supplier Rebates",
		"Leadership Academy", "Data Analytics", "Global Standards", "Franchise Council", "Empire Charter"]
	for t in 50:
		var nm: String = ("" if t < 25 else "Global ") + roy[t % 25]
		_add("r_%d" % t, nm, "royalty", 4.0e5 * ladder(0.0, 2.0, 2.0, t, 50), [["mul", "royalty", 1.25 if t % 5 != 4 else 1.5]], ["locs", 1 + t])
	for t in 10:
		_add("fc_%d" % t, "Franchise Lawyers %s" % roman(t + 1), "royalty", 1.0e7 * pow(10.0, 9.0 * t), [["citycost", 0.75]], ["locs", 3 + 4 * t])
	# ---- 10. city-specific: 30 x 8
	for ci in NC:
		for mi in CITY_MILESTONES.size():
			var n: int = CITY_MILESTONES[mi]
			var c := float(city_cost[ci]) * pow(CITY_GROWTH, n - 1) * 3.0
			_add("cm_%d_%d" % [ci, n], "%s: %s" % [CITY_NAMES[ci], CITY_MS_NAME[mi]], "city", c,
				[["city", ci, CITY_MS_MULT[mi]]], ["city", ci, n])
	# ---- 11. ventures: 8 x 12
	for vi in NV:
		for mi in VENT_MILESTONES.size():
			var n: int = VENT_MILESTONES[mi]
			var c := float(vent_cost[vi]) * pow(VENT_GROWTH, n - 1) * 3.0
			_add("vm_%d_%d" % [vi, n], "%s: Level %d" % [VENTURES[vi].name, n], "venture", c,
				[["vent", vi, 1.15]], ["vent", vi, n])
	# ---- 12. concept-specific: 4 x 30
	var cnames := {
		"diner": ["Bottomless Coffee", "Blue Plate Special", "Jukebox", "Neon Sign", "Pie Case", "Counter Regulars",
			"Breakfast All Day", "Chrome Stools", "Milkshake Machine", "Late-Night Crowd", "Family Booths", "Diner Classic",
			"Truckers' Favourite", "Hometown Hero", "Americana"],
		"fastfood": ["Drive-Thru", "Combo Meals", "Heat Lamps", "Kids' Toys", "Value Menu", "Order Kiosks", "Fry Robot",
			"Second Drive-Thru Lane", "Mascot Costume", "Late-Night Window", "Super Size", "App Deals",
			"Conveyor Grill", "Global Jingle", "Golden Arches of Flavour"],
		"fine": ["Tasting Spoons", "White Tablecloths", "Sommelier", "Amuse-Bouche", "Tweezers", "Michelin Star",
			"Second Michelin Star", "Third Michelin Star", "Chef's Garden", "Truffle Hunter", "Private Cellar",
			"Gastronomy Award", "Foraging Team", "Edible Gold", "Temple of Taste"],
		"cafe": ["Latte Art", "Pastry Case", "Cosy Armchairs", "Free Wi-Fi", "Barista Training", "Single Origin Beans",
			"Book Nook", "Croissant Lamination", "Pour-Over Bar", "Regulars' Mugs", "Roastery", "Cold Brew Tap",
			"Matcha Ceremony", "Third-Wave Legend", "Bean to Cup Empire"],
	}
	var cpat := {
		"diner": [["mul", "global", 1.4], ["syn", "tables", "ticket", 0.002], ["mul", "seating", 1.6], ["mul", "ticket", 1.5]],
		"fastfood": [["mul", "demand", 2.0], ["mul", "kitchen", 1.6], ["mul", "seating", 1.6], ["cost", "ads", 0.7]],
		"fine": [["mul", "ticket", 1.8], ["mul", "ceiling", 1.25], ["mul", "seating", 1.5], ["mul", "demand", 1.5]],
		"cafe": [["mul", "tap", 3.0], ["tappct", 0.005], ["mul", "global", 1.35], ["offline", 0.05]],
	}
	for cn in CONCEPTS:
		for t in 30:
			var nm: String = ("" if t < 15 else "Master ") + cnames[cn][t % 15]
			var eff: Array = [cpat[cn][t % 4]]
			_add("k_%s_%d" % [cn, t], nm, "concept", ladder(2.2, 3.2, 3.2, t, 30), eff, [], {"concept": cn})
	# ---- 13. crossroads: 8 pairs x 5 tiers (buying one locks the other for this run)
	var cross := [
		["Union Kitchen", [["mul", "kitchen", 3.0], ["cost", "cooks", 1.6]], "Gig Cooks", [["mul", "kitchen", 1.6], ["cost", "cooks", 0.5]]],
		["Billboard Blitz", [["mul", "demand", 3.0]], "Word of Mouth Club", [["mul", "demand", 1.6], ["mul", "ticket", 1.3]]],
		["Premium Pricing", [["mul", "ceiling", 1.5], ["mul", "demand", 0.85]], "Value Menu", [["mul", "demand", 2.0], ["mul", "ceiling", 0.9]]],
		["Tasting Course", [["mul", "ticket", 2.5], ["mul", "seating", 0.8]], "Family Platters", [["mul", "seating", 2.0], ["mul", "ticket", 1.2]]],
		["Corporate Chain", [["mul", "royalty", 2.5], ["citycost", 1.3]], "Owner-Operators", [["citycost", 0.5], ["mul", "royalty", 1.3]]],
		["Front-Line Owner", [["mul", "tap", 10.0], ["tappct", 0.01]], "Absentee Owner", [["mul", "global", 1.4], ["offline", 0.1]]],
		["Imported Ingredients", [["mul", "ticket", 2.0]], "Local Sourcing", [["mul", "ticket", 1.4], ["cost", "recipes", 0.5]]],
		["Open 24/7", [["mul", "global", 1.8], ["cost", "ads", 1.3], ["cost", "tables", 1.3], ["cost", "cooks", 1.3], ["cost", "recipes", 1.3]],
			"Weekends Off", [["mul", "global", 1.3], ["cost", "ads", 0.8], ["cost", "tables", 0.8], ["cost", "cooks", 0.8], ["cost", "recipes", 0.8]]],
	]
	for ci in cross.size():
		var row: Array = cross[ci]
		for t in 5:
			var c := pow(10.0, 3.5 + 30.0 * t + 4.0 * ci)
			var a := _add("x_%d_%d_a" % [ci, t], "%s %s" % [row[0], roman(t + 1)], "cross", c, row[1])
			var b := _add("x_%d_%d_b" % [ci, t], "%s %s" % [row[2], roman(t + 1)], "cross", c, row[3])
			a.excl = b.id
			b.excl = a.id
	# ---- 14. legacy perks (stars, survive selling the company): 80
	var leg := [
		["Family Recipes", 10, "startcash"], ["Reputation", 20, "global"], ["Star Power", 10, "starpow"],
		["Head Start", 10, "startreps"], ["Franchise Network", 10, "royalty"], ["Silver Spoon", 5, "tap"],
		["Night Owl", 5, "offline"], ["Venture Capital", 5, "vent"], ["Old Managers", 5, "flags"]]
	var flag_list := ["auto_price", "auto_ads", "auto_tables", "auto_cooks", "auto_recipes"]
	for row in leg:
		var base_n: String = row[0]
		for t in int(row[1]):
			var kind: String = row[2]
			var eff: Array
			var sc := 1.0
			match kind:
				"startcash":
					eff = [["startcash", pow(10.0, 3.0 + 3.0 * t)]]; sc = 1.0 + pow(t, 2.2) * 2.0
				"global":
					eff = [["mul", "global", 2.0]]; sc = 10.0 * pow(3.0, t)
				"starpow":
					eff = [["starpow", 0.005]]; sc = 10.0 * pow(2.5, t)
				"startreps":
					eff = [["startreps", 10]]; sc = 3.0 * pow(2.0, t)
				"royalty":
					eff = [["mul", "royalty", 2.0]]; sc = 20.0 * pow(2.4, t)
				"tap":
					eff = [["mul", "tap", 5.0]]; sc = 2.0 * pow(3.0, t)
				"offline":
					eff = [["offline", 0.1], ["offhours", 2.0]]; sc = 4.0 * pow(3.0, t)
				"vent":
					eff = [["vent_all", 2.0]]; sc = 100.0 * pow(4.0, t)
				"flags":
					eff = [["flag", flag_list[t]]]; sc = 2.0 + 3.0 * t
			_add("l_%s_%d" % [kind, t], "%s %s" % [base_n, roman(t + 1)], "legacy", 0.0, eff, ["legacy", kind, t],
				{"legacy": true, "star": floor(sc)})
	# ---- 15. side businesses: 6 x 40 + 10
	Biz.add_upgrades(self)
	# ---- 16. grit perks (earned by going bankrupt, survive every reset): 73
	var grit_lines := [
		["Comeback Kid", 10, "empire", [["mul", "empire", 1.5]], 3.0, 2.2],
		["Thick Skin", 8, "skin", [["event_cost", 0.8]], 2.0, 2.0],
		["Line of Credit", 8, "credit", [["credit", 1.5]], 2.0, 2.0],
		["Friendly Banker", 8, "rates", [["interest", 0.8]], 2.0, 2.0],
		["Lean Operations", 8, "lean", [["upkeep", 0.8]], 3.0, 2.0],
		["Bulk Buyer", 6, "food", [["foodcut", 3.0]], 3.0, 2.2],
		["Second Wind", 5, "wind", [["deadline", 60.0]], 2.0, 2.5],
		["Side Hustle", 10, "hustle", [["mul", "biz", 2.0]], 3.0, 2.2],
		["Lucky Break", 5, "luck", [["luck", 0.08]], 4.0, 2.5],
		["Fire Sale", 5, "sale", [["firesale", 0.1]], 2.0, 2.0],
	]
	for row in grit_lines:
		for t in int(row[1]):
			_add("gr_%s_%d" % [row[2], t], "%s %s" % [row[0], roman(t + 1)], "grit", 0.0, row[3], ["legacy", row[2], t],
				{"legacy": true, "cur": "grit", "lp": "gr", "star": floor(float(row[4]) * pow(float(row[5]), t))})


# ================================================================= lifecycle

func reset_run_state() -> void:
	cash = 0.0
	run_earned = 0.0
	run_time = 0.0
	for r in REPS:
		reps[r] = 0
	owned = {}
	cities = []
	for i in NC:
		cities.append(0)
	vents = []
	for i in NV:
		vents.append(0)
	price = 1.0
	biz = []
	for i in Biz.N:
		biz.append(Biz.blank(i))
	debt = 0.0
	red_t = 0.0
	peak_gross = 0.0
	effects = []
	event = {}
	event_t = Events.MIN_GAP
	_dirty = true
	var a := agg()
	cash = maxf(5.0, float(a.startcash))
	for r in REPS:
		reps[r] = int(a.startreps)
	_dirty = true


func new_game() -> void:
	life_earned = 0.0
	stars = 0.0
	stars_earned = 0.0
	prestiges = 0
	legacy = {}
	concept = "diner"
	concept_chosen = false
	play_time = 0.0
	taps = 0
	best_income = 0.0
	auto_on = {}
	grit = 0.0
	grit_earned = 0.0
	bankruptcies = 0
	last_bankrupt = {}
	reset_run_state()


func choose_concept(c: String) -> bool:
	if not CONCEPT.has(c) or not concept_unlocked(c):
		return false
	concept = c
	concept_chosen = true
	_dirty = true
	return true


func concept_unlocked(c: String) -> bool:
	return prestiges + bankruptcies >= int(CONCEPT[c].unlock)


# ================================================================= aggregate

func mark_dirty() -> void:
	_dirty = true


func agg() -> Dictionary:
	if _dirty or _agg.is_empty():
		_agg = _aggregate(owned)
		_dirty = false
	return _agg


func _blank_agg() -> Dictionary:
	var a := {
		"mul": {"demand": 1.0, "seating": 1.0, "kitchen": 1.0, "ticket": 1.0, "global": 1.0, "tap": 1.0, "royalty": 1.0, "ceiling": 1.0},
		"cost": {"ads": 1.0, "tables": 1.0, "cooks": 1.0, "recipes": 1.0},
		"syn": [], "tappct": 0.0, "city": [], "citycost": 1.0, "vent": [], "flags": {},
		"offline": OFFLINE_BASE, "offhours": OFFLINE_HOURS_BASE, "starpow": 0.0, "startcash": 0.0, "startreps": 0,
		"elastic": 2.0, "ceiling": 3.0,
		"biz": [], "twist": {"truck": 1.0, "bakery": 1.0, "catering": 1.0, "bar": 1.0, "hotel": 1.0, "wholesale": 1.0},
		"upkeep": 1.0, "foodcut": 0.0, "event_cost": 1.0, "credit": 1.0, "interest": 1.0, "deadline": 0.0,
		"luck": 0.0, "firesale": 0.0,
	}
	a.mul["biz"] = 1.0
	a.mul["empire"] = 1.0
	for i in Biz.N:
		a.biz.append(1.0)
	for i in NC:
		a.city.append(1.0)
	for i in NV:
		a.vent.append(1.0)
	return a


func _aggregate(own: Dictionary) -> Dictionary:
	var a := _blank_agg()
	var cc: Dictionary = CONCEPT[concept]
	for k in cc.mult:
		a.mul[k] *= float(cc.mult[k])
	for k in cc.rep_cost:
		a.cost[k] *= float(cc.rep_cost[k])
	a.elastic = float(cc.elastic)
	a.ceiling = float(cc.ceiling)
	a.tappct += float(cc.get("tappct", 0.0))
	for id in own:
		apply_effects(a, upgrades[id].eff)
	for id in legacy:
		apply_effects(a, upgrades[id].eff)
	return a


func apply_effects(a: Dictionary, eff: Array) -> void:
	for e in eff:
		match String(e[0]):
			"mul": a.mul[e[1]] *= float(e[2])
			"cost": a.cost[e[1]] *= float(e[2])
			"syn": a.syn.append([e[1], e[2], float(e[3])])
			"tappct": a.tappct += float(e[1])
			"city": a.city[int(e[1])] *= float(e[2])
			"citycost": a.citycost *= float(e[1])
			"vent": a.vent[int(e[1])] *= float(e[2])
			"vent_all":
				for i in NV:
					a.vent[i] *= float(e[1])
			"flag": a.flags[e[1]] = true
			"offline": a.offline = minf(1.0, a.offline + float(e[1]))
			"offhours": a.offhours += float(e[1])
			"starpow": a.starpow += float(e[1])
			"startcash": a.startcash = maxf(a.startcash, float(e[1]))
			"startreps": a.startreps += int(e[1])
			"biz": a.biz[int(e[1])] *= float(e[2])
			"twist": a.twist[e[1]] *= float(e[2])
			"upkeep": a.upkeep *= float(e[1])
			"foodcut": a.foodcut += float(e[1])
			"event_cost": a.event_cost *= float(e[1])
			"credit": a.credit *= float(e[1])
			"interest": a.interest *= float(e[1])
			"deadline": a.deadline += float(e[1])
			"luck": a.luck += float(e[1])
			"firesale": a.firesale += float(e[1])


func copy_with(a: Dictionary, eff: Array) -> Dictionary:
	var b := a.duplicate(true)
	apply_effects(b, eff)
	return b


# ================================================================= stats & income

func locations() -> int:
	var n := 0
	for c in cities:
		n += int(c)
	return n


func vent_effect(i: int, a: Dictionary) -> float:
	return 1.0 + VENT_RATE * float(vents[i]) * float(a.vent[i])


func stat(s: String, a: Dictionary, rep_override: Dictionary = {}) -> float:
	var r: String = STAT_REP[s]
	var n := int(rep_override.get(r, reps[r]))
	var v: float = float(BASE[s]) + n * float(REP_ADD[r])
	v *= float(a.mul[s])
	for sy in a.syn:
		if sy[1] == s:
			v *= 1.0 + float(sy[2]) * float(rep_override.get(sy[0], reps[sy[0]]))
	for i in NV:
		if VENTURES[i].stat == s:
			v *= vent_effect(i, a)
	return v


func global_mult(a: Dictionary) -> float:
	var g: float = float(a.mul.global)
	for i in NV:
		if VENTURES[i].stat == "global":
			g *= vent_effect(i, a)
	return g


func royalty_mult(a: Dictionary) -> float:
	var r: float = float(a.mul.royalty)
	for i in NV:
		if VENTURES[i].stat == "royalty":
			r *= vent_effect(i, a)
	return r


func franchise_mult(a: Dictionary, city_override: Array = []) -> float:
	var cs: Array = city_override if not city_override.is_empty() else cities
	var s := 0.0
	for i in NC:
		if int(cs[i]) > 0:
			s += float(city_yield[i]) * float(cs[i]) * float(a.city[i])
	return 1.0 + 0.1 * royalty_mult(a) * s


func star_mult(a: Dictionary) -> float:
	return 1.0 + stars * (STAR_BASE + float(a.starpow))


func ceiling(a: Dictionary) -> float:
	return float(a.ceiling) * float(a.mul.ceiling)


func price_unlocked(a: Dictionary) -> bool:
	return a.flags.has("price") or a.flags.has("auto_price")


## Smooth minimum of seating and kitchen: the weaker side dominates, but both always help.
static func capacity(se: float, k: float) -> float:
	var lo := minf(se, k)
	if lo <= 0.0:
		return 0.0
	var x := se / lo
	var y := k / lo
	return lo * pow(pow(x, -3.0) + pow(y, -3.0), -1.0 / 3.0)


func best_price(a: Dictionary, rep_override: Dictionary = {}) -> float:
	var d := stat("demand", a, rep_override)
	var c := capacity(stat("seating", a, rep_override), stat("kitchen", a, rep_override))
	return clampf(pow(d / maxf(c, 1e-300), 1.0 / float(a.elastic)), PRICE_MIN, ceiling(a))


func effective_price(a: Dictionary, rep_override: Dictionary = {}, force_best := false) -> float:
	if force_best or (a.flags.has("auto_price") and price_auto):
		return best_price(a, rep_override)
	if not price_unlocked(a):
		return 1.0
	return clampf(price, PRICE_MIN, ceiling(a))


## Full breakdown of income per second for an aggregate.
func income_info(a: Dictionary, rep_override: Dictionary = {}, city_override: Array = [], force_best := false) -> Dictionary:
	var d := stat("demand", a, rep_override) * effect_mult("demand")
	var se := stat("seating", a, rep_override) * effect_mult("seating")
	var k := stat("kitchen", a, rep_override) * effect_mult("kitchen")
	var t := stat("ticket", a, rep_override)
	var p := effective_price(a, rep_override, force_best)
	var want := d * pow(p, -float(a.elastic))
	var cap := capacity(se, k)
	var served := minf(want, cap)
	var fr := franchise_mult(a, city_override)
	var g := global_mult(a)
	var sm := star_mult(a) * grit_mult(a) * float(a.mul.empire) * effect_mult("income")
	var closed := effect_mult("closed") <= 0.0
	var total := 0.0 if closed else served * t * p * g * fr * sm
	var limit := "demand"
	if want > cap:
		limit = "seating" if se <= k else "kitchen"
	# costs are measured against a plate's base value (ticket x ambience), not price or royalties,
	# so raising prices widens your margin and franchise royalties are pure profit
	var unit := t * g
	var srv := 0.0 if closed else served
	var food := srv * unit * food_cost_pct(a) / 100.0
	var wm := float(a.upkeep) * effect_mult("wages")
	# idle capacity and turned-away guests are what cost you: balance pays
	var rent := maxf(0.0, se - srv) * unit * RENT_K * wm
	var wages := maxf(0.0, k - srv) * unit * WAGE_K * wm
	var mkt := maxf(0.0, want - srv) * unit * MARKETING_K * wm
	var up := rent + wages + mkt
	return {"demand": d, "seating": se, "kitchen": k, "ticket": t, "price": p, "want": want, "cap": cap,
		"served": srv, "fr": fr, "global": g, "star": sm, "total": total, "limit": limit,
		"food": food, "rent": rent, "wages": wages, "marketing": mkt, "upkeep": up, "net": total - food - up, "closed": closed}


func food_cost_pct(a: Dictionary = {}) -> float:
	if a.is_empty():
		a = agg()
	var cut := float(a.foodcut)
	for i in Biz.N:
		if String(Biz.DEFS[i].id) == "wholesale":
			cut += Biz.food_cut(biz[i])
	return clampf(FOOD_BASE - cut + effect_add("food"), 5.0, 80.0)


func grit_mult(_a: Dictionary = {}) -> float:
	return 1.0 + grit * GRIT_BASE


## Money in and out per second for the whole empire (businesses use steady-state estimates).
func empire(offline := false) -> Dictionary:
	var a := agg()
	var inf := income_info(a)
	var br := 0.0
	var bc := 0.0
	var per: Array = []
	for i in Biz.N:
		var est := Biz.estimate(i, biz[i], self, offline)
		per.append(est)
		br += float(est.rev)
		bc += float(est.cost)
	var it := interest_per_s()
	var gross := float(inf.total) + br
	var costs := float(inf.food) + float(inf.upkeep) + bc + it
	return {"rest_rev": float(inf.total), "food": float(inf.food), "rest_upkeep": float(inf.upkeep),
		"biz_rev": br, "biz_cost": bc, "interest": it, "gross": gross, "costs": costs, "net": gross - costs, "per": per}


## Net money per second for the whole empire.
func income(_a: Dictionary = {}, _force_best := false) -> float:
	return float(empire().net)


func gross_income() -> float:
	return float(empire().gross)


func tap_value(a: Dictionary = {}) -> float:
	if a.is_empty():
		a = agg()
	var inf := income_info(a)
	var base := float(inf.ticket) * float(inf.price) * float(inf.global) * float(inf.fr) * float(inf.star)
	return base * float(a.mul.tap) + float(inf.total) * float(a.tappct)


# ================================================================= costs & buying

func rep_growth(r: String) -> float:
	return pow(float(REP_GROWTH[r]), COST_POW)


func rep_cost_at(r: String, n: int, m: float) -> float:
	return cp(float(REP_COST[r])) * pow(rep_growth(r), n) * m


func rep_cost(r: String, k: int = 1) -> float:
	var a := agg()
	var g := rep_growth(r)
	var c0 := rep_cost_at(r, int(reps[r]), float(a.cost[r]))
	return c0 * (pow(g, k) - 1.0) / (g - 1.0)


func rep_max_affordable(r: String) -> int:
	var a := agg()
	var g := rep_growth(r)
	var c0 := rep_cost_at(r, int(reps[r]), float(a.cost[r]))
	if cash < c0:
		return 0
	return maxi(1, int(floor(log(cash * (g - 1.0) / c0 + 1.0) / log(g))))


func buy_rep(r: String, k: int = 1) -> bool:
	if k <= 0:
		return false
	var c := rep_cost(r, k)
	if c > cash:
		return false
	cash -= c
	reps[r] = int(reps[r]) + k
	return true


func next_milestone(r: String) -> int:
	for n in MILESTONES:
		if int(reps[r]) < n:
			return n
	return -1


func city_unlocked(i: int) -> bool:
	if not franchise_unlocked():
		return false
	if i == 0:
		return true
	return int(cities[i - 1]) > 0 and run_earned >= cp(float(city_cost[i])) * 0.05


func franchise_unlocked() -> bool:
	return run_earned >= cp(1.0e7) or locations() > 0


func city_next_cost(i: int) -> float:
	return cp(float(city_cost[i]) * pow(CITY_GROWTH, int(cities[i]))) * float(agg().citycost)


func buy_city(i: int) -> bool:
	if not city_unlocked(i):
		return false
	var c := city_next_cost(i)
	if c > cash:
		return false
	cash -= c
	cities[i] = int(cities[i]) + 1
	return true


func ventures_unlocked() -> bool:
	return locations() >= 15 or vents[0] > 0


func vent_unlocked(i: int) -> bool:
	if not ventures_unlocked():
		return false
	if i == 0:
		return true
	return int(vents[i - 1]) > 0 and run_earned >= cp(float(vent_cost[i])) * 0.05


func vent_next_cost(i: int) -> float:
	return cp(float(vent_cost[i]) * pow(VENT_GROWTH, int(vents[i])))


func buy_vent(i: int) -> bool:
	if not vent_unlocked(i):
		return false
	var c := vent_next_cost(i)
	if c > cash:
		return false
	cash -= c
	vents[i] = int(vents[i]) + 1
	_dirty = true
	return true


# ================================================================= upgrades

func req_met(u: Dictionary) -> bool:
	var q: Array = u.req
	match String(q[0]):
		"earn": return run_earned >= float(q[1])
		"rep": return int(reps[q[1]]) >= int(q[2])
		"city": return int(cities[int(q[1])]) >= int(q[2])
		"vent": return int(vents[int(q[1])]) >= int(q[2])
		"locs": return locations() >= int(q[1])
		"legacy": return true
		"bizopen": return biz_open_count() >= int(q[1])
		"biz":
			var s: Dictionary = biz[int(q[1])]
			if not s.open:
				return false
			match String(q[2]):
				"a": return int(s.a) >= int(q[3])
				"b": return int(s.b) >= int(q[3])
				"open": return true
				"earn": return run_earned >= float(u.cost) * 0.08
	return false


func req_text(u: Dictionary) -> String:
	var q: Array = u.req
	match String(q[0]):
		"earn": return "Earn %s this run" % fmt_money(float(q[1]))
		"rep": return "Own %d %s" % [int(q[2]), REP_PLURAL[q[1]]]
		"city": return "%d locations in %s" % [int(q[2]), CITY_NAMES[int(q[1])]]
		"vent": return "%s level %d" % [VENTURES[int(q[1])].name, int(q[2])]
		"locs": return "%d franchise locations" % int(q[1])
		"bizopen": return "Run %d side business%s" % [int(q[1]), "" if int(q[1]) == 1 else "es"]
		"biz":
			var d: Dictionary = Biz.DEFS[int(q[1])]
			match String(q[2]):
				"a": return "%d %s at the %s" % [int(q[3]), d.as, d.name]
				"b": return "%d %s at the %s" % [int(q[3]), d.bs, d.name]
				"open": return "Open the %s" % d.name
				"earn": return "Open the %s and earn %s this run" % [d.name, fmt_money(float(u.cost) * 0.08)]
	return ""


func is_owned(u: Dictionary) -> bool:
	return legacy.has(u.id) if u.legacy else owned.has(u.id)


func blocked(u: Dictionary) -> bool:
	if u.concept != "" and u.concept != concept:
		return true
	if int(u.excl) >= 0 and owned.has(int(u.excl)):
		return true
	return false


func available(u: Dictionary) -> bool:
	return not u.legacy and not owned.has(u.id) and not blocked(u) and req_met(u)


func visible_upgrades() -> Array:
	var out: Array = []
	for u in upgrades:
		if available(u):
			out.append(u)
	out.sort_custom(func(x, y): return float(x.cost) < float(y.cost))
	return out


## The next few run upgrades that are not yet unlocked, cheapest first.
func upcoming_upgrades(n: int) -> Array:
	var out: Array = []
	for u in upgrades:
		if not u.legacy and not owned.has(u.id) and not blocked(u) and not req_met(u):
			out.append(u)
	out.sort_custom(func(x, y): return float(x.cost) < float(y.cost))
	return out.slice(0, n)


func buy_upgrade(id: int) -> bool:
	var u: Dictionary = upgrades[id]
	if u.legacy:
		return buy_legacy(id)
	if not available(u) or float(u.cost) > cash:
		return false
	cash -= float(u.cost)
	owned[id] = true
	_dirty = true
	return true


func legacy_available(u: Dictionary) -> bool:
	if not u.legacy or legacy.has(u.id):
		return false
	var q: Array = u.req
	var t := int(q[2])
	if t == 0:
		return true
	return legacy.has(by_key["%s_%s_%d" % [String(u.get("lp", "l")), q[1], t - 1]])


func currency(u: Dictionary) -> String:
	return String(u.get("cur", "star"))


func wallet(cur: String) -> float:
	return grit if cur == "grit" else stars


func buy_legacy(id: int) -> bool:
	var u: Dictionary = upgrades[id]
	var cur := currency(u)
	if not legacy_available(u) or float(u.star) > wallet(cur):
		return false
	if cur == "grit":
		grit -= float(u.star)
	else:
		stars -= float(u.star)
	legacy[id] = true
	_dirty = true
	return true


func upgrade_count_owned() -> int:
	return owned.size() + legacy.size()


func effect_text(eff: Array) -> String:
	var parts: PackedStringArray = []
	for e in eff:
		match String(e[0]):
			"mul":
				parts.append("%s ×%s" % [STAT_NAME[e[1]], fmt_mult(float(e[2]))])
			"cost": parts.append("%s cost ×%s" % [REP_NAME[e[1]], fmt_mult(float(e[2]))])
			"syn": parts.append("%s +%s%% per %s" % [STAT_NAME[e[2]], fmt_mult(float(e[3]) * 100.0), REP_NAME[e[1]]])
			"tappct": parts.append("Serve +%s%% of income/s" % fmt_mult(float(e[1]) * 100.0))
			"city": parts.append("%s locations ×%s" % [CITY_NAMES[int(e[1])], fmt_mult(float(e[2]))])
			"citycost": parts.append("Franchise cost ×%s" % fmt_mult(float(e[1])))
			"vent": parts.append("%s effect ×%s" % [VENTURES[int(e[1])].name, fmt_mult(float(e[2]))])
			"vent_all": parts.append("All ventures ×%s" % fmt_mult(float(e[1])))
			"flag": parts.append(FLAG_TEXT.get(e[1], e[1]))
			"offline": parts.append("Offline earnings +%d%%" % int(round(float(e[1]) * 100.0)))
			"offhours": parts.append("+%dh offline cap" % int(e[1]))
			"starpow": parts.append("Each star +%s%% more" % fmt_mult(float(e[1]) * 100.0))
			"startcash": parts.append("Start runs with %s" % fmt_money(float(e[1])))
			"startreps": parts.append("Start with +%d of each build" % int(e[1]))
			"biz": parts.append("%s income ×%s" % [Biz.DEFS[int(e[1])].name, fmt_mult(float(e[2]))])
			"twist": parts.append(TWIST_TEXT.get(e[1], e[1]) % fmt_mult(float(e[2])))
			"upkeep": parts.append("Upkeep ×%s" % fmt_mult(float(e[1])))
			"foodcut": parts.append("Food costs -%s pts" % fmt_mult(float(e[1])))
			"event_cost": parts.append("Event costs and fines ×%s" % fmt_mult(float(e[1])))
			"credit": parts.append("Credit limit ×%s" % fmt_mult(float(e[1])))
			"interest": parts.append("Loan interest ×%s" % fmt_mult(float(e[1])))
			"deadline": parts.append("+%ds in the red before bankruptcy" % int(e[1]))
			"luck": parts.append("+%d%% chance of good events" % int(round(float(e[1]) * 100.0)))
			"firesale": parts.append("+%d%% back when selling off" % int(round(float(e[1]) * 100.0)))
	return ", ".join(parts)


const TWIST_TEXT := {
	"truck": "Truck crowds ×%s", "bakery": "Counter speed ×%s", "catering": "Contract pay ×%s",
	"bar": "Rowdiness ×%s", "hotel": "Hotel guest demand ×%s", "wholesale": "Wholesale prices ×%s",
}


const FLAG_TEXT := {
	"price": "Unlocks the price slider",
	"auto_price": "Sets the best price automatically",
	"auto_ads": "Auto-buys Ad Campaigns",
	"auto_tables": "Auto-buys Tables",
	"auto_cooks": "Auto-buys Line Cooks",
	"auto_recipes": "Auto-buys Recipes",
	"auto_upg": "Auto-buys the cheapest upgrade",
	"mgr_truck": "Moves the truck to the best spot",
	"mgr_bakery": "Bigger shelves, bread stays fresh",
	"mgr_catering": "Accepts the best contracts",
	"mgr_bar": "Calms rowdy crowds (-40% incidents)",
	"mgr_hotel": "Sets the best room rate each season",
	"mgr_wholesale": "Sells when prices are high",
}


# ================================================================= time

## Advances the game. active=false for catch-up after the game was paused (no events,
## no bankruptcy clock, businesses use their averages).
func tick(dt: float, active := true) -> float:
	_tick_effects(dt)
	var a := agg()
	var inf := income_info(a)
	var flow := float(inf.net) * dt
	var gross := float(inf.total)
	for i in Biz.N:
		var s: Dictionary = biz[i]
		if not s.open:
			continue
		var r: Dictionary
		if active and dt <= 5.0:
			r = Biz.step(i, s, self, dt)
		else:
			var est := Biz.estimate(i, s, self, not active)
			r = {"rev": float(est.rev) * dt, "cost": float(est.cost) * dt}
		flow += float(r.rev) - float(r.cost)
		s.earned = float(s.earned) + float(r.rev)
		gross += float(r.rev) / maxf(dt, 1e-9)
	flow -= interest_per_s() * dt
	cash = minf(cash + flow, MAX_MONEY)
	if flow > 0.0:
		run_earned += flow
		life_earned += flow
	run_time += dt
	play_time += dt
	best_income = maxf(best_income, gross)
	peak_gross = maxf(peak_gross, gross)
	if active:
		_tick_events(dt, gross)
		_tick_red(dt)
	return flow


# ================================================================= effects

func add_effect(kind: String, m: float, dur: float, src: String) -> void:
	effects.append({"kind": kind, "mult": m, "t": dur, "dur": dur, "src": src})


func _tick_effects(dt: float) -> void:
	if effects.is_empty():
		return
	var keep: Array = []
	for f in effects:
		f.t = float(f.t) - dt
		if float(f.t) > 0.0:
			keep.append(f)
	effects = keep


func effect_mult(kind: String) -> float:
	var m := 1.0
	for f in effects:
		if String(f.kind) == kind:
			m *= float(f.mult)
	return m


func effect_add(kind: String) -> float:
	var v := 0.0
	for f in effects:
		if String(f.kind) == kind:
			v += float(f.mult)
	return v


func notify(msg: String) -> void:
	notes.append(msg)
	if notes.size() > 8:
		notes.pop_front()


# ================================================================= events

func _tick_events(dt: float, gross: float) -> void:
	if not events_on or not concept_chosen:
		return
	if not event.is_empty():
		event.t = float(event.t) - dt
		if float(event.t) <= 0.0:
			var line := answer_event(int(event.default))
			notify("%s: no answer, so %s" % [event.get("title", ""), line])
		return
	# no surprises until the restaurant is up and running
	if run_time < 120.0 or run_earned < cp(3.0e6):
		return
	event_t -= dt
	if event_t <= 0.0:
		event_t = rng.randf_range(Events.MIN_GAP, Events.MAX_GAP)
		var a := agg()
		event = Events.make(rng, maxf(gross, 1.0), float(a.luck), float(a.event_cost), cash > 0.0)


## Answers the open event card. Returns a short description of what happened.
func answer_event(idx: int) -> String:
	if event.is_empty():
		return ""
	var ev := event
	event = {}
	var ch: Dictionary = (ev.choices as Array)[clampi(idx, 0, (ev.choices as Array).size() - 1)]
	var line := Events.resolve(self, ev, idx)
	_dirty = true
	return (String(ch.label).to_lower() + (". " + line if line != "" else "")).strip_edges()


# ================================================================= loans

## Banks lend against your best income this run, so a temporary closure doesn't cancel your credit.
func credit_limit() -> float:
	var g := float(income_info(agg()).total)
	for i in Biz.N:
		g += float(Biz.estimate(i, biz[i], self).rev)
	return maxf(maxf(0.0, g), peak_gross) * CREDIT_SECS * float(agg().credit)


func credit_available() -> float:
	return maxf(0.0, credit_limit() - debt)


## Interest per second on the current debt; it climbs steeply as you max out your credit.
func interest_rate(at_debt := -1.0) -> float:
	var d := debt if at_debt < 0.0 else at_debt
	var lim := maxf(credit_limit(), 1.0)
	var u := minf(d / lim, 2.0)
	return INTEREST_BASE * float(agg().interest) * (1.0 + 2.0 * u * u)


func interest_per_s() -> float:
	if debt <= 0.0:
		return 0.0
	return debt * interest_rate()


func borrow(amount: float) -> float:
	amount = minf(amount, credit_available())
	if amount <= 0.0:
		return 0.0
	debt += amount
	cash += amount
	return amount


func repay(amount: float) -> float:
	amount = minf(amount, minf(debt, maxf(0.0, cash)))
	if amount <= 0.0:
		return 0.0
	debt -= amount
	cash -= amount
	if debt < 1e-6:
		debt = 0.0
	return amount


# ================================================================= bankruptcy

func deadline() -> float:
	return DEADLINE_BASE + float(agg().deadline)


func in_red() -> bool:
	return cash < 0.0


func _tick_red(dt: float) -> void:
	if cash >= 0.0:
		red_t = 0.0
		return
	red_t += dt
	if red_t >= deadline():
		go_bankrupt()


static func grit_for(earned: float) -> float:
	return floor(6.0 * pow(pow(maxf(0.0, earned), 1.0 / COST_POW) / 1.0e7, 0.25))


func grit_pending() -> float:
	return grit_for(run_earned)


## Everything resets like selling, but you get Grit instead of stars and this run's stars are lost.
func go_bankrupt() -> float:
	var g := grit_pending()
	var lost := stars_pending()
	grit += g
	grit_earned += g
	bankruptcies += 1
	stars_earned = maxf(stars_earned, stars_for(life_earned))
	last_bankrupt = {"grit": g, "lost_stars": lost, "debt": debt, "run_earned": run_earned}
	concept_chosen = false
	reset_run_state()
	return g


func refund_rate() -> float:
	return 0.5 + float(agg().firesale)


## Sells a side business for part of what you put into it.
func sell_biz(i: int) -> float:
	var s: Dictionary = biz[i]
	if not s.open:
		return 0.0
	var v := Biz.invested(i, s) * refund_rate()
	cash += v
	biz[i] = Biz.blank(i)
	_dirty = true
	return v


## Sells the newest franchise location in your most expensive city.
func sell_location() -> float:
	for i in range(NC - 1, -1, -1):
		if int(cities[i]) > 0:
			cities[i] = int(cities[i]) - 1
			var v := cp(float(city_cost[i]) * pow(CITY_GROWTH, int(cities[i]))) * float(agg().citycost) * refund_rate()
			cash += v
			return v
	return 0.0


# ================================================================= businesses

func biz_open_count() -> int:
	var n := 0
	for s in biz:
		if s.open:
			n += 1
	return n


func biz_unlocked(i: int) -> bool:
	return biz[i].open or run_earned >= Biz.unlock_at(i)


func open_biz(i: int) -> bool:
	var s: Dictionary = biz[i]
	if s.open or not biz_unlocked(i) or cash < Biz.open_cost(i):
		return false
	cash -= Biz.open_cost(i)
	s.open = true
	s.a = 1
	s.b = 1
	_dirty = true
	return true


func biz_cost(i: int, which: String, k: int = 1) -> float:
	return Biz.cost_of(i, which, int(biz[i][which]), k)


func biz_max_affordable(i: int, which: String) -> int:
	var g := Biz.growth(i, which)
	var c0 := Biz.cost_at(i, which, int(biz[i][which]))
	if cash < c0:
		return 0
	return maxi(1, int(floor(log(cash * (g - 1.0) / c0 + 1.0) / log(g))))


func buy_biz(i: int, which: String, k: int = 1) -> bool:
	var s: Dictionary = biz[i]
	if not s.open or k <= 0:
		return false
	var c := biz_cost(i, which, k)
	if c > cash:
		return false
	cash -= c
	s[which] = int(s[which]) + k
	return true


func automation_owned(key: String) -> bool:
	return agg().flags.has(key)


func automation_active(key: String) -> bool:
	return automation_owned(key) and bool(auto_on.get(key, true))


func run_automation() -> void:
	for r in REPS:
		if automation_active("auto_" + r):
			var k := rep_max_affordable(r)
			if k > 0:
				# spend at most half the cash on any one build so the others keep up
				var g := rep_growth(r)
				var c0 := rep_cost_at(r, int(reps[r]), float(agg().cost[r]))
				var lim := int(floor(log(cash * 0.5 * (g - 1.0) / c0 + 1.0) / log(g)))
				if lim > 0:
					buy_rep(r, lim)
	if automation_active("auto_upg"):
		var vis := visible_upgrades()
		if not vis.is_empty() and float(vis[0].cost) <= cash * 0.5:
			buy_upgrade(int(vis[0].id))


func tap() -> float:
	var v := tap_value()
	cash = minf(cash + v, MAX_MONEY)
	run_earned += v
	life_earned += v
	taps += 1
	return v


func offline_gain(seconds: float) -> float:
	var a := agg()
	var s := minf(seconds, float(a.offhours) * 3600.0)
	return maxf(0.0, float(empire(true).net)) * s * float(a.offline)


# ================================================================= prestige

static func stars_for(earned: float) -> float:
	return floor(STAR_COEF * pow(pow(maxf(0.0, earned), 1.0 / COST_POW) / 1.0e10, 0.2))


func stars_pending() -> float:
	return maxf(0.0, stars_for(life_earned) - stars_earned)


func can_prestige() -> bool:
	return stars_pending() >= 1.0


func prestige() -> float:
	var g := stars_pending()
	if g < 1.0:
		return 0.0
	stars += g
	stars_earned += g
	prestiges += 1
	concept_chosen = false
	reset_run_state()
	return g


# ================================================================= save

func to_dict() -> Dictionary:
	return {"v": 1, "cash": cash, "run_earned": run_earned, "life_earned": life_earned, "stars": stars,
		"stars_earned": stars_earned, "prestiges": prestiges, "concept": concept, "concept_chosen": concept_chosen,
		"reps": reps.duplicate(), "owned": _keys_of(owned), "legacy": _keys_of(legacy), "cities": cities.duplicate(),
		"vents": vents.duplicate(), "price": price, "price_auto": price_auto, "auto_on": auto_on.duplicate(),
		"run_time": run_time, "play_time": play_time, "taps": taps, "best_income": best_income,
		"biz": biz.duplicate(true), "debt": debt, "grit": grit, "grit_earned": grit_earned, "bankruptcies": bankruptcies,
		"red_t": red_t, "peak_gross": peak_gross, "effects": effects.duplicate(true), "event": event.duplicate(true), "event_t": event_t}


func _keys_of(d: Dictionary) -> Array:
	var out: Array = []
	for id in d:
		out.append(upgrades[id].key)
	return out


func from_dict(d: Dictionary) -> void:
	new_game()
	cash = float(d.get("cash", 0.0))
	run_earned = float(d.get("run_earned", 0.0))
	life_earned = float(d.get("life_earned", 0.0))
	stars = float(d.get("stars", 0.0))
	stars_earned = float(d.get("stars_earned", 0.0))
	prestiges = int(d.get("prestiges", 0))
	var c := String(d.get("concept", "diner"))
	concept = c if CONCEPT.has(c) else "diner"
	concept_chosen = bool(d.get("concept_chosen", true))
	var rd: Dictionary = d.get("reps", {})
	for r in REPS:
		reps[r] = int(rd.get(r, 0))
	owned = {}
	for k in d.get("owned", []):
		if by_key.has(k) and not upgrades[by_key[k]].legacy:
			owned[by_key[k]] = true
	legacy = {}
	for k in d.get("legacy", []):
		if by_key.has(k) and upgrades[by_key[k]].legacy:
			legacy[by_key[k]] = true
	var cs: Array = d.get("cities", [])
	for i in mini(cs.size(), NC):
		cities[i] = int(cs[i])
	var vs: Array = d.get("vents", [])
	for i in mini(vs.size(), NV):
		vents[i] = int(vs[i])
	price = float(d.get("price", 1.0))
	price_auto = bool(d.get("price_auto", true))
	auto_on = d.get("auto_on", {})
	run_time = float(d.get("run_time", 0.0))
	play_time = float(d.get("play_time", 0.0))
	taps = int(d.get("taps", 0))
	best_income = float(d.get("best_income", 0.0))
	var bz: Array = d.get("biz", [])
	for i in mini(bz.size(), Biz.N):
		if bz[i] is Dictionary:
			var s := Biz.blank(i)
			for k in bz[i]:
				if s.has(k):
					s[k] = bz[i][k]
			biz[i] = s
	debt = float(d.get("debt", 0.0))
	grit = float(d.get("grit", 0.0))
	grit_earned = float(d.get("grit_earned", 0.0))
	bankruptcies = int(d.get("bankruptcies", 0))
	red_t = float(d.get("red_t", 0.0))
	peak_gross = float(d.get("peak_gross", 0.0))
	effects = d.get("effects", [])
	event = d.get("event", {})
	event_t = float(d.get("event_t", Events.MIN_GAP))
	_dirty = true


# ================================================================= formatting

const SUFFIX := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "UDc", "DDc", "TDc", "QaDc",
	"QiDc", "SxDc", "SpDc", "OcDc", "NoDc", "Vg"]


static func fmt_num(v: float) -> String:
	if is_nan(v):
		return "0"
	var neg := v < 0.0
	v = absf(v)
	var s: String
	if v < 1000.0:
		if v < 10.0 and v != floor(v):
			s = "%.2f" % v
		elif v < 100.0 and v != floor(v):
			s = "%.1f" % v
		else:
			s = "%d" % int(round(v))
	else:
		var e := int(floor(log(v) / log(10.0) + 1e-9))
		var g := e / 3
		if g < SUFFIX.size():
			var m := v / pow(10.0, g * 3)
			if m >= 999.995:
				m /= 1000.0
				g += 1
			if g < SUFFIX.size():
				s = ("%.2f" % m if m < 100.0 else "%.1f" % m) + SUFFIX[g]
			else:
				s = "%.2fe%d" % [v / pow(10.0, e), e]
		else:
			s = "%.2fe%d" % [v / pow(10.0, e), e]
	return ("-" if neg else "") + s


static func fmt_money(v: float) -> String:
	return "$" + fmt_num(v)


static func fmt_mult(v: float) -> String:
	if absf(v - round(v)) < 1e-9 and v < 1e6:
		return "%d" % int(round(v))
	if v < 100.0:
		var t := "%.2f" % v
		while t.ends_with("0"):
			t = t.trim_suffix("0")
		return t.trim_suffix(".")
	return fmt_num(v)


static func fmt_time(sec: float) -> String:
	if sec < 0.0 or is_inf(sec) or is_nan(sec):
		return "—"
	if sec < 1.0:
		return "now"
	if sec < 60.0:
		return "%ds" % int(ceil(sec))
	if sec < 3600.0:
		return "%dm %ds" % [int(sec / 60.0), int(sec) % 60]
	if sec < 86400.0:
		return "%dh %dm" % [int(sec / 3600.0), int(sec / 60.0) % 60]
	if sec < 86400.0 * 999:
		return "%dd %dh" % [int(sec / 86400.0), int(sec / 3600.0) % 24]
	return "ages"
