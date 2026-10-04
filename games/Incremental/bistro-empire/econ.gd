class_name Econ
extends RefCounted
## Bistro Empire economy: game state and rules only, no rendering.
##
## Income = served customers/s x ticket x price x multipliers.
##   served = smooth-min(demand x price^-elasticity, seating, kitchen)
## so the three volume stats bottleneck each other, and price turns surplus demand into money
## up to a price ceiling. Franchises, ventures, stars and Grit multiply the flagship on top.
##
## BIG NUMBERS: everything that can grow without limit is kept as a base-10 logarithm (see
## num.gd). Names ending in _l are logs: cash_l = 3.0 means $1,000. Money, prices, income,
## multipliers, stars and Grit all work this way, so the economy has no ceiling.
##
## INFINITE UPGRADES: the catalogue (fixed keys, so saves keep working) is followed by TRACKS.
## When the last catalogue tier of a line is owned, the line carries on with generated tiers
## forever (track_next()). Run lines reset when you sell; star and Grit perk lines don't.
##
## Normal runs have no running costs and can't lose money; events (events.gd) are the only
## bills, and they never take more than the cash you have. Optional challenge runs (CHALLENGES)
## add running costs, the bank and the risk of going bust, and pay Grit, a second prestige
## currency. Side businesses (biz.gd) earn alongside the restaurant on their own scale.

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
## Every cash price is raised to this power. Larger = slower growth per order of magnitude.
const COST_POW := 1.2
const PRICE_K := 1.0
const OFFLINE_BASE := 0.25
const OFFLINE_HOURS_BASE := 2.0
const CITY_GROWTH := 1.8
# Running costs (challenges only), measured against a plate's base value (ticket x ambience),
# half the franchise royalty and the square root of the prestige bonus, never price.
const FOOD_BASE := 35.0           # % of a plate's base value spent on ingredients, per plate served
const RENT_K := 0.15              # per seat per second
const WAGE_K := 0.15              # per unit of kitchen per second
const AD_K := 0.15                # per guest per second your ads bring in (before price)
const FR_COST := 0.5              # franchise royalties carry half the running costs of your own plates
const SMOOTH := 8.0               # how sharply the weakest of guests, seats and kitchen limits service
const INSURE_RATE := 0.025        # insurance premium, share of gross sales
const INSURE_COVER := 0.75        # share of event bills insurance pays
const CREDIT_SECS := 600.0        # credit limit = this many seconds of gross income
const INTEREST_BASE := 0.005 / 60.0  # 0.5% per minute at low borrowing
const DEADLINE_BASE := 300.0      # seconds you can stay in the red
const TAP_SECS := 0.25            # every serve also pays this many seconds of restaurant income
const VENT_GROWTH := 1.5

# ---------------------------------------------------------------- prestige curve
## Stars for lifetime earnings of 10^L: STAR_COEF * 10^((L / COST_POW - STAR_START) * STAR_EXP).
## Every star ever earned adds STAR_BASE to the income multiplier. A smaller STAR_EXP means each
## sale lifts the next run less, so numbers grow more gently.
const STAR_COEF := 25.0
const STAR_START := 10.0
const STAR_EXP := 0.13
const STAR_BASE := 0.02
## Grit for a challenge run that earned 10^L: GRIT_COEF * 10^((L / COST_POW - GRIT_START) * GRIT_EXP).
const GRIT_COEF := 3.0
const GRIT_START := 6.0
const GRIT_EXP := 0.13
const GRIT_BASE := 0.01           # +1% all income per Grit ever earned (spending it never lowers this)

