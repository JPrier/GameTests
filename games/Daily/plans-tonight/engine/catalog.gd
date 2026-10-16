class_name PTCatalog
extends RefCounted
## Content for the generator: plan templates, friends, avatars and personality lines.
## Icons are Twemoji code points; the SVGs live in res://icons/.

const T := 60  # minutes per hour, for readability below

## One entry per kind of plan. "in"/"out" are names for the indoor/outdoor version (an empty
## list means that setting never happens). "food" lists possible menus ("" = no real food).
const TEMPLATES := [
	# --- dinners (activity "Dinner"; the menu is what tells them apart)
	{"key": "sushi", "activity": "Dinner", "icon": "1f363", "in": ["Sushi Bar", "Omakase Counter"], "out": [],
		"food": ["Sushi"], "price": [26, 58], "dur": [60, 90, 120], "noise": ["quiet", "lively"], "start": [17 * T + 30, 21 * T], "w": 3},
	{"key": "tacos", "activity": "Dinner", "icon": "1f32e", "in": ["Taco Bar", "Taqueria"], "out": ["Patio Tacos", "Taco Truck Patio"],
		"food": ["Tacos"], "price": [14, 32], "dur": [60, 90, 120], "noise": ["lively", "loud"], "start": [17 * T + 30, 21 * T + 30], "w": 3},
	{"key": "pizza", "activity": "Dinner", "icon": "1f355", "in": ["Pizza Place", "Brick Oven Pizza"], "out": ["Rooftop Pizza"],
		"food": ["Pizza"], "price": [13, 28], "dur": [60, 90], "noise": ["lively", "loud"], "start": [17 * T + 30, 21 * T + 30], "w": 3},
	{"key": "ramen", "activity": "Dinner", "icon": "1f35c", "in": ["Ramen Bar", "Noodle House"], "out": [],
		"food": ["Ramen"], "price": [16, 29], "dur": [60, 90], "noise": ["quiet", "lively"], "start": [17 * T + 30, 22 * T], "w": 3},
	{"key": "burgers", "activity": "Dinner", "icon": "1f354", "in": ["Burger Joint", "All-Night Diner"], "out": ["Burger Patio"],
		"food": ["Burgers"], "price": [13, 26], "dur": [60, 90], "noise": ["lively", "loud"], "start": [17 * T + 30, 22 * T], "w": 3},
	{"key": "curry", "activity": "Dinner", "icon": "1f35b", "in": ["Curry House", "Thai Kitchen"], "out": [],
		"food": ["Curry"], "price": [17, 34], "dur": [60, 90, 120], "noise": ["quiet", "lively"], "start": [17 * T + 30, 21 * T], "w": 3},
	{"key": "bbq", "activity": "Dinner", "icon": "1f356", "in": ["BBQ Smokehouse"], "out": ["BBQ Yard"],
		"food": ["BBQ"], "price": [22, 41], "dur": [90, 120], "noise": ["lively", "loud"], "start": [17 * T + 30, 20 * T + 30], "w": 3},
	{"key": "dumplings", "activity": "Dinner", "icon": "1f95f", "in": ["Dumpling House", "Dim Sum Hall"], "out": [],
		"food": ["Dumplings"], "price": [14, 31], "dur": [60, 90], "noise": ["lively", "loud"], "start": [17 * T + 30, 21 * T], "w": 3},
	{"key": "pasta", "activity": "Dinner", "icon": "1f35d", "in": ["Trattoria", "Pasta Bar"], "out": ["Garden Trattoria"],
		"food": ["Pasta"], "price": [22, 46], "dur": [90, 120], "noise": ["quiet", "lively"], "start": [17 * T + 30, 21 * T], "w": 3},
	# --- things to do
	{"key": "bowling", "activity": "Bowling", "icon": "1f3b3", "in": ["Bowling Alley", "Retro Lanes"], "out": [],
		"food": ["", "Wings"], "price": [18, 38], "dur": [90, 120], "noise": ["loud", "lively"], "start": [18 * T, 22 * T], "w": 4},
	{"key": "movie", "activity": "Movie", "icon": "1f3ac", "in": ["Indie Cinema", "Late Show"], "out": ["Outdoor Movie"],
		"food": [""], "price": [13, 24], "dur": [120, 150], "noise": ["quiet"], "start": [18 * T, 22 * T], "w": 4},
	{"key": "karaoke", "activity": "Karaoke", "icon": "1f3a4", "in": ["Karaoke Box", "Karaoke Bar"], "out": [],
		"food": ["", "Pub food"], "price": [15, 36], "dur": [90, 120, 150], "noise": ["loud"], "start": [19 * T, 22 * T + 30], "w": 4},
	{"key": "trivia", "activity": "Trivia night", "icon": "1f9e0", "in": ["Pub Trivia", "Trivia Night"], "out": [],
		"food": ["Pub food", ""], "price": [9, 22], "dur": [90, 120], "noise": ["lively"], "start": [18 * T + 30, 21 * T], "w": 4},
	{"key": "comedy", "activity": "Comedy show", "icon": "1f3ad", "in": ["Comedy Club", "Improv Show"], "out": [],
		"food": [""], "price": [18, 39], "dur": [90, 120], "noise": ["lively", "loud"], "start": [19 * T, 22 * T], "w": 4},
	{"key": "escape", "activity": "Escape room", "icon": "1f510", "in": ["Escape Room", "Puzzle Rooms"], "out": [],
		"food": [""], "price": [27, 44], "dur": [60, 90], "noise": ["lively"], "start": [17 * T + 30, 21 * T + 30], "w": 4},
	{"key": "minigolf", "activity": "Mini golf", "icon": "26f3", "in": ["Glow Mini Golf"], "out": ["Mini Golf", "Putt Park"],
		"food": [""], "price": [12, 24], "dur": [60, 90], "noise": ["lively"], "start": [17 * T + 30, 21 * T], "w": 4},
	{"key": "cocktails", "activity": "Bar", "icon": "1f378", "in": ["Cocktail Lounge", "Speakeasy"], "out": ["Rooftop Bar"],
		"food": [""], "price": [19, 42], "dur": [90, 120, 150, 180], "noise": ["quiet", "lively", "loud"], "start": [18 * T, 22 * T + 30], "w": 4},
	{"key": "wine", "activity": "Wine bar", "icon": "1f377", "in": ["Wine Bar"], "out": ["Wine Garden"],
		"food": ["", "Small plates"], "price": [21, 44], "dur": [90, 120, 150], "noise": ["quiet"], "start": [18 * T, 21 * T + 30], "w": 3},
	{"key": "beer", "activity": "Brewery", "icon": "1f37a", "in": ["Brewery Taproom"], "out": ["Beer Garden"],
		"food": ["Pub food", ""], "price": [12, 26], "dur": [90, 120, 150], "noise": ["loud", "lively"], "start": [17 * T + 30, 21 * T + 30], "w": 3},
	{"key": "boardgames", "activity": "Board games", "icon": "1f3b2", "in": ["Board Game Café"], "out": [],
		"food": ["", "Sandwiches"], "price": [8, 19], "dur": [120, 150, 180], "noise": ["quiet", "lively"], "start": [17 * T + 30, 21 * T], "w": 3},
	{"key": "music", "activity": "Live music", "icon": "1f3b8", "in": ["Live Music Hall", "Jazz Club"], "out": ["Park Concert"],
		"food": [""], "price": [14, 42], "dur": [120, 150], "noise": ["loud", "lively"], "start": [19 * T, 22 * T], "w": 3},
	{"key": "arcade", "activity": "Arcade", "icon": "1f579", "in": ["Arcade Bar", "Retro Arcade"], "out": [],
		"food": ["", "Pizza"], "price": [11, 27], "dur": [90, 120], "noise": ["loud"], "start": [18 * T, 22 * T + 30], "w": 3},
	{"key": "axe", "activity": "Axe throwing", "icon": "1fa93", "in": ["Axe Throwing"], "out": [],
		"food": [""], "price": [22, 39], "dur": [60, 90], "noise": ["loud"], "start": [18 * T, 21 * T], "w": 3},
	{"key": "climbing", "activity": "Climbing", "icon": "1f9d7", "in": ["Climbing Gym", "Bouldering Gym"], "out": [],
		"food": [""], "price": [18, 29], "dur": [90, 120], "noise": ["lively"], "start": [17 * T + 30, 20 * T + 30], "w": 3},
	{"key": "market", "activity": "Night market", "icon": "1f3ee", "in": [], "out": ["Night Market", "Street Fair"],
		"food": ["Street food"], "price": [11, 26], "dur": [90, 120, 150], "noise": ["loud", "lively"], "start": [18 * T, 21 * T], "w": 3},
	{"key": "picnic", "activity": "Picnic", "icon": "1f9fa", "in": [], "out": ["Park Picnic", "Sunset Picnic"],
		"food": ["Sandwiches"], "price": [9, 19], "dur": [90, 120, 150], "noise": ["quiet"], "start": [17 * T, 19 * T + 30], "w": 3},
	{"key": "skating", "activity": "Ice skating", "icon": "26f8", "in": ["Indoor Rink"], "out": ["Ice Skating"],
		"food": [""], "price": [11, 21], "dur": [60, 90], "noise": ["lively"], "start": [17 * T + 30, 21 * T], "w": 3},
	{"key": "paint", "activity": "Paint & sip", "icon": "1f3a8", "in": ["Paint & Sip"], "out": [],
		"food": ["", "Small plates"], "price": [31, 48], "dur": [120, 150], "noise": ["quiet", "lively"], "start": [18 * T, 20 * T + 30], "w": 3},
]

