class_name GTUI
extends RefCounted
## GameTests product UI: tokens + drawing primitives shared by every game.
##
## Read ui/VISUAL_GUIDE.md first. In short:
##   * A game supplies a palette (semantic colours) with GTUI.setup(self, {...}).
##   * Geometry, type sizes, states, focus and motion come from here and are the same in every game.
##   * Everything is in dp ("design px" on a ~400 px wide phone). GTUI.dp(n) converts to the game's
##     canvas units, so a 44 dp button is ~44 CSS px tall on any screen, whatever the project's base size.
##   * Game art (boards, scenery, logos, particles) does NOT go through GTUI and may break these rules.
##
## This file is vendored into games/*/addons/gametests_ui/. Edit ui/gametests_ui/ and run
## .github/scripts/sync-ui.py; CI fails if a copy drifts.

# ------------------------------------------------------------------ tokens (dp)

const SP_XS := 4.0
const SP_S := 8.0
const SP_M := 12.0
const SP_L := 16.0
const SP_XL := 24.0
const SP_2XL := 32.0
const SP_3XL := 48.0
const SPACING := [4.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0]

const R_CONTROL := 6.0      # buttons, inputs, chips, toasts, tooltips, list rows
const R_PANEL := 8.0        # panels and cards that sit in the layout
const R_OVERLAY := 12.0     # modals / dialogs only
const RADII := [6.0, 8.0, 12.0]

const BORDER := 1.0
const FOCUS_WIDTH := 2.0
const FOCUS_GAP := 3.0
const TARGET := 44.0        # minimum height (and width) of anything tappable
const TARGET_COMPACT := 32.0  # minimum width of keyboard keys; height is still TARGET

# Type scale (dp). Six sizes; game logos/titles drawn as art may use their own.
const FS_CAPTION := 12      # meta lines, page counters, legal footers
const FS_LABEL := 14        # button labels, small labels, list secondary text
const FS_BODY := 16         # paragraphs, instructions
const FS_TITLE := 20        # modal / section titles
const FS_HEADING := 26      # game name in the standard header
const FS_DISPLAY := 36      # big result numbers
const FONT_SIZES := [12, 14, 16, 20, 26, 36]

const T_FAST := 0.10        # hover / press feedback
const T_NORMAL := 0.16      # modal, toast, panel transitions

const PALETTE_KEYS := ["bg", "surface", "surface_high", "text", "text_muted", "border",
	"accent", "on_accent", "success", "danger"]

# ------------------------------------------------------------------ state

static var S := 1.0                      # canvas units per dp
static var pal: Dictionary = {}
static var font: Font
static var font_bold: Font
static var _owner: WeakRef
static var _fixed_scale := 0.0

static var _targets: Array = []          # this frame: [{id, rect, layer, enabled, compact}]
static var _last: Array = []             # last completed frame
static var _layer := 0
static var _pointer := Vector2(-9999, -9999)
static var _down := false
static var _hover := ""
static var _focus := ""
static var _keyboard := false            # show focus rings only after keyboard use


## Call once in _ready(). `palette` keys: see PALETTE_KEYS (missing ones are derived).
## `scale` > 0 forces a fixed dp scale (tests); otherwise it follows the screen.
static func setup(owner: CanvasItem, palette: Dictionary, scale := 0.0) -> void:
	_owner = weakref(owner)
	_fixed_scale = scale
	pal = _complete(palette)
	font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = font
	fv.variation_embolden = 0.6
	font_bold = fv
	_targets = []
	_last = []
	_focus = ""
	_hover = ""
	refresh_scale(owner)
	var vp := owner.get_viewport()
	if vp and not vp.size_changed.is_connected(_on_resize):
		vp.size_changed.connect(_on_resize)


static func _on_resize() -> void:
	var o := owner()
	if o:
		refresh_scale(o)


static func owner() -> CanvasItem:
	return _owner.get_ref() if _owner else null


## dp per CSS px is 1, so S = canvas units per CSS px (never below 1).
static func refresh_scale(ci: CanvasItem) -> void:
	if _fixed_scale > 0.0:
		S = _fixed_scale
		return
	var logical := ci.get_viewport_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	if DisplayServer.get_name() == "headless" or win.x <= 0.0 or logical.x <= 0.0:
		S = 1.0
		return
	var css_w := win.x / maxf(DisplayServer.screen_get_scale(), 1.0)
	S = clampf(logical.x / css_w, 1.0, 3.0)