const CONCEPTS := ["diner", "fastfood", "fine", "cafe"]
const CONCEPT := {
	"diner": {"name": "Diner", "blurb": "Forgiving. +25% all income and cheap tables. A good all-rounder.",
		"cblurb": "In challenges: running costs 8% lower.",
		"mult": {"global": 1.25}, "elastic": 2.0, "ceiling": 3.0, "rep_cost": {"tables": 0.75},
		"costs": {"food": 0.0, "rent": 0.92, "wages": 0.92, "ads": 0.92}, "risk": {},
		"unlock": 0, "color": "f5c451"},
	"fastfood": {"name": "Fast Food", "blurb": "Volume. Huge crowds and kitchens, tiny bills and price-shy guests. Kitchens run hot, so inspectors love you.",
		"cblurb": "In challenges: cheap food and rent.",
		"mult": {"kitchen": 3.0, "seating": 2.5, "demand": 4.0, "ticket": 0.5}, "elastic": 2.6, "ceiling": 2.0,
		"costs": {"food": -7.0, "rent": 0.6, "wages": 1.0, "ads": 1.15}, "risk": {"kitchen": 1.5},
		"rep_cost": {"ads": 0.7, "cooks": 0.8}, "unlock": 0, "color": "ff7a45"},
	"fine": {"name": "Fine Dining", "blurb": "Big bills. Set prices from day one, but tables and cooks cost 40% more, and critics and reviews hit twice as hard.",
		"cblurb": "In challenges: pricey food, rent and chefs.",
		"mult": {"ticket": 2.5, "seating": 0.4, "demand": 0.5, "kitchen": 0.5}, "elastic": 1.6, "ceiling": 4.5,
		"costs": {"food": 8.0, "rent": 1.5, "wages": 1.5, "ads": 0.6}, "risk": {"floor": 1.5, "queue": 1.5, "stakes": 2.0}, "flags": ["price"],
		"rep_cost": {"recipes": 0.7, "tables": 1.4, "cooks": 1.4}, "unlock": 1, "color": "c58bff"},
	"cafe": {"name": "Café", "blurb": "Hands-on. Every serve is worth 10x and pays an extra second of income, but other income is 10% lower.",
		"cblurb": "In challenges: food a little pricier.",
		"mult": {"tap": 10.0, "global": 0.9}, "tappct": 1.0, "elastic": 2.0, "ceiling": 3.0,
		"costs": {"food": 3.0, "rent": 1.0, "wages": 1.0, "ads": 1.0}, "risk": {},
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
var city_cost_l: Array = []       # log10 of each city's base price (before COST_POW)
var city_yield: Array = []
var vent_cost_l: Array = []

# ---------------------------------------------------------------- upgrade catalogue
var run_upgrade_count := 0
var upgrades: Array = []          # [{id, key, name, cat, cost_l, star_l, req, eff, excl, concept, legacy}]
var by_key: Dictionary = {}
## Infinite lines: [{id, keys (catalogue keys in order), perm, cur, gen: Callable(level) -> dict}]
var tracks: Array = []
var track_by_id: Dictionary = {}
var track_of_key: Dictionary = {}  # catalogue key -> track index
const VID := 1000000               # generated upgrades have id VID + track index

# ---------------------------------------------------------------- state (logs end in _l)
var cash_l := Num.ZERO
var owed_l := Num.ZERO            # how far below $0 you are (challenges only)
var run_l := Num.ZERO             # earned this run
var life_l := Num.ZERO            # earned ever
var stars_l := Num.ZERO           # unspent
var stars_earned_l := Num.ZERO    # ever
var prestiges := 0
var concept := "diner"
var reps := {"ads": 0, "tables": 0, "cooks": 0, "recipes": 0}
var owned := {}                   # run upgrades id -> true
var legacy := {}                  # legacy upgrades id -> true
var inf := {}                     # run track id -> generated tiers owned this run
var perk_inf := {}                # star/Grit track id -> generated tiers owned
var cities: Array = []
var vents: Array = []
var price_l := 0.0                # manual menu price (log); 0 = x1
var price_auto := true            # only honoured once the auto-price flag is owned
var auto_on := {}                 # automation key -> bool (player toggles)
var run_time := 0.0
var play_time := 0.0
var taps := 0
var best_l := Num.ZERO            # best income per second ever
var concept_chosen := false
var biz: Array = []               # side businesses, see biz.gd
var debt_l := Num.ZERO
var grit_l := Num.ZERO            # unspent
var grit_earned_l := Num.ZERO
var bankruptcies := 0
var red_t := 0.0                  # seconds spent with cash below zero
var effects: Array = []           # [{kind, mult, t, dur, src}] timed effects from events
var event: Dictionary = {}        # the event card waiting for an answer
var event_t := Events.MIN_GAP     # seconds of active play until the next event
var peak_l := Num.ZERO            # best gross income per second this run
var rest_peak_l := Num.ZERO       # best restaurant income this run, ignoring events (keeps taps worth it in a slump)
const ECON_VERSION := 5            # 3: running costs; 4: those only in challenges; 5: big numbers, infinite lines
## Challenge runs: opt-in runs with running costs, bankruptcy and the bank. Reach the level's
## earnings goal and sell the company to collect Grit. Going bust only ends the run.
const CHALLENGE_LEVELS := 10
const CHALLENGES := {
	"margins": {"name": "Tight Margins", "mult": 1.0,
		"blurb": "Every seat, cook, ad and plate costs money to run. Stay below $0 too long and the run is over. Each level runs 15% more expensive.", "mods": {}},
	"health": {"name": "Health Code", "mult": 1.5,
		"blurb": "Tight Margins, plus bad events cost twice as much and nobody sells you insurance.", "mods": {"stakes": 2.0, "no_insure": true}},
	"shoestring": {"name": "Shoestring", "mult": 1.75,
		"blurb": "Tight Margins with no bank at all: no loans, no insurance, and no Legacy starting cash.", "mods": {"no_bank": true, "no_startcash": true}},
	"solo": {"name": "One Restaurant", "mult": 2.0,
		"blurb": "Tight Margins with no side businesses and no franchises. Just you and the kitchen.", "mods": {"no_biz": true, "no_franchise": true}},
	"recession": {"name": "Recession", "mult": 2.0,
		"blurb": "Tight Margins, your price limit is halved and rent, wages and ads cost 20% more.", "mods": {"ceiling": 0.5, "upkeep": 1.2}},
}
const CHALLENGE_ORDER := ["margins", "health", "shoestring", "solo", "recession"]
var challenge := ""               # the challenge this run is (empty: a normal run)
var challenge_level := 0          # 0-based level of the current challenge run
var challenge_best := {}          # challenge id -> levels completed
var last_challenge := {}          # what the last sale completed, for the UI
var old_busts := 0                # bankruptcies under the old rules (they still unlock concepts)
var grace := 0.0                  # seconds of play with no bankruptcy clock and no events (after a rules change)
var rules_notice := false         # tell the player the rules changed (set when an older save loads)
var insured := false              # pays a premium on sales; insurance covers most event bills
var events_on := true
var last_bankrupt: Dictionary = {}
var notes: Array = []             # short messages for the UI to show
var rng := RandomNumberGenerator.new()

var _agg: Dictionary = {}
var _dirty := true
var _next_cache := {}


func _init() -> void:
	rng.randomize()
	for i in NC:
		city_cost_l.append(Num.L(5.0e6) + ladder_l(0.0, 2.4, 3.4, i, NC))
		city_yield.append(pow(4.0, i))
	for i in NV:
		vent_cost_l.append(9.0 + ladder_l(0.0, 10.0, 10.0, i, NV))
	_build_catalogue()
	for u in upgrades:
		if not u.legacy:
			run_upgrade_count += 1
	reset_run_state()


# ================================================================= catalogue

## log10 of the price for a base price of 10^c (prices are raised to COST_POW).
static func cp_l(c_l: float) -> float:
	return c_l * COST_POW + Num.L(PRICE_K)


## Ordinary-number version, for small thresholds.
static func cp(c: float) -> float:
	return pow(c, COST_POW) * PRICE_K


## Cost exponent (log10) for tier t of n, with the step widening from s0 to s1 decades.
static func ladder_l(start: float, s0: float, s1: float, t: int, n: int) -> float:
	var k := (s1 - s0) / maxf(1.0, float(n - 1))
	return start + s0 * t + k * t * t * 0.5


static func roman(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var s := ""
	for i in vals.size():
		while n >= vals[i]:
			s += syms[i]
			n -= vals[i]
	return s


## Adds a run upgrade. base_l is log10 of the base price (before COST_POW); legacy perks pass
## Num.ZERO and their star/Grit price in extra.star_l.
func _add(key: String, name: String, cat: String, base_l: float, eff: Array, req: Array = [], extra: Dictionary = {}) -> Dictionary:
	var u := {"id": upgrades.size(), "key": key, "name": name, "cat": cat,
		"cost_l": cp_l(base_l) if not Num.is_zero(base_l) else Num.ZERO, "eff": eff,
		"req": req, "excl": -1, "concept": "", "legacy": false, "star_l": Num.ZERO}
	for k in extra:
		u[k] = extra[k]
	if req.is_empty() and not u.legacy:
		u.req = ["earn", float(u.cost_l) + Num.L(0.08)]
	upgrades.append(u)
	by_key[key] = u.id
	return u


## Registers an infinite line. keys: the catalogue keys it continues, in order. gen(level) must
## return {name, eff, req, cost_l} for run lines or {name, eff, star_l} for perk lines.
func _track(id: String, keys: Array, gen: Callable, perm := false, extra: Dictionary = {}) -> void:
	var t := {"id": id, "keys": keys, "gen": gen, "perm": perm, "idx": tracks.size()}
	for k in extra:
		t[k] = extra[k]
	tracks.append(t)
	track_by_id[id] = t
	for k in keys:
		track_of_key[k] = t.idx


const STAT_NOUNS := {
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
const ERAS := ["", "Pro ", "Galactic ", "Cosmic ", "Eternal "]
const DISHES := ["Grilled Cheese", "Fries", "Milkshakes", "Burgers", "Hot Dogs", "Pancakes", "Club Sandwich",
	"Chili", "Fried Chicken", "Mac & Cheese", "Tacos", "Caesar Salad", "Pizza", "BBQ Ribs", "Fish & Chips",
	"Pad Thai", "Ramen", "Pho", "Burritos", "Gyros", "Dumplings", "Curry", "Lasagna", "Paella", "Sushi",
	"Poke Bowls", "Bibimbap", "Shakshuka", "Risotto", "Steak Frites", "Crab Cakes", "Lobster Roll",
	"Duck Confit", "Beef Wellington", "Bouillabaisse", "Oysters", "Wagyu Steak", "Truffle Pasta",
	"Caviar Blini", "Omakase", "Tasting Menu", "Peking Duck", "King Crab", "Chocolate Souffle",
	"Creme Brulee", "Tiramisu", "Baklava", "Mochi", "Churros", "Cheesecake", "Gelato Bar",
	"Craft Cocktails", "Wine Pairing", "Sommelier Picks", "Chef's Table", "Saffron Rice",
	"Golden Dessert", "Zero-G Noodles", "Moon Cheese Plate", "Martian Chili"]
const AMB := ["Fresh Paint", "Potted Plants", "Soft Lighting", "Background Jazz", "Spotless Restrooms",
	"Uniforms", "Logo Redesign", "Local Art", "Fireplace", "Live Pianist", "Aquarium", "Chandelier",
	"Open Kitchen", "Inspector Visit", "Signature Scent", "Hand-Thrown Plates", "Marble Bar",
	"Indoor Waterfall", "Gold Leaf Ceiling", "Zero-G Lounge"]
const AMB_ERA := ["", "Refined ", "Legendary ", "Mythic ", "Celestial "]
const STAT_OFF := {"demand": 0.0, "seating": 0.15, "kitchen": 0.3, "ticket": 0.55}
const TAP_NAMES := ["Quick Hands", "Rush Bell", "Hustle Shoes", "Double Plating"]
const BRAND := ["Price Tags", "Word of Mouth", "Regulars", "Loyalty Program", "Signature Sauce", "Brand Story",
	"Cult Following", "Secret Menu", "Glowing Reviews", "Waiting List", "Members' Club", "Household Name"]
const ROY := ["Franchise Manual", "Training Program", "Regional Manager", "Supply Contract", "Brand Standards",
	"Mystery Shoppers", "Central Kitchen", "Logistics Hub", "Franchise Awards", "Owner Summit",
	"Point-of-Sale Network", "Shared Marketing Fund", "Quality Audits", "Franchisee Bonus", "Master Franchise",
	"Distribution Centre", "Brand Bible", "Area Developers", "Franchise TV Spot", "Supplier Rebates",
	"Leadership Academy", "Data Analytics", "Global Standards", "Franchise Council", "Empire Charter"]
const CR_NAMES := {"ads": "Bulk Ad Buys", "tables": "Flat-Pack Tables", "cooks": "Staffing Agency", "recipes": "Test Kitchen"}
const CNAMES := {
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
const CPAT := {
	"diner": [["mul", "global", 1.4], ["syn", "tables", "ticket", 0.002], ["mul", "seating", 1.6], ["mul", "ticket", 1.5]],
	"fastfood": [["mul", "demand", 2.0], ["mul", "kitchen", 1.6], ["mul", "seating", 1.6], ["cost", "ads", 0.7]],
	"fine": [["mul", "ticket", 1.8], ["mul", "ceiling", 1.25], ["mul", "seating", 1.5], ["mul", "demand", 1.5]],
	"cafe": [["mul", "tap", 3.0], ["tappct", 0.25], ["mul", "global", 1.35], ["offline", 0.05]],
}


## A name for tier i of a line that started with a fixed list of 20 names per era.
static func _era_name(eras: Array, nouns: Array, i: int) -> String:
	var era := i / nouns.size()
	if era < eras.size():
		return eras[era] + nouns[i % nouns.size()]
	return "Infinite %s %s" % [nouns[i % nouns.size()], roman(era - eras.size() + 2)]


func _build_catalogue() -> void:
	upgrades.clear()
	by_key.clear()
	tracks.clear()
	track_by_id.clear()
	track_of_key.clear()
	# ---- 1. stat tiers: 60 each for demand, seating, kitchen; 60 dishes for ticket; then forever
	var stat_name := func(s: String, i: int) -> String:
		if s == "ticket":
			return "Menu: " + DISHES[i % 60] + ("" if i < 60 else " " + roman(i / 60 + 1))
		return _era_name(ERAS, STAT_NOUNS[s], i)
	var stat_x := func(i: int) -> float:
		return 1.5 if i % 5 != 4 else 2.0
	var stat_c := func(s: String, i: int) -> float:
		return ladder_l(1.8 + float(STAT_OFF[s]), 1.6, 1.6, i, 60)
	for i in 60:
		for s in ["seating", "kitchen", "demand", "ticket"]:
			_add("t_%s_%d" % [s, i], stat_name.call(s, i), s, stat_c.call(s, i), [["mul", s, stat_x.call(i)]])
	for s in STATS:
		var keys: Array = []
		for i in 60:
			keys.append("t_%s_%d" % [s, i])
		var ss: String = s
		_track("t_" + s, keys, func(i: int) -> Dictionary:
			var c: float = cp_l(stat_c.call(ss, i))
			return {"name": stat_name.call(ss, i), "cat": ss, "eff": [["mul", ss, stat_x.call(i)]], "cost_l": c, "req": ["earn", c + Num.L(0.08)]})
	# ---- 2. global ambience: 60, then forever
	var amb_x := func(i: int) -> float:
		return 1.35 if i % 4 != 3 else 1.7
	var gkeys: Array = []
	for i in 60:
		_add("g_%d" % i, _era_name(AMB_ERA, AMB, i), "global", 2.5 + 1.7 * i, [["mul", "global", amb_x.call(i)]])
		gkeys.append("g_%d" % i)
	_track("g", gkeys, func(i: int) -> Dictionary:
		var c := cp_l(2.5 + 1.7 * i)
		return {"name": _era_name(AMB_ERA, AMB, i), "cat": "global", "eff": [["mul", "global", amb_x.call(i)]], "cost_l": c, "req": ["earn", c + Num.L(0.08)]})
	# ---- 3. build milestones: 4 x 21, then every 250 builds forever
	var ms_x := func(mi: int) -> float:
		return 2.0 if (mi < 2 or mi % 4 == 3) else 1.5
	for r in REPS:
		var mkeys: Array = []
		for mi in MILESTONES.size():
			var n: int = MILESTONES[mi]
			var c := Num.L(float(REP_COST[r])) + (n - 1) * Num.L(float(REP_GROWTH[r])) + Num.L(4.0)
			_add("m_%s_%d" % [r, n], "%d %s" % [n, REP_PLURAL[r]], REP_STAT[r], c, [["mul", REP_STAT[r], ms_x.call(mi)]], ["rep", r, n])
			mkeys.append("m_%s_%d" % [r, n])
		var rr: String = r
		_track("m_" + r, mkeys, func(mi: int) -> Dictionary:
			var n: int = 2000 + 250 * (mi - MILESTONES.size() + 1)
			var c := cp_l(Num.L(float(REP_COST[rr])) + (n - 1) * Num.L(float(REP_GROWTH[rr])) + Num.L(4.0))
			return {"name": "%d %s" % [n, REP_PLURAL[rr]], "cat": REP_STAT[rr], "eff": [["mul", REP_STAT[rr], ms_x.call(mi)]], "cost_l": c, "req": ["rep", rr, n]})
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
			_add("s_%s_%s_%d" % [parts[0], parts[1], t], "%s %s" % [syn_names[pair], roman(t + 1)], parts[1], 5.0 + 25.0 * t + 2.0 * p,
				[["syn", parts[0], parts[1], syn_v[t]]])
		p += 1
	# ---- 5. cheaper builds: 4 x 10, then forever
	var ri := 0
	for r in REPS:
		var ckeys: Array = []
		for t in 10:
			_add("c_%s_%d" % [r, t], "%s %s" % [CR_NAMES[r], roman(t + 1)], "cost", 3.0 + 10.0 * t + 0.4 * ri, [["cost", r, 0.7]])
			ckeys.append("c_%s_%d" % [r, t])
		var rr2: String = r
		var off := 0.4 * ri
		_track("c_" + r, ckeys, func(t: int) -> Dictionary:
			var c := cp_l(3.0 + 10.0 * t + off)
			return {"name": "%s %s" % [CR_NAMES[rr2], roman(t + 1)], "cat": "cost", "eff": [["cost", rr2, 0.7]], "cost_l": c, "req": ["earn", c + Num.L(0.08)]})
		ri += 1
	# ---- 6. serve tap: 40, then forever
	var tap_eff := func(t: int) -> Array:
		return [["mul", "tap", 3.0]] if t % 2 == 0 else [["tappct", 0.1]]
	var tkeys: Array = []
	for t in 40:
		_add("tap_%d" % t, "%s %s" % [TAP_NAMES[t % 4], roman(t / 4 + 1)], "tap", 1.3 + 2.4 * t, tap_eff.call(t))
		tkeys.append("tap_%d" % t)
	_track("tap", tkeys, func(t: int) -> Dictionary:
		var c := cp_l(1.3 + 2.4 * t)
		return {"name": "%s %s" % [TAP_NAMES[t % 4], roman(t / 4 + 1)], "cat": "tap", "eff": tap_eff.call(t), "cost_l": c, "req": ["earn", c + Num.L(0.08)]})
	# ---- 7. brand / price ceiling: 25, then forever
	var bkeys: Array = []
	for t in 25:
		var nm: String = BRAND[t % 12] + ("" if t < 12 else " " + roman(t / 12 + 1))
		_add("b_%d" % t, nm, "ceiling", 2.6 + 4.0 * t, [["mul", "ceiling", 1.25]] if t > 0 else [["flag", "price"]])
		bkeys.append("b_%d" % t)
	_track("b", bkeys, func(t: int) -> Dictionary:
		var c := cp_l(2.6 + 4.0 * t)
		return {"name": BRAND[t % 12] + " " + roman(t / 12 + 1), "cat": "ceiling", "eff": [["mul", "ceiling", 1.25]], "cost_l": c, "req": ["earn", c + Num.L(0.08)]})
	# ---- 8. automation + offline: 6 + 10
	_add("a_price", "Floor Manager", "auto", Num.L(2.5e3), [["flag", "auto_price"]])
	_add("a_ads", "Marketing Manager", "auto", Num.L(5.0e4), [["flag", "auto_ads"]])
	_add("a_tables", "Front-of-House Manager", "auto", Num.L(8.0e4), [["flag", "auto_tables"]])
	_add("a_cooks", "Head Chef", "auto", Num.L(1.2e5), [["flag", "auto_cooks"]])
	_add("a_recipes", "Menu Developer", "auto", Num.L(2.0e5), [["flag", "auto_recipes"]])
	_add("a_upg", "Operations Director", "auto", 9.0, [["flag", "auto_upg"]])
	for t in 10:
		_add("o_%d" % t, "Night Shift %s" % roman(t + 1), "offline", 4.0 + 5.0 * t, [["offline", 0.075], ["offhours", 1.0]])
	# ---- 9. franchise royalties: 50 then forever; lawyers 10
	var rkeys: Array = []
	var roy_name := func(t: int) -> String:
		return ("" if t < 25 else ("Global " if t < 50 else "Galactic ")) + ROY[t % 25] + ("" if t < 75 else " " + roman(t / 25 - 1))
	var roy_x := func(t: int) -> float:
		return 1.25 if t % 5 != 4 else 1.5
	for t in 50:
		_add("r_%d" % t, roy_name.call(t), "royalty", Num.L(2.0e4) + 1.9 * t, [["mul", "royalty", roy_x.call(t)]], ["locs", 1 + t])
		rkeys.append("r_%d" % t)
	_track("r", rkeys, func(t: int) -> Dictionary:
		return {"name": roy_name.call(t), "cat": "royalty", "eff": [["mul", "royalty", roy_x.call(t)]], "cost_l": cp_l(Num.L(2.0e4) + 1.9 * t), "req": ["locs", 1 + t]})
	for t in 10:
		_add("fc_%d" % t, "Franchise Lawyers %s" % roman(t + 1), "royalty", 7.0 + 9.0 * t, [["citycost", 0.75]], ["locs", 3 + 4 * t])
	# ---- 10. city-specific: 30 x 8, then every 25 locations forever
	for ci in NC:
		var ckeys2: Array = []
		for mi in CITY_MILESTONES.size():
			var n: int = CITY_MILESTONES[mi]
			_add("cm_%d_%d" % [ci, n], "%s: %s" % [CITY_NAMES[ci], CITY_MS_NAME[mi]], "city",
				float(city_cost_l[ci]) + (n - 1) * Num.L(CITY_GROWTH) + Num.L(3.0), [["city", ci, CITY_MS_MULT[mi]]], ["city", ci, n])
			ckeys2.append("cm_%d_%d" % [ci, n])
		var cci: int = ci
		_track("cm_%d" % ci, ckeys2, func(mi: int) -> Dictionary:
			var n: int = 50 + 25 * (mi - CITY_MILESTONES.size() + 1)
			return {"name": "%s: %d Locations" % [CITY_NAMES[cci], n], "cat": "city", "eff": [["city", cci, 1.25]],
				"cost_l": cp_l(float(city_cost_l[cci]) + (n - 1) * Num.L(CITY_GROWTH) + Num.L(3.0)), "req": ["city", cci, n]})
	# ---- 11. ventures: 8 x 12, then every 100 levels forever
	for vi in NV:
		var vkeys: Array = []
		for mi in VENT_MILESTONES.size():
			var n: int = VENT_MILESTONES[mi]
			_add("vm_%d_%d" % [vi, n], "%s: Level %d" % [VENTURES[vi].name, n], "venture",
				float(vent_cost_l[vi]) + (n - 1) * Num.L(VENT_GROWTH) + Num.L(3.0), [["vent", vi, 1.15]], ["vent", vi, n])
			vkeys.append("vm_%d_%d" % [vi, n])
		var vvi: int = vi
		_track("vm_%d" % vi, vkeys, func(mi: int) -> Dictionary:
			var n: int = 400 + 100 * (mi - VENT_MILESTONES.size() + 1)
			return {"name": "%s: Level %d" % [VENTURES[vvi].name, n], "cat": "venture", "eff": [["vent", vvi, 1.15]],
				"cost_l": cp_l(float(vent_cost_l[vvi]) + (n - 1) * Num.L(VENT_GROWTH) + Num.L(3.0)), "req": ["vent", vvi, n]})
	# ---- 12. concept-specific: 4 x 30, then forever
	for cn in CONCEPTS:
		var kkeys: Array = []
		var cname := func(t: int, c2: String) -> String:
			return ("" if t < 15 else ("Master " if t < 30 else "Legendary ")) + CNAMES[c2][t % 15] + ("" if t < 45 else " " + roman(t / 15 - 1))
		for t in 30:
			_add("k_%s_%d" % [cn, t], cname.call(t, cn), "concept", 2.2 + 3.2 * t, [CPAT[cn][t % 4]], [], {"concept": cn})
			kkeys.append("k_%s_%d" % [cn, t])
		var ccn: String = cn
		_track("k_" + cn, kkeys, func(t: int) -> Dictionary:
			var c := cp_l(2.2 + 3.2 * t)
			return {"name": cname.call(t, ccn), "cat": "concept", "eff": [CPAT[ccn][t % 4]], "cost_l": c, "req": ["earn", c + Num.L(0.08)], "concept": ccn})
	# ---- 13. crossroads: 8 pairs x 5 tiers (buying one locks the other for this run)
	var cross := [
		["Union Kitchen", [["mul", "kitchen", 3.0], ["cost", "cooks", 1.6]], "Gig Cooks", [["mul", "kitchen", 1.6], ["cost", "cooks", 0.5]]],
		["Billboard Blitz", [["mul", "demand", 3.0]], "Word of Mouth Club", [["mul", "demand", 1.6], ["mul", "ticket", 1.3]]],
		["Premium Pricing", [["mul", "ceiling", 1.5], ["mul", "demand", 0.85]], "Value Menu", [["mul", "demand", 2.0], ["mul", "ceiling", 0.9]]],
		["Tasting Course", [["mul", "ticket", 2.5], ["mul", "seating", 0.8]], "Family Platters", [["mul", "seating", 2.0], ["mul", "ticket", 1.2]]],
		["Corporate Chain", [["mul", "royalty", 2.5], ["citycost", 1.3]], "Owner-Operators", [["citycost", 0.5], ["mul", "royalty", 1.3]]],
		["Front-Line Owner", [["mul", "tap", 10.0], ["tappct", 0.5]], "Absentee Owner", [["mul", "global", 1.4], ["offline", 0.1]]],
		["Imported Ingredients", [["mul", "ticket", 2.0]], "Local Sourcing", [["mul", "ticket", 1.4], ["cost", "recipes", 0.5]]],
		["Open 24/7", [["mul", "global", 1.8], ["cost", "ads", 1.3], ["cost", "tables", 1.3], ["cost", "cooks", 1.3], ["cost", "recipes", 1.3]],
			"Weekends Off", [["mul", "global", 1.3], ["cost", "ads", 0.8], ["cost", "tables", 0.8], ["cost", "cooks", 0.8], ["cost", "recipes", 0.8]]],
	]
	for ci in cross.size():
		var row: Array = cross[ci]
		for t in 5:
			var c := 3.5 + 30.0 * t + 4.0 * ci
			var a := _add("x_%d_%d_a" % [ci, t], "%s %s" % [row[0], roman(t + 1)], "cross", c, row[1])
			var b := _add("x_%d_%d_b" % [ci, t], "%s %s" % [row[2], roman(t + 1)], "cross", c, row[3])
			a.excl = b.id
			b.excl = a.id
	# ---- 14. legacy perks (stars, survive selling the company): 80, then most lines forever
	var leg := [
		["Family Recipes", 10, "startcash"], ["Reputation", 20, "global"], ["Star Power", 10, "starpow"],
		["Head Start", 10, "startreps"], ["Franchise Network", 10, "royalty"], ["Silver Spoon", 5, "tap"],
		["Night Owl", 5, "offline"], ["Venture Capital", 5, "vent"], ["Old Managers", 5, "flags"]]
	for row in leg:
		var base_n: String = row[0]
		var kind: String = row[2]
		var lkeys: Array = []
		for t in int(row[1]):
			var pk := _perk(kind, t)
			_add("l_%s_%d" % [kind, t], "%s %s" % [base_n, roman(t + 1)], "legacy", Num.ZERO, pk.eff, ["legacy", kind, t],
				{"legacy": true, "star_l": float(pk.star_l)})
			lkeys.append("l_%s_%d" % [kind, t])
		if kind != "flags" and kind != "offline":
			var kk: String = kind
			var bn: String = base_n
			_track("l_" + kind, lkeys, func(t: int) -> Dictionary:
				var pk2 := _perk(kk, t)
				return {"name": "%s %s" % [bn, roman(t + 1)], "cat": "legacy", "eff": pk2.eff, "star_l": float(pk2.star_l), "kind": kk}, true, {"cur": "star"})
	# ---- 15. side businesses
	Biz.add_upgrades(self)
	# ---- 16. grit perks (Grit is earned by completing challenges; perks survive every reset): 73, then forever
	# Every line helps in normal runs; some also carry a smaller part that only matters in
	# challenges (running costs, the bank, the deadline), which their text labels.
	for row in GRIT_LINES:
		var gkeys2: Array = []
		for t in int(row[1]):
			_add("gr_%s_%d" % [row[2], t], "%s %s" % [row[0], roman(t + 1)], "grit", Num.ZERO, row[3], ["legacy", row[2], t],
				{"legacy": true, "cur": "grit", "lp": "gr", "star_l": _grit_price_l(row, t)})
			gkeys2.append("gr_%s_%d" % [row[2], t])
		var grow: Array = row
		_track("gr_" + String(row[2]), gkeys2, func(t: int) -> Dictionary:
			return {"name": "%s %s" % [grow[0], roman(t + 1)], "cat": "grit", "eff": grow[3], "star_l": _grit_price_l(grow, t), "kind": grow[2]}, true, {"cur": "grit"})


const GRIT_LINES := [
	["Battle-Tested", 10, "empire", [["mul", "empire", 1.5]], 5.0, 4.0],
	["Thick Skin", 8, "skin", [["mul", "demand", 1.25], ["event_cost", 0.85]], 2.0, 4.0],
	["Supplier Credit", 8, "credit", [["cost", "ads", 0.85], ["cost", "tables", 0.85], ["cost", "cooks", 0.85], ["cost", "recipes", 0.85], ["credit", 1.4]], 2.0, 4.0],
	["Trusted Name", 8, "rates", [["citycost", 0.8], ["interest", 0.85]], 2.0, 4.0],
	["Lean Operations", 8, "lean", [["mul", "kitchen", 1.4], ["mul", "seating", 1.4], ["upkeep", 0.9]], 3.0, 4.0],
	["Supply Chain", 6, "food", [["mul", "ticket", 1.5], ["foodcut", 2.0]], 3.0, 4.0],
	["Second Wind", 5, "wind", [["startreps", 5], ["deadline", 60.0]], 2.0, 4.0],
	["Side Hustle", 10, "hustle", [["mul", "biz", 1.4]], 3.0, 4.0],
	["Lucky Break", 5, "luck", [["luck", 0.06], ["mul", "global", 1.15]], 4.0, 4.0],
	["Know Your Worth", 5, "sale", [["mul", "ceiling", 1.2], ["firesale", 0.08]], 2.0, 4.0],
]


## Past the catalogue, each tier of a star or Grit line costs a little more than the last
## growth step on top (0.04 x tiers^2 extra decades), so lines never end but bought tiers grow
## like the square root of what you have: prestige can't feed itself into a runaway.
static func _ramp(x: int) -> float:
	return 0.04 * x * x if x > 0 else 0.0


static func _grit_price_l(row: Array, t: int) -> float:
	return Num.L(float(row[4])) + t * Num.L(float(row[5])) + _ramp(t - int(row[1]) + 1)


const PERK_N := {"startcash": 10, "global": 20, "starpow": 10, "startreps": 10, "royalty": 10, "tap": 5, "offline": 5, "vent": 5, "flags": 5}


## Effect and star price of tier t of a legacy perk line. Prices grow faster than the effects,
## so each tier is a bigger step; every line but the managers and night owl goes on forever.
static func _perk(kind: String, t: int) -> Dictionary:
	var p := _perk_raw(kind, t)
	p.star_l = Num.floor_l(float(p.star_l))
	return p


static func _perk_raw(kind: String, t: int) -> Dictionary:
	var flag_list := ["auto_price", "auto_ads", "auto_tables", "auto_cooks", "auto_recipes"]
	var r := _ramp(t - int(PERK_N.get(kind, 0)) + 1)
	match kind:
		"startcash":
			return {"eff": [["startcash", 2.0 + 2.5 * t]], "star_l": Num.L(2.0) + t * Num.L(4.0) + r}
		"global":
			return {"eff": [["mul", "global", 2.0]], "star_l": Num.L(10.0) + t * Num.L(3.0) + r}
		"starpow":
			return {"eff": [["starpow", 0.005]], "star_l": Num.L(10.0) + t * Num.L(2.5) + r}
		"startreps":
			return {"eff": [["startreps", 10]], "star_l": Num.L(4.0) + t * Num.L(2.5) + r}
		"royalty":
			return {"eff": [["mul", "royalty", 2.0]], "star_l": Num.L(20.0) + t * Num.L(2.4) + r}
		"tap":
			return {"eff": [["mul", "tap", 5.0]], "star_l": Num.L(2.0) + t * Num.L(3.0) + r}
		"offline":
			return {"eff": [["offline", 0.1], ["offhours", 2.0]], "star_l": Num.L(4.0) + t * Num.L(3.0)}
		"vent":
			return {"eff": [["vent_all", 2.0]], "star_l": Num.L(100.0) + t * Num.L(4.0) + r}
		"flags":
			return {"eff": [["flag", flag_list[mini(t, 4)]]], "star_l": Num.L(floor(2.0 + 3.0 * t))}
	return {"eff": [], "star_l": 0.0}


# ================================================================= lifecycle

func reset_run_state() -> void:
	cash_l = Num.ZERO
	owed_l = Num.ZERO
	run_l = Num.ZERO
	run_time = 0.0
	for r in REPS:
		reps[r] = 0
	owned = {}
	inf = {}
	cities = []
	for i in NC:
		cities.append(0)
	vents = []
	for i in NV:
		vents.append(0)
	price_l = 0.0
	biz = []
	for i in Biz.N:
		biz.append(Biz.blank(i))
	debt_l = Num.ZERO
	red_t = 0.0
	peak_l = Num.ZERO
	rest_peak_l = Num.ZERO
	effects = []
	event = {}
	event_t = Events.MIN_GAP
	_dirty = true
	var a := agg()
	cash_l = maxf(Num.L(5.0), Num.ZERO if cmod("no_startcash") else float(a.startcash_l))
	for r in REPS:
		reps[r] = int(a.startreps)
	_dirty = true


func new_game() -> void:
	life_l = Num.ZERO
	stars_l = Num.ZERO
	stars_earned_l = Num.ZERO
	prestiges = 0
	legacy = {}
	perk_inf = {}
	concept = "diner"
	concept_chosen = false
	play_time = 0.0
	taps = 0
	best_l = Num.ZERO
	auto_on = {}
	grit_l = Num.ZERO
	grit_earned_l = Num.ZERO
	bankruptcies = 0
	last_bankrupt = {}
	challenge = ""
	challenge_level = 0
	challenge_best = {}
	old_busts = 0
	reset_run_state()


func choose_concept(c: String) -> bool:
	if not CONCEPT.has(c) or not concept_unlocked(c):
		return false
	concept = c
	concept_chosen = true
	_dirty = true
	return true


## Concepts unlock with sales. Bankruptcies from before challenges existed still count, so
## nobody loses a concept they had; failing or quitting a challenge doesn't.
func concept_unlocked(c: String) -> bool:
	return prestiges + old_busts >= int(CONCEPT[c].unlock)


# ================================================================= aggregate

func mark_dirty() -> void:
	_dirty = true


func agg() -> Dictionary:
	if _dirty or _agg.is_empty():
		_agg = _aggregate(owned)
		_next_cache = {}
		_dirty = false
	return _agg


## Multipliers that can grow forever (lm, lcost, city_l, vent_l, biz_l, citycost_l, credit_l)
## are logs; the rest are small ordinary numbers.
func _blank_agg() -> Dictionary:
	var a := {
		"lm": {"demand": 0.0, "seating": 0.0, "kitchen": 0.0, "ticket": 0.0, "global": 0.0, "tap": 0.0,
			"royalty": 0.0, "ceiling": 0.0, "biz": 0.0, "empire": 0.0},
		"lcost": {"ads": 0.0, "tables": 0.0, "cooks": 0.0, "recipes": 0.0},
		"syn": [], "tappct": 0.0, "city_l": [], "citycost_l": 0.0, "vent_l": [], "flags": {},
		"offline": OFFLINE_BASE, "offhours": OFFLINE_HOURS_BASE, "starpow": 0.0, "startcash_l": Num.ZERO, "startreps": 0,
		"elastic": 2.0, "ceiling": 3.0,
		"biz_l": [], "twist": {"truck": 1.0, "bakery": 1.0, "catering": 1.0, "bar": 1.0, "hotel": 1.0, "wholesale": 1.0},
		"upkeep": 1.0, "foodcut": 0.0, "event_cost": 1.0, "credit_l": 0.0, "interest": 1.0, "deadline": 0.0,
		"luck": 0.0, "firesale": 0.0,
	}
	for i in Biz.N:
		a.biz_l.append(0.0)
	for i in NC:
		a.city_l.append(0.0)
	for i in NV:
		a.vent_l.append(0.0)
	return a


func _aggregate(own: Dictionary) -> Dictionary:
	var a := _blank_agg()
	var cc: Dictionary = CONCEPT[concept]
	for k in cc.mult:
		a.lm[k] += Num.L(float(cc.mult[k]))
	for k in cc.rep_cost:
		a.lcost[k] += Num.L(float(cc.rep_cost[k]))
	a.elastic = float(cc.elastic)
	a.ceiling = float(cc.ceiling)
	a.tappct += float(cc.get("tappct", 0.0))
	for f in cc.get("flags", []):
		a.flags[f] = true
	if challenge != "":
		a.ceiling *= float(cmod("ceiling", 1.0))
		a.upkeep *= float(cmod("upkeep", 1.0)) * (1.0 + 0.15 * challenge_level)   # each level runs 15% hotter
	for id in own:
		apply_effects(a, upgrades[id].eff)
	for id in legacy:
		apply_effects(a, upgrades[id].eff)
	for t in tracks:
		var n := int((perk_inf if t.perm else inf).get(t.id, 0))
		for j in n:
			apply_effects(a, _gen(t, (t.keys as Array).size() + j).eff)
	return a


var _gen_cache := {}
## Tier `level` of a track (levels count from the start of the line, catalogue tiers included).
func _gen(t: Dictionary, level: int) -> Dictionary:
	var k := "%d:%d" % [int(t.idx), level]
	if not _gen_cache.has(k):
		_gen_cache[k] = (t.gen as Callable).call(level)
	return _gen_cache[k]


func apply_effects(a: Dictionary, eff: Array) -> void:
	for e in eff:
		match String(e[0]):
			"mul": a.lm[e[1]] += Num.L(float(e[2]))
			"cost": a.lcost[e[1]] += Num.L(float(e[2]))
			"syn": a.syn.append([e[1], e[2], float(e[3])])
			"tappct": a.tappct += float(e[1])
			"city": a.city_l[int(e[1])] += Num.L(float(e[2]))
			"citycost": a.citycost_l += Num.L(float(e[1]))
			"vent": a.vent_l[int(e[1])] += Num.L(float(e[2]))
			"vent_all":
				for i in NV:
					a.vent_l[i] += Num.L(float(e[1]))
			"flag": a.flags[e[1]] = true
			"offline": a.offline = minf(1.0, a.offline + float(e[1]))
			"offhours": a.offhours += float(e[1])
			"starpow": a.starpow += float(e[1])
			"startcash": a.startcash_l = maxf(a.startcash_l, float(e[1]))
			"startreps": a.startreps += int(e[1])
			"biz": a.biz_l[int(e[1])] += Num.L(float(e[2]))
			"twist": a.twist[e[1]] *= float(e[2])
			"upkeep": a.upkeep *= float(e[1])
			"foodcut": a.foodcut += float(e[1])
			"event_cost": a.event_cost *= float(e[1])
			"credit": a.credit_l += Num.L(float(e[1]))
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


## log10 of a venture's multiplier: 1 + 2% per level x its upgrades.
func vent_l(i: int, a: Dictionary) -> float:
	return Num.add(0.0, Num.L(VENT_RATE * float(vents[i])) + float(a.vent_l[i]))


func stat_l(s: String, a: Dictionary, rep_override: Dictionary = {}) -> float:
	var r: String = STAT_REP[s]
	var n := int(rep_override.get(r, reps[r]))
	var v: float = Num.L(float(BASE[s]) + n * float(REP_ADD[r])) + float(a.lm[s])
	for sy in a.syn:
		if sy[1] == s:
			v += Num.L(1.0 + float(sy[2]) * float(rep_override.get(sy[0], reps[sy[0]])))
	for i in NV:
		if VENTURES[i].stat == s:
			v += vent_l(i, a)
	return v


func global_l(a: Dictionary) -> float:
	var g: float = float(a.lm.global)
	for i in NV:
		if VENTURES[i].stat == "global":
			g += vent_l(i, a)
	return g


func royalty_l(a: Dictionary) -> float:
	var r: float = float(a.lm.royalty)
	for i in NV:
		if VENTURES[i].stat == "royalty":
			r += vent_l(i, a)
	return r


## log10 of the franchise multiplier: 1 + 10% x royalties x the sum of every location's yield.
func fr_l(a: Dictionary, city_override: Array = []) -> float:
	var cs: Array = city_override if not city_override.is_empty() else cities
	var parts: Array = []
	for i in NC:
		if int(cs[i]) > 0:
			parts.append(i * Num.L(4.0) + Num.L(float(cs[i])) + float(a.city_l[i]))
	if parts.is_empty():
		return 0.0
	return Num.add(0.0, Num.L(0.1) + royalty_l(a) + Num.sum(parts))


## Every star you've ever earned counts, spent or not.
func star_l(a: Dictionary) -> float:
	return Num.add(0.0, stars_earned_l + Num.L(STAR_BASE + float(a.starpow)))


## Every Grit you've ever earned counts, spent or not.
func grit_mult_l(_a: Dictionary = {}) -> float:
	return Num.add(0.0, grit_earned_l + Num.L(GRIT_BASE))


## Everything that boosts the whole empire (restaurant and businesses alike): stars, Grit and
## the empire multiplier from Grit perks.
func prestige_l(a: Dictionary = {}) -> float:
	if a.is_empty():
		a = agg()
	return star_l(a) + grit_mult_l(a) + float(a.lm.empire)


func ceiling_l(a: Dictionary) -> float:
	return Num.L(float(a.ceiling)) + float(a.lm.ceiling)


func price_unlocked(a: Dictionary) -> bool:
	return a.flags.has("price") or a.flags.has("auto_price")


## Smooth minimum: the weakest value dominates, but anything less than ~30% above it still
## drags a little, so a small buffer in the other two pays.
static func smin_l(ls: Array) -> float:
	var parts: Array = []
	for l in ls:
		if Num.is_zero(float(l)):
			return Num.ZERO
		parts.append(-SMOOTH * float(l))
	return -Num.sum(parts) / SMOOTH


func effect_mult(kind: String) -> float:
	var m := 1.0
	for f in effects:
		if String(f.kind) == kind:
			m *= float(f.mult)
	return m


func effect_l(kind: String) -> float:
	return Num.L(effect_mult(kind))


func effect_add(kind: String) -> float:
	var v := 0.0
	for f in effects:
		if String(f.kind) == kind:
			v += float(f.mult)
	return v


## The price that earns the most from the guests you have: it fills your capacity.
func best_price_l(a: Dictionary, rep_override: Dictionary = {}) -> float:
	var d := stat_l("demand", a, rep_override) + effect_l("demand")
	var c := smin_l([stat_l("seating", a, rep_override) + effect_l("seating"), stat_l("kitchen", a, rep_override) + effect_l("kitchen")])
	var e := float(a.elastic)
	var x := pow(maxf(e - 1.0, 0.05), -1.0 / SMOOTH)
	return clampf((Num.L(x) + d - c) / e, Num.L(PRICE_MIN), ceiling_l(a))


func effective_price_l(a: Dictionary, rep_override: Dictionary = {}, force_best := false) -> float:
	if force_best or (a.flags.has("auto_price") and price_auto):
		return best_price_l(a, rep_override)
	if not price_unlocked(a):
		return 0.0
	return clampf(price_l, Num.L(PRICE_MIN), ceiling_l(a))


func cost_mod(kind: String, a: Dictionary) -> float:
	return float((CONCEPT[concept].costs as Dictionary).get(kind, 1.0)) * float(a.upkeep) * effect_mult("wages" if kind != "ads" else "adcost")


## Full breakdown of the restaurant's money per second for an aggregate. Every amount is a log
## (keys ending _l); net is signed: net_l with net_neg.
func income_info(a: Dictionary, rep_override: Dictionary = {}, city_override: Array = [], force_best := false) -> Dictionary:
	var d := stat_l("demand", a, rep_override) + effect_l("demand")
	var se := stat_l("seating", a, rep_override) + effect_l("seating")
	var k := stat_l("kitchen", a, rep_override) + effect_l("kitchen")
	var t := stat_l("ticket", a, rep_override)
	var p := effective_price_l(a, rep_override, force_best)
	var want := d - float(a.elastic) * p
	var cap := smin_l([se, k])
	var closed := effect_mult("closed") <= 0.0
	var served := Num.ZERO if closed else smin_l([want, se, k])
	var fr := fr_l(a, city_override)
	var g := global_l(a)
	var pres := prestige_l(a)
	var sm := pres + effect_l("income") + Num.L(supply_mult())
	var total := served + t + p + g + fr + sm
	if closed:
		total = Num.ZERO
	# what holds service back. When the Floor Manager prices to fill every seat, extra guests
	# become higher prices, so the limit is whichever of seats and kitchen is smaller, unless
	# even the lowest price can't fill them.
	var limit := "demand"
	var priced: bool = (force_best or (a.flags.has("auto_price") and price_auto))
	if priced and p > Num.L(PRICE_MIN) + 1e-6:
		limit = "seating" if se <= k else "kitchen"
	elif want > minf(se, k):
		limit = "seating" if se <= k else "kitchen"
	# running costs (challenges only), against a plate's base value: a bigger name (stars, Grit)
	# means busier, pricier operations too, but only by its square root, so costs always matter
	var food := Num.ZERO
	var rent := Num.ZERO
	var wages := Num.ZERO
	var ads := Num.ZERO
	if costs_on():
		var unit := t + g + Num.add(Num.L(1.0 - FR_COST), Num.L(FR_COST) + fr) + 0.5 * pres
		if not closed:
			food = served + unit + Num.L(food_cost_pct(a) / 100.0)
		rent = se + unit + Num.L(RENT_K * cost_mod("rent", a))
		wages = k + unit + Num.L(WAGE_K * cost_mod("wages", a))
		ads = d - effect_l("demand") + unit + Num.L(AD_K * cost_mod("ads", a))
	var up := Num.sum([rent, wages, ads])
	var cost := Num.add(food, up)
	var net := Num.diff(total, cost)
	var ratio := func(x: float, y: float) -> float:
		return 0.0 if Num.is_zero(x) or Num.is_zero(y) else Num.V(minf(x - y, 300.0))
	return {"d_l": d, "se_l": se, "k_l": k, "t_l": t, "p_l": p, "want_l": want, "cap_l": cap,
		"served_l": served, "fr_l": fr, "g_l": g, "sm_l": sm, "total_l": total, "limit": limit,
		"food_l": food, "rent_l": rent, "wages_l": wages, "ads_l": ads, "upkeep_l": up, "cost_l": cost,
		"net_l": net[0], "net_neg": net[1], "closed": closed,
		"kstrain": ratio.call(served, k), "fstrain": ratio.call(served, se),
		"queue": clampf(1.0 - ratio.call(served, want), 0.0, 1.0) if not Num.is_zero(want) else 0.0}


## Signed net of an income_info: [log, is negative].
static func net_of(info: Dictionary) -> Array:
	return [float(info.net_l), bool(info.net_neg)]


## Wholesale Delivery Trucks: in normal runs they boost restaurant income (in a challenge they
## cut food costs instead, see food_cost_pct).
func supply_mult() -> float:
	if costs_on():
		return 1.0
	var m := 1.0
	for i in Biz.N:
		if String(Biz.DEFS[i].id) == "wholesale":
			m += Biz.supply_boost(biz[i])
	return m


func food_cost_pct(a: Dictionary = {}) -> float:
	if a.is_empty():
		a = agg()
	var cut := float(a.foodcut)
	for i in Biz.N:
		if String(Biz.DEFS[i].id) == "wholesale":
			cut += Biz.food_cut(biz[i])
	return clampf(FOOD_BASE + float(CONCEPT[concept].costs.food) - cut + effect_add("food"), 5.0, 80.0)


## Money in and out per second for the whole empire (businesses use steady-state estimates).
## All logs; net is signed (net_l, net_neg).
func empire(offline := false) -> Dictionary:
	var a := agg()
	var info := income_info(a)
	var br := Num.ZERO
	var bc := Num.ZERO
	var per: Array = []
	for i in Biz.N:
		var est := Biz.estimate(i, biz[i], self, offline)
		per.append(est)
		br = Num.add(br, float(est.rev_l))
		bc = Num.add(bc, float(est.cost_l))
	var it := interest_l()
	var gross := Num.add(float(info.total_l), br)
	var ins := insurance_l(gross)
	var costs := Num.sum([float(info.cost_l), bc, it, ins])
	var net := Num.diff(gross, costs)
	return {"rest_l": float(info.total_l), "food_l": float(info.food_l), "rest_upkeep_l": float(info.upkeep_l),
		"rent_l": float(info.rent_l), "wages_l": float(info.wages_l), "ads_l": float(info.ads_l),
		"biz_rev_l": br, "biz_cost_l": bc, "interest_l": it, "insurance_l": ins, "gross_l": gross, "costs_l": costs,
		"net_l": net[0], "net_neg": net[1], "per": per}


func insurance_l(gross_l: float) -> float:
	return gross_l + Num.L(INSURE_RATE) if insured and insurance_on() else Num.ZERO


## Net money per second for the whole empire (log; 0 when losing money, see empire()).
func income_l() -> float:
	var em := empire()
	return Num.ZERO if bool(em.net_neg) else float(em.net_l)


func gross_l() -> float:
	return float(empire().gross_l)


## A serve is worth one guest's bill (multiplied by serving upgrades) plus a slice of a second of
## your restaurant's income, so tapping stays worth something all game.
func tap_value_l(a: Dictionary = {}) -> float:
	if a.is_empty():
		a = agg()
	var info := income_info(a)
	var base := float(info.t_l) + float(info.p_l) + float(info.g_l) + float(info.fr_l) + float(info.sm_l) + float(a.lm.tap)
	return Num.add(base, float(info.total_l) + Num.L(TAP_SECS + float(a.tappct)))


# ================================================================= money

func can_afford(c_l: float) -> bool:
	return Num.is_zero(c_l) or c_l <= cash_l + 1e-12


## Pays a price from cash. False (and nothing happens) if you can't afford it.
func spend(c_l: float) -> bool:
	if not can_afford(c_l):
		return false
	cash_l = Num.sub(cash_l, c_l)
	return true


## Money that comes in without counting as earnings (loans, refunds, event windfalls). It pays
## off anything owed first.
func add_cash(v_l: float) -> void:
	if Num.is_zero(v_l):
		return
	if not Num.is_zero(owed_l):
		if v_l >= owed_l:
			v_l = Num.sub(v_l, owed_l)
			owed_l = Num.ZERO
		else:
			owed_l = Num.sub(owed_l, v_l)
			return
	cash_l = Num.add(cash_l, v_l)


## Money earned: it counts towards this run's and lifetime earnings.
func earn(v_l: float) -> void:
	if Num.is_zero(v_l):
		return
	run_l = Num.add(run_l, v_l)
	life_l = Num.add(life_l, v_l)
	add_cash(v_l)


## A bill. In a challenge what cash can't cover is owed (you're in the red); a normal run never
## goes below $0.
func charge(c_l: float) -> void:
	if Num.is_zero(c_l):
		return
	if c_l <= cash_l:
		cash_l = Num.sub(cash_l, c_l)
		return
	var rest := Num.sub(c_l, cash_l)
	cash_l = Num.ZERO
	if costs_on():
		owed_l = Num.add(owed_l, rest)


# ================================================================= builds

func rep_growth_l(r: String) -> float:
	return Num.L(float(REP_GROWTH[r])) * COST_POW


func rep_c0_l(r: String) -> float:
	return cp_l(Num.L(float(REP_COST[r]))) + int(reps[r]) * rep_growth_l(r) + float(agg().lcost[r])


func rep_cost_l(r: String, k: int = 1) -> float:
	return Num.geo(rep_c0_l(r), Num.V(rep_growth_l(r)), k)


func rep_max_affordable(r: String) -> int:
	return Num.geo_max(cash_l, rep_c0_l(r), Num.V(rep_growth_l(r)))


func buy_rep(r: String, k: int = 1) -> bool:
	if k <= 0:
		return false
	if not spend(rep_cost_l(r, k)):
		return false
	reps[r] = int(reps[r]) + k
	return true


## The next build milestone (catalogue or past it), or -1.
func next_milestone(r: String) -> int:
	var n := int(reps[r])
	for m in MILESTONES:
		if n < int(m):
			return int(m)
	return (n / 250 + 1) * 250


func franchise_unlocked() -> bool:
	if cmod("no_franchise"):
		return false
	return run_l >= cp_l(7.0) or locations() > 0


func city_unlocked(i: int) -> bool:
	if not franchise_unlocked():
		return false
	if i == 0:
		return true
	return int(cities[i - 1]) > 0 and run_l >= cp_l(float(city_cost_l[i])) + Num.L(0.05)


func city_next_cost_l(i: int) -> float:
	return cp_l(float(city_cost_l[i]) + int(cities[i]) * Num.L(CITY_GROWTH)) + float(agg().citycost_l)


func buy_city(i: int) -> bool:
	if not city_unlocked(i) or not spend(city_next_cost_l(i)):
		return false
	cities[i] = int(cities[i]) + 1
	return true


func ventures_unlocked() -> bool:
	return locations() >= 15 or vents[0] > 0


func vent_unlocked(i: int) -> bool:
	if not ventures_unlocked():
		return false
	if i == 0:
		return true
	return int(vents[i - 1]) > 0 and run_l >= cp_l(float(vent_cost_l[i])) + Num.L(0.05)


func vent_next_cost_l(i: int) -> float:
	return cp_l(float(vent_cost_l[i]) + int(vents[i]) * Num.L(VENT_GROWTH))


func buy_vent(i: int) -> bool:
	if not vent_unlocked(i) or not spend(vent_next_cost_l(i)):
		return false
	vents[i] = int(vents[i]) + 1
	_dirty = true
	return true


# ================================================================= upgrades

## An upgrade by id: catalogue ids, or VID + track index for the next generated tier of a line.
func get_up(id: int) -> Dictionary:
	if id >= VID:
		return track_next(tracks[id - VID])
	return upgrades[id]


func upgrade_cost_l(u: Dictionary) -> float:
	return float(u.cost_l)


## The next generated tier of an infinite line, or {} while the catalogue part isn't finished
## (or the line doesn't apply: another concept's line, say).
func track_next(t: Dictionary) -> Dictionary:
	var idx := int(t.idx)
	if _next_cache.has(idx) and not _dirty:
		return _next_cache[idx]
	var out := {}
	var have: Dictionary = legacy if t.perm else owned
	var done := true
	for k in t.keys:
		if not have.has(by_key[k]):
			done = false
			break
	if done:
		var n := int((perk_inf if t.perm else inf).get(t.id, 0))
		var level := (t.keys as Array).size() + n
		var g := _gen(t, level)
		out = {"id": VID + idx, "key": "%s#%d" % [t.id, level], "name": g.name, "cat": String(g.get("cat", "legacy")),
			"cost_l": float(g.get("cost_l", Num.ZERO)), "star_l": float(g.get("star_l", Num.ZERO)),
			"req": g.get("req", ["legacy", String(g.get("kind", "")), level]), "eff": g.eff, "excl": -1,
			"concept": String(g.get("concept", "")), "legacy": bool(t.perm), "track": idx, "level": level,
			"cur": String(t.get("cur", "star"))}
		for k in ["biz"]:
			if g.has(k):
				out[k] = g[k]
	_next_cache[idx] = out
	return out


## How many tiers of a line you own (catalogue and generated).
func track_owned(t: Dictionary) -> int:
	var have: Dictionary = legacy if t.perm else owned
	var n := 0
	for k in t.keys:
		if have.has(by_key[k]):
			n += 1
	return n + int((perk_inf if t.perm else inf).get(t.id, 0))


func req_met(u: Dictionary) -> bool:
	var q: Array = u.req
	match String(q[0]):
		"earn": return run_l >= float(q[1]) - 1e-9
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
				"earn": return run_l >= upgrade_cost_l(u) + Num.L(0.08)
	return false


func req_text(u: Dictionary) -> String:
	var q: Array = u.req
	match String(q[0]):
		"earn": return "Earn %s this run" % Num.fmt_money(float(q[1]))
		"rep": return "Own %s %s" % [fmt_count(int(q[2])), REP_PLURAL[q[1]]]
		"city": return "%s locations in %s" % [fmt_count(int(q[2])), CITY_NAMES[int(q[1])]]
		"vent": return "%s level %s" % [VENTURES[int(q[1])].name, fmt_count(int(q[2]))]
		"locs": return "%s franchise locations" % fmt_count(int(q[1]))
		"bizopen": return "Run %d side business%s" % [int(q[1]), "" if int(q[1]) == 1 else "es"]
		"biz":
			var d: Dictionary = Biz.DEFS[int(q[1])]
			match String(q[2]):
				"a": return "%s %s at the %s" % [fmt_count(int(q[3])), d.as, d.name]
				"b": return "%s %s at the %s" % [fmt_count(int(q[3])), d.bs, d.name]
				"open": return "Open the %s" % d.name
				"earn": return "Open the %s and earn %s this run" % [d.name, Num.fmt_money(upgrade_cost_l(u) + Num.L(0.08))]
	return ""


func is_owned(u: Dictionary) -> bool:
	if int(u.id) >= VID:
		return false
	return legacy.has(u.id) if u.legacy else owned.has(u.id)


func blocked(u: Dictionary) -> bool:
	if u.concept != "" and u.concept != concept:
		return true
	if int(u.excl) >= 0 and owned.has(int(u.excl)):
		return true
	return false


func available(u: Dictionary) -> bool:
	return not u.legacy and not is_owned(u) and not blocked(u) and req_met(u)


## Every run upgrade you could buy now (catalogue, plus the next tier of every finished line).
func _run_candidates() -> Array:
	var out: Array = []
	for u in upgrades:
		if not u.legacy and not owned.has(u.id) and not blocked(u):
			out.append(u)
	for t in tracks:
		if not t.perm:
			var u := track_next(t)
			if not u.is_empty() and not blocked(u):
				out.append(u)
	return out


func visible_upgrades() -> Array:
	var out: Array = []
	for u in _run_candidates():
		if req_met(u):
			out.append(u)
	out.sort_custom(func(x, y): return float(x.cost_l) < float(y.cost_l))
	return out


## The next few run upgrades that are not yet unlocked, cheapest first.
func upcoming_upgrades(n: int) -> Array:
	var out: Array = []
	for u in _run_candidates():
		if not req_met(u):
			out.append(u)
	out.sort_custom(func(x, y): return float(x.cost_l) < float(y.cost_l))
	return out.slice(0, n)


func buy_upgrade(id: int) -> bool:
	var u := get_up(id)
	if u.is_empty():
		return false
	if u.legacy:
		return buy_legacy(id)
	if not available(u) or not spend(float(u.cost_l)):
		return false
	if id >= VID:
		var t: Dictionary = tracks[id - VID]
		inf[t.id] = int(inf.get(t.id, 0)) + 1
	else:
		owned[id] = true
	_dirty = true
	return true


func legacy_available(u: Dictionary) -> bool:
	if u.is_empty() or not u.legacy:
		return false
	if int(u.id) >= VID:
		return true
	if legacy.has(u.id):
		return false
	var q: Array = u.req
	var t := int(q[2])
	if t == 0:
		return true
	return legacy.has(by_key["%s_%s_%d" % [String(u.get("lp", "l")), q[1], t - 1]])


func currency(u: Dictionary) -> String:
	return String(u.get("cur", "star"))


func wallet_l(cur: String) -> float:
	return grit_l if cur == "grit" else stars_l


func buy_legacy(id: int) -> bool:
	var u := get_up(id)
	var cur := currency(u)
	if not legacy_available(u) or float(u.star_l) > wallet_l(cur) + 1e-9:
		return false
	if cur == "grit":
		grit_l = Num.sub(grit_l, float(u.star_l))
	else:
		stars_l = Num.sub(stars_l, float(u.star_l))
	if id >= VID:
		var t: Dictionary = tracks[id - VID]
		perk_inf[t.id] = int(perk_inf.get(t.id, 0)) + 1
	else:
		legacy[id] = true
	_dirty = true
	return true


## The star (or Grit) perk lines, in catalogue order: [{kind, name, owned, next}] where next is
## the upgrade to buy next ({} once a finite line is complete).
func perk_lines(cur: String) -> Array:
	var out: Array = []
	var seen := {}
	for u in upgrades:
		if not u.legacy or currency(u) != cur:
			continue
		var kind := String(u.req[1])
		if seen.has(kind):
			continue
		seen[kind] = true
		var prefix := "%s_%s_" % [String(u.get("lp", "l")), kind]
		var nxt := {}
		var n := 0
		var t := 0
		while by_key.has(prefix + str(t)):
			var v: Dictionary = upgrades[by_key[prefix + str(t)]]
			if legacy.has(v.id):
				n += 1
			elif nxt.is_empty():
				nxt = v
			t += 1
		var tid := ("gr_" if cur == "grit" else "l_") + kind
		if track_by_id.has(tid):
			n += int(perk_inf.get(tid, 0))
			if nxt.is_empty():
				nxt = track_next(track_by_id[tid])
		out.append({"kind": kind, "owned": n, "next": nxt, "first": u})
	return out


## Stars (or Grit) spent on perks so far.
func perk_spent_l(cur: String) -> float:
	var parts: Array = []
	for id in legacy:
		var u: Dictionary = upgrades[id]
		if currency(u) == cur:
			parts.append(float(u.star_l))
	for t in tracks:
		if t.perm and String(t.get("cur", "star")) == cur:
			for j in int(perk_inf.get(t.id, 0)):
				parts.append(float(_gen(t, (t.keys as Array).size() + j).star_l))
	return Num.sum(parts)


func upgrade_count_owned() -> int:
	var n := owned.size() + legacy.size()
	for k in inf:
		n += int(inf[k])
	for k in perk_inf:
		n += int(perk_inf[k])
	return n


func effect_text(eff: Array) -> String:
	var parts: PackedStringArray = []
	# the same discount on all four builds reads as one line
	var costs := {}
	for e in eff:
		if String(e[0]) == "cost":
			costs[String(e[1])] = float(e[2])
	var all_cost: bool = costs.size() == REPS.size() and costs.values().min() == costs.values().max()
	if all_cost:
		parts.append("All build prices ×%s" % fmt_mult(float(costs.values()[0])))
	for e in eff:
		if all_cost and String(e[0]) == "cost":
			continue
		match String(e[0]):
			"mul":
				parts.append("%s ×%s" % [STAT_NAME[e[1]], fmt_mult(float(e[2]))])
			"cost": parts.append("%s price ×%s" % [REP_NAME[e[1]], fmt_mult(float(e[2]))])
			"syn": parts.append("Each %s you own: +%s%% %s" % [REP_NAME[e[1]], fmt_mult(float(e[3]) * 100.0), String(STAT_NAME[e[2]]).to_lower()])
			"tappct": parts.append("Each serve +%ss of income" % fmt_mult(float(e[1])))
			"city": parts.append("%s locations ×%s" % [CITY_NAMES[int(e[1])], fmt_mult(float(e[2]))])
			"citycost": parts.append("Franchise price ×%s" % fmt_mult(float(e[1])))
			"vent": parts.append("%s effect ×%s" % [VENTURES[int(e[1])].name, fmt_mult(float(e[2]))])
			"vent_all": parts.append("All ventures ×%s" % fmt_mult(float(e[1])))
			"flag": parts.append(FLAG_TEXT.get(e[1], e[1]))
			"offline": parts.append("Offline earnings +%d%%" % int(round(float(e[1]) * 100.0)))
			"offhours": parts.append("+%dh offline cap" % int(e[1]))
			"starpow": parts.append("Each star +%s%% more" % fmt_mult(float(e[1]) * 100.0))
			"startcash": parts.append("Start runs with %s" % Num.fmt_money(float(e[1])))
			"startreps": parts.append("Start with +%d of each build" % int(e[1]))
			"biz": parts.append("%s income ×%s" % [Biz.DEFS[int(e[1])].name, fmt_mult(float(e[2]))])
			"twist": parts.append(TWIST_TEXT.get(e[1], e[1]) % fmt_mult(float(e[2])))
			"upkeep": parts.append("Running costs ×%s (challenges)" % fmt_mult(float(e[1])))
			"foodcut": parts.append("Food costs -%s pts (challenges)" % fmt_mult(float(e[1])))
			"event_cost": parts.append("Event bills ×%s" % fmt_mult(float(e[1])))
			"credit": parts.append("Credit limit ×%s (challenges)" % fmt_mult(float(e[1])))
			"interest": parts.append("Loan interest ×%s (challenges)" % fmt_mult(float(e[1])))
			"deadline": parts.append("+%ds to recover from the red (challenges)" % int(e[1]))
			"luck": parts.append("+%d%% chance of good events" % int(round(float(e[1]) * 100.0)))
			"firesale": parts.append("+%d%% back when selling off (challenges)" % int(round(float(e[1]) * 100.0)))
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
	"auto_truck": "Auto-buys trucks and menu items", "auto_bakery": "Auto-buys ovens and counters",
	"auto_catering": "Auto-buys crew and vans", "auto_bar": "Auto-buys bartenders and bouncers",
	"auto_hotel": "Auto-buys rooms and concierges", "auto_wholesale": "Auto-buys warehouses and trucks",
}


# ================================================================= time

## Advances the game. active=false for catch-up after the game was paused (no events,
## no bankruptcy clock, businesses use their averages). Returns the signed net [log, neg].
func tick(dt: float, active := true) -> Array:
	_tick_effects(dt)
	var a := agg()
	var info := income_info(a)
	var ldt := Num.L(dt)
	var in_l := float(info.total_l) + ldt
	var out_l := float(info.cost_l) + ldt
	var gross := float(info.total_l)
	for i in Biz.N:
		var s: Dictionary = biz[i]
		if not s.open:
			continue
		var r: Dictionary
		if active and dt <= 5.0:
			r = Biz.step(i, s, self, dt)
		else:
			var est := Biz.estimate(i, s, self, not active)
			r = {"rev_l": float(est.rev_l) + ldt, "cost_l": float(est.cost_l) + ldt}
		in_l = Num.add(in_l, float(r.rev_l))
		out_l = Num.add(out_l, float(r.cost_l))
		s.earned_l = Num.add(float(s.earned_l), float(r.rev_l))
		gross = Num.add(gross, float(r.rev_l) - ldt)
	out_l = Num.add(out_l, interest_l() + ldt)
	out_l = Num.add(out_l, insurance_l(gross) + ldt)
	var net := Num.diff(in_l, out_l)
	if net[1]:
		charge(net[0])
	else:
		earn(net[0])
	run_time += dt
	play_time += dt
	best_l = maxf(best_l, gross)
	peak_l = maxf(peak_l, gross)
	update_rest_peak()
	if active:
		grace = maxf(0.0, grace - dt)
		_tick_events(dt, gross)
		_tick_red(dt)
	return net


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


func notify(msg: String) -> void:
	notes.append(msg)
	if notes.size() > 8:
		notes.pop_front()


# ================================================================= events

func _tick_events(dt: float, gross: float) -> void:
	if not events_on or not concept_chosen:
		return
	if not event.is_empty():
		return   # waits for an answer
	if grace > 0.0:
		return
	# no surprises until the restaurant is up and running
	if run_time < 120.0 or run_l < cp_l(Num.L(2.0e4)):
		return
	event_t -= dt
	if event_t <= 0.0:
		var rk := Events.risks(self)
		event_t = Events.next_gap(rng, rk)
		event = new_event(event_ref_l(gross), rk)


## Event bills are measured in seconds of profit (at least a quarter of sales), so they sting
## the same whether your margins are thin or fat. A log.
func event_ref_l(gross := NAN) -> float:
	var em := empire()
	if is_nan(gross):
		gross = float(em.gross_l)
	var net := Num.ZERO if bool(em.net_neg) else float(em.net_l)
	return maxf(maxf(net, gross + Num.L(0.25)), 0.0)


func new_event(ref_l: float, rk: Dictionary = {}, only := "") -> Dictionary:
	if rk.is_empty():
		rk = Events.risks(self)
	var a := agg()
	var ev := Events.make(rng, ref_l, float(a.luck), float(a.event_cost), rk, CONCEPT[concept].get("risk", {}),
		INSURE_COVER if insured and insurance_on() else 0.0, only, not costs_on())
	if not ev.is_empty() and not bool(ev.good):
		ev.cost_mult = float(ev.cost_mult) * float(cmod("stakes", 1.0))   # Health Code
	return ev


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
func credit_limit_l() -> float:
	var g := float(income_info(agg()).total_l)
	for i in Biz.N:
		g = Num.add(g, float(Biz.estimate(i, biz[i], self).rev_l))
	return maxf(g, peak_l) + Num.L(CREDIT_SECS) + float(agg().credit_l)


func credit_available_l() -> float:
	return Num.sub(credit_limit_l(), debt_l)


## Share of your credit line in use (0 with no debt).
func debt_use() -> float:
	if Num.is_zero(debt_l):
		return 0.0
	return Num.V(minf(debt_l - credit_limit_l(), 1.0))


## Interest per second (a fraction of the debt); it climbs steeply as you max out your credit.
func interest_rate(at_debt_l := NAN) -> float:
	var d := debt_l if is_nan(at_debt_l) else at_debt_l
	var u := 0.0 if Num.is_zero(d) else minf(Num.V(minf(d - credit_limit_l(), 1.0)), 2.0)
	return INTEREST_BASE * float(agg().interest) * (1.0 + 2.0 * u * u) * effect_mult("rate")


func interest_l() -> float:
	if Num.is_zero(debt_l):
		return Num.ZERO
	return debt_l + Num.L(interest_rate())


## Borrows up to amount (a log). Returns what was lent.
func borrow(amount_l: float) -> float:
	if not bank_on():
		return Num.ZERO
	amount_l = minf(amount_l, credit_available_l())
	if Num.is_zero(amount_l):
		return Num.ZERO
	debt_l = Num.add(debt_l, amount_l)
	add_cash(amount_l)
	return amount_l


func repay(amount_l: float) -> float:
	amount_l = minf(amount_l, minf(debt_l, cash_l))
	if Num.is_zero(amount_l):
		return Num.ZERO
	debt_l = Num.sub(debt_l, amount_l)
	cash_l = Num.sub(cash_l, amount_l)
	if debt_l < amount_l - 12.0:
		debt_l = Num.ZERO
	return amount_l


# ================================================================= bankruptcy

func deadline() -> float:
	return DEADLINE_BASE + float(agg().deadline)


func in_red() -> bool:
	return not Num.is_zero(owed_l)


func _tick_red(dt: float) -> void:
	if not costs_on():
		owed_l = Num.ZERO   # normal runs can't go below $0
	if not in_red() or grace > 0.0 or not costs_on():
		red_t = 0.0
		return
	red_t += dt
	if red_t >= deadline():
		go_bankrupt()


## Going bust only happens in a challenge: the run ends and you're back to a normal run.
## Nothing else is lost; this run's earnings still count towards your next sale's stars.
func go_bankrupt() -> void:
	last_bankrupt = {"challenge": challenge, "level": challenge_level, "debt_l": Num.add(debt_l, owed_l), "run_l": run_l}
	bankruptcies += 1
	challenge = ""
	challenge_level = 0
	concept_chosen = false
	reset_run_state()


# ================================================================= challenges

func costs_on() -> bool:
	return challenge != ""


func cmod(key: String, dflt = false):
	if challenge == "":
		return dflt
	return (CHALLENGES[challenge].mods as Dictionary).get(key, dflt)


func bank_on() -> bool:
	return costs_on() and not cmod("no_bank")


func insurance_on() -> bool:
	return bank_on() and not cmod("no_insure")


func challenge_next_level(id: String) -> int:
	return int(challenge_best.get(id, 0))


## Earnings goal (log) for a challenge level. Levels go on forever; each needs 1,000x more
## (before COST_POW) and runs 15% more expensive.
func challenge_goal_l(level := -1) -> float:
	if level < 0:
		level = challenge_level
	return cp_l(8.0 + 3.0 * level)


func challenge_done() -> bool:
	return challenge != "" and run_l >= challenge_goal_l()


## Grit for a challenge run that earned 10^e_l.
static func grit_for_l(e_l: float) -> float:
	if Num.is_zero(e_l):
		return Num.ZERO
	return Num.floor_l(Num.L(GRIT_COEF) + (e_l / COST_POW - GRIT_START) * GRIT_EXP)


## Grit for finishing the current challenge with what you've earned this run.
func challenge_reward_l(earned_l := NAN) -> float:
	if challenge == "":
		return Num.ZERO
	if is_nan(earned_l):
		earned_l = run_l
	return challenge_reward_for_l(challenge, challenge_level, earned_l)


## Earnings past 20x the goal don't add Grit, so climbing levels pays better than farming one.
const REWARD_CAP := 20.0
func challenge_reward_for_l(id: String, level: int, earned_l: float) -> float:
	var e2 := minf(earned_l, challenge_goal_l(level) + Num.L(REWARD_CAP))
	return Num.floor_l(maxf(0.0, grit_for_l(e2)) + Num.L(float(CHALLENGES[id].mult)) + Num.L(1.0 + 0.5 * level))


## Ends the current run (nothing is lost: its earnings still count towards stars) and starts
## the next level of a challenge. The player then picks a concept as usual.
func start_challenge(id: String) -> bool:
	if not CHALLENGES.has(id):
		return false
	challenge = id
	challenge_level = challenge_next_level(id)
	concept_chosen = false
	reset_run_state()
	return true


func abandon_challenge() -> void:
	challenge = ""
	challenge_level = 0
	concept_chosen = false
	reset_run_state()


func refund_rate() -> float:
	return minf(0.95, 0.5 + float(agg().firesale))


## Sells a side business for part of what you put into it. Returns the log amount.
func sell_biz(i: int) -> float:
	var s: Dictionary = biz[i]
	if not s.open:
		return Num.ZERO
	var v := Biz.invested_l(i, s, self) + Num.L(refund_rate())
	add_cash(v)
	biz[i] = Biz.blank(i)
	_dirty = true
	return v


## Sells the newest franchise location in your most expensive city.
func sell_location() -> float:
	for i in range(NC - 1, -1, -1):
		if int(cities[i]) > 0:
			cities[i] = int(cities[i]) - 1
			var v := city_next_cost_l(i) + Num.L(refund_rate())
			add_cash(v)
			return v
	return Num.ZERO


# ================================================================= businesses

## The restaurant's best income this run, without temporary event effects (log). Only used to
## keep taps worth something in a slump; businesses no longer depend on it.
func update_rest_peak() -> void:
	if effects.is_empty():
		rest_peak_l = maxf(rest_peak_l, float(income_info(agg()).total_l))
		return
	var saved := effects
	effects = []
	var v := float(income_info(agg()).total_l)
	effects = saved
	rest_peak_l = maxf(rest_peak_l, v)


func biz_open_count() -> int:
	var n := 0
	for s in biz:
		if s.open:
			n += 1
	return n


func biz_unlocked(i: int) -> bool:
	if cmod("no_biz"):
		return false
	return biz[i].open or run_l >= Biz.unlock_at_l(i)


func open_biz(i: int) -> bool:
	var s: Dictionary = biz[i]
	if s.open or not biz_unlocked(i) or not spend(Biz.open_cost_l(i)):
		return false
	s.open = true
	s.a = 1
	s.b = 1
	_dirty = true
	return true


func biz_next_milestone(i: int, which: String) -> int:
	var n := int(biz[i][which])
	for m in (Biz.A_MILESTONES if which == "a" else Biz.B_MILESTONES):
		if n < int(m):
			return int(m)
	if which == "a":
		return (n / 25 + 1) * 25
	return -1


func biz_cost_l(i: int, which: String, k: int = 1) -> float:
	return Biz.cost_of_l(i, which, int(biz[i][which]), k)


func biz_max_affordable(i: int, which: String) -> int:
	return Num.geo_max(cash_l, Biz.cost_at_l(i, which, int(biz[i][which])), Biz.growth(i, which))


func buy_biz(i: int, which: String, k: int = 1) -> bool:
	var s: Dictionary = biz[i]
	if not s.open or k <= 0:
		return false
	if not spend(biz_cost_l(i, which, k)):
		return false
	s[which] = int(s[which]) + k
	return true


## Signed change in the whole empire's net income from swapping in a different state for one
## business (more builds, say). Counts knock-on effects such as Wholesale trucks boosting the
## restaurant. Returns [log, is negative].
func biz_gain_with(i: int, s2: Dictionary) -> Array:
	var s: Dictionary = biz[i]
	var cur: Dictionary = Biz.estimate(i, s, self)
	var nxt: Dictionary = Biz.estimate(i, s2, self)
	var g := Num.sadd(Num.diff(float(nxt.rev_l), float(nxt.cost_l)), Num.sneg(Num.diff(float(cur.rev_l), float(cur.cost_l))))
	if String(Biz.DEFS[i].id) == "wholesale":
		var a := agg()
		var r0 := net_of(income_info(a))
		biz[i] = s2
		var r1 := net_of(income_info(a))
		biz[i] = s
		g = Num.sadd(g, Num.sadd(r1, Num.sneg(r0)))
	return g


func automation_owned(key: String) -> bool:
	return agg().flags.has(key)


func automation_active(key: String) -> bool:
	return automation_owned(key) and bool(auto_on.get(key, true))


## Managers only buy what pays: a build must raise profit and pay for itself within 10 minutes,
## an upgrade must not lower profit, and neither spends more than half your cash.
func run_automation() -> void:
	var half := cash_l + Num.L(0.5)
	for r in REPS:
		if not automation_active("auto_" + r):
			continue
		for n in 25:
			var c := rep_cost_l(r, 1)
			if c > cash_l + Num.L(0.5):
				break
			var a := agg()
			var g := Num.sadd(net_of(income_info(a, {r: int(reps[r]) + 1})), Num.sneg(net_of(income_info(a))))
			if g[1] or Num.is_zero(g[0]) or c - float(g[0]) > Num.L(600.0):
				break
			buy_rep(r, 1)
	for i in Biz.N:
		var bs: Dictionary = biz[i]
		if bs.open and automation_active("auto_" + String(Biz.DEFS[i].id)):
			_auto_biz(i)
	if automation_active("auto_upg"):
		half = cash_l + Num.L(0.5)
		var a := agg()
		var cur := net_of(income_info(a))
		var k := 0
		for u in visible_upgrades():
			k += 1
			if k > 12:
				break
			if float(u.cost_l) > half or String(u.cat) == "cross":
				continue
			if Num.scmp(net_of(income_info(copy_with(a, u.eff))), cur, 1e-9) < 0:
				continue
			buy_upgrade(int(u.id))
			break


## Expansion Manager: buys whichever build of this business pays back fastest, with up to a
## quarter of your cash, as long as it pays back within 15 minutes.
func _auto_biz(i: int) -> void:
	for k in 4:
		var s: Dictionary = biz[i]
		var best := ""
		var best_pb := Num.L(900.0)
		for w in ["a", "b"]:
			var c := biz_cost_l(i, w, 1)
			if c > cash_l + Num.L(0.25):
				continue
			var s2 := s.duplicate(true)
			s2[w] = int(s2[w]) + 1
			var g := biz_gain_with(i, s2)
			if not g[1] and not Num.is_zero(g[0]) and c - float(g[0]) < best_pb:
				best_pb = c - float(g[0])
				best = w
		if best == "" or not buy_biz(i, best, 1):
			return


func tap() -> float:
	var v := tap_value_l()
	earn(v)
	taps += 1
	return v


## Selling by hand at a side business: half a second of its sales, at least a quarter of a restaurant tap.
func biz_tap(i: int) -> float:
	if not bool(biz[i].open):
		return Num.ZERO
	var est: Dictionary = Biz.estimate(i, biz[i], self)
	var v := maxf(float(est.rev_l) + Num.L(0.5), tap_value_l() + Num.L(0.25))
	earn(v)
	return v


## What you earn while away for `seconds` (log). Doesn't add it.
func offline_gain_l(seconds: float) -> float:
	var a := agg()
	var s := minf(seconds, float(a.offhours) * 3600.0)
	var em := empire(true)
	if bool(em.net_neg) or s <= 0.0:
		return Num.ZERO
	return float(em.net_l) + Num.L(s * float(a.offline))


# ================================================================= prestige

## Stars for lifetime earnings of 10^life_l.
static func stars_for_l(life: float) -> float:
	if Num.is_zero(life):
		return Num.ZERO
	var v := Num.L(STAR_COEF) + (life / COST_POW - STAR_START) * STAR_EXP
	return Num.floor_l(v) if v >= 0.0 else Num.ZERO


func stars_pending_l() -> float:
	return Num.floor_l(Num.sub(stars_for_l(life_l), stars_earned_l))


func can_prestige() -> bool:
	return stars_pending_l() >= -1e-9 or challenge_done()


## Sells the company. In a challenge that has reached its goal, this also pays Grit and
## completes the level. Selling an unfinished challenge just ends it. Returns the stars (log).
func prestige() -> float:
	if not can_prestige():
		return Num.ZERO
	var g := stars_pending_l()
	if challenge_done():
		var gr := challenge_reward_l()
		grit_l = Num.add(grit_l, gr)
		grit_earned_l = Num.add(grit_earned_l, gr)
		challenge_best[challenge] = maxi(challenge_next_level(challenge), challenge_level + 1)
		last_challenge = {"id": challenge, "level": challenge_level, "grit_l": gr}
	else:
		last_challenge = {}
	stars_l = Num.add(stars_l, g)
	stars_earned_l = Num.add(stars_earned_l, g)
	prestiges += 1
	challenge = ""
	challenge_level = 0
	concept_chosen = false
	reset_run_state()
	return g


# ================================================================= save

func to_dict() -> Dictionary:
	return {"v": 1, "econ": ECON_VERSION, "grace": grace, "cash_l": cash_l, "owed_l": owed_l, "run_l": run_l, "life_l": life_l,
		"stars_l": stars_l, "stars_earned_l": stars_earned_l, "prestiges": prestiges, "concept": concept, "concept_chosen": concept_chosen,
		"reps": reps.duplicate(), "owned": _keys_of(owned), "legacy": _keys_of(legacy), "inf": inf.duplicate(), "perk_inf": perk_inf.duplicate(),
		"cities": cities.duplicate(), "vents": vents.duplicate(), "price_l": price_l, "price_auto": price_auto, "auto_on": auto_on.duplicate(),
		"run_time": run_time, "play_time": play_time, "taps": taps, "best_l": best_l,
		"biz": biz.duplicate(true), "debt_l": debt_l, "grit_l": grit_l, "grit_earned_l": grit_earned_l, "bankruptcies": bankruptcies,
		"red_t": red_t, "peak_l": peak_l, "rest_peak_l": rest_peak_l, "insured": insured, "challenge": challenge,
		"challenge_level": challenge_level, "challenge_best": challenge_best.duplicate(), "old_busts": old_busts,
		"effects": effects.duplicate(true), "event": event.duplicate(true), "event_t": event_t}


func _keys_of(d: Dictionary) -> Array:
	var out: Array = []
	for id in d:
		out.append(upgrades[id].key)
	return out


## A log from a save: new saves store logs (key_l), older ones plain numbers (key).
static func _load_l(d: Dictionary, key: String) -> float:
	if d.has(key + "_l"):
		var v := float(d[key + "_l"])
		return Num.ZERO if Num.is_zero(v) else v
	return Num.L(float(d.get(key, 0.0)))


func from_dict(d: Dictionary) -> void:
	new_game()
	var ver := int(d.get("econ", 1))
	cash_l = _load_l(d, "cash")
	owed_l = _load_l(d, "owed")
	if ver < 5 and float(d.get("cash", 0.0)) < 0.0:
		owed_l = Num.L(-float(d.get("cash", 0.0)))
	run_l = _load_l(d, "run") if d.has("run_l") else Num.L(float(d.get("run_earned", 0.0)))
	life_l = _load_l(d, "life") if d.has("life_l") else Num.L(float(d.get("life_earned", 0.0)))
	stars_l = _load_l(d, "stars")
	stars_earned_l = _load_l(d, "stars_earned")
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
	inf = {}
	var di: Dictionary = d.get("inf", {})
	for k in di:
		if track_by_id.has(k) and not track_by_id[k].perm:
			inf[k] = int(di[k])
	perk_inf = {}
	var dp: Dictionary = d.get("perk_inf", {})
	for k in dp:
		if track_by_id.has(k) and track_by_id[k].perm:
			perk_inf[k] = int(dp[k])
	var cs: Array = d.get("cities", [])
	for i in mini(cs.size(), NC):
		cities[i] = int(cs[i])
	var vs: Array = d.get("vents", [])
	for i in mini(vs.size(), NV):
		vents[i] = int(vs[i])
	price_l = float(d.get("price_l", Num.L(maxf(float(d.get("price", 1.0)), PRICE_MIN))))
	price_auto = bool(d.get("price_auto", true))
	auto_on = d.get("auto_on", {})
	run_time = float(d.get("run_time", 0.0))
	play_time = float(d.get("play_time", 0.0))
	taps = int(d.get("taps", 0))
	best_l = _load_l(d, "best") if d.has("best_l") else Num.L(float(d.get("best_income", 0.0)))
	var bz: Array = d.get("biz", [])
	for i in mini(bz.size(), Biz.N):
		if bz[i] is Dictionary:
			biz[i] = Biz.load_state(i, bz[i])
	debt_l = _load_l(d, "debt")
	grit_l = _load_l(d, "grit")
	grit_earned_l = _load_l(d, "grit_earned")
	bankruptcies = int(d.get("bankruptcies", 0))
	red_t = float(d.get("red_t", 0.0))
	peak_l = _load_l(d, "peak") if d.has("peak_l") else Num.L(float(d.get("peak_gross", 0.0)))
	rest_peak_l = _load_l(d, "rest_peak")
	insured = bool(d.get("insured", false))
	grace = float(d.get("grace", 0.0))
	challenge = String(d.get("challenge", ""))
	if not CHALLENGES.has(challenge):
		challenge = ""
	challenge_level = int(d.get("challenge_level", 0))
	challenge_best = (d.get("challenge_best", {}) as Dictionary).duplicate()
	old_busts = int(d.get("old_busts", 0))
	if ver < 4:
		old_busts = maxi(old_busts, bankruptcies)
		# costs and bankruptcy moved into challenges: forgive any debt from the old rules
		debt_l = Num.ZERO
		owed_l = Num.ZERO
		red_t = 0.0
		grace = 0.0
		insured = false
		if concept_chosen and ver >= 3:
			rules_notice = true
	if challenge == "":
		debt_l = Num.ZERO
		owed_l = Num.ZERO
		red_t = 0.0
	effects = d.get("effects", [])
	event = d.get("event", {})
	if not event.is_empty() and not event.has("r_l"):
		event = {}   # an old card priced in plain numbers: drop it, a new one will come
	event_t = float(d.get("event_t", Events.MIN_GAP))
	_dirty = true


# ================================================================= formatting

## Small ordinary numbers (counts, percentages). Money and anything that grows uses Num.fmt.
static func fmt_num(v: float) -> String:
	if is_nan(v):
		return "0"
	if v < 0.0:
		return "-" + Num.fmt(Num.L(-v))
	return Num.fmt(Num.L(v))


## Whole counts: 950, 1,234, 98,765, then 123K and up.
static func fmt_count(n: int) -> String:
	if n >= 100000:
		return Num.fmt(Num.L(float(n)))
	var s := str(absi(n))
	if s.length() > 3:
		s = s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)
	return ("-" if n < 0 else "") + s


static func fmt_mult(v: float) -> String:
	if absf(v - round(v)) < 1e-9 and v < 1e6:
		return "%d" % int(round(v))
	if v < 100.0:
		var t := "%.2f" % v
		while t.ends_with("0"):
			t = t.trim_suffix("0")
		return t.trim_suffix(".")
	return fmt_num(v)


## A multiplier given as a log: ×1.5, ×12.3K, ×1.00e1,234.
static func fmt_mult_l(l: float) -> String:
	if l < 2.0:
		return fmt_mult(Num.V(l))
	return Num.fmt(l)


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


## Seconds to save up a price (log) at an income (log), for display.
static func secs_to_l(cost_l: float, rate_l: float) -> float:
	if Num.is_zero(cost_l):
		return 0.0
	if Num.is_zero(rate_l):
		return INF
	return Num.V(minf(cost_l - rate_l, 300.0))
