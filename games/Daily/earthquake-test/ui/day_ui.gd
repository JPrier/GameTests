extends RefCounted
## Drawing for the day's conditions, kept out of main.gd: the seismograph panel (quake caption,
## ground + footing line, today's condition, velocity + vertical traces), the briefing card,
## the Heavy Top weight and the dev menu's generator lines. Every function takes the main
## scene (`m`) and draws on it; game state stays in main.gd.

const Arch = preload("res://challenge/archetypes.gd")
const Terrain = preload("res://site/terrain.gd")

const SEIS_SPAN := 30.0               # s shown across the seismograph (longer quakes stretch it)
const SEIS_FULL_PGV := 1.6            # m/s of ground velocity that fills the seismograph (sqrt scale)


static func price(v: float) -> String:
	return ("%d" % int(round(v))) if is_equal_approx(v, round(v)) else ("%.2f" % v).trim_suffix("0")


# ------------------------------------------------------------------ seismograph

## "M6.8 · 17s · LONG ROLLER" (legacy days keep their old caption).
static func quake_caption(m) -> String:
	if not m.can_brief():
		return "TODAY'S QUAKE  " + m.quake.describe()
	return "M%.1f · %ds · %s" % [m.quake.magnitude, int(round(m.quake.duration)), m.challenge.quake_name().to_upper()]


static func conditions_line(m) -> String:
	if not m.can_brief():
		return "CLASSIC QUAKE · %d ANCHORS" % m.anchors.size()
	var c = m.challenge
	if c.terrain_archetype != "":
		return "%s · %s" % [Arch.soil_name(c.soil).to_upper(), c.terrain_name().to_upper()]
	return "%s · %s" % [Arch.soil_name(c.soil).to_upper(), Arch.site_name(c.site_archetype).to_upper()]


static func modifier_caption(m) -> String:
	if m.challenge == null or m.challenge.modifier == "":
		return ""
	return Arch.modifier_name(m.challenge.modifier).to_upper()


static func seismograph(m) -> void:
	var r: Rect2 = m.seis_rect
	GTUI.panel(m, r)
	var pad := GTUI.dp(GTUI.SP_M)
	var cap_h := GTUI.line_height(GTUI.FS_CAPTION)
	var inner_w := r.size.x - pad * 2
	var top := Rect2(r.position.x + pad, r.position.y + GTUI.dp(GTUI.SP_XS), inner_w, cap_h)
	var bottom := Rect2(top.position.x, r.end.y - GTUI.dp(GTUI.SP_XS) - cap_h, inner_w, cap_h)
	var running: bool = m.phase == m.Phase.RUN and m.sim != null
	var info_w := cap_h if (m.phase == m.Phase.BUILD and m.can_brief()) else 0.0
	var title_w := inner_w * 0.62 if running else inner_w - info_w - (GTUI.dp(GTUI.SP_S) if info_w > 0.0 else 0.0)
	GTUI.text_in(m, Rect2(top.position, Vector2(title_w, cap_h)), quake_caption(m), GTUI.FS_CAPTION, m.C_MUTED, -1, true)
	if info_w > 0.0:   # tap the panel for the briefing
		GTUI.glyph(m, "help", Vector2(top.end.x - info_w / 2.0, top.get_center().y), info_w * 0.8, Color(m.C_MUTED, 0.9))
	# today's conditions: ground + footing on the left, the modifier (if any) on the right
	var mod := modifier_caption(m)
	var mod_w := GTUI.text_width(mod, GTUI.FS_CAPTION, true) if mod != "" else 0.0
	var left_w := inner_w - (mod_w + GTUI.dp(GTUI.SP_M) if mod != "" else 0.0)
	GTUI.text_in(m, Rect2(bottom.position, Vector2(left_w, cap_h)), conditions_line(m), GTUI.FS_CAPTION, m.C_MUTED, -1)
	if mod != "":
		GTUI.text_in(m, Rect2(bottom.end.x - mod_w, bottom.position.y, mod_w, cap_h), mod, GTUI.FS_CAPTION, m.C_ACCENT, 1, true)
	var tr := Rect2(top.position.x, top.end.y, inner_w, bottom.position.y - top.end.y)
	var mid := tr.get_center().y
	m.draw_line(Vector2(tr.position.x, mid), Vector2(tr.end.x, mid), Color(1, 1, 1, 0.08), 1.0)
	var quake = m.quake
	var tr_data: PackedFloat32Array = quake.trace
	var n := tr_data.size()
	if n < 2:
		return
	# v2 days share one time scale and one amplitude scale, so a short sharp quake looks short
	# and sharp next to a long rolling one; legacy days keep their stretched trace
	var span: float = maxf(SEIS_SPAN, quake.duration) if m.can_brief() else float(quake.duration)
	var amp: float = clampf(sqrt(quake.pgv / SEIS_FULL_PGV), 0.35, 1.0) if m.can_brief() else 1.0
	var n_span := int(n * span / quake.duration)
	var cols := int(tr.size.x / 2.0)
	var head_frac := -1.0
	if running:
		head_frac = clampf(m.sim.quake_time() / span, 0.0, 1.0)
	elif m.phase == m.Phase.RESULT or m.phase == m.Phase.FINAL:
		head_frac = 1.0
	# vertical shaking first (blue, behind), then horizontal on top
	var tv: PackedFloat32Array = quake.trace_v
	for pass_ in 2:
		var data: PackedFloat32Array = tv if pass_ == 0 else tr_data
		if data.size() != n:
			continue
		for c in cols:
			var i0 := int(float(c) / cols * n_span)
			if i0 >= n:
				break
			var i1 := maxi(i0 + 1, int(float(c + 1) / cols * n_span))
			var lo := 0.0
			var hi := 0.0
			for i in range(i0, mini(i1, n)):
				lo = minf(lo, data[i])
				hi = maxf(hi, data[i])
			lo = maxf(lo * amp, -1.0)
			hi = minf(hi * amp, 1.0)
			var x := tr.position.x + c * 2.0 + 1.0
			var frac := float(c) / cols
			var col: Color
			if pass_ == 0:
				col = Color(m.C_STEEL, 0.75 if head_frac >= 0.0 and frac <= head_frac else 0.4)
			else:
				col = Color(m.C_ACCENT, 0.9) if head_frac >= 0.0 and frac <= head_frac else Color(m.C_MUTED, 0.55)
			m.draw_line(Vector2(x, mid - hi * tr.size.y * 0.5), Vector2(x, mid - lo * tr.size.y * 0.5 + 1), col, 1.6 if pass_ == 1 else 1.2)
	if running:
		var qt: float = m.sim.quake_time()
		var hx := tr.position.x + head_frac * tr.size.x
		m.draw_line(Vector2(hx, tr.position.y), Vector2(hx, tr.end.y), m.C_INK, 2.0)
		var status := "settling…" if qt < 0.0 else ("%.1fs" % minf(qt, quake.duration) if qt < quake.duration else "aftershock check…")
		GTUI.text_in(m, Rect2(top.position.x + inner_w * 0.64, top.position.y, inner_w * 0.36, cap_h), status, GTUI.FS_CAPTION, m.C_INK, 1, true)