static func _complete(p: Dictionary) -> Dictionary:
	var o := p.duplicate()
	var bg: Color = o.get("bg", Color("16161a"))
	o["bg"] = bg
	var dark := bg.get_luminance() < 0.5
	if not o.has("surface"):
		o["surface"] = bg.lightened(0.05) if dark else bg.darkened(0.03)
	if not o.has("surface_high"):
		o["surface_high"] = (o.surface as Color).lightened(0.07) if dark else (o.surface as Color).darkened(0.05)
	if not o.has("text"):
		o["text"] = Color("f2f2f2") if dark else Color("222222")
	if not o.has("text_muted"):
		o["text_muted"] = (o.text as Color).lerp(bg, 0.4)
	if not o.has("border"):
		o["border"] = Color(o.text, 0.14)
	if not o.has("accent"):
		o["accent"] = Color("f5b942")
	if not o.has("on_accent"):
		o["on_accent"] = ink_on(o.accent)
	if not o.has("success"):
		o["success"] = Color("4caf6e")
	if not o.has("danger"):
		o["danger"] = Color("e0524a")
	if not o.has("focus"):
		o["focus"] = o.accent
	if not o.has("scrim"):
		o["scrim"] = Color(0, 0, 0, 0.55) if dark else Color(bg.darkened(0.7), 0.45)
	return o


## Black or white text, whichever reads better on `c`.
static func ink_on(c: Color) -> Color:
	return Color("16130f") if c.get_luminance() > 0.55 else Color("ffffff")


static func c(key: String) -> Color:
	return pal.get(key, Color.MAGENTA)


# ------------------------------------------------------------------ units

static func dp(v: float) -> float:
	return v * S


static func fs(size_dp: int) -> int:
	return int(round(size_dp * S))


static func target() -> float:
	return TARGET * S


static func space(v: float) -> float:
	return v * S


# ------------------------------------------------------------------ frame + input

## Call at the top of the game's _draw() (the canvas item that draws product UI).
static func begin(ci: CanvasItem = null) -> void:
	_last = _targets
	_targets = []
	_layer = 0


## Registers a tappable rect so it gets hover/press/focus treatment and is checked by the target-size test.
## Product controls drawn with GTUI register themselves; call this for custom-drawn controls.
static func register(id: String, rect: Rect2, enabled := true, compact := false) -> void:
	_targets.append({"id": id, "rect": rect, "layer": _layer, "enabled": enabled, "compact": compact})


static func is_hover(id: String) -> bool:
	return _hover == id and not _keyboard


static func is_pressed(id: String, rect: Rect2) -> bool:
	return _down and rect.has_point(_pointer)


static func is_focused(id: String) -> bool:
	return _keyboard and _focus == id


static func focused_id() -> String:
	return _focus if _keyboard else ""


## Feed every input event through this from the game's _input(). Returns:
##   {}                                  nothing for the game to do
##   {"activate": id, "pos": Vector2}    keyboard Enter/Space on a focused control; treat as a tap at pos
##   {"cancel": true}                    Escape; close the top-most overlay if there is one
static func handle_input(ev: InputEvent) -> Dictionary:
	if ev.has_meta("gt_synth"):
		return {}
	if ev is InputEventMouseMotion or ev is InputEventScreenDrag:
		_pointer = ev.position
		if _keyboard:
			_keyboard = false
			_redraw()
		_update_hover()
		return {}
	if ev is InputEventMouseButton or ev is InputEventScreenTouch:
		if ev is InputEventMouseButton and ev.button_index != MOUSE_BUTTON_LEFT:
			return {}
		_pointer = ev.position
		_down = ev.pressed
		_keyboard = false
		_update_hover()
		_redraw()
		return {}
	if ev is InputEventKey and ev.pressed:
		var k: int = ev.keycode
		if k == KEY_TAB:
			_move_focus(-1 if ev.shift_pressed else 1)
			return {"consumed": true}
		if _keyboard and _focus != "" and (k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE) and not ev.echo:
			for t in _active_targets():
				if t.id == _focus:
					return {"activate": _focus, "pos": (t.rect as Rect2).get_center()}
		if k == KEY_ESCAPE and not ev.echo:
			return {"cancel": true}
	return {}


## A press + release at `pos` for replaying a keyboard activation through the game's own tap handling:
##   for e in GTUI.tap_events(g.pos): _input(e)
static func tap_events(pos: Vector2) -> Array:
	var out: Array = []
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		e.set_meta("gt_synth", true)
		out.append(e)
	return out


static func _active_targets() -> Array:
	var top := 0
	for t in _last:
		top = maxi(top, int(t.layer))
	var out: Array = []
	for t in _last:
		if int(t.layer) == top and t.enabled:
			out.append(t)
	return out


static func _move_focus(step: int) -> void:
	var ts := _active_targets()
	if ts.is_empty():
		return
	var idx := -1
	for i in ts.size():
		if ts[i].id == _focus:
			idx = i
	if not _keyboard and idx >= 0:
		idx -= step          # first Tab shows the ring on the current control
	_keyboard = true
	idx = posmod(idx + step, ts.size()) if idx >= 0 else (0 if step > 0 else ts.size() - 1)
	_focus = ts[idx].id
	_redraw()


static func _update_hover() -> void:
	var h := ""
	for t in _active_targets():
		if (t.rect as Rect2).has_point(_pointer):
			h = t.id
	if h != _hover:
		_hover = h
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if h != "" else Input.CURSOR_ARROW)
		_redraw()


