extends Node2D
## World rendering: the venue (art), the density/risk heat layer, the crowd (one MultiMesh) and the
## operational layer drawn above the crowd (gates, signs, barriers, overlays, previews).
## Everything is in world pixels: metres * PPM. Labels are drawn crisp in screen space by ui.gd.
## This node only *shows* simulation state; it never changes it.

const PPM := 8.0

const C_GRASS := Color("21352a")
const C_GRASS_DARK := Color("1c2e24")
const C_PAVING := Color("d8d2c4")
const C_PAVING_LINE := Color("c9c2b2")
const C_WALL := Color("4a545d")
const C_BUILDING := Color("323c46")
const C_BUILDING_EDGE := Color("46525e")
const C_ROOF_LINE := Color("3b4652")
const C_STADIUM := Color("2b333b")
const C_SEATS := Color("3c4752")
const C_PITCH := Color("3c7a48")
const C_PITCH_LINE := Color("cfe8d3")
const C_TREE := Color("2c5638")
const C_TREE_DARK := Color("234530")
const C_OPEN := Color("2f9e44")
const C_METER := Color("f59f00")
const C_CLOSED := Color("e03131")
const C_DANGER := Color("ff3b3b")
const C_FARE := Color("5c6f82")
const C_BARRIER := Color("ffd43b")
const C_BARRIER_DARK := Color("2b2b2b")
const C_SELECT := Color("ffffff")
const C_ZONE := Color(1, 0.83, 0.23, 0.55)
const C_STEWARD := Color("c6f432")       # hi-vis vests
const C_STEWARD_EDGE := Color("1f2a07")
const C_LANE := Color("4dabf7")
const C_ONEWAY := Color("e8590c")
const DEST_COLORS := [Color("0b7a8a"), Color("c2410c"), Color("7048e8"), Color("2b8a3e")]
const PROFILE_COLORS := [Color("1c7ed6"), Color("f08c00"), Color("2f9e44"), Color("e03131"), Color("ae3ec9"), Color("495057"), Color("0ca678"), Color("d6336c")]

var main: Node                  # owner with state (scenario, telemetry, selection, overlays, ...)
var sc: Dictionary = {}
var heat: Sprite2D
var crowd: MultiMeshInstance2D
var top: Node2D
var crowd_mat: ShaderMaterial
var heat_mat: ShaderMaterial
var _heat_img: Image
var _heat_tex: ImageTexture
var _dims := Vector3i.ZERO      # density cols, rows, cell (cm)
var flow_cells := PackedByteArray()
var count := 0


func setup(owner_node: Node, scenario: Dictionary) -> void:
	main = owner_node
	sc = scenario
	heat = Sprite2D.new()
	heat.centered = false
	heat.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	heat_mat = ShaderMaterial.new()
	heat_mat.shader = load("res://shaders/heat.gdshader")
	heat.material = heat_mat
	heat.visible = false
	add_child(heat)
	crowd = MultiMeshInstance2D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	# the default bounds come from the unit quad at the origin, which would cull the whole crowd
	# whenever the origin is off screen: cover the map instead (local units are metres)
	mm.custom_aabb = AABB(Vector3(-50, -50, -1), Vector3(float(sc.map.size[0]) + 100, float(sc.map.size[1]) + 100, 2))
	crowd.multimesh = mm
	crowd.scale = Vector2(PPM, PPM)
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = load("res://shaders/crowd.gdshader")
	var dc := PackedVector4Array()
	for c in DEST_COLORS:
		dc.append(Vector4(c.r, c.g, c.b, 1))
	var pc := PackedVector4Array()
	for c in PROFILE_COLORS:
		pc.append(Vector4(c.r, c.g, c.b, 1))
	crowd_mat.set_shader_parameter("dest_colors", dc)
	crowd_mat.set_shader_parameter("profile_colors", pc)
	crowd.material = crowd_mat
	add_child(crowd)
	top = Node2D.new()
	top.draw.connect(_draw_top)
	add_child(top)
	queue_redraw()


