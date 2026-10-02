class_name BridgeSim
extends RefCounted
## Deterministic 2D bridge physics: an XPBD truss (beams = distance constraints that report
## their force and snap when it exceeds the material's strength) plus a two-wheeled vehicle
## that rolls on road beams and loads the joints it touches.
## Units: metres, kilograms, seconds. +y is down. The deck level and both cliff tops are y = 0.
## Fixed timestep and fixed solve order, so the same design gives the same run everywhere.

const G := 9.81
const FRAME_DT := 1.0 / 60.0
const SUBSTEPS := 24
const H := FRAME_DT / SUBSTEPS
const DAMPING := 0.35          # per second, keeps a broken bridge from swinging forever
const WATER_Y := 6.0
const MAX_TIME := 30.0
const MAX_LEN := 4.0           # longest single beam, in metres (grid units)
const BUCKLE_LEN := 2.3        # beams longer than this lose compression strength (Euler: ~1/L²)
const JOINT_MASS := 1.5

enum Mat { ROAD, WOOD }
const MAT_NAME := ["Road", "Wood"]
const DENSITY := [12.0, 5.0]          # kg per metre
const STIFFNESS := [2.5e6, 2.0e6]     # EA in newtons; beam stiffness k = EA / length
const STRENGTH := [11000.0, 13500.0]   # newtons of tension or compression before it snaps
const COST := [15, 10]                # material per metre

const VEHICLES := [
	{"name": "Hatchback", "mass": 320.0, "base": 1.5, "r": 0.33, "speed": 4.5, "color": "e8584a"},
	{"name": "Camper van", "mass": 480.0, "base": 1.9, "r": 0.38, "speed": 4.0, "color": "4aa3e8"},
	{"name": "Pickup truck", "mass": 620.0, "base": 2.2, "r": 0.42, "speed": 3.6, "color": "f2b33d"},
]

# level
var gap := 10
var vehicle: Dictionary = {}
var statics: Array = []        # [Vector2, Vector2] terrain segments

# nodes (wheels are nodes too)
var px := PackedFloat64Array()
var py := PackedFloat64Array()
var ox := PackedFloat64Array()
var oy := PackedFloat64Array()
var inv := PackedFloat64Array()
var node_grid: Array = []      # Vector2i per bridge node (grid position at build time)

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
var progress := -99.0          # furthest the front wheel got, metres past the left edge
var progress_t := 0.0          # when progress last moved on


## level: {gap:int, anchors:Array[Vector2i], pillar_h:int, vehicle:int}
## design: Array of {p:Vector2i, q:Vector2i, m:int}
func setup(level: Dictionary, design: Array) -> void:
	gap = int(level.gap)
	vehicle = VEHICLES[int(level.vehicle)]
	_build_statics(level)
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
		var gp: Vector2i = b.p
		var gq: Vector2i = b.q
		var L := Vector2(gp).distance_to(Vector2(gq))
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
	# vehicle: rear wheel w0, front wheel w1, resting on the left cliff
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
	_push_node(float(g.x), float(g.y), 0.0 if fixed else 1.0 / JOINT_MASS)


func _push_node(x: float, y: float, w: float) -> int:
	px.append(x)
	py.append(y)
	ox.append(x)
	oy.append(y)
	inv.append(w)
	return px.size() - 1


func bridge_node_count() -> int:
	return node_grid.size()


static func terrain_segments(level: Dictionary) -> Array:
	var g := float(level.gap)
	var s: Array = [
		[Vector2(-40, 0), Vector2(0, 0)], [Vector2(0, 0), Vector2(0, 12)],
		[Vector2(g, 0), Vector2(g + 40, 0)], [Vector2(g, 12), Vector2(g, 0)],
	]
	var h := float(level.get("pillar_h", 0))
	if h > 0.0:
		var c := g * 0.5
		s.append([Vector2(c - 0.5, h), Vector2(c + 0.5, h)])
		s.append([Vector2(c - 0.5, 12), Vector2(c - 0.5, h)])
		s.append([Vector2(c + 0.5, h), Vector2(c + 0.5, 12)])
	return s


func _build_statics(level: Dictionary) -> void:
	statics = terrain_segments(level)


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

static func beam(p: Vector2i, q: Vector2i, m: int) -> Dictionary:
	return {"p": p, "q": q, "m": m}


## A plain Warren truss over the deck: 2 m road panels, a 2 m deep top chord.
## The daily budget is derived from its cost, so every day is solvable.
static func reference_design(level: Dictionary, height := 2) -> Array:
	var g := int(level.gap)
	var d: Array = []
	var x := 0
	while x < g:
		d.append(beam(Vector2i(x, 0), Vector2i(x + 2, 0), Mat.ROAD))
		var top := Vector2i(x + 1, -height)
		d.append(beam(Vector2i(x, 0), top, Mat.WOOD))
		d.append(beam(top, Vector2i(x + 2, 0), Mat.WOOD))
		if x + 2 < g:
			d.append(beam(top, Vector2i(x + 3, -height), Mat.WOOD))
		x += 2
	return d


## Pillar days (pillar top 2 m below the deck, mid-gap): props from the pillar up to the deck,
## optionally with a truss on top as well.
static func pillar_design(level: Dictionary, truss_h := 0) -> Array:
	var g := int(level.gap)
	var c := g / 2
	var d: Array = []
	if truss_h > 0:
		d = reference_design(level, truss_h)
	else:
		var x := 0
		while x < g:
			d.append(beam(Vector2i(x, 0), Vector2i(x + 2, 0), Mat.ROAD))
			x += 2
	var top := Vector2i(c, 2)
	if c % 2 == 0:
		d.append(beam(top, Vector2i(c, 0), Mat.WOOD))
	else:
		d.append(beam(top, Vector2i(c - 1, 0), Mat.WOOD))
		d.append(beam(top, Vector2i(c + 1, 0), Mat.WOOD))
	return d


## The candidate designs the daily budget is measured against.
static func candidates(level: Dictionary) -> Array:
	var c: Array = [reference_design(level, 1), reference_design(level, 2)]
	if int(level.get("pillar_h", 0)) > 0:
		c.append(pillar_design(level, 0))
		c.append(pillar_design(level, 1))
	return c


static func beam_cost(b: Dictionary) -> int:
	var p: Vector2i = b.p
	var q: Vector2i = b.q
	return roundi(Vector2(p).distance_to(Vector2(q)) * float(COST[int(b.m)]))


static func design_cost(design: Array) -> int:
	var c := 0
	for b in design:
		c += beam_cost(b)
	return c