static func _redraw() -> void:
	var o := owner()
	if o:
		o.queue_redraw()


## Rects of registered controls smaller than the touch-target minimum (used by tests/test_gtui.gd).
static func undersized() -> Array:
	var out: Array = []
	var min_h := TARGET * S - 0.5
	for t in _last:
		var r: Rect2 = t.rect
		var min_w := (TARGET_COMPACT if t.compact else TARGET) * S - 0.5
		if r.size.y < min_h or r.size.x < min_w:
			out.append({"id": t.id, "size": r.size, "min": Vector2(min_w, min_h)})
	return out


static func targets() -> Array:
	return _last


# ------------------------------------------------------------------ text

static func text_width(s: String, size_dp: int, bold := false) -> float:
	return (font_bold if bold else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(size_dp)).x


## Draws one line with its top-left at `pos` (not the baseline).
static func text(ci: CanvasItem, pos: Vector2, s: String, size_dp: int, col: Color, bold := false, max_w := -1.0) -> void:
	var f: Font = font_bold if bold else font
	var px := fs(size_dp)
	ci.draw_string(f, pos + Vector2(0, f.get_ascent(px)), s, HORIZONTAL_ALIGNMENT_LEFT, max_w, px, col)


## One line inside `r`, vertically centred. align: -1 left, 0 centre, 1 right. Shrinks to fit (down to CAPTION).
static func text_in(ci: CanvasItem, r: Rect2, s: String, size_dp: int, col: Color, align := 0, bold := false) -> void:
	var f: Font = font_bold if bold else font
	var px := fs(size_dp)
	var min_px := fs(FS_CAPTION)
	while px > min_px and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > r.size.x:
		px -= 1
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x := r.position.x
	if align == 0:
		x += (r.size.x - w) / 2.0
	elif align > 0:
		x = r.end.x - w
	var base := r.position.y + (r.size.y + f.get_ascent(px) - f.get_descent(px)) / 2.0
	ci.draw_string(f, Vector2(x, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


static func line_height(size_dp: int) -> float:
	return roundf(fs(size_dp) * 1.4)


## Wrapped paragraph, left aligned, top at y. Returns the y below it. Pass draw=false to measure.
static func paragraph(ci: CanvasItem, x: float, y: float, w: float, s: String, size_dp: int, col: Color, bold := false, draw := true) -> float:
	var f: Font = font_bold if bold else font
	var px := fs(size_dp)
	var lh := line_height(size_dp)
	var lines := wrap_lines(s, size_dp, w, bold)
	if draw and ci:
		for i in lines.size():
			ci.draw_string(f, Vector2(x, y + i * lh + (lh + f.get_ascent(px) - f.get_descent(px)) / 2.0), lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	return y + lines.size() * lh


static func wrap_lines(s: String, size_dp: int, w: float, bold := false) -> PackedStringArray:
	var f: Font = font_bold if bold else font
	var px := fs(size_dp)
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for word in para.split(" "):
			var t := word if line == "" else line + " " + word
			if line != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > w:
				out.append(line)
				line = word
			else:
				line = t
		out.append(line)
	return out


# ------------------------------------------------------------------ surfaces

static func box(ci: CanvasItem, r: Rect2, fill: Color, radius_dp: float, border := Color(0, 0, 0, 0), width_dp := BORDER) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(round(radius_dp * S)))
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 0.75
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(maxi(1, int(round(width_dp * S))))
	ci.draw_style_box(sb, r)


## A layout panel: flat surface, 1 dp border, panel radius. level 1 = raised (surface_high).
static func panel(ci: CanvasItem, r: Rect2, level := 0) -> void:
	box(ci, r, c("surface_high") if level > 0 else c("surface"), R_PANEL, c("border"))


## Full-screen scrim + overlay card. Controls drawn after this belong to the overlay layer (keyboard focus
## stays inside it). With `close_id`, a close (x) icon button sits top-right; route it like any button.
## Returns the padded content rect below the title row.
static func modal(ci: CanvasItem, card: Rect2, title := "", close_id := "", alpha := 1.0) -> Rect2:
	_layer += 1
	var vs := ci.get_viewport_rect().size
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(c("scrim"), c("scrim").a * alpha))
	box(ci, card, Color(c("surface"), alpha), R_OVERLAY, Color(c("border"), c("border").a * alpha))
	var pad := dp(SP_XL)
	var content := card.grow(-pad)
	if title != "" or close_id != "":
		var th := target()
		var head := Rect2(content.position.x, card.position.y + dp(SP_M), content.size.x, th)
		var tw := head.size.x
		if close_id != "":
			var cr := Rect2(card.end.x - dp(SP_M) - th, head.position.y, th, th)
			icon_button(ci, close_id, cr, "close")
			tw = cr.position.x - dp(SP_S) - head.position.x
		if title != "":
			text_in(ci, Rect2(head.position, Vector2(tw, th)), title, FS_TITLE, Color(c("text"), alpha), -1, true)
		var top := head.end.y + dp(SP_M)
		content.size.y -= top - content.position.y
		content.position.y = top
	return content


## Rect of the close button GTUI.modal() draws for `card` (for hit-testing before drawing).
static func modal_close_rect(card: Rect2) -> Rect2:
	var th := target()
	return Rect2(card.end.x - dp(SP_M) - th, card.position.y + dp(SP_M), th, th)


## Content rect GTUI.modal() will return for `card` (for laying out buttons before drawing).
static func modal_content(card: Rect2, has_head := true) -> Rect2:
	var content := card.grow(-dp(SP_XL))
	if has_head:
		var top := card.position.y + dp(SP_M) + target() + dp(SP_M)
		content.size.y -= top - content.position.y
		content.position.y = top
	return content


## Standard overlay card rect: centred, `w_dp` wide at most, `h` tall (canvas units), 16 dp from the edges.
static func modal_rect(ci: CanvasItem, w_dp: float, h: float) -> Rect2:
	var vs := ci.get_viewport_rect().size
	var m := dp(SP_L)
	var w := minf(dp(w_dp), vs.x - m * 2.0)
	h = minf(h, vs.y - m * 2.0)
	return Rect2((vs.x - w) / 2.0, (vs.y - h) / 2.0, w, h)


## Height a modal needs for `content_h` of content plus padding, the title row and (optionally) one button row.
static func modal_height(content_h: float, has_title := true, buttons := true) -> float:
	var h := dp(SP_XL) * 2.0 + content_h
	if has_title:
		h += dp(SP_M) * 2.0 + target() - dp(SP_XL)
	if buttons:
		h += dp(SP_XL) + target()
	return h


## Bottom button row of a modal content rect.
static func modal_buttons_rect(content: Rect2) -> Rect2:
	return Rect2(content.position.x, content.end.y - target(), content.size.x, target())


# ------------------------------------------------------------------ controls

## variant: "primary" (one per view), "secondary", "quiet" (no fill), "danger".
static func button(ci: CanvasItem, id: String, r: Rect2, label: String, variant := "secondary", enabled := true, size_dp := FS_LABEL + 2) -> void:
	register(id, r, enabled)
	var fill := Color(0, 0, 0, 0)
	var ink := c("text")
	var edge := Color(0, 0, 0, 0)
	match variant:
		"primary":
			fill = c("accent")
			ink = c("on_accent")
		"danger":
			fill = c("danger")
			ink = ink_on(c("danger"))
		"quiet":
			edge = Color(0, 0, 0, 0)
		_:
			fill = c("surface_high")
			edge = c("border")
	if enabled:
		if is_pressed(id, r):
			fill = _shade(fill, 0.16) if fill.a > 0.0 else Color(c("text"), 0.12)
		elif is_hover(id):
			fill = _shade(fill, 0.08) if fill.a > 0.0 else Color(c("text"), 0.06)
	else:
		fill = Color(fill, fill.a * 0.4)
		ink = Color(ink, 0.45)
		edge = Color(edge, edge.a * 0.5)
	box(ci, r, fill, R_CONTROL, edge)
	text_in(ci, r.grow_individual(-dp(SP_M), 0, -dp(SP_M), 0), label, size_dp, ink, 0, true)
	focus_ring(ci, id, r)


## Square icon button (TARGET x TARGET by default). icon: help, calendar, close, back, next, share,
## sound_on, sound_off, menu, restart, settings — or "" and draw your own glyph on top.
static func icon_button(ci: CanvasItem, id: String, r: Rect2, icon: String, enabled := true, active := false) -> void:
	register(id, r, enabled)
	var fill := c("surface_high")
	if active:
		fill = c("accent")
	if enabled and is_pressed(id, r):
		fill = _shade(fill, 0.16)
	elif enabled and is_hover(id):
		fill = _shade(fill, 0.08)
	var ink := c("on_accent") if active else c("text")
	if not enabled:
		fill = Color(fill, 0.4)
		ink = Color(ink, 0.45)
	box(ci, r, fill, R_CONTROL, c("border"))
	glyph(ci, icon, r.get_center(), minf(r.size.x, r.size.y) * 0.5, ink)
	focus_ring(ci, id, r)


## Row of standard header icon buttons ending at `right`, top at `y`. Returns {id: rect}.
## Order convention (left to right): game-specific, then "calendar", then "help" last.
static func icon_row(right: float, y: float, ids: Array, size := 0.0) -> Dictionary:
	var s := size if size > 0.0 else target()
	var gap := dp(SP_S)
	var out := {}
	var x := right - s
	for i in range(ids.size() - 1, -1, -1):
		out[ids[i]] = Rect2(x, y, s, s)
		x -= s + gap
	return out


## Toggle chip / tool selector: square-cornered, never a pill.
static func chip(ci: CanvasItem, id: String, r: Rect2, label: String, on := false, enabled := true) -> void:
	register(id, r, enabled)
	var fill := Color(c("accent"), 0.16) if on else c("surface_high")
	var edge := c("accent") if on else c("border")
	if enabled and is_pressed(id, r):
		fill = _shade(fill, 0.16)
	elif enabled and is_hover(id):
		fill = _shade(fill, 0.08)
	var ink := c("text")
	if not enabled:
		fill = Color(fill, fill.a * 0.4)
		ink = Color(ink, 0.45)
	box(ci, r, fill, R_CONTROL, edge)
	text_in(ci, r.grow_individual(-dp(SP_S), 0, -dp(SP_S), 0), label, FS_LABEL, ink, 0, on)
	focus_ring(ci, id, r)


## Segmented control. Returns the segment rects; segment i is registered as "<id>:<i>".
static func segmented(ci: CanvasItem, id: String, r: Rect2, labels: Array, selected: int, enabled := true) -> Array:
	var n := labels.size()
	var rects: Array = []
	box(ci, r, c("surface_high"), R_CONTROL, c("border"))
	var inner := r.grow(-dp(2))
	var w := inner.size.x / maxf(n, 1)
	for i in n:
		var sr := Rect2(inner.position.x + i * w, inner.position.y, w, inner.size.y)
		rects.append(sr)
		var sid := "%s:%d" % [id, i]
		register(sid, sr, enabled)
		if i == selected:
			box(ci, sr, c("accent"), R_CONTROL - 2.0)
		elif enabled and is_pressed(sid, sr):
			box(ci, sr, Color(c("text"), 0.12), R_CONTROL - 2.0)
		elif enabled and is_hover(sid):
			box(ci, sr, Color(c("text"), 0.06), R_CONTROL - 2.0)
		var ink := c("on_accent") if i == selected else c("text")
		if not enabled:
			ink = Color(ink, 0.45)
		text_in(ci, sr.grow_individual(-dp(SP_XS), 0, -dp(SP_XS), 0), String(labels[i]), FS_LABEL, ink, 0, i == selected)
		focus_ring(ci, sid, sr)
	return rects


## One row of a list picker (e.g. the "Past puzzles" archive). Tappable; registered as `id`.
static func list_row(ci: CanvasItem, id: String, r: Rect2, lead: String, label: String, trail: String,
		current := false, trail_col := Color(0, 0, 0, 0)) -> void:
	register(id, r, true)
	var fill := c("surface_high")
	if is_pressed(id, r):
		fill = _shade(fill, 0.16)
	elif is_hover(id):
		fill = _shade(fill, 0.08)
	box(ci, r, fill, R_CONTROL, c("accent") if current else c("border"), FOCUS_WIDTH if current else BORDER)
	var pad := dp(SP_L)
	var inner := r.grow_individual(-pad, 0, -pad, 0)
	var lead_w := text_width("#0000", FS_BODY, true)
	text_in(ci, Rect2(inner.position, Vector2(lead_w, inner.size.y)), lead, FS_BODY, c("accent"), -1, true)
	var tw := minf(text_width(trail, FS_LABEL) + 1.0, inner.size.x * 0.45)
	text_in(ci, Rect2(inner.end.x - tw, inner.position.y, tw, inner.size.y), trail, FS_LABEL,
		trail_col if trail_col.a > 0.0 else c("text_muted"), 1)
	var lx := inner.position.x + lead_w + dp(SP_S)
	text_in(ci, Rect2(lx, inner.position.y, inner.end.x - tw - dp(SP_S) - lx, inner.size.y), label, FS_BODY, c("text"), -1)
	focus_ring(ci, id, r)


## Splits `r` horizontally into n rects with SP_S gaps. weights optional (e.g. [2, 1] for primary + secondary).
static func row(r: Rect2, n: int, weights: Array = []) -> Array:
	var gap := dp(SP_S)
	var total := 0.0
	for i in n:
		total += float(weights[i]) if i < weights.size() else 1.0
	var free := r.size.x - gap * (n - 1)
	var out: Array = []
	var x := r.position.x
	for i in n:
		var w := free * ((float(weights[i]) if i < weights.size() else 1.0) / total)
		out.append(Rect2(x, r.position.y, w, r.size.y))
		x += w + gap
	return out


## Focus ring around a control; only visible after keyboard navigation.
static func focus_ring(ci: CanvasItem, id: String, r: Rect2, radius_dp := R_CONTROL) -> void:
	if not is_focused(id):
		return
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = c("focus")
	sb.set_border_width_all(maxi(2, int(round(FOCUS_WIDTH * S))))
	sb.set_corner_radius_all(int(round((radius_dp + FOCUS_GAP) * S)))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r.grow(dp(FOCUS_GAP)))