func set_density_dims(cols: int, rows: int, cell: float) -> void:
	_dims = Vector3i(cols, rows, int(cell * 100))
	heat.scale = Vector2(cell * PPM, cell * PPM)


## Upload the latest crowd buffer (16 floats per person, built by Rust).
func set_crowd(buffer: PackedFloat32Array) -> void:
	var n := buffer.size() / 16
	var mm := crowd.multimesh
	if mm.instance_count != n:
		mm.instance_count = n
	if n > 0:
		mm.buffer = buffer
	count = n


func set_density(bytes: PackedByteArray) -> void:
	if _dims.x == 0 or bytes.size() != _dims.x * _dims.y * 4:
		return
	flow_cells = bytes
	if _heat_img == null:
		_heat_img = Image.create_from_data(_dims.x, _dims.y, false, Image.FORMAT_RGBA8, bytes)
		_heat_tex = ImageTexture.create_from_image(_heat_img)
		heat.texture = _heat_tex
	else:
		_heat_img.set_data(_dims.x, _dims.y, false, Image.FORMAT_RGBA8, bytes)
		_heat_tex.update(_heat_img)


func set_frame(alpha: float, zoom: float, color_mode: int, heat_mode: int) -> void:
	crowd_mat.set_shader_parameter("alpha", alpha)
	crowd_mat.set_shader_parameter("mode", color_mode)
	crowd_mat.set_shader_parameter("detail", clampf((zoom - 0.9) / 0.8, 0.0, 1.0))
	# keep people visible when zoomed far out
	crowd_mat.set_shader_parameter("draw_scale", lerpf(2.6, 1.5, clampf((zoom - 0.6) / 1.2, 0.0, 1.0)))
	heat.visible = heat_mode >= 0
	if heat_mode >= 0:
		heat_mat.set_shader_parameter("mode", heat_mode)


static func m2p(v) -> Vector2:
	return Vector2(v[0], v[1]) * PPM


static func rect_px(r) -> Rect2:
	return Rect2(r[0] * PPM, r[1] * PPM, r[2] * PPM, r[3] * PPM)


# ------------------------------------------------------------------ base map (art)

