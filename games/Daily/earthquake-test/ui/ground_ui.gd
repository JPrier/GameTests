extends RefCounted
## Drawing the ground: the day's terrain shape, styled by its soil, so Bedrock, Firm Ground
## and Soft Soil look like what they are (grey layered rock, packed earth, dark wet mud).
## Everything takes the main scene (`m`) and draws on it in world coordinates via
## m.world_to_screen; `g` is the ground's (drawn) offset from the quake.

const Terrain = preload("res://site/terrain.gd")

const STYLES := {
	"bedrock": {"fill": Color("4f535a"), "top": Color("a7aeb8"), "band": Color("656a72"), "dark": Color(0, 0, 0, 0.3)},
	"firm": {"fill": Color("6a5236"), "top": Color("a8875a"), "band": Color("7a6044"), "dark": Color(0, 0, 0, 0.2)},
	"soft": {"fill": Color("2e241c"), "top": Color("5c4632"), "band": Color("3d3024"), "dark": Color(0, 0, 0, 0.25), "wet": Color("7fa6c4")},
}


static func style(m) -> Dictionary:
	var soil := "firm"
	if m.challenge != null and m.challenge.soil != "":
		soil = m.challenge.soil
	return STYLES.get(soil, STYLES.firm)


static func soil(m) -> String:
	return m.challenge.soil if m.challenge != null and m.challenge.soil != "" else "firm"


## Surface points (world metres) across the board, from beyond the left edge to beyond the right.
static func _surface(m, g: Vector2, x_from: float, x_to: float) -> PackedVector2Array:
	var h: PackedInt32Array = m.ground
	var pts := PackedVector2Array()
	pts.append(Vector2(x_from, h[0] / 100.0 + g.y))
	for i in h.size():
		var x := float(i) + g.x
		if x > x_from and x < x_to:
			pts.append(Vector2(x, h[i] / 100.0 + g.y))
	pts.append(Vector2(x_to, h[-1] / 100.0 + g.y))
	return pts


## The terrain on the board: filled columns, soil texture, and a bright surface edge.
static func draw_board(m, r: Rect2, g: Vector2) -> void:
	var st := style(m)
	var x_from: float = m.screen_to_world(r.position).x - 1.0
	var x_to: float = m.screen_to_world(r.end).x + 1.0
	var bottom: float = m.screen_to_world(r.end).y - 1.0
	var pts := _surface(m, g, x_from, x_to)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var quad := PackedVector2Array([m.world_to_screen(a), m.world_to_screen(b),
			m.world_to_screen(Vector2(b.x, bottom)), m.world_to_screen(Vector2(a.x, bottom))])
		m.draw_colored_polygon(quad, st.fill)
	_texture(m, pts, bottom, st)
	var edge := PackedVector2Array()
	for p in pts:
		edge.append(m.world_to_screen(p))
	m.draw_polyline(edge, st.top, 3.0)


## Horizontal stratum at height `y` wherever it lies inside the ground (not too near the top).
static func _strata(m, pts: PackedVector2Array, x0: float, x1: float, y: float, bottom: float, col: Color) -> void:
	if y <= bottom:
		return
	var start := NAN
	var x := x0
	while x <= x1 + 0.05:
		var inside := x <= x1 and _under(pts, x) > y + 0.25
		if inside and is_nan(start):
			start = x
		elif not inside and not is_nan(start):
			m.draw_line(m.world_to_screen(Vector2(start, y)), m.world_to_screen(Vector2(x - 0.1, y)), col, 2.0)
			start = NAN
		x += 0.1


## Depth below the surface at world x (for texture lines that follow the ground's shape).
static func _under(pts: PackedVector2Array, x: float) -> float:
	for i in pts.size() - 1:
		if x >= pts[i].x and x <= pts[i + 1].x:
			var f := (x - pts[i].x) / maxf(pts[i + 1].x - pts[i].x, 1e-6)
			return lerpf(pts[i].y, pts[i + 1].y, f)
	return pts[-1].y


