extends RefCounted
## Drawing only: the venue, the people, the bouquet. Every function draws onto the CanvasItem
## it is given, in world coordinates (the caller sets the transform). No game state here.

const INK := Color("2e2440")
const SOFT_INK := Color(0.18, 0.14, 0.25, 0.18)
const CORAL := Color("e0607e")
const TEAL := Color("2fa39a")
const MUSTARD := Color("f2b84b")
const LILAC := Color("9b8ce0")
const SKY := Color("7cc4ef")
const WHITE := Color("fffdf8")
const GOLD := Color("d9a441")

## Ballroom wall, trim and floor colours per level palette.
const WALLS := [
	[Color("f7e4ee"), Color("dcb6cb"), Color("c99f74")],
	[Color("e2f2ed"), Color("b1d6cc"), Color("bf9670")],
	[Color("fdebd3"), Color("e8c59c"), Color("b88a62")],
	[Color("e5ebfb"), Color("bfcaeb"), Color("c6a27c")],
	[Color("fbf1cc"), Color("e2d090"), Color("b48e6a")],
	[Color("efe3f8"), Color("cdb8e3"), Color("c09a73")],
]
const SKIN := [Color("f6d3b8"), Color("e9b48f"), Color("c98e66"), Color("a66b47"), Color("7a4a2e"), Color("f1c7a3")]
const OUTFIT := [Color("2fa39a"), Color("e0607e"), Color("6c63c9"), Color("f2b84b"), Color("3b6fb6"),
	Color("e58b48"), Color("8a5aa8"), Color("4f9a5c"), Color("d94f4f"), Color("4a4e69"), Color("1f8fb3"), Color("c45c9a")]
const HAIR := [Color("2b1d17"), Color("5a3a22"), Color("b7752f"), Color("e3c27a"), Color("8c8c8c"), Color("3a2a4a")]
const BLOOM := [Color("ff8fab"), Color("ffd166"), Color("f78c6b"), Color("c8a2ff"), Color("ffffff"), Color("ff6b8b")]
const BALLOON := [Color("ff8fab"), Color("7cc4ef"), Color("ffd166"), Color("9be3c2"), Color("c8a2ff"), Color("f78c6b")]


# ------------------------------------------------------------------ helpers

static func rrect(ci: CanvasItem, r: Rect2, c: Color, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)


