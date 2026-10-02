class_name BridgeSim
extends RefCounted
## Deterministic 2D bridge physics: an XPBD truss (beams = distance constraints that report
## their force and snap when it exceeds the material's strength) plus a two-wheeled vehicle
## that rolls on road beams and loads the joints it touches.
## Units: metres, kilograms, seconds. +y is down. The left bank's top is y = 0; the right
## bank's top is y = dy. Build points are integer centimetres (Vector2i), so joints can sit
## between grid dots. Fixed timestep and solve order: the same design runs the same everywhere.

const U := 100                 # build points are centimetres
const G := 9.81
const FRAME_DT := 1.0 / 60.0
const SUBSTEPS := 24
const H := FRAME_DT / SUBSTEPS
const DAMPING := 0.35          # per second, keeps a broken bridge from swinging forever
const WATER_Y := 6.5
const MAX_TIME := 30.0
const MAX_LEN := 4.0           # longest single beam, in metres
const BUCKLE_LEN := 2.3        # beams longer than this lose compression strength (Euler: ~1/L²)
const JOINT_MASS := 1.5

enum Mat { ROAD, WOOD }
const MAT_NAME := ["Road", "Wood"]
const DENSITY := [12.0, 5.0]          # kg per metre
const STIFFNESS := [2.5e6, 2.0e6]     # EA in newtons; beam stiffness k = EA / length
const STRENGTH := [11000.0, 13500.0]  # newtons of tension or compression before it snaps
const COST := [15, 10]                # material per metre

const VEHICLES := [
	{"name": "Hatchback", "mass": 550.0, "base": 1.5, "r": 0.33, "speed": 4.5, "color": "e8584a"},
	{"name": "Camper van", "mass": 800.0, "base": 1.9, "r": 0.38, "speed": 4.0, "color": "4aa3e8"},
	{"name": "Pickup truck", "mass": 1050.0, "base": 2.2, "r": 0.42, "speed": 3.6, "color": "f2b33d"},
]
const MAX_GAP := [13, 12, 11]         # longest gap each vehicle gets

# level
var gap := 10
var dy := 0
var vehicle: Dictionary = {}
var statics: Array = []        # [Vector2, Vector2] terrain segments

# nodes (wheels are nodes too)
var px := PackedFloat64Array()
var py := PackedFloat64Array()
var ox := PackedFloat64Array()
var oy := PackedFloat64Array()
var inv := PackedFloat64Array()
var node_grid: Array = []      # Vector2i (cm) per bridge node at build time

# beams
var ba := PackedInt32Array()
var bb := PackedInt32Array()
var rest := PackedFloat64Array()
var mat := PackedInt32Array()
var comp := PackedFloat64Array()   # compliance (1 / k)
var str_t := PackedFloat64Array()  # tension strength
var str_c := PackedFloat64Array()  # compression strength (lower for long, slender beams)
var force := PackedFloat64Array()  # last solved force: + tension, - compression
var load := PackedFloat64Array()   # smoothed |force| / strength
var peak := PackedFloat64Array()   # highest load seen before snapping
var broken := PackedByteArray()

# vehicle
var w0 := -1                   # rear wheel node
var w1 := -1                   # front wheel node
var wheel_r := 0.35
var wheelbase := 1.5
var target_speed := 4.0
var contact_n: Array = [Vector2.ZERO, Vector2.ZERO]
var spin := 0.0                # wheel rotation for drawing

# run
var time := 0.0
var done := false
var crossed := false
var outcome := ""              # "crossed", "splash", "stuck"
var first_break := -1.0
var progress := -99.0          # furthest the front wheel got
var progress_t := 0.0          # when progress last moved on


static func wpos(p: Vector2i) -> Vector2:
	return Vector2(p) / U


static func cm(v: Vector2) -> Vector2i:
	return Vector2i(roundi(v.x * U), roundi(v.y * U))


