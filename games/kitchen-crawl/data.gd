extends RefCounted
## Static game data for Kitchen Crawl: ingredients, recipes, upgrades and daily events.

## Base price of each finished ingredient on a plate.
const ITEM_PRICE := {"bun": 3, "patty": 7, "lettuce": 4, "tomato": 4, "cheese": 5, "fries": 6}

## Items that can go on a plate.
const PLATEABLE := ["bun", "patty", "lettuce", "tomato", "cheese", "fries"]

## Raw -> chopped at the cutting board.
const CHOP := {"lettuce_raw": "lettuce", "tomato_raw": "tomato"}

## Cooking stations: [raw, cooked, burnt].
const COOK := {
	"grill": ["patty_raw", "patty", "patty_burnt"],
	"fryer": ["potato", "fries", "fries_burnt"],
}

const RECIPES := [
	{"name": "Burger", "items": ["bun", "patty"], "needs": []},
	{"name": "Garden Burger", "items": ["bun", "patty", "lettuce"], "needs": []},
	{"name": "Side Salad", "items": ["lettuce"], "needs": []},
	{"name": "Salad", "items": ["lettuce", "tomato"], "needs": ["tomato"]},
	{"name": "Deluxe", "items": ["bun", "patty", "lettuce", "tomato"], "needs": ["tomato"]},
	{"name": "Cheeseburger", "items": ["bun", "patty", "cheese"], "needs": ["cheese"]},
	{"name": "Big Cheese", "items": ["bun", "patty", "cheese", "lettuce"], "needs": ["cheese"]},
	{"name": "Fries", "items": ["fries"], "needs": ["fryer"]},
	{"name": "Combo", "items": ["bun", "patty", "fries"], "needs": ["fryer"]},
	{"name": "Cheesy Fries", "items": ["fries", "cheese"], "needs": ["fryer", "cheese"]},
]

## kind: "unlock" (new ingredients/recipes), "station" (more equipment), "perk" (stat boost).
const UPGRADES := [
	{"id": "tomato", "kind": "unlock", "name": "Tomato Supplier", "desc": "Unlocks tomatoes. New orders: Salad and the Deluxe.", "max": 1},
	{"id": "cheese", "kind": "unlock", "name": "Cheese Supplier", "desc": "Unlocks cheese. New orders: Cheeseburger and Big Cheese.", "max": 1},
	{"id": "fryer", "kind": "unlock", "name": "Deep Fryer", "desc": "A fryer and a sack of potatoes. New orders: Fries and the Combo.", "max": 1},
	{"id": "grill2", "kind": "station", "name": "Second Grill", "desc": "Another grill, so two patties can cook at once.", "max": 1},
	{"id": "board2", "kind": "station", "name": "Second Board", "desc": "Another cutting board.", "max": 1},
	{"id": "plate3", "kind": "station", "name": "More Plates", "desc": "A third plating spot on the island.", "max": 1},
	{"id": "stool", "kind": "station", "name": "Extra Stool", "desc": "+1 seat at the counter. More guests, more money, more chaos.", "max": 2},
	{"id": "clogs", "kind": "perk", "name": "Comfy Clogs", "desc": "Move 20% faster.", "max": 3},
	{"id": "hot_grill", "kind": "perk", "name": "Hotter Burners", "desc": "Grill and fryer cook 25% faster.", "max": 3},
	{"id": "bell", "kind": "perk", "name": "Kitchen Timer", "desc": "Cooked food takes twice as long to burn.", "max": 2},
	{"id": "sharp_knife", "kind": "perk", "name": "Sharp Knife", "desc": "Chop 40% faster.", "max": 2},
	{"id": "breadsticks", "kind": "perk", "name": "Free Breadsticks", "desc": "Customers are 25% more patient.", "max": 3},
	{"id": "smile", "kind": "perk", "name": "Winning Smile", "desc": "+40% tips.", "max": 3},
	{"id": "fancy", "kind": "perk", "name": "Fancy Menu", "desc": "+25% prices, but customers are 10% less patient.", "max": 3},
	{"id": "landlord", "kind": "perk", "name": "Friendly Landlord", "desc": "Rent is 20% cheaper.", "max": 2},
	{"id": "review", "kind": "perk", "name": "Rave Review", "desc": "+1 max reputation, and fully restore it.", "max": 2},
]

const EVENTS := [
	{"id": "normal", "name": "Business as Usual", "desc": "Just a regular day."},
	{"id": "rush", "name": "Lunch Rush", "desc": "Customers arrive 30% faster. Tips +25%."},
	{"id": "heat", "name": "Heatwave", "desc": "Burners run hot: food cooks a bit faster but burns twice as fast."},
	{"id": "picky", "name": "Picky Eaters", "desc": "Customers are 25% less patient, but pay 25% more."},
	{"id": "critic", "name": "Food Critic", "desc": "A critic (gold) visits: 4x pay, but anger them and lose 2 reputation."},
	{"id": "rain", "name": "Rainy Day", "desc": "Fewer customers today. Rent is 20% lower tonight."},
	{"id": "payday", "name": "Payday", "desc": "Everyone's flush: tips are doubled."},
]
const OPENING := {"id": "opening", "name": "Opening Day", "desc": "Grill patties, plate them with buns, serve the counter. Pay rent tonight."}
const GALA := {"id": "gala", "name": "Grand Gala", "desc": "Final night! A rush of guests and a food critic. Make rent to win."}


static func upgrade(id: String) -> Dictionary:
	for u in UPGRADES:
		if u.id == id:
			return u
	return {}


static func recipe(recipe_name: String) -> Dictionary:
	for r in RECIPES:
		if r.name == recipe_name:
			return r
	return {}
