extends RefCounted
## Fictional guests. Descriptions are flavour only: they never name other guests and never
## matter for the puzzle. Names are short so they fit on a seat card.

const NAMES := [
	"Maya", "Chris", "Alex", "Jordan", "Sam", "Taylor", "Morgan", "Priya", "Lee", "Kevin",
	"Rosa", "Dev", "Nina", "Omar", "Hazel", "Felix", "Ivy", "Theo", "June", "Ravi",
	"Lucia", "Marco", "Ada", "Otis", "Wren", "Kofi", "Greta", "Hugo", "Lena", "Jasper",
	"Mabel", "Rhys", "Tess", "Bruno", "Cleo", "Dante", "Elsie", "Finn", "Gus", "Hana",
	"Iris", "Jules", "Kit", "Luz", "Milo", "Noor", "Oscar", "Pip", "Quinn", "Ruth",
	"Saul", "Tara", "Uma", "Vic", "Walt", "Xena", "Yara", "Zeke", "Bea", "Cyrus",
	"Dot", "Eli", "Fern", "Gabe", "Ines", "Joan", "Kai", "Lou", "Mona", "Ned",
]

const DESCS := [
	"College roommate", "Bride's boss", "Groom's boss", "Will request ABBA",
	"Brought a plus-one nobody met", "Cried at the rehearsal", "Knows every dance move",
	"Wants the speech mic", "Gluten-free, loudly", "Flew in from Lisbon",
	"Still owes the groom $20", "Ex-bandmate", "Officiant (ordained online)",
	"Took 400 photos already", "Allergic to small talk", "Asks when you're getting married",
	"Has opinions on the cake", "Groom's childhood neighbour", "Bride's tennis partner",
	"Arrived two hours early", "Here for the open bar", "Will start the conga line",
	"Brought a casserole", "Wearing white, somehow", "Knows the DJ personally",
	"Fell asleep at the ceremony", "Rehearsed a toast for weeks", "Collects wedding favours",
	"Destroys the buffet", "Never misses a slow dance", "Hates the chicken dance",
	"Groomsman, emotionally", "Bridesmaid, loudly", "Lost in the parking lot",
	"Once dated the caterer", "Has a fascinator", "Chases the bouquet",
	"Talks about crypto", "Brought their own hot sauce", "Booked the wrong hotel",
	"Great-aunt, sharp as a tack", "Teaches salsa on weekends", "Took the long way here",
	"Sends memes to the family chat", "Mysteriously knows everyone", "Bride's first boss",
	"Plays the bagpipes", "Wants to talk about their podcast", "Signed the guestbook twice",
	"Seeks the photo booth", "Ironed the groom's shirt", "Bride's oldest friend",
	"Won't stop doing magic tricks", "Learned the vows by heart", "Designed the invitations",
	"Is definitely not crying", "Forgot the gift at home", "Here for the cake only",
]

# seat-card colours (pastels that work on the dark background)
const COLORS := [
	Color("f6a5a5"), Color("f7c58a"), Color("f2e18b"), Color("a8dc9b"), Color("8fd6c8"),
	Color("9cc7f2"), Color("b8a8f0"), Color("e3a6e0"), Color("f2b8cf"), Color("c9d48a"),
]