## level: see make_level(). design: Array of {p:Vector2i cm, q:Vector2i cm, m:int}
func setup(level: Dictionary, design: Array) -> void:
	gap = int(level.gap)
	dy = int(level.dy)
	vehicle = VEHICLES[int(level.vehicle)]
	statics = terrain_segments(level)
	var index := {}
	for a in level.anchors:
		_add_node(a, true, index)
	for b in design:
		_add_node(b.p, false, index)
		_add_node(b.q, false, index)
	for b in design:
		var i: int = index[b.p]
		var j: int = index[b.q]
		var m: int = b.m
		var L := wpos(b.p).distance_to(wpos(b.q))
		ba.append(i)
		bb.append(j)
		rest.append(L)
		mat.append(m)
		comp.append(L / float(STIFFNESS[m]))
		str_t.append(float(STRENGTH[m]))
		str_c.append(float(STRENGTH[m]) * minf(1.0, pow(BUCKLE_LEN / L, 2.0)))
		force.append(0.0)
		load.append(0.0)
		peak.append(0.0)
		broken.append(0)
		var half: float = float(DENSITY[m]) * L * 0.5
		for n: int in [i, j]:
			if inv[n] > 0.0:
				inv[n] = 1.0 / (1.0 / inv[n] + half)
	# vehicle: rear wheel w0, front wheel w1, resting on the left bank
	wheel_r = float(vehicle.r)
	wheelbase = float(vehicle.base)
	target_speed = float(vehicle.speed)
	var wm: float = float(vehicle.mass) * 0.5
	var fx := -3.5
	w1 = _push_node(fx, -wheel_r, 1.0 / wm)
	w0 = _push_node(fx - wheelbase, -wheel_r, 1.0 / wm)
	for w in [w0, w1]:
		ox[w] = px[w] - target_speed * H


func _add_node(g: Vector2i, fixed: bool, index: Dictionary) -> void:
	if index.has(g):
		return
	index[g] = px.size()
	node_grid.append(g)
	var w := wpos(g)
	_push_node(w.x, w.y, 0.0 if fixed else 1.0 / JOINT_MASS)


func _push_node(x: float, y: float, w: float) -> int:
	px.append(x)
	py.append(y)
	ox.append(x)
	oy.append(y)
	inv.append(w)
	return px.size() - 1


func bridge_node_count() -> int:
	return node_grid.size()


# ------------------------------------------------------------------ levels