static func rrect_outline(ci: CanvasItem, r: Rect2, fill: Color, line: Color, rad: float, w: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = line
	sb.set_border_width_all(int(w))
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	ci.draw_colored_polygon(pts, col)


static func tri(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([a, b, c]), col)


static func flower(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	for i in 5:
		var t := TAU * i / 5.0
		ci.draw_circle(p + Vector2(cos(t), sin(t)) * r * 0.55, r * 0.5, col)
	ci.draw_circle(p, r * 0.32, MUSTARD if col != MUSTARD else WHITE)


# ------------------------------------------------------------------ venue

static func background(ci: CanvasItem, lv: Dictionary, extra_top: float, extra_bottom: float, extra_side: float) -> void:
	var w := float(lv.w)
	var fl := float(lv.floor)
	var garden := String(lv.theme) == "garden"
	var left := -extra_side
	var right := w + extra_side
	if garden:
		var top := -extra_top - 400.0
		ci.draw_polygon(PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, fl), Vector2(left, fl)]),
			PackedColorArray([Color("9fd3f2"), Color("9fd3f2"), Color("e8f6ee"), Color("e8f6ee")]))
		ci.draw_circle(Vector2(w - 110, 110), 42, Color("ffe08a"))
		ci.draw_circle(Vector2(w - 110, 110), 56, Color(1, 0.9, 0.5, 0.25))
		for d in lv.decor:
			match String(d.k):
				"cloud": _cloud(ci, Vector2(d.x, d.y), 1.0 + int(d.s) * 0.2)
				"tree": _tree(ci, Vector2(d.x, d.y), int(d.s))
		# picket fence
		var fy := fl - 54
		ci.draw_rect(Rect2(left, fy + 16, right - left, 8), Color("ffffff"))
		ci.draw_rect(Rect2(left, fy + 36, right - left, 8), Color("ffffff"))
		var x := left - fmod(left, 26.0)
		while x < right:
			ci.draw_rect(Rect2(x, fy, 14, 54), Color("fbfbf6"))
			tri(ci, Vector2(x, fy), Vector2(x + 14, fy), Vector2(x + 7, fy - 8), Color("fbfbf6"))
			x += 26
		ci.draw_rect(Rect2(left, fl, right - left, 400 + extra_bottom), Color("8fcf7a"))
		ci.draw_rect(Rect2(left, fl, right - left, 10), Color("7cc068"))
		var gx := left
		var k := 0
		while gx < right:
			ci.draw_line(Vector2(gx, fl + 18 + (k % 3) * 22), Vector2(gx + 6, fl + 10 + (k % 3) * 22), Color("6fb45e"), 2.0)
			gx += 17
			k += 1
		return
	var pal: Array = WALLS[int(lv.get("palette", 0)) % WALLS.size()]
	var wall: Color = pal[0]
	var trim: Color = pal[1]
	var wood: Color = pal[2]
	var ceil_y := float(lv.ceiling)
	ci.draw_rect(Rect2(left, -extra_top - 400, right - left, fl + extra_top + 400), wall)
	# soft vertical stripes
	var sx := left - fmod(left, 80.0)
	while sx < right:
		ci.draw_rect(Rect2(sx, ceil_y, 40, fl - ceil_y), Color(1, 1, 1, 0.16))
		sx += 80
	# wainscot
	ci.draw_rect(Rect2(left, fl - 120, right - left, 120), trim.lightened(0.25))
	ci.draw_rect(Rect2(left, fl - 124, right - left, 6), trim)
	for d in lv.decor:
		match String(d.k):
			"window": _window(ci, Vector2(d.x, d.y), fl, int(d.s))
	# ceiling
	ci.draw_rect(Rect2(left, -extra_top - 400, right - left, ceil_y + extra_top + 400), trim.darkened(0.08))
	ci.draw_rect(Rect2(left, ceil_y - 10, right - left, 10), trim.darkened(0.2))
	for d in lv.decor:
		match String(d.k):
			"lights": _lights(ci, float(d.y), ceil_y, left, right, int(d.s))
			"bunting": _bunting(ci, float(d.y), ceil_y, left, right, int(d.s))
	# side walls (the room ends at 0 and w)
	if extra_side > 0:
		ci.draw_rect(Rect2(left, -extra_top - 400, extra_side, fl + extra_top + 800 + extra_bottom), trim.darkened(0.12))
		ci.draw_rect(Rect2(w, -extra_top - 400, extra_side, fl + extra_top + 800 + extra_bottom), trim.darkened(0.12))
	ci.draw_rect(Rect2(-8, ceil_y, 8, fl - ceil_y), trim.darkened(0.25))
	ci.draw_rect(Rect2(w, ceil_y, 8, fl - ceil_y), trim.darkened(0.25))
	# floor
	ci.draw_rect(Rect2(left, fl, right - left, 400 + extra_bottom), wood)
	var py := fl + 14.0
	var row := 0
	while py < fl + 400 + extra_bottom:
		ci.draw_line(Vector2(left, py), Vector2(right, py), wood.darkened(0.12), 2.0)
		var px := left + float((row * 53) % 120) - 120.0
		while px < right:
			ci.draw_line(Vector2(px, py - 14 if row > 0 else fl), Vector2(px, py), wood.darkened(0.12), 2.0)
			px += 120
		py += 14.0 + row * 2.0
		row += 1
	ci.draw_rect(Rect2(left, fl, right - left, 4), wood.darkened(0.25))


static func _cloud(ci: CanvasItem, p: Vector2, s: float) -> void:
	var c := Color(1, 1, 1, 0.9)
	ci.draw_circle(p, 22 * s, c)
	ci.draw_circle(p + Vector2(24, 6) * s, 18 * s, c)
	ci.draw_circle(p + Vector2(-24, 7) * s, 16 * s, c)
	ci.draw_rect(Rect2(p + Vector2(-26, 6) * s, Vector2(52, 16) * s), c)