func _draw() -> void:
	if sc.is_empty():
		return
	var size: Vector2 = m2p(sc.map.size)
	draw_rect(Rect2(Vector2(-400, -400), size + Vector2(800, 800)), C_GRASS)
	# mown stripes
	var x := -400.0
	while x < size.x + 400:
		draw_rect(Rect2(x, -400, 48, size.y + 800), C_GRASS_DARK)
		x += 96
	var decor: Dictionary = sc.map.get("decor", {})
	for b in decor.get("buildings", []):
		var r := rect_px(b.rect)
		draw_rect(r, C_BUILDING)
		draw_rect(r, C_BUILDING_EDGE, false, 2.0)
		var y := r.position.y + 12
		while y < r.end.y - 6:
			draw_line(Vector2(r.position.x + 6, y), Vector2(r.end.x - 6, y), C_ROOF_LINE, 1.0)
			y += 14
	if decor.has("stadium"):
		_draw_stadium(rect_px(decor.stadium))
	for w in sc.map.walkable:
		draw_rect(rect_px(w), C_PAVING)
	# paving joints every 2 m
	for w in sc.map.walkable:
		var r := rect_px(w)
		var gx := ceilf(r.position.x / 16.0) * 16.0
		while gx < r.end.x:
			draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), C_PAVING_LINE, 1.0)
			gx += 16.0
		var gy := ceilf(r.position.y / 16.0) * 16.0
		while gy < r.end.y:
			draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), C_PAVING_LINE, 1.0)
			gy += 16.0
	for a in sc.map.areas:
		if a.get("speed_factor", 1.0) < 1.0:
			_draw_stairs(rect_px(a.rect))
	for w in sc.map.get("walls", []):
		draw_line(Vector2(w[0], w[1]) * PPM, Vector2(w[2], w[3]) * PPM, C_WALL, 4.0)
	for t in decor.get("trees", []):
		var p := m2p(t)
		draw_circle(p + Vector2(3, 4), 15, Color(0, 0, 0, 0.18))
		draw_circle(p, 15, C_TREE)
		draw_circle(p + Vector2(-4, -4), 9, C_TREE.lightened(0.12))
	# car park bays and a few parked cars (art)
	for a in sc.map.areas:
		if a.get("kind", "") == "parking":
			var r := rect_px(a.rect)
			var bay := Color("b9b2a3")
			var by := r.position.y + 40
			while by < r.end.y - 30:
				for k in range(int(r.size.x / 22.0)):
					var bx := r.position.x + 30 + k * 22
					if bx + 18 > r.end.x - 8:
						break
					draw_line(Vector2(bx, by), Vector2(bx, by + 36), bay, 1.5)
					if (k * 7 + int(by)) % 5 < 2:
						var car := Color("5c7c99") if (k + int(by / 10)) % 3 == 0 else (Color("9a4e46") if k % 2 == 0 else Color("6f7378"))
						draw_rect(Rect2(bx + 3, by + 4, 13, 28), car)
						draw_rect(Rect2(bx + 5, by + 10, 9, 8), Color(1, 1, 1, 0.25))
				by += 64
	# platform edge
	for a in sc.map.areas:
		if a.get("kind", "") == "platform":
			var r := rect_px(a.rect)
			draw_rect(Rect2(r.end.x - 10, r.position.y, 10, r.size.y), Color("f4d35e"))
			draw_rect(Rect2(r.end.x, r.position.y - 8, 40, r.size.y + 16), Color("3a3f45"))
			for k in 6:
				draw_rect(Rect2(r.end.x + 8, r.position.y + k * r.size.y / 6.0 + 4, 24, r.size.y / 6.0 - 8), Color("5f6b77"))


func _draw_stadium(r: Rect2) -> void:
	draw_rect(r, C_STADIUM)
	var inner := r.grow(-14)
	for k in 5:
		draw_rect(inner.grow(-k * 10), C_SEATS.lerp(C_STADIUM, k * 0.12), false, 5.0)
	var pitch := r.grow(-70)
	draw_rect(pitch, C_PITCH)
	draw_rect(pitch.grow(-6), C_PITCH_LINE, false, 1.5)
	draw_line(Vector2(pitch.position.x + 6, pitch.get_center().y), Vector2(pitch.end.x - 6, pitch.get_center().y), C_PITCH_LINE, 1.5)
	draw_arc(pitch.get_center(), 22, 0, TAU, 32, C_PITCH_LINE, 1.5)
	# exits on the right wall
	for d in sc.get("spawn_schedules", []):
		for door in d.doors:
			var s := rect_px(door.spawn)
			draw_rect(Rect2(r.end.x - 10, s.position.y + 4, 12, s.size.y - 8), C_PAVING)


func _draw_stairs(r: Rect2) -> void:
	var x := r.position.x + 4
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(0, 0, 0, 0.10), 2.0)
		x += 7


# ------------------------------------------------------------------ operational layer