## Today's level, seeded from the date. Poly Bridge-style variety: gap width, uneven banks,
## anchors down the cliff faces, sometimes a rock ledge jutting out or a pillar mid-gap.
static func make_level(d: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily-bridge:v2:" + d)
	var v := rng.randi_range(0, VEHICLES.size() - 1)
	var g := rng.randi_range(7, int(MAX_GAP[v]))
	var ddy: int = [-2, -1, 0, 0, 1, 2][rng.randi_range(0, 5)]
	var anchors: Array = [Vector2i(0, 0), Vector2i(g * U, ddy * U)]
	var rocks: Array = []           # Rect2 in metres (solid)
	# anchors down each cliff face
	for side in 2:
		var top := 0 if side == 0 else ddy
		var x := 0 if side == 0 else g
		var depths: Array = [1, 2, 3, 4]
		var n := rng.randi_range(1, 2)
		for k in n:
			var dd: int = depths.pop_at(rng.randi_range(0, depths.size() - 1))
			if top + dd < WATER_Y - 1.0:
				anchors.append(Vector2i(x * U, (top + dd) * U))
	# a ledge jutting out from one face, or a pillar mid-gap (or neither)
	var feature := rng.randi_range(0, 9)
	if feature <= 2 and g >= 8:
		var side := rng.randi_range(0, 1)
		var top := 0 if side == 0 else ddy
		var depth := top + rng.randi_range(2, 3)
		var out := rng.randi_range(1, 2)
		var x0 := 0 if side == 0 else g - out
		rocks.append(Rect2(x0, depth, out, 1))
		anchors.append(Vector2i((out if side == 0 else g - out) * U, depth * U))
	elif feature <= 5 and g >= 8:
		var cx := rng.randi_range(3, g - 3)
		var deck_y := ddy * float(cx) / g
		var ptop := int(ceil(deck_y)) + rng.randi_range(2, 3)
		rocks.append(Rect2(cx - 0.5, ptop, 1.0, 20.0))
		anchors.append(Vector2i(cx * U, ptop * U))
	return {"gap": g, "dy": ddy, "vehicle": v, "anchors": anchors, "rocks": rocks}


## Is world point w (metres) inside rock? Points on a surface count as rock unless `surface_ok`.
static func in_rock(level: Dictionary, w: Vector2, surface_ok := false) -> bool:
	var e := 0.01 if surface_ok else -0.01     # e > 0 shrinks the rock: surface points stay outside
	var g := float(level.gap)
	if w.x <= 0.0 - e and w.y >= 0.0 + e:
		return true
	if w.x >= g + e and w.y >= float(level.dy) + e:
		return true
	for r: Rect2 in level.get("rocks", []):
		if r.grow(-e).has_point(w):
			return true
	return false


static func terrain_segments(level: Dictionary) -> Array:
	var g := float(level.gap)
	var d := float(level.dy)
	var s: Array = [
		[Vector2(-40, 0), Vector2(0, 0)], [Vector2(0, 0), Vector2(0, 20)],
		[Vector2(g, d), Vector2(g + 40, d)], [Vector2(g, 20), Vector2(g, d)],
	]
	for r: Rect2 in level.get("rocks", []):
		s.append([r.position, Vector2(r.end.x, r.position.y)])
		s.append([Vector2(r.position.x, r.end.y), r.position])
		s.append([Vector2(r.end.x, r.position.y), r.end])
	return s


# ------------------------------------------------------------------ stepping

## Advance one 1/60 s frame.
func step_frame() -> void:
	if done:
		return
	for _s in SUBSTEPS:
		_substep()
	time += FRAME_DT
	spin += (px[w1] - ox[w1]) / H * FRAME_DT / wheel_r
	if px[w1] > progress + 0.05:
		progress = px[w1]
		progress_t = time
	if minf(px[w0], px[w1]) > float(gap) + 2.0:
		_finish("crossed")
	elif py[w0] > WATER_Y or py[w1] > WATER_Y:
		_finish("splash")
	elif time >= MAX_TIME or time - progress_t > 4.0:
		_finish("stuck")


func _finish(why: String) -> void:
	done = true
	outcome = why
	crossed = why == "crossed"


func _substep() -> void:
	var damp := 1.0 - DAMPING * H
	var n := px.size()
	# drive: wheels in contact accelerate (or brake) toward the target speed along the surface
	for k in 2:
		var w: int = w0 if k == 0 else w1
		var cn: Vector2 = contact_n[k]
		if cn == Vector2.ZERO:
			continue
		var t := Vector2(-cn.y, cn.x)
		if t.x < 0.0:
			t = -t
		var vx := (px[w] - ox[w]) / H
		var vy := (py[w] - oy[w]) / H
		var vt := vx * t.x + vy * t.y
		var dv := clampf(target_speed - vt, -12.0 * H, 7.0 * H)
		ox[w] -= t.x * dv * H
		oy[w] -= t.y * dv * H
	# integrate
	for i in n:
		if inv[i] == 0.0:
			continue
		var vx := (px[i] - ox[i]) * damp
		var vy := (py[i] - oy[i]) * damp + G * H * H
		ox[i] = px[i]
		oy[i] = py[i]
		px[i] += vx
		py[i] += vy
	# beams
	var h2 := H * H
	for b in ba.size():
		if broken[b] == 1:
			continue
		var i := ba[b]
		var j := bb[b]
		var wi := inv[i]
		var wj := inv[j]
		var ws := wi + wj
		if ws == 0.0:
			continue
		var dx := px[j] - px[i]
		var dy := py[j] - py[i]
		var L := sqrt(dx * dx + dy * dy)
		if L < 1e-9:
			continue
		var nx := dx / L
		var ny := dy / L
		var dl := -(L - rest[b]) / (ws + comp[b] / h2)
		px[i] -= wi * nx * dl
		py[i] -= wi * ny * dl
		px[j] += wj * nx * dl
		py[j] += wj * ny * dl
		var f := -dl / h2
		force[b] = f
		var m := mat[b]
		var ld := f / str_t[b] if f > 0.0 else -f / str_c[b]
		load[b] += (ld - load[b]) * 0.06
		if load[b] > 1.0:
			broken[b] = 1
			if first_break < 0.0:
				first_break = time
		elif load[b] > peak[b]:
			peak[b] = load[b]
	# chassis
	_rigid_link(w0, w1, wheelbase)
	# wheel contacts
	for k in 2:
		contact_n[k] = _wheel_contacts(w0 if k == 0 else w1)


func _rigid_link(i: int, j: int, len0: float) -> void:
	var dx := px[j] - px[i]
	var dy := py[j] - py[i]
	var L := sqrt(dx * dx + dy * dy)
	var ws := inv[i] + inv[j]
	if L < 1e-9 or ws == 0.0:
		return
	var dl := -(L - len0) / ws
	px[i] -= inv[i] * dx / L * dl
	py[i] -= inv[i] * dy / L * dl
	px[j] += inv[j] * dx / L * dl
	py[j] += inv[j] * dy / L * dl


## Push the wheel out of every road beam and terrain segment it overlaps; returns the
## combined contact normal (zero when airborne).
func _wheel_contacts(w: int) -> Vector2:
	var normal := Vector2.ZERO
	var r := wheel_r
	for s in statics:
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var hit := _contact(w, a.x, a.y, c.x, c.y, -1, -1)
		if hit != Vector2.ZERO:
			normal += hit
	for b in ba.size():
		if broken[b] == 1 or mat[b] != Mat.ROAD:
			continue
		var i := ba[b]
		var j := bb[b]
		# cheap reject
		if absf(px[w] - (px[i] + px[j]) * 0.5) > rest[b] * 0.5 + r + 0.5:
			continue
		var hit := _contact(w, px[i], py[i], px[j], py[j], i, j)
		if hit != Vector2.ZERO:
			normal += hit
	return normal.normalized() if normal != Vector2.ZERO else Vector2.ZERO


func _contact(w: int, ax: float, ay: float, cx: float, cy: float, i: int, j: int) -> Vector2:
	var dx := cx - ax
	var dy := cy - ay
	var dd := dx * dx + dy * dy
	if dd < 1e-12:
		return Vector2.ZERO
	var t := clampf(((px[w] - ax) * dx + (py[w] - ay) * dy) / dd, 0.0, 1.0)
	var qx := ax + dx * t
	var qy := ay + dy * t
	var ex := px[w] - qx
	var ey := py[w] - qy
	var dist := sqrt(ex * ex + ey * ey)
	if dist >= wheel_r or dist < 1e-9:
		return Vector2.ZERO
	var nx := ex / dist
	var ny := ey / dist
	var wi := inv[i] if i >= 0 else 0.0
	var wj := inv[j] if j >= 0 else 0.0
	var ws := inv[w] + (1.0 - t) * (1.0 - t) * wi + t * t * wj
	var dl := (wheel_r - dist) / ws
	px[w] += inv[w] * nx * dl
	py[w] += inv[w] * ny * dl
	if i >= 0:
		px[i] -= wi * (1.0 - t) * nx * dl
		py[i] -= wi * (1.0 - t) * ny * dl
		px[j] -= wj * t * nx * dl
		py[j] -= wj * t * ny * dl
	return Vector2(nx, ny)


## Run to the end (for tests and score checks). Returns a summary.
func run_to_end() -> Dictionary:
	while not done:
		step_frame()
	return summary()


func summary() -> Dictionary:
	var snapped := 0
	var worst := 0.0
	for b in ba.size():
		if broken[b] == 1:
			snapped += 1
		worst = maxf(worst, peak[b])
	return {"crossed": crossed, "outcome": outcome, "time": snappedf(time, 0.01),
		"snapped": snapped, "peak": snappedf(worst, 0.001), "progress": snappedf(progress, 0.01)}


# ------------------------------------------------------------------ drawing helpers

func node_pos(i: int) -> Vector2:
	return Vector2(px[i], py[i])


func vehicle_angle() -> float:
	return atan2(py[w1] - py[w0], px[w1] - px[w0])


# ------------------------------------------------------------------ reference designs

## A beam between two build points (centimetres).
static func beam(p: Vector2i, q: Vector2i, m: int) -> Dictionary:
	return {"p": p, "q": q, "m": m}


## A beam between two world points (metres).
static func mbeam(p: Vector2, q: Vector2, m: int) -> Dictionary:
	return beam(cm(p), cm(q), m)


## Deck joints from the left bank to the right, in ~2 m panels (metres).
static func deck_points(level: Dictionary, panel := 2.0) -> Array:
	var a := Vector2(0, 0)
	var b := Vector2(float(level.gap), float(level.dy))
	var n := maxi(2, roundi(a.distance_to(b) / panel))
	var pts: Array = []
	for i in n + 1:
		pts.append(wpos(cm(a.lerp(b, float(i) / n))))
	return pts


static func _deck(pts: Array) -> Array:
	var d: Array = []
	for i in pts.size() - 1:
		d.append(mbeam(pts[i], pts[i + 1], Mat.ROAD))
	return d


## Warren truss along the deck: offset h metres above (h > 0) or below (h < 0) the road.
static func _truss(pts: Array, h: float) -> Array:
	var d: Array = []
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[pts.size() - 1]
	var up := Vector2((b - a).y, -(b - a).x).normalized()
	if up.y > 0.0:
		up = -up
	var prev := Vector2.INF
	for i in pts.size() - 1:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		var t := wpos(cm((p + q) * 0.5 + up * h))
		d.append(mbeam(p, t, Mat.WOOD))
		d.append(mbeam(t, q, Mat.WOOD))
		if prev != Vector2.INF:
			d.append(mbeam(prev, t, Mat.WOOD))
		prev = t
	return d


## Props from every non-deck anchor (faces, ledge, pillar) to the nearest deck joint in reach.
static func _props(level: Dictionary, pts: Array) -> Array:
	var d: Array = []
	var deck_a := [Vector2i(0, 0), Vector2i(int(level.gap) * U, int(level.dy) * U)]
	for a: Vector2i in level.anchors:
		if deck_a.has(a):
			continue
		var w := wpos(a)
		var order: Array = []
		for i in range(1, pts.size() - 1):
			order.append([w.distance_to(pts[i]), i])
		order.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var used := 0
		for o in order:
			if float(o[0]) <= MAX_LEN and used < 2:
				d.append(mbeam(w, pts[int(o[1])], Mat.WOOD))
				used += 1
	return d


static func reference_design(level: Dictionary, height := 2.0) -> Array:
	var pts := deck_points(level)
	return _deck(pts) + _truss(pts, height)


static func under_design(level: Dictionary, h := 2.0) -> Array:
	var pts := deck_points(level)
	return _deck(pts) + _truss(pts, -h)


static func double_design(level: Dictionary, top := 2.0, below := 2.0) -> Array:
	var pts := deck_points(level)
	return _deck(pts) + _truss(pts, top) + _truss(pts, -below)


static func props_design(level: Dictionary, top := 0.0) -> Array:
	var pts := deck_points(level)
	var d := _deck(pts) + _props(level, pts)
	if top > 0.0:
		d += _truss(pts, top)
	return d


## True when every beam fits the rules (length, no joints inside rock, no duplicates).
static func design_valid(level: Dictionary, design: Array) -> bool:
	var seen := {}
	var anchors: Array = level.anchors
	for b in design:
		var L := wpos(b.p).distance_to(wpos(b.q))
		if L < 0.05 or L > MAX_LEN + 0.001:
			return false
		for p: Vector2i in [b.p, b.q]:
			if not anchors.has(p) and in_rock(level, wpos(p)):
				return false
		var k := [b.p, b.q] if b.p < b.q else [b.q, b.p]
		if seen.has(k):
			return false
		seen[k] = true
	return true


## Candidate bridges the ideal is measured against, cheapest first.
static func candidates(level: Dictionary) -> Array:
	var c: Array = []
	for h in [1.0, 1.5, 2.0, 2.5]:
		c.append(reference_design(level, h))
		c.append(under_design(level, h))
	for hh in [[1.0, 1.0], [1.5, 1.5], [2.0, 1.5], [2.0, 2.0], [2.5, 2.5]]:
		c.append(double_design(level, hh[0], hh[1]))
	if level.anchors.size() > 2:
		for t in [0.0, 1.0, 1.5, 2.0]:
			c.append(props_design(level, t))
	var ok: Array = []
	for d in c:
		if design_valid(level, d):
			ok.append(d)
	ok.sort_custom(func(x, y): return design_cost(x) < design_cost(y))
	return ok


static func beam_cost(b: Dictionary) -> int:
	return roundi(wpos(b.p).distance_to(wpos(b.q)) * float(COST[int(b.m)]))


static func design_cost(design: Array) -> int:
	var c := 0
	for b in design:
		c += beam_cost(b)
	return c


## Finds today's ideal: runs the candidates cheapest-first until one crosses.
## step() spreads the work over frames so the game stays responsive.
class IdealSearch:
	extends RefCounted
	var level: Dictionary
	var queue: Array = []
	var idx := 0
	var sim: BridgeSim
	var done := false
	var cost := -1
	var design: Array = []

	func _init(lv: Dictionary) -> void:
		level = lv
		queue = BridgeSim.candidates(lv)

	## Advance up to `frames` physics frames. Returns true when finished.
	func step(frames: int) -> bool:
		while frames > 0 and not done:
			if sim == null:
				if idx >= queue.size():
					done = true
					break
				sim = BridgeSim.new()
				sim.setup(level, queue[idx])
			sim.step_frame()
			frames -= 1
			if sim.first_break >= 0.0 and not sim.done:
				sim.done = true              # the ideal must cross without snapping anything
			if sim.done:
				if sim.crossed and sim.first_break < 0.0:
					design = queue[idx]
					cost = BridgeSim.design_cost(design)
					done = true
				else:
					idx += 1
				sim = null
		return done

	func run() -> void:
		while not step(1 << 20):
			pass

	## Index of the ideal in candidates(level), or -1.
	func index() -> int:
		return idx if cost > 0 else -1