static func _tree(ci: CanvasItem, base: Vector2, s: int) -> void:
	var h := 160.0 + s * 30.0
	ci.draw_rect(Rect2(base.x - 7, base.y - h * 0.45, 14, h * 0.45), Color("9a7656"))
	var g: Color = [Color("a8d99a"), Color("94cf86"), Color("b7e0a0")][s % 3]
	ci.draw_circle(base + Vector2(0, -h * 0.62), h * 0.3, g)
	ci.draw_circle(base + Vector2(-h * 0.18, -h * 0.5), h * 0.22, g)
	ci.draw_circle(base + Vector2(h * 0.18, -h * 0.5), h * 0.22, g)


static func _window(ci: CanvasItem, p: Vector2, fl: float, s: int) -> void:
	var w := 80.0
	var top := p.y
	var bottom := fl - 140.0
	if bottom - top < 120.0:
		return
	var frame := Color("ffffff")
	rrect(ci, Rect2(p.x - 6, top - 6, w + 12, bottom - top + 12), frame, 40)
	var glass: Color = [Color("cfe9f7"), Color("d8ecff"), Color("e0f3ea")][s % 3]
	rrect(ci, Rect2(p.x, top, w, bottom - top), glass, 34)
	ci.draw_line(Vector2(p.x + w / 2, top + 4), Vector2(p.x + w / 2, bottom), frame, 4)
	ci.draw_line(Vector2(p.x, top + (bottom - top) * 0.5), Vector2(p.x + w, top + (bottom - top) * 0.5), frame, 4)
	ci.draw_line(Vector2(p.x + 14, top + 30), Vector2(p.x + 28, top + 16), Color(1, 1, 1, 0.8), 3)


static func _catenary(x0: float, x1: float, y: float, sag: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector2(lerpf(x0, x1, t), y + sag * 4.0 * t * (1.0 - t)))
	return pts


static func _lights(ci: CanvasItem, y: float, ceil_y: float, left: float, right: float, s: int) -> void:
	var span := 200.0
	var x := left - fmod(left, span) - span
	var cols := [MUSTARD, Color("fff1b0"), CORAL, SKY]
	while x < right:
		var pts := _catenary(x, x + span, ceil_y, y - ceil_y, 12)
		ci.draw_polyline(pts, Color(0.2, 0.15, 0.2, 0.5), 2.0)
		for i in range(1, 12, 2):
			var c: Color = cols[(i / 2 + s) % cols.size()] if s % 2 == 0 else Color("fff1b0")
			ci.draw_circle(pts[i] + Vector2(0, 6), 9, Color(c, 0.25))
			ci.draw_circle(pts[i] + Vector2(0, 6), 4.5, c)
		x += span


static func _bunting(ci: CanvasItem, y: float, ceil_y: float, left: float, right: float, s: int) -> void:
	var span := 260.0
	var x := left - fmod(left, span) - span
	var cols := [CORAL, MUSTARD, TEAL, LILAC, SKY]
	while x < right:
		var pts := _catenary(x, x + span, ceil_y, y - ceil_y, 10)
		ci.draw_polyline(pts, Color(0.2, 0.15, 0.2, 0.4), 2.0)
		for i in 10:
			var a := pts[i]
			var b := pts[i + 1]
			var m := (a + b) * 0.5 + Vector2(0, 18)
			tri(ci, a, b, m, Color(cols[(i + s) % cols.size()], 0.85))
		x += span


## Things drawn behind the solids (strings, chains, arch flowers, lamp glow).
static func back_decor(ci: CanvasItem, lv: Dictionary) -> void:
	for d in lv.decor:
		match String(d.k):
			"string":
				ci.draw_line(Vector2(d.x, d.y), Vector2(d.x2, d.y2), Color(0.3, 0.25, 0.3, 0.6), 1.5)
			"chain":
				ci.draw_line(Vector2(d.x, d.y), Vector2(d.x2, d.y2), Color("b08a3c"), 3.0)
			"arch":
				_arch(ci, float(d.x), float(d.y), float(d.y2))
			"banner":
				pass