# ------------------------------------------------------------------ feedback

## Toast / snackbar: inverted colours, control radius, centred at x on `bottom_y` (its bottom edge).
static func toast(ci: CanvasItem, msg: String, alpha: float, bottom_y: float) -> void:
	if msg == "" or alpha <= 0.0:
		return
	var vs := ci.get_viewport_rect().size
	var pad := dp(SP_L)
	var max_w := minf(vs.x - dp(SP_L) * 2.0, dp(420))
	var lines := wrap_lines(msg, FS_LABEL + 1, max_w - pad * 2.0, true)
	var w := 0.0
	for l in lines:
		w = maxf(w, text_width(l, FS_LABEL + 1, true))
	var lh := line_height(FS_LABEL + 1)
	var h := maxf(target(), lines.size() * lh + dp(SP_M) * 2.0)
	var r := Rect2((vs.x - (w + pad * 2.0)) / 2.0, bottom_y - h, w + pad * 2.0, h)
	box(ci, r, Color(c("text"), 0.96 * alpha), R_CONTROL)
	var y := r.position.y + (h - lines.size() * lh) / 2.0
	for l in lines:
		text_in(ci, Rect2(r.position.x, y, r.size.x, lh), l, FS_LABEL + 1, Color(c("bg"), alpha), 0, true)
		y += lh


