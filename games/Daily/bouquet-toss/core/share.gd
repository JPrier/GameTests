extends RefCounted
## Spoiler-free share text: how many tries each throw took and how they ended, never where
## they went.
##
##   Bouquet Toss #12 💐
##   🎯 8 tries for 5 throws · Good
##   ✨ 91%
##   1️⃣ 💐
##   2️⃣ 💥 💐
##   3️⃣ ⬇️ 💨 💐
##   4️⃣ 💐
##   5️⃣ 🪑 💐
##   https://jprier.github.io/GameTests/bouquet-toss/

const Scoring = preload("res://core/scoring.gd")

const OUTCOME_EMOJI := {
	"catch": "💐", "splat": "💥", "fumble": "💨", "floor": "⬇️", "rest": "🪑", "out": "↗️", "timeout": "🌀",
}


static func emoji_for(outcome: String) -> String:
	return OUTCOME_EMOJI.get(outcome, "▫️")


const KEYCAPS := ["1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣"]


## One throw's tries as emoji, shortened when there are lots of them.
static func marks(outcomes: Array) -> String:
	var m: Array = []
	for o in outcomes:
		m.append(emoji_for(String(o)))
	if m.size() > 8:
		m = m.slice(0, 3) + ["…%d…" % (m.size() - 6)] + m.slice(m.size() - 3)
	return " ".join(m)


## result: {throws (total tries), accuracy, holes: [[outcome, ...] per throw]}
static func text(number: int, result: Dictionary, url: String) -> String:
	var t := int(result.get("throws", 0))
	var holes: Array = result.get("holes", [])
	var lines: Array = []
	lines.append("Bouquet Toss #%d 💐" % number)
	lines.append("🎯 %d %s for %d throws · %s" % [t, "try" if t == 1 else "tries", holes.size(), Scoring.rating_total(t, holes.size())])
	lines.append("✨ %d%%" % int(result.get("accuracy", 0)))
	for i in holes.size():
		lines.append("%s %s" % [KEYCAPS[i % KEYCAPS.size()], marks(holes[i])])
	lines.append(url)
	return "\n".join(lines)