static func _arch(ci: CanvasItem, x: float, top: float, bottom: float) -> void:
	# A ring of flowers framing the opening in the curtain wall.
	var c := Vector2(x, (top + bottom) * 0.5)
	var ry := (bottom - top) * 0.5 + 10
	var rx := 34.0
	ellipse(ci, c, rx + 10, ry + 10, Color(0.55, 0.75, 0.5, 0.5))
	ellipse(ci, c, rx, ry, Color(1, 1, 1, 0.35))
	for i in 18:
		var t := TAU * i / 18.0
		var p := c + Vector2(cos(t) * (rx + 4), sin(t) * (ry + 4))
		ci.draw_circle(p + Vector2(3, 2), 8, Color("6fae5f"))
		flower(ci, p, 9, BLOOM[i % BLOOM.size()])


## Things drawn in front of the solids (centerpieces, cake topper, lamp heads, banner).
static func front_decor(ci: CanvasItem, lv: Dictionary) -> void:
	for d in lv.decor:
		match String(d.k):
			"centerpiece":
				var p := Vector2(d.x, d.y)
				ci.draw_rect(Rect2(p.x - 3, p.y - 22, 6, 22), Color(0.8, 0.9, 1.0, 0.8))
				for i in 4:
					flower(ci, p + Vector2(-9 + i * 6, -24 - (i % 2) * 6), 6, BLOOM[(i + int(d.look)) % BLOOM.size()])
			"topper":
				var q := Vector2(d.x, d.y)
				ci.draw_line(q, q + Vector2(0, -16), INK, 2)
				ci.draw_circle(q + Vector2(-5, -20), 5, CORAL)
				ci.draw_circle(q + Vector2(5, -20), 5, CORAL)
				tri(ci, q + Vector2(-10, -19), q + Vector2(10, -19), q + Vector2(0, -8), CORAL)
			"lamp":
				var l := Vector2(d.x, d.y)
				ci.draw_circle(l + Vector2(0, -6), 22, Color(1, 0.9, 0.5, 0.3))
				rrect(ci, Rect2(l.x - 10, l.y - 18, 20, 20), Color("3a3442"), 4)
				ci.draw_rect(Rect2(l.x - 6, l.y - 14, 12, 12), Color("ffe9a0"))
			"banner":
				var b := Vector2(d.x, d.y)
				var cols := [CORAL, MUSTARD, TEAL]
				for i in 3:
					ci.draw_circle(b + Vector2(-10 + i * 10, -2), 7, cols[i])