func _draw_top() -> void:
	if main == null or sc.is_empty():
		return
	var t: Dictionary = main.telemetry
	var ov: Dictionary = main.overlays
	var zoom: float = main.camera.zoom.x
	var lw := 2.0 / zoom
	# placement zones (only scenarios that restrict placement have any) while drawing
	if main.tool != "select":
		for z in sc.map.get("barrier_zones", []):
			_dashed_rect(rect_px(z.rect), C_ZONE, lw * 1.5, 10.0 / zoom)
	# flow arrows
	if ov.get("flow", false) and flow_cells.size() > 0:
		_draw_flow(zoom)
	# routes: where people are heading next
	if ov.get("routes", false):
		_draw_routes(t, zoom)
	# gates
	var gates_t := {}
	for g in t.get("gates", []):
		gates_t[g.id] = g
	for g in sc.gates:
		var a := Vector2(g.line[0], g.line[1]) * PPM
		var b := Vector2(g.line[2], g.line[3]) * PPM
		var gt: Dictionary = gates_t.get(g.id, {})
		var mode: String = gt.get("mode", g.default_mode)
		var col := C_FARE
		if g.get("controllable", false):
			col = C_OPEN if mode == "open" else (C_METER if mode == "metered" else C_CLOSED)
		elif gt.get("service_factor", 1.0) < 1.0:
			col = C_METER
		var sel: Dictionary = main.selection
		if sel.get("kind", "") == "gate" and sel.get("id", "") == g.id:
			draw_line_on(top, a, b, C_SELECT, lw * 6.0)
		if mode == "closed":
			draw_line_on(top, a, b, col, lw * 3.5)
			var mid := (a + b) * 0.5
			var s := 6.0 / zoom
			top.draw_line(mid + Vector2(-s, -s), mid + Vector2(s, s), Color.WHITE, lw)
			top.draw_line(mid + Vector2(-s, s), mid + Vector2(s, -s), Color.WHITE, lw)
		else:
			# turnstile posts between lanes
			var lanes: int = g.lanes
			draw_line_on(top, a, b, Color(col, 0.35), lw * 2.0)
			for k in lanes + 1:
				var p := a.lerp(b, float(k) / lanes)
				top.draw_circle(p, lw * 1.6, col)
		# queue bars
		if ov.get("queues", false) and gt.get("queue", 0) > 0:
			var q: int = gt.queue
			var n := (b - a).normalized().orthogonal()
			var mid := (a + b) * 0.5
			var up := -n if n.dot(m2p(_node_pos(g.node)) - mid) > 0 else n
			top.draw_line(mid, mid + up * minf(q, 150) * 0.8 * PPM * 0.25, Color(C_METER, 0.85), lw * 4.0)
	# signs
	for s in sc.get("signs", []):
		var p := m2p(s.pos)
		var on := false
		for st in t.get("signs", []):
			if st.id == s.id:
				on = st.mode != "off"
		var sel: Dictionary = main.selection
		var r := Rect2(p - Vector2(14, 9), Vector2(28, 18))
		if sel.get("kind", "") == "sign" and sel.get("id", "") == s.id:
			top.draw_rect(r.grow(4), C_SELECT, false, lw * 1.5)
			top.draw_arc(p, s.radius * PPM, 0, TAU, 64, Color(1, 1, 1, 0.35), lw)
		top.draw_rect(Rect2(p + Vector2(-1.5, 9), Vector2(3, 10)), C_WALL)
		top.draw_rect(r, Color("1e2328"))
		top.draw_rect(r, Color("596470"), false, 1.5)
		var led := Color("ffb627") if on else Color("3a4148")
		for k in 3:
			top.draw_rect(Rect2(r.position + Vector2(5, 4 + k * 4), Vector2(18 if on else 10, 2)), led)
	# fences, steward lines and arrows (arrows first: they are floor markings)
	var placed: Array = t.get("barriers", [])
	for pass_i in 2:
		for bar in placed:
			var kind: String = bar.get("kind", "fence")
			if (kind == "arrow") != (pass_i == 0):
				continue
			var pts := PackedVector2Array()
			for q in bar.get("points", [bar.a, bar.b]):
				pts.append(Vector2(q.x, q.y) * PPM)
			var selected: bool = main.selection.get("kind", "") == "barrier" and int(main.selection.get("id", -1)) == int(bar.id)
			match kind:
				"arrow":
					_draw_lane(pts, bool(bar.get("one_way", false)), lw, selected, 1.0)
				"stewards":
					_draw_stewards(pts[0], pts[pts.size() - 1], bool(bar.get("hold", true)), lw, selected)
				_:
					for i in range(1, pts.size()):
						_draw_barrier(pts[i - 1], pts[i], lw, selected)
	# what is being drawn
	if main.drag_active and main.draw_points.size() >= 2:
		var pts := PackedVector2Array()
		for q in main.draw_points:
			pts.append(q * PPM)
		var ok: bool = main.preview_ok
		match main.tool:
			"arrow", "oneway":
				_draw_lane(pts, main.tool == "oneway", lw, false, 0.6 if ok else 0.3)
			"stewards":
				_draw_stewards(pts[0], pts[pts.size() - 1], true, lw, false)
			_:
				for i in range(1, pts.size()):
					top.draw_line(pts[i - 1], pts[i], Color(C_BARRIER, 0.7), lw * 4.0)
		if not ok:
			for i in range(1, pts.size()):
				top.draw_line(pts[i - 1], pts[i], Color(C_CLOSED, 0.8), lw * 2.0)
		top.draw_circle(pts[0], lw * 3.0, Color.WHITE)
		top.draw_circle(pts[pts.size() - 1], lw * 3.0, Color.WHITE)
	# dangerous crowding (staff alarm, never delayed): the whole area outlined in red
	for at in t.get("areas", []):
		if at.get("alarm", false):
			for a in sc.map.areas:
				if a.id == at.id:
					var ar := rect_px(a.rect)
					top.draw_rect(ar, Color(C_DANGER, 0.14))
					top.draw_rect(ar, C_DANGER, false, lw * 3.0)
	# selected area outline
	var sel: Dictionary = main.selection
	if sel.get("kind", "") == "area":
		for a in sc.map.areas:
			if a.id == sel.id:
				top.draw_rect(rect_px(a.rect), C_SELECT, false, lw * 1.5)
	# inspector target
	if sel.get("kind", "") == "person" and main.inspected is Dictionary and main.inspected.has("pos"):
		var p := Vector2(main.inspected.pos[0], main.inspected.pos[1]) * PPM
		top.draw_arc(p, 6.0, 0, TAU, 24, C_SELECT, lw)


