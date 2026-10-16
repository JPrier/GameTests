extends RefCounted
## Spoiler-free share text: how many throws, how they ended, never where they went.
##
##   Bouquet Toss #12 💐
##   🎯 2 throws · Great
##   ✨ 94%
##   💥 💐
##   https://jprier.github.io/GameTests/bouquet-toss/

const Scoring = preload("res://core/scoring.gd")

const OUTCOME_EMOJI := {
	"catch": "💐", "splat": "💥", "fumble": "💨", "floor": "⬇️", "rest": "🪑", "out": "↗️", "timeout": "🌀",
}


static func emoji_for(outcome: String) -> String:
	return OUTCOME_EMOJI.get(outcome, "▫️")


## result: {throws, accuracy, outcomes: Array of outcome strings}
static func text(number: int, result: Dictionary, url: String) -> String:
	var t := int(result.get("throws", 0))
	var lines: Array = []
	lines.append("Bouquet Toss #%d 💐" % number)
	lines.append("🎯 %d throw%s · %s" % [t, "" if t == 1 else "s", Scoring.rating(t)])
	lines.append("✨ %d%%" % int(result.get("accuracy", 0)))
	var outs: Array = result.get("outcomes", [])
	var marks: Array = []
	for o in outs:
		marks.append(emoji_for(String(o)))
	if marks.size() > 12:
		marks = marks.slice(0, 5) + ["…%d…" % (marks.size() - 10)] + marks.slice(marks.size() - 5)
	lines.append(" ".join(marks))
	lines.append(url)
	return "\n".join(lines)
