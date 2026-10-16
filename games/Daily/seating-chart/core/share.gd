extends RefCounted
## Spoiler-free share text: no names, no positions that give anything away.
##
##   Seating Chart #12 · Tricky 💒
##   ⏱️ 3:42
##   🟩🟩🟩🟨🟩
##   🟩🟩🟩🟩🟩
##   ✨ Flawless
##   https://jprier.github.io/GameTests/seating-chart/
##
## One row per table, one square per seat: 🟩 you seated them, 🟨 a hint did, ⬜ revealed.

const D = preload("res://core/difficulty.gd")


static func clock(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


## result: {seconds, mistakes, hints, hinted: Array of guests, revealed: bool}
static func summary_line(result: Dictionary) -> String:
	var mistakes := int(result.get("mistakes", 0))
	var hints := int(result.get("hints", 0))
	if bool(result.get("revealed", false)):
		return "🏳️ Answer revealed"
	if mistakes == 0 and hints == 0:
		return "✨ Flawless"
	var parts: Array = []
	if hints > 0:
		parts.append("💡 %d hint%s" % [hints, "" if hints == 1 else "s"])
	if mistakes > 0:
		parts.append("❌ %d wrong check%s" % [mistakes, "" if mistakes == 1 else "s"])
	return " · ".join(parts)


static func text(m, seat_of: PackedInt32Array, result: Dictionary, url: String) -> String:
	var lines: Array = []
	lines.append("Seating Chart #%d · %s 💒" % [m.number, D.tier_name(m.tier)])
	lines.append("⏱️ " + clock(int(result.get("seconds", 0))))
	var hinted: Array = result.get("hinted", [])
	var revealed := bool(result.get("revealed", false))
	var at: PackedInt32Array = m.guest_at_from(seat_of)
	for t in m.tables:
		var row := ""
		for p in m.seats:
			var g: int = at[m.seat(t, p)]
			if revealed:
				row += "⬜"
			elif hinted.has(g):
				row += "🟨"
			else:
				row += "🟩"
		lines.append(row)
	lines.append(summary_line(result))
	lines.append(url)
	return "\n".join(lines)
