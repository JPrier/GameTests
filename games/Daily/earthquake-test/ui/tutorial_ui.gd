extends RefCounted
## The "How Earthquake Test works" card (opened from the ? button and on first launch).
## Takes the main scene (`m`) and draws on it.

const Sim = preload("res://quake_sim.gd")

const NOTE := "While you draw, a magnifier above your finger shows where the line will land, and Lock (on by default) snaps it onto nearby joints. Pinch or use + and - to zoom."


static func rows(m) -> Array:
	return [
		["anchor", "Everyone gets the same site: the same grey anchors and the same budget."],
		["beam", "Pick a max piece length (1, 2 or 3 m), then drag a line from an anchor or joint to any dot, at any angle. It's split into equal pieces no longer than that. Only the Erase tool removes pieces."],
		["steel", "Wood is cheap and light. Steel usually costs 3× but is ~5× stronger. Long pieces buckle more easily when squeezed."],
		["quake", "Every day brings its own kind of quake, ground and footing (tap the seismograph for today's briefing). Start the quake: that exact seismogram hits your build and overloaded beams snap."],
		["height", "Score = height still standing (attached to an anchor) when the shaking stops."],
		["tries", "%d tries a day — best counts. Share your result; the link opens the same quake." % m.MAX_TRIES],
	]


static func content_h(m, w: float) -> float:
	var icon := GTUI.dp(20)
	var h := 0.0
	for row in rows(m):
		h = GTUI.paragraph(m, 0, h, w - icon - GTUI.dp(GTUI.SP_M), row[1], GTUI.FS_BODY, m.C_INK, false, false) + GTUI.dp(GTUI.SP_S)
	return GTUI.paragraph(m, 0, h + GTUI.dp(GTUI.SP_XS), w, NOTE, GTUI.FS_LABEL, m.C_MUTED, false, false)


static func card(m) -> Rect2:
	var vs: Vector2 = m.get_viewport_rect().size
	var w := minf(GTUI.dp(540), vs.x - GTUI.dp(GTUI.SP_L) * 2) - GTUI.dp(GTUI.SP_XL) * 2
	return GTUI.modal_rect(m, 540, GTUI.modal_height(content_h(m, w) + GTUI.dp(GTUI.SP_S)))


static func draw(m) -> void:
	var c := GTUI.modal(m, card(m), "How Earthquake Test works", "tut_x")
	var x := c.position.x
	var tw := c.size.x
	var y := c.position.y
	var bottom := c.end.y - GTUI.target() - GTUI.dp(GTUI.SP_M)
	var icon := GTUI.dp(20)
	var k := icon / 30.0   # icon art below was drawn in a 30 px box
	for row in rows(m):
		var ir := Rect2(x, y + (GTUI.line_height(GTUI.FS_BODY) - icon) / 2.0, icon, icon)
		var p := ir.position
		match row[0]:
			"anchor":
				m.draw_colored_polygon(PackedVector2Array([p + Vector2(3, 26) * k, p + Vector2(27, 26) * k, p + Vector2(15, 4) * k]), m.C_ANCHOR)
			"beam":
				m._draw_beam(p + Vector2(3, 26) * k, p + Vector2(27, 4) * k, Sim.Mat.WOOD)
			"steel":
				m._draw_beam(p + Vector2(3, 26) * k, p + Vector2(27, 4) * k, Sim.Mat.STEEL)
			"quake":
				var pts := PackedVector2Array()
				for j in 9:
					pts.append(p + Vector2(j * 3.4, 15 + (12 if j % 2 == 0 else -12) * (1.0 - absf(j - 4) / 5.0)) * k)
				m.draw_polyline(pts, m.C_ACCENT, 2.0)
			"height":
				m._dashed(p + Vector2(0, 8) * k, p + Vector2(30, 8) * k, m.C_OK)
				m.draw_line(p + Vector2(15, 28) * k, p + Vector2(15, 10) * k, m.C_OK, 2.5)
			"tries":
				GTUI.text_in(m, ir, str(m.MAX_TRIES), GTUI.FS_BODY, m.C_ACCENT, 0, true)
		y = GTUI.paragraph(m, x + icon + GTUI.dp(GTUI.SP_M), y, tw - icon - GTUI.dp(GTUI.SP_M), row[1], GTUI.FS_BODY, m.C_INK) + GTUI.dp(GTUI.SP_S)
	if GTUI.paragraph(m, x, y, tw, NOTE, GTUI.FS_LABEL, m.C_MUTED, false, false) < bottom:
		GTUI.paragraph(m, x, y + GTUI.dp(GTUI.SP_XS), tw, NOTE, GTUI.FS_LABEL, m.C_MUTED)