## Toast alpha from its remaining time: fades in and out over T_NORMAL.
static func toast_alpha(time_left: float, duration := 2.0) -> float:
	return clampf(minf(time_left, duration - time_left) / T_NORMAL, 0.0, 1.0) if time_left < duration else 1.0


## Small explanatory bubble above (or below, if no room) `anchor`.
static func tooltip(ci: CanvasItem, anchor: Rect2, msg: String) -> void:
	var vs := ci.get_viewport_rect().size
	var max_w := minf(dp(280), vs.x - dp(SP_L) * 2.0)
	var pad := dp(SP_M)
	var lines := wrap_lines(msg, FS_LABEL, max_w - pad * 2.0)
	var w := 0.0
	for l in lines:
		w = maxf(w, text_width(l, FS_LABEL))
	var lh := line_height(FS_LABEL)
	var size := Vector2(w + pad * 2.0, lines.size() * lh + dp(SP_S) * 2.0)
	var x := clampf(anchor.get_center().x - size.x / 2.0, dp(SP_S), vs.x - size.x - dp(SP_S))
	var y := anchor.position.y - size.y - dp(SP_S)
	if y < dp(SP_S):
		y = anchor.end.y + dp(SP_S)
	var r := Rect2(x, y, size.x, size.y)
	box(ci, r, c("surface_high"), R_CONTROL, c("border"))
	for i in lines.size():
		text_in(ci, Rect2(r.position.x + pad, r.position.y + dp(SP_S) + i * lh, r.size.x - pad * 2.0, lh), lines[i], FS_LABEL, c("text"), -1)