# ------------------------------------------------------------------ briefing card

## Rows: [text, size, colour, bold, gap_before].
static func brief_rows(m) -> Array:
	var c = m.challenge
	var rows: Array = []
	rows.append(["M%.1f · %d sec" % [m.quake.magnitude, int(round(m.quake.duration))], GTUI.FS_TITLE, m.C_INK, true, 0.0])
	rows.append([c.quake_name().to_upper(), GTUI.FS_BODY, m.C_ACCENT, true, GTUI.dp(GTUI.SP_S)])
	rows.append([String(Arch.QUAKE_INFO[c.quake_archetype].tip), GTUI.FS_LABEL, m.C_MUTED, false, 0.0])
	rows.append([Arch.soil_name(c.soil).to_upper(), GTUI.FS_BODY, m.C_INK, true, GTUI.dp(GTUI.SP_M)])
	rows.append([String(Arch.SOIL_INFO[c.soil].tip), GTUI.FS_LABEL, m.C_MUTED, false, 0.0])
	if c.terrain_archetype != "":
		rows.append([c.terrain_name().to_upper(), GTUI.FS_BODY, m.C_INK, true, GTUI.dp(GTUI.SP_M)])
		rows.append([String(Terrain.TERRAIN_INFO[c.terrain_archetype].tip), GTUI.FS_LABEL, m.C_MUTED, false, 0.0])
	rows.append([Arch.site_name(c.site_archetype).to_upper(), GTUI.FS_BODY, m.C_INK, true, GTUI.dp(GTUI.SP_M)])
	rows.append(["%d anchors. Budget $%d · wood $%s/m · steel $%s/m" % [m.anchors.size(), m.budget, price(m.mat_cost(0)), price(m.mat_cost(1))],
		GTUI.FS_LABEL, m.C_MUTED, false, 0.0])
	if c.modifier != "":
		rows.append(["TODAY'S CONDITION", GTUI.FS_CAPTION, m.C_MUTED, true, GTUI.dp(GTUI.SP_L)])
		rows.append([Arch.modifier_name(c.modifier).to_upper(), GTUI.FS_BODY, m.C_ACCENT, true, 0.0])
		rows.append([c.modifier_text(), GTUI.FS_LABEL, m.C_INK, false, 0.0])
	return rows


static func brief_card(m) -> Rect2:
	var vs: Vector2 = m.get_viewport_rect().size
	var w := minf(GTUI.dp(440), vs.x - GTUI.dp(GTUI.SP_L) * 2) - GTUI.dp(GTUI.SP_XL) * 2
	var h := 0.0
	for row in brief_rows(m):
		h = GTUI.paragraph(m, 0, h + float(row[4]), w, row[0], row[1], row[2], row[3], false)
	return GTUI.modal_rect(m, 440, GTUI.modal_height(h + GTUI.dp(GTUI.SP_S)))