static func solid(ci: CanvasItem, s: Dictionary, lv: Dictionary) -> void:
	var k := String(s.k)
	if k == "guest":
		return     # people are drawn by person()
	if String(s.t) == "circle":
		var c := Vector2(s.x, s.y)
		var r := float(s.r)
		match k:
			"balloon":
				var col: Color = BALLOON[int(s.get("look", 0)) % BALLOON.size()]
				ellipse(ci, c, r, r * 1.08, col)
				ellipse(ci, c + Vector2(-r * 0.35, -r * 0.4), r * 0.22, r * 0.32, Color(1, 1, 1, 0.55))
				tri(ci, c + Vector2(-4, r * 1.05), c + Vector2(4, r * 1.05), c + Vector2(0, r * 1.05 - 6), col.darkened(0.15))
			"chandelier":
				ci.draw_circle(c, r + 6, Color(1, 0.95, 0.7, 0.35))
				ci.draw_circle(c, r, Color("e8c66a"))
				ci.draw_circle(c, r - 6, Color("fff1c4"))
				for i in 8:
					var t := TAU * i / 8.0
					ci.draw_circle(c + Vector2(cos(t), sin(t)) * (r - 2), 4, Color("cfe9f7"))
				ci.draw_circle(c + Vector2(0, r + 6), 5, Color("cfe9f7"))
			_:
				ci.draw_circle(c, r, Color("bbbbbb"))
		return
	var rc := Rect2(float(s.x), float(s.y), float(s.w), float(s.h))
	match k:
		"table":
			var cloth: Color = WHITE if int(s.get("look", 0)) == 99 else [WHITE, Color("fdf0f4"), Color("eef7f5"), Color("fdf6e3")][int(s.look) % 4]
			ci.draw_rect(Rect2(rc.position + Vector2(4, 6), rc.size), SOFT_INK)
			rrect(ci, rc, cloth, 6)
			ci.draw_rect(Rect2(rc.position.x, rc.position.y, rc.size.x, 8), cloth.darkened(0.05))
			var swag: Color = CORAL if int(s.get("look", 0)) == 99 else [TEAL, CORAL, LILAC, MUSTARD][int(s.look) % 4]
			var n := maxi(2, int(rc.size.x / 30))
			for i in n:
				var x0 := rc.position.x + rc.size.x * i / n
				var x1 := rc.position.x + rc.size.x * (i + 1) / n
				ci.draw_polyline(_catenary(x0, x1, rc.position.y + 8, 10, 6), Color(swag, 0.7), 3)
		"chair":
			var col := Color("d9a441")
			ci.draw_rect(Rect2(rc.position.x, rc.position.y, 4, rc.size.y), col)
			ci.draw_rect(Rect2(rc.end.x - 4, rc.position.y + rc.size.y * 0.45, 4, rc.size.y * 0.55), col)
			ci.draw_rect(Rect2(rc.position.x, rc.position.y + rc.size.y * 0.45, rc.size.x, 5), col)
			for i in 3:
				ci.draw_rect(Rect2(rc.position.x, rc.position.y + 4 + i * 7, rc.size.x * 0.3, 2), col)
		"cake":
			var tier := int(s.get("look", 0))
			var base: Color = [Color("fffaf3"), Color("fdeef3"), Color("fff7e3")][tier % 3]
			rrect(ci, rc, base, 4)
			var dy := rc.position.y + 5
			var x := rc.position.x
			while x < rc.end.x - 2:
				ci.draw_circle(Vector2(x + 4, dy), 4, Color("ffd1dc"))
				x += 8
			ci.draw_rect(Rect2(rc.position.x, rc.position.y, rc.size.x, 4), Color("ffd1dc"))
			for i in 3:
				ci.draw_circle(Vector2(rc.position.x + rc.size.x * (i + 1) / 4.0, rc.end.y - 7), 3, CORAL)
		"curtain":
			rrect(ci, rc, Color("b9506a"), 4)
			var fx := rc.position.x + 5
			while fx < rc.end.x - 2:
				ci.draw_line(Vector2(fx, rc.position.y), Vector2(fx, rc.end.y), Color("9c3f57"), 2)
				fx += 7
			ci.draw_rect(Rect2(rc.position.x - 4, rc.end.y - 10, rc.size.x + 8, 10), MUSTARD)
		"plant":
			var box := Rect2(rc.position.x, rc.position.y + minf(30, rc.size.y * 0.35), rc.size.x, rc.size.y - minf(30, rc.size.y * 0.35))
			rrect(ci, Rect2(rc.position.x, rc.position.y, rc.size.x, rc.size.y), Color(0.42, 0.68, 0.37), 10)
			rrect(ci, box, Color("c98a5a") if int(s.get("look", 0)) % 2 == 0 else Color("e6e2da"), 4)
			for i in maxi(2, int(rc.size.x / 12)):
				flower(ci, Vector2(rc.position.x + 6 + i * 12, rc.position.y + 8 + (i % 2) * 8), 6, BLOOM[i % BLOOM.size()])
		"hedge":
			rrect(ci, rc, Color("6fb45e"), 18)
			for i in int(rc.size.x / 18):
				ci.draw_circle(Vector2(rc.position.x + 10 + i * 18, rc.position.y + 8), 11, Color("7cc068"))
			for i in int(rc.size.x / 26):
				flower(ci, Vector2(rc.position.x + 14 + i * 26, rc.position.y + 22 + (i % 2) * 14), 5, BLOOM[(i + int(s.get("look", 0))) % BLOOM.size()])
		"balcony":
			rrect(ci, rc, Color("f2e8dd"), 3)
			ci.draw_rect(Rect2(rc.position.x, rc.end.y - 6, rc.size.x, 6), Color("d8c8b6"))
			# balusters behind the target, along the platform
			var bx := rc.position.x + 16
			while bx < rc.end.x - 6:
				ci.draw_rect(Rect2(bx, rc.position.y - 30, 5, 30), Color(0.95, 0.92, 0.88, 0.75))
				bx += 18
			ci.draw_rect(Rect2(rc.position.x, rc.position.y - 32, rc.size.x, 5), Color(0.95, 0.92, 0.88, 0.75))
		"railing":
			rrect(ci, rc, Color("f2e8dd"), 3)
			ci.draw_rect(Rect2(rc.position.x - 2, rc.position.y, rc.size.x + 4, 6), Color("d8c8b6"))
		"pillar":
			var lamp := int(s.get("look", 0)) == 2
			if lamp:
				ci.draw_rect(rc, Color("3a3442"))
			else:
				rrect(ci, rc, Color("f4ede4"), 3)
				var lx := rc.position.x + 6
				while lx < rc.end.x - 3:
					ci.draw_line(Vector2(lx, rc.position.y + 8), Vector2(lx, rc.end.y - 8), Color("ddd2c4"), 2)
					lx += 7
				ci.draw_rect(Rect2(rc.position.x - 4, rc.position.y, rc.size.x + 8, 8), Color("e6dccf"))
				ci.draw_rect(Rect2(rc.position.x - 4, rc.end.y - 8, rc.size.x + 8, 8), Color("e6dccf"))
		_:
			rrect(ci, rc, Color("cccccc"), 4)