## Small uppercase label over a big number (scores, budgets). Right- or left-aligned at `pos` (top).
static func stat(ci: CanvasItem, pos: Vector2, label: String, value: String, align := -1, value_col := Color(0, 0, 0, 0)) -> Rect2:
	var lw := text_width(label.to_upper(), FS_CAPTION, true)
	var vw := text_width(value, FS_HEADING, true)
	var w := maxf(lw, vw)
	var x := pos.x - w if align > 0 else pos.x
	var lr := Rect2(x, pos.y, w, line_height(FS_CAPTION))
	text_in(ci, lr, label.to_upper(), FS_CAPTION, c("text_muted"), align, true)
	var vr := Rect2(x, lr.end.y, w, line_height(FS_HEADING))
	text_in(ci, vr, value, FS_HEADING, value_col if value_col.a > 0.0 else c("text"), align, true)
	return Rect2(x, pos.y, w, vr.end.y - pos.y)


## "4h 12m" until local midnight (or UTC midnight with utc=true).
static func countdown(utc := false) -> String:
	var t := Time.get_time_dict_from_system(utc)
	var left := 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	return "%dh %02dm" % [left / 3600, (left % 3600) / 60]


static func _shade(col: Color, amt: float) -> Color:
	# Lighten dark fills, darken light ones, so hover/press reads on any palette.
	return col.lightened(amt) if col.get_luminance() < 0.6 else col.darkened(amt)


# ------------------------------------------------------------------ glyphs