static func draw_brief(m) -> void:
	var c := GTUI.modal(m, brief_card(m), "Earthquake #%d" % m.quake_no, "brief_x")
	var y := c.position.y
	for row in brief_rows(m):
		y = GTUI.paragraph(m, c.position.x, y + float(row[4]), c.size.x, row[0], row[1], row[2], row[3])


# ------------------------------------------------------------------ board art

## A kettlebell-style weight sitting on joint s (screen position), labelled with its kg.
static func draw_weight(m, s: Vector2) -> void:
	var w := maxf(22.0, m.ppm * 0.8)
	var h := w * 0.8
	var body := PackedVector2Array([s + Vector2(-w * 0.5, -h * 0.15), s + Vector2(w * 0.5, -h * 0.15), s + Vector2(w * 0.36, -h * 1.05), s + Vector2(-w * 0.36, -h * 1.05)])
	m.draw_colored_polygon(body, Color("4a423c"))
	m.draw_polyline(body + PackedVector2Array([body[0]]), Color(m.C_ACCENT, 0.9), 2.0)
	m.draw_arc(s + Vector2(0, -h * 1.05), w * 0.2, PI, TAU, 12, Color(m.C_ACCENT, 0.9), 3.0)
	GTUI.text_in(m, Rect2(s.x - w * 0.5, s.y - h * 1.0, w, h * 0.8), "%d" % int(m.challenge.top_mass()), GTUI.FS_CAPTION, m.C_INK, 0, true, 9)


# ------------------------------------------------------------------ dev

## Generator debug lines for the dev menu.
static func dev_info(m) -> Array:
	var c = m.challenge
	var out := ["#%d (%s) · generator v%d" % [m.quake_no, m.date, c.version if c else 0]]
	if c == null or c.is_legacy():
		out.append("legacy day: v1 site + quake")
		out.append("")
		return out
	out.append("%s / %s / %s%s · cand %d" % [c.quake_archetype, c.site_archetype, c.soil, (" / " + c.modifier) if c.modifier != "" else "", c.candidate])
	out.append("score %.2f · novelty %.2f · diff %.2f · rej %d" % [c.score, c.novelty, float(c.metrics.get("difficulty", 0.0)), c.rejected])
	return out


const DEV_INFO_LINES := 3


static func dev_modal_rect(m) -> Rect2:
	return GTUI.modal_rect(m, 420, GTUI.modal_height(GTUI.line_height(GTUI.FS_LABEL) * DEV_INFO_LINES + GTUI.dp(GTUI.SP_L) + GTUI.target() * 4 + GTUI.dp(GTUI.SP_S) * 3, true, false))


## The dev menu's buttons: day stepping, resets, close.
static func dev_buttons(m) -> void:
	var c := GTUI.modal_content(dev_modal_rect(m))
	var y := c.position.y + GTUI.line_height(GTUI.FS_LABEL) * DEV_INFO_LINES + GTUI.dp(GTUI.SP_L)
	var nav := GTUI.row(Rect2(c.position.x, y, c.size.x, GTUI.target()), 2)
	m.buttons.append({"id": "dev_prev", "label": "< Day", "primary": false, "enabled": true, "kind": "button", "rect": nav[0]})
	m.buttons.append({"id": "dev_next", "label": "Day >", "primary": false, "enabled": true, "kind": "button", "rect": nav[1]})
	y += GTUI.target() + GTUI.dp(GTUI.SP_S)
	for l in [["dev_today", "Reset today", false], ["dev_all", "Reset all days", false], ["dev_close", "Close", true]]:
		m.buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": true, "kind": "button", "rect": Rect2(c.position.x, y, c.size.x, GTUI.target())})
		y += GTUI.target() + GTUI.dp(GTUI.SP_S)


static func draw_dev(m) -> void:
	var c := GTUI.modal(m, dev_modal_rect(m), "Dev menu")
	var info := dev_info(m)
	for i in info.size():
		GTUI.text(m, c.position + Vector2(0, i * GTUI.line_height(GTUI.FS_LABEL)), info[i], GTUI.FS_LABEL, m.C_MUTED, false, c.size.x)


static func brief_buttons(m) -> void:
	var card := brief_card(m)
	var label := "Start building" if m.phase == m.Phase.BUILD and m.design.is_empty() else "Back to the site"
	m.buttons.append({"id": "brief_close", "label": label, "primary": true, "enabled": true, "kind": "button",
		"rect": GTUI.modal_buttons_rect(GTUI.modal_content(card))})
	m.buttons.append({"id": "brief_x", "label": "", "primary": false, "enabled": true, "kind": "row", "rect": GTUI.modal_close_rect(card)})


## Heavy Top days: the highest attached joint (ties: leftmost) of design d, matching
## quake_sim.top_joint. (-1, -1) when there's no weight today or nothing is built.
static func heavy_point(m, d: Array) -> Vector2i:
	if m.challenge == null or m.challenge.top_mass() <= 0.0:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	for p in m.attached_points(d):
		if m.is_anchor(p):
			continue
		if best.x < 0 or p.y > best.y or (p.y == best.y and p.x < best.x):
			best = p
	return best