## Menu icons for food served at a non-dinner plan.
const FOOD_ICON := {
	"Sushi": "1f363", "Tacos": "1f32e", "Pizza": "1f355", "Ramen": "1f35c", "Burgers": "1f354",
	"Curry": "1f35b", "BBQ": "1f356", "Dumplings": "1f95f", "Pasta": "1f35d", "Wings": "1f357",
	"Pub food": "1f37d", "Small plates": "1f37d", "Sandwiches": "1f37d", "Street food": "1f37d",
}

const TRAVEL := [7, 8, 9, 12, 13, 14, 17, 18, 19, 22, 23, 24, 27, 28, 32, 34, 38]

const NAMES := [
	"Maya", "Chris", "Jordan", "Priya", "Sam", "Alex", "Jamie", "Taylor", "Morgan", "Ben", "Jules",
	"Riley", "Noah", "Zoe", "Omar", "Lena", "Theo", "Ava", "Dev", "Mia", "Kai", "Rosa", "Leo",
	"Nina", "Eli", "Hana", "Marcus", "Ivy", "Felix", "Tess", "Ravi", "Sofia", "Diego", "Grace",
	"Owen", "Aisha", "Wes", "Lucy", "Mateo", "June",
]

const AVATARS := [
	"1f600", "1f60e", "1f913", "1f634", "1f973", "1f920", "1f60f", "1f643", "1f9d0", "1f62c",
	"1f914", "1f607", "1f929", "1f624", "1f971", "1f60c", "1fae0", "1f917",
]