func draw_line_on(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, w: float) -> void:
	ci.draw_line(a, b, c, w)


func _node_pos(id: String) -> Array:
	for n in sc.nodes:
		if n.id == id:
			return n.pos
	return [0, 0]


func _draw_barrier(a: Vector2, b: Vector2, lw: float, selected: bool) -> void:
	if selected:
		top.draw_line(a, b, C_SELECT, lw * 7.0)
	top.draw_line(a, b, C_BARRIER_DARK, lw * 4.0)
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 0.001)
	var seg := 8.0
	var k := 0.0
	var on := true
	while k < len:
		var e := minf(k + seg, len)
		if on:
			top.draw_line(a + dir * k, a + dir * e, C_BARRIER, lw * 3.0)
		on = not on
		k = e
	top.draw_circle(a, lw * 2.2, C_BARRIER_DARK)
	top.draw_circle(b, lw * 2.2, C_BARRIER_DARK)


## A steward line: a row of people in hi-vis vests, arms linked while holding; spaced out and faded
## once they stand aside.
func _draw_stewards(a: Vector2, b: Vector2, hold: bool, lw: float, selected: bool) -> void:
	if selected:
		top.draw_line(a, b, C_SELECT, lw * 7.0)
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 0.001)
	var gap := 1.2 * PPM if hold else 3.0 * PPM
	var n := maxi(2, int(len / gap) + 1)
	var alpha := 1.0 if hold else 0.55
	if hold:
		top.draw_line(a, b, Color(C_STEWARD, 0.85), lw * 2.0)
	var r := 0.32 * PPM
	for k in n:
		var p := a + dir * (len * float(k) / float(n - 1))
		top.draw_circle(p, r + lw, Color(C_STEWARD_EDGE, alpha))
		top.draw_circle(p, r, Color(C_STEWARD, alpha))