## Monoline icons drawn in a box of `size` around `ctr`. One stroke weight (size/11, at least 1.5 px).
static func glyph(ci: CanvasItem, icon: String, ctr: Vector2, size: float, col: Color) -> void:
	var u := size / 2.0
	var w := maxf(1.5, size / 11.0)
	match icon:
		"help":
			var f: Font = font_bold
			var px := int(size * 0.95)
			var gw := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			ci.draw_string(f, Vector2(ctr.x - gw / 2.0, ctr.y + (f.get_ascent(px) - f.get_descent(px)) / 2.0), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		"calendar":
			var r := Rect2(ctr.x - u * 0.85, ctr.y - u * 0.62, u * 1.7, u * 1.5)
			ci.draw_rect(r, col, false, w)
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x, u * 0.38)), col)
			for dx in [-0.4, 0.4]:
				ci.draw_line(Vector2(ctr.x + u * dx, ctr.y - u * 0.9), Vector2(ctr.x + u * dx, ctr.y - u * 0.45), col, w)
			for i in 3:
				var s := u * 0.26
				ci.draw_rect(Rect2(ctr.x - u * 0.55 + i * u * 0.42, ctr.y + u * 0.12, s, s), col)
		"close":
			ci.draw_line(ctr + Vector2(-u, -u) * 0.6, ctr + Vector2(u, u) * 0.6, col, w, true)
			ci.draw_line(ctr + Vector2(u, -u) * 0.6, ctr + Vector2(-u, u) * 0.6, col, w, true)
		"back", "next":
			var d := -1.0 if icon == "back" else 1.0
			ci.draw_polyline(PackedVector2Array([ctr + Vector2(-d * u * 0.25, -u * 0.6), ctr + Vector2(d * u * 0.35, 0),
				ctr + Vector2(-d * u * 0.25, u * 0.6)]), col, w, true)
		"share":
			ci.draw_line(ctr + Vector2(0, u * 0.25), ctr + Vector2(0, -u * 0.8), col, w, true)
			ci.draw_polyline(PackedVector2Array([ctr + Vector2(-u * 0.4, -u * 0.4), ctr + Vector2(0, -u * 0.8),
				ctr + Vector2(u * 0.4, -u * 0.4)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([ctr + Vector2(-u * 0.35, -u * 0.15), ctr + Vector2(-u * 0.7, -u * 0.15),
				ctr + Vector2(-u * 0.7, u * 0.8), ctr + Vector2(u * 0.7, u * 0.8), ctr + Vector2(u * 0.7, -u * 0.15),
				ctr + Vector2(u * 0.35, -u * 0.15)]), col, w, true)
		"sound_on", "sound_off":
			var body := PackedVector2Array([ctr + Vector2(-u * 0.8, -u * 0.3), ctr + Vector2(-u * 0.4, -u * 0.3),
				ctr + Vector2(0, -u * 0.7), ctr + Vector2(0, u * 0.7), ctr + Vector2(-u * 0.4, u * 0.3), ctr + Vector2(-u * 0.8, u * 0.3)])
			ci.draw_colored_polygon(body, col)
			if icon == "sound_on":
				ci.draw_arc(ctr + Vector2(u * 0.05, 0), u * 0.42, -0.9, 0.9, 10, col, w, true)
				ci.draw_arc(ctr + Vector2(u * 0.05, 0), u * 0.78, -0.9, 0.9, 14, col, w, true)
			else:
				ci.draw_line(ctr + Vector2(u * 0.3, -u * 0.35), ctr + Vector2(u * 0.9, u * 0.35), col, w, true)
				ci.draw_line(ctr + Vector2(u * 0.9, -u * 0.35), ctr + Vector2(u * 0.3, u * 0.35), col, w, true)
		"menu":
			for dy in [-0.5, 0.0, 0.5]:
				ci.draw_line(ctr + Vector2(-u * 0.7, u * dy), ctr + Vector2(u * 0.7, u * dy), col, w, true)
		"restart":
			ci.draw_arc(ctr, u * 0.62, -PI * 0.35, PI * 1.45, 24, col, w, true)
			var tip := ctr + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * u * 0.62
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-u * 0.32, -u * 0.12), tip + Vector2(u * 0.12, u * 0.3),
				tip + Vector2(u * 0.2, -u * 0.32)]), col)
		"settings":
			ci.draw_arc(ctr, u * 0.32, 0, TAU, 16, col, w, true)
			for i in 8:
				var a := i * TAU / 8.0
				ci.draw_line(ctr + Vector2(cos(a), sin(a)) * u * 0.52, ctr + Vector2(cos(a), sin(a)) * u * 0.8, col, w * 1.4, true)
		_:
			pass


# ------------------------------------------------------------------ Control-node games