# ------------------------------------------------------------------ people

## A guest. feet = bottom centre. arms: 0 down, 1 cheering up (target), 2 throwing pose.
## pose_t animates (bounce / wave); throw_dir is a unit vector for the throwing arm.
static func person(ci: CanvasItem, feet: Vector2, look: int, arms: int, t: float, face := 1, throw_dir := Vector2(1, -1), lean := 0.0) -> void:
	var outfit: Color = OUTFIT[look % OUTFIT.size()]
	var skin: Color = SKIN[(look * 5 + 1) % SKIN.size()]
	var hair: Color = HAIR[(look * 7 + 2) % HAIR.size()]
	var style := (look / 3) % 4
	var w := 34.0
	var h := 74.0
	var body := Rect2(feet.x - w / 2 + lean, feet.y - h, w, h)
	# shadow
	ellipse(ci, feet + Vector2(0, 2), 22, 5, SOFT_INK)
	# legs
	ci.draw_rect(Rect2(feet.x - 11, feet.y - 24, 9, 24), outfit.darkened(0.45))
	ci.draw_rect(Rect2(feet.x + 2, feet.y - 24, 9, 24), outfit.darkened(0.45))
	# torso
	rrect(ci, Rect2(body.position.x, body.position.y + 6, w, h - 26), outfit, 14)
	if style == 1:
		tri(ci, Vector2(body.position.x - 4, feet.y - 18), Vector2(body.end.x + 4, feet.y - 18), Vector2(body.get_center().x, body.position.y + 26), outfit)
	# collar / accessory
	var neck := Vector2(feet.x + lean, body.position.y + 8)
	match look % 4:
		0:
			tri(ci, neck + Vector2(-7, 2), neck + Vector2(0, 6), neck + Vector2(-7, 10), INK)
			tri(ci, neck + Vector2(7, 2), neck + Vector2(0, 6), neck + Vector2(7, 10), INK)
		1:
			ci.draw_rect(Rect2(neck.x - 2, neck.y + 2, 4, 18), outfit.darkened(0.35))
		2:
			for i in 5:
				ci.draw_circle(neck + Vector2(-8 + i * 4, 4 + absf(i - 2) * -1.0 + 3), 2, WHITE)
		_:
			flower(ci, neck + Vector2(9, 8), 5, BLOOM[look % BLOOM.size()])
	# arms
	var sh_l := Vector2(body.position.x + 3, body.position.y + 14)
	var sh_r := Vector2(body.end.x - 3, body.position.y + 14)
	var aw := 7.0
	match arms:
		1:
			var wv := sin(t * 7.0) * 4.0
			ci.draw_line(sh_l, sh_l + Vector2(-10 + wv, -52), outfit.darkened(0.12), aw)
			ci.draw_line(sh_r, sh_r + Vector2(10 - wv, -52), outfit.darkened(0.12), aw)
			ci.draw_circle(sh_l + Vector2(-10 + wv, -54), 5.5, skin)
			ci.draw_circle(sh_r + Vector2(10 - wv, -54), 5.5, skin)
		2:
			var back := sh_l if face > 0 else sh_r
			var front := sh_r if face > 0 else sh_l
			ci.draw_line(back, back + Vector2(-6 * face, 24), outfit.darkened(0.12), aw)
			ci.draw_circle(back + Vector2(-6 * face, 26), 5, skin)
			var hand := front + throw_dir * 30.0
			ci.draw_line(front, hand, outfit.darkened(0.12), aw)
			ci.draw_circle(hand, 5, skin)
		_:
			ci.draw_line(sh_l, sh_l + Vector2(-5, 26), outfit.darkened(0.12), aw)
			ci.draw_line(sh_r, sh_r + Vector2(5, 26), outfit.darkened(0.12), aw)
			ci.draw_circle(sh_l + Vector2(-5, 28), 5, skin)
			ci.draw_circle(sh_r + Vector2(5, 28), 5, skin)
	# head
	var head := Vector2(feet.x + lean, feet.y - h - 16 + 2)
	ci.draw_circle(head, 16, skin)
	match style:
		0:
			ci.draw_arc(head, 16, PI * 1.05, PI * 1.95, 12, hair, 9)
		1:
			ci.draw_arc(head, 15, PI * 0.85, PI * 2.15, 14, hair, 8)
			ci.draw_circle(head + Vector2(-15, 6), 6, hair)
			ci.draw_circle(head + Vector2(15, 6), 6, hair)
		2:
			ci.draw_circle(head + Vector2(0, -12), 9, hair)
			ci.draw_arc(head, 16, PI * 1.1, PI * 1.9, 10, hair, 6)
		_:
			for i in 7:
				ci.draw_circle(head + Vector2(cos(PI + PI * i / 6.0), sin(PI + PI * i / 6.0)) * 15, 5, hair)
	# face
	var fx := 3.0 * face
	ci.draw_circle(head + Vector2(-5 + fx, -1), 2, INK)
	ci.draw_circle(head + Vector2(5 + fx, -1), 2, INK)
	ci.draw_arc(head + Vector2(fx, 4), 5, 0.2, PI - 0.2, 8, INK, 2)
	ci.draw_circle(head + Vector2(-9 + fx, 5), 3, Color(1, 0.5, 0.55, 0.35))
	ci.draw_circle(head + Vector2(9 + fx, 5), 3, Color(1, 0.5, 0.55, 0.35))