## Avatar ring colours (readable on the dark card).
const COLORS := ["ff7a59", "ffc145", "5ad1a0", "4fb3ff", "b18cff", "ff6fa8", "7ee081", "ffa35c"]

## Personality lines, by the friend's first rule. They never state a number or a rule,
## so they can't change what the rules mean.
const FLAVOR := {
	"max_price": ["Is “saving up for something.” Won't say what.", "Checked their banking app and went quiet.",
		"Splits every bill to the cent.", "Just paid rent. Emotionally fragile."],
	"min_start": ["Has been “leaving work now” for an hour.", "Is stuck on a call that should've been an email.",
		"Running late. Has always been running late."],
	"max_start": ["Turns into a pumpkin if things start too late.", "Eats dinner at grandparent hours and is proud of it."],
	"max_end": ["Has an early spin class they will definitely skip.", "Promised the babysitter a reasonable night.",
		"Has to walk the dog. The dog is very punctual."],
	"min_end": ["Insists the night is young.", "Took tomorrow off and wants it to count.", "Has never once been first to leave."],
	"max_travel": ["Considers crossing the river “a whole trip.”", "Insists a long walk counts as hiking.",
		"Their bus pass expired and they're in denial."],
	"setting": {"outdoor": ["Has been inside all week and is getting weird about it.", "Bought a new jacket and needs people to see it."],
		"indoor": ["Checked the forecast twice. Trusts none of it.", "Just got a haircut. Wind is the enemy."]},
	"wants_food": ["Skipped lunch and has opinions about it.", "Says “snacks are not dinner” once a week.", "Hangry. Approach with breadsticks."],
	"no_food_type": ["Had a bad experience once. Will not elaborate.", "Ate that every day last week."],
	"no_activity": ["Still recovering from last time.", "Was banned from the last one. Allegedly.", "Did it at a work offsite. Never again."],
	"not_loud": ["Left the last concert with ringing ears.", "Has big gossip and needs to be heard."],
	"not_quiet": ["Refuses to have a “chill night.”", "Talks loud. Needs a room that can take it."],
	"max_duration": ["Social battery: low.", "Has a big presentation tomorrow."],
	"min_duration": ["Got a babysitter and intends to use every minute.", "Didn't get dressed up for a quick one."],
	"multi": ["Says they're “down for anything,” then vetoes everything.", "Sent a voice memo of conditions.",
		"Has a list. It's laminated."],
}

## Themes reuse the same engine; they only change copy and which plans show up.
const THEMES := {
	"night": {"title": "Tonight's plans", "line": "Pick the one plan that works for everyone."},
	"birthday": {"title": "Birthday plans", "line": "Pick the one plan that works for everyone, birthday person included."},
}

const BIRTHDAY_FLAVOR := "It's their birthday, so their rules count double. (They don't.)"