## A Theme for games built from Control nodes. Type variations: "GTPrimary", "GTQuiet", "GTIcon",
## "GTChip", "GTPanel" (PanelContainer), "GTOverlay" (PanelContainer), "GTCaption"/"GTTitle" (Label).
static func make_theme(scale := 1.0) -> Theme:
	var k := scale
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = int(FS_BODY * k)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = c("focus")
	focus.set_border_width_all(int(FOCUS_WIDTH * k))
	focus.set_corner_radius_all(int((R_CONTROL + FOCUS_GAP) * k))
	focus.set_expand_margin_all(FOCUS_GAP * k)
	var hi: Color = c("surface_high")
	for type in ["Button", "GTPrimary", "GTQuiet", "GTIcon", "GTChip"]:
		var fill := hi
		var ink := c("text")
		var edge := c("border")
		if type == "GTPrimary":
			fill = c("accent")
			ink = c("on_accent")
			edge = Color(0, 0, 0, 0)
		elif type == "GTQuiet":
			fill = Color(0, 0, 0, 0)
			edge = Color(0, 0, 0, 0)
		if type != "Button":
			t.set_type_variation(type, "Button")
		var pad_h := SP_S if type == "GTIcon" else SP_M
		var hover := _shade(fill, 0.08) if fill.a > 0.0 else Color(c("text"), 0.06)
		var press := _shade(fill, 0.16) if fill.a > 0.0 else Color(c("text"), 0.12)
		t.set_stylebox("normal", type, _sb(k, fill, R_CONTROL, edge, pad_h))
		t.set_stylebox("hover", type, _sb(k, hover, R_CONTROL, edge, pad_h))
		t.set_stylebox("pressed", type, _sb(k, press, R_CONTROL, edge, pad_h))
		t.set_stylebox("hover_pressed", type, _sb(k, press, R_CONTROL, edge, pad_h))
		t.set_stylebox("disabled", type, _sb(k, Color(fill, fill.a * 0.4), R_CONTROL, Color(edge, edge.a * 0.5), pad_h))
		t.set_stylebox("focus", type, focus)
		for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			t.set_color(st, type, ink)
		t.set_color("font_disabled_color", type, Color(ink, 0.45))
		t.set_color("icon_disabled_color", type, Color(ink, 0.45))
		t.set_font("font", type, font_bold)
		t.set_font_size("font_size", type, int((FS_LABEL + 2) * k))
		t.set_constant("h_separation", type, int(SP_S * k))
	t.set_stylebox("pressed", "GTChip", _sb(k, Color(c("accent"), 0.16), R_CONTROL, c("accent")))
	t.set_type_variation("GTPanel", "PanelContainer")
	t.set_stylebox("panel", "GTPanel", _sb(k, c("surface"), R_PANEL, c("border"), SP_M, SP_M))
	t.set_type_variation("GTPanelHigh", "PanelContainer")
	t.set_stylebox("panel", "GTPanelHigh", _sb(k, c("surface_high"), R_PANEL, c("border"), SP_M, SP_M))
	t.set_type_variation("GTOverlay", "PanelContainer")
	t.set_stylebox("panel", "GTOverlay", _sb(k, c("surface"), R_OVERLAY, c("border"), SP_XL, SP_XL))
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", c("text"))
	t.set_type_variation("GTCaption", "Label")
	t.set_color("font_color", "GTCaption", c("text_muted"))
	t.set_font_size("font_size", "GTCaption", int(FS_CAPTION * k))
	t.set_type_variation("GTLabel", "Label")
	t.set_color("font_color", "GTLabel", c("text_muted"))
	t.set_font_size("font_size", "GTLabel", int(FS_LABEL * k))
	t.set_type_variation("GTTitle", "Label")
	t.set_font("font", "GTTitle", font_bold)
	t.set_font_size("font_size", "GTTitle", int(FS_TITLE * k))
	t.set_type_variation("GTHeading", "Label")
	t.set_font("font", "GTHeading", font_bold)
	t.set_font_size("font_size", "GTHeading", int(FS_HEADING * k))
	t.set_color("default_color", "RichTextLabel", c("text"))
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_stylebox("normal", "LineEdit", _sb(k, c("surface_high"), R_CONTROL, c("border")))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", c("text"))
	t.set_color("font_placeholder_color", "LineEdit", c("text_muted"))
	t.set_color("caret_color", "LineEdit", c("accent"))
	var grab: StyleBoxFlat = _sb(k, Color(c("text"), 0.25), 3.0, Color(0, 0, 0, 0), 0.0, 0.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0)
	track.content_margin_left = 3 * k
	track.content_margin_right = 3 * k
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", _sb(k, Color(c("text"), 0.4), 3.0, Color(0, 0, 0, 0), 0.0, 0.0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _sb(k, Color(c("text"), 0.5), 3.0, Color(0, 0, 0, 0), 0.0, 0.0))
	t.set_color("font_color", "TooltipLabel", c("text"))
	t.set_font_size("font_size", "TooltipLabel", int(FS_LABEL * k))
	t.set_stylebox("panel", "TooltipPanel", _sb(k, c("surface_high"), R_CONTROL, c("border"), SP_M, SP_S))
	return t


static func _sb(k: float, fill: Color, radius: float, edge := Color(0, 0, 0, 0), pad_h := SP_M, pad_v := SP_S) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(int(radius * k))
	if edge.a > 0.0:
		s.border_color = edge
		s.set_border_width_all(maxi(1, int(BORDER * k)))
	s.content_margin_left = pad_h * k
	s.content_margin_right = pad_h * k
	s.content_margin_top = pad_v * k
	s.content_margin_bottom = pad_v * k
	s.anti_aliasing = true
	return s