## A marked lane: a tinted band with chevrons pointing the way; one-way lanes have orange edges.
func _draw_lane(pts: PackedVector2Array, one_way: bool, lw: float, selected: bool, alpha: float) -> void:
	var half := float(sc.player_resources.get("arrow_width", 8.0)) * 0.5 * PPM
	var col := C_ONEWAY if one_way else C_LANE
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var len := a.distance_to(b)
		if len < 0.01:
			continue
		var dir := (b - a) / len
		var nrm := dir.orthogonal() * half
		var quad := PackedVector2Array([a + nrm, b + nrm, b - nrm, a - nrm])
		top.draw_colored_polygon(quad, Color(col, 0.26 * alpha))
		if selected:
			top.draw_line(a + nrm, b + nrm, C_SELECT, lw * 2.0)
			top.draw_line(a - nrm, b - nrm, C_SELECT, lw * 2.0)
		elif one_way:
			top.draw_line(a + nrm, b + nrm, Color(col, 0.8 * alpha), lw * 1.5)
			top.draw_line(a - nrm, b - nrm, Color(col, 0.8 * alpha), lw * 1.5)
		var step := 6.0 * PPM
		var k := step * 0.5
		var s := half * 0.55
		while k < len:
			var c := a + dir * k
			var tip := c + dir * s * 0.6
			top.draw_line(tip, tip - dir * s + dir.orthogonal() * s, Color(col, 0.9 * alpha), lw * 2.0)
			top.draw_line(tip, tip - dir * s - dir.orthogonal() * s, Color(col, 0.9 * alpha), lw * 2.0)
			k += step


func _dashed_rect(r: Rect2, c: Color, w: float, dash: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		var d := (b - a) / len
		var k := 0.0
		while k < len:
			top.draw_line(a + d * k, a + d * minf(k + dash, len), c, w)
			k += dash * 2.0


func _draw_flow(zoom: float) -> void:
	var cols := _dims.x
	var rows := _dims.y
	var cell := _dims.z / 100.0 * PPM
	var step := 1 if zoom >= 1.4 else 2
	for y in range(0, rows, step):
		for x in range(0, cols, step):
			var i := (y * cols + x) * 4
			var d := flow_cells[i] / 50.0
			if d < 0.15:
				continue
			var v := Vector2((flow_cells[i + 2] - 128) / 60.0, (flow_cells[i + 3] - 128) / 60.0)
			var sp := v.length()
			if sp < 0.08:
				continue
			var c := Vector2((x + 0.5) * cell, (y + 0.5) * cell)
			var dir := v / sp
			var len := cell * step * 0.42 * clampf(sp / 1.2, 0.35, 1.0)
			var col := Color(0.08, 0.32, 0.6, 0.75).lerp(Color(0.75, 0.1, 0.1, 0.85), clampf(1.0 - sp / 1.0, 0.0, 1.0))
			var w := 1.6 / zoom
			top.draw_line(c - dir * len, c + dir * len, col, w)
			top.draw_line(c + dir * len, c + dir * len - dir.rotated(0.5) * len * 0.6, col, w)
			top.draw_line(c + dir * len, c + dir * len - dir.rotated(-0.5) * len * 0.6, col, w)


func _draw_routes(t: Dictionary, zoom: float) -> void:
	var heading: Dictionary = t.get("heading", {})
	var w := 1.0 / zoom
	for e in sc.edges:
		var a := m2p(_node_pos(e.a))
		var b := m2p(_node_pos(e.b))
		var n: int = int(heading.get(e.b, 0))
		var col := Color(0.11, 0.26, 0.45, 0.55)
		top.draw_line(a, b, col, w * (1.5 + minf(n, 300) / 20.0))
	for nd in sc.nodes:
		top.draw_circle(m2p(nd.pos), 4.0 / zoom, Color(0.11, 0.26, 0.45, 0.9))
