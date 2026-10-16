extends RefCounted
## Spoiler-free share text: no drink names, values or candidates, only the feedback shapes.
##
##   Mystery Drink #12 🍸
##   🟥🟩🟥🟥🟩⬇️
##   🟨🟩🟨🟩🟩🟩
##   🟩🟩🟩🟩🟩🟩
##   3/6 · 💡 1 hint
##   https://jprier.github.io/GameTests/mystery-drink/

const Cmp = preload("res://core/compare.gd")
const DB = preload("res://core/db.gd")


static func text(number: int, game, url: String) -> String:
	var lines: Array = []
	lines.append("Mystery Drink #%d 🍸" % number)
	for i in game.guesses.size():
		lines.append(Cmp.emoji_row(game.feedback(i)))
	var score: String = game.result_label()
	if game.hints_used > 0:
		score += " · 💡 %d hint%s" % [game.hints_used, "" if game.hints_used == 1 else "s"]
	lines.append(score)
	lines.append(url)
	return "\n".join(lines)