## The bouquet, centred at p, radius ~11, spun by rot.
static func bouquet(ci: CanvasItem, p: Vector2, rot: float, scale := 1.0) -> void:
	var s := scale
	var down := Vector2(sin(rot), cos(rot))
	var side := Vector2(down.y, -down.x)
	# stems + ribbon
	var st := p + down * 6 * s
	ci.draw_line(st, st + down * 12 * s + side * 3 * s, Color("5e9a4a"), 3 * s)
	ci.draw_line(st, st + down * 12 * s - side * 3 * s, Color("5e9a4a"), 3 * s)
	ci.draw_line(st + down * 3 * s - side * 5 * s, st + down * 3 * s + side * 5 * s, CORAL, 4 * s)
	tri(ci, st + down * 3 * s, st + down * 10 * s + side * 7 * s, st + down * 8 * s + side * 2 * s, CORAL)
	# leaves
	ci.draw_circle(p + side * 9 * s + down * 2 * s, 4 * s, Color("7cc068"))
	ci.draw_circle(p - side * 9 * s + down * 2 * s, 4 * s, Color("7cc068"))
	# blooms
	ci.draw_circle(p, 10 * s, Color("ffe4ec"))
	var offs := [Vector2(0, 0), Vector2(-6, -3), Vector2(6, -3), Vector2(-3, 4), Vector2(4, 4), Vector2(0, -7)]
	var cols := [Color("ff6b8b"), Color("ffd166"), Color("ffffff"), Color("c8a2ff"), Color("f78c6b"), Color("ff8fab")]
	for i in offs.size():
		var o: Vector2 = offs[i]
		var q := p + (side * o.x + down * o.y) * s
		ci.draw_circle(q, 4.2 * s, cols[i])
		ci.draw_circle(q, 1.6 * s, Color(1, 1, 1, 0.7) if i != 2 else MUSTARD)