static func _texture(m, pts: PackedVector2Array, bottom: float, st: Dictionary) -> void:
	var x0: float = pts[0].x
	var x1: float = pts[-1].x
	var gx: float = pts[1].x - floorf(pts[1].x) if pts.size() > 2 else 0.0   # slides with the ground
	match soil(m):
		"bedrock":
			# layered rock: level strata (they run straight through hills and spikes) and cracks
			var gy: float = pts[0].y - m.ground[0] / 100.0   # the ground's vertical offset
			var level := -1.1
			while level < 5.5:
				_strata(m, pts, x0, x1, level + gy, bottom, st.band)
				level += 0.7
			var k := 0
			var x := floorf(x0) + gx
			while x < x1:
				if k % 3 == 1:
					var top: float = _under(pts, x) - 0.15
					var c := PackedVector2Array([m.world_to_screen(Vector2(x, top)), m.world_to_screen(Vector2(x + 0.12, top - 0.18)),
						m.world_to_screen(Vector2(x - 0.04, top - 0.36))])
					if top - 0.36 > bottom:
						m.draw_polyline(c, st.dark, 2.0)
				x += 1.0
				k += 1
		"soft":
			# wet mud: a wobbly darker band under a glossy rim, and little puddles in low spots
			var band := PackedVector2Array()
			var x := x0
			while x <= x1:
				var y: float = _under(pts, x) - 0.3 - 0.07 * sin((x - gx) * 4.0)
				if y > bottom:
					band.append(m.world_to_screen(Vector2(x, y)))
				x += 0.2
			if band.size() > 1:
				m.draw_polyline(band, st.band, maxf(4.0, m.ppm * 0.18))
			# a wet sheen along the top, and puddles and bubbles in the mud
			var gloss := PackedVector2Array()
			x = x0
			while x <= x1:
				gloss.append(m.world_to_screen(Vector2(x, _under(pts, x) - 0.06)))
				x += 0.25
			m.draw_polyline(gloss, Color(st.wet, 0.45), 2.0)
			var k := 0
			x = floorf(x0) + gx + 0.5
			while x < x1:
				var y: float = _under(pts, x)
				var s: Vector2 = m.world_to_screen(Vector2(x, y))
				var flat_here := absf(_under(pts, x + 0.3) - _under(pts, x - 0.3)) < 0.06
				if k % 3 == 1 and flat_here:   # puddles only sit on level mud
					m.draw_line(s + Vector2(-m.ppm * 0.3, 1), s + Vector2(m.ppm * 0.3, 1), Color(st.wet, 0.55), 3.0)
				var b2: Vector2 = m.world_to_screen(Vector2(x + 0.3, y - 0.55 - 0.15 * float(k % 2)))
				if (y - 0.6) > bottom:
					m.draw_arc(b2, maxf(2.0, m.ppm * 0.06), 0, TAU, 10, Color(st.wet, 0.25), 1.5)
				x += 1.0
				k += 1
		_:
			# packed earth: short dashes at a few depths
			var k := 0
			var x := floorf(x0 * 2.0) / 2.0 + fposmod(gx, 0.5)
			while x < x1:
				var y: float = _under(pts, x) - 0.3 - float(k % 3) * 0.28
				if y > bottom:
					var s: Vector2 = m.world_to_screen(Vector2(x, y))
					m.draw_line(s, s + Vector2(m.ppm * 0.3, 0), st.dark, 2.0)
				x += 0.5
				k += 1


## The terrain inside the loupe (`ls` maps world -> loupe screen), clipped to `inner`.
static func draw_loupe(m, ls: Callable, inner: Rect2, wc: Vector2, half: float) -> void:
	var st := style(m)
	var pts := _surface(m, Vector2.ZERO, wc.x - half - 1.0, wc.x + half + 1.0)
	var clip := PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)])
	var bottom := wc.y - half * 2.0 - 1.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var quad := PackedVector2Array([ls.call(a), ls.call(b), ls.call(Vector2(b.x, bottom)), ls.call(Vector2(a.x, bottom))])
		for poly in Geometry2D.intersect_polygons(quad, clip):
			if poly.size() >= 3:
				m.draw_colored_polygon(poly, st.fill)
		var seg: Array = m._clip_seg(ls.call(a), ls.call(b), inner)
		if not seg.is_empty():
			m.draw_line(seg[0], seg[1], st.top, 3.0)
