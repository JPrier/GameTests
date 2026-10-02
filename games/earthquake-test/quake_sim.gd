extends RefCounted
## Deterministic 2D truss physics for Earthquake Test.
##
## Joints are point masses, beams are XPBD distance constraints (small-step XPBD: one
## iteration per substep, lambda reset each substep). Anchors are pinned to the ground,
## and the ground follows today's seismogram. A beam snaps when its average axial force
## over a step exceeds the material's strength. Everything runs on a fixed timestep with
## no randomness, so the same design + the same quake gives the same result on every device.
##
## World units: metres, y up, ground at y = 0.

const G := 9.81
const STEP := 1.0 / 60.0
const SUB := 10
const JOINT_MASS := 3.0
const AIR_DAMP := 0.35          # 1/s, global velocity damping
const BEAM_DAMP := 0.6          # fraction of relative axial velocity removed per step
const FRICTION := 0.85          # ground contact friction (0..1 of slip removed per substep)
const SETTLE := 1.5             # seconds of gravity before the shaking starts
const AFTER := 3.0              # seconds after the quake before scoring
const BUCKLE_LEN := 1.8         # beams longer than this lose compression strength ~ (BUCKLE_LEN / L)^2

enum Mat { WOOD, STEEL }
# density kg/m, EA (axial stiffness, N), strength (N), cost per metre
const MATS := [
	{"name": "Wood", "density": 4.0, "ea": 2.5e5, "strength": 6000.0, "cost": 1.0},
	{"name": "Steel", "density": 8.0, "ea": 1.2e6, "strength": 30000.0, "cost": 3.0},
]

# --- structure
var n := 0                       # joints
var px := PackedFloat64Array()
var py := PackedFloat64Array()
var ox := PackedFloat64Array()
var oy := PackedFloat64Array()
var vx := PackedFloat64Array()
var vy := PackedFloat64Array()
var inv_m := PackedFloat64Array()
var anchor := PackedByteArray()
var rest_x := PackedFloat64Array()   # build positions (anchors follow ground from here)
var rest_y := PackedFloat64Array()
var grid_pts: Array = []             # joint index -> Vector2i grid point

var m := 0                       # beams
var ba := PackedInt32Array()
var bb := PackedInt32Array()
var b_rest := PackedFloat64Array()
var b_alpha := PackedFloat64Array()  # compliance (1/stiffness)
var b_strength := PackedFloat64Array()   # tension limit (N)
var b_cstrength := PackedFloat64Array()  # compression limit (N), lower for long beams (buckling)
var b_mat := PackedByteArray()
var b_ok := PackedByteArray()
var b_force := PackedFloat64Array()  # signed avg axial force last step (+ = tension)
var b_peak := PackedFloat64Array()   # peak |force| / strength seen
var broken_at := PackedFloat64Array()

# --- time + ground
var quake = null                 # QuakeProfile (quake.gd)
var t := 0.0
var steps := 0
var gx := 0.0
var gy := 0.0
var total_time := 0.0
var start_height := 0.0


## design: Array of {a: Vector2i, b: Vector2i, m: int}; anchors: Array of Vector2i (y == 0).
func setup(design: Array, anchors: Array, q) -> void:
	quake = q
	total_time = SETTLE + q.duration + AFTER
	var index := {}
	grid_pts.clear()
	var masses: Array = []
	for bdef in design:
		for key in [bdef.a, bdef.b]:
			if not index.has(key):
				index[key] = grid_pts.size()
				grid_pts.append(key)
				masses.append(JOINT_MASS)
	n = grid_pts.size()
	m = design.size()
	px.resize(n); py.resize(n); ox.resize(n); oy.resize(n)
	vx.resize(n); vy.resize(n); inv_m.resize(n); rest_x.resize(n); rest_y.resize(n)
	anchor.resize(n)
	b_rest.resize(m); b_alpha.resize(m); b_strength.resize(m); b_cstrength.resize(m)
	b_force.resize(m); b_peak.resize(m); broken_at.resize(m)
	ba.resize(m)
	bb.resize(m)
	b_mat.resize(m)
	b_ok.resize(m)
	for i in m:
		var bdef: Dictionary = design[i]
		var a: int = index[bdef.a]
		var b: int = index[bdef.b]
		var mat: Dictionary = MATS[int(bdef.m)]
		var len := Vector2(bdef.a).distance_to(Vector2(bdef.b))
		ba[i] = a
		bb[i] = b
		b_rest[i] = len
		b_alpha[i] = len / float(mat.ea)
		b_strength[i] = mat.strength
		b_cstrength[i] = mat.strength * minf(1.0, pow(BUCKLE_LEN / len, 2.0))
		b_mat[i] = int(bdef.m)
		b_ok[i] = 1
		b_force[i] = 0.0
		b_peak[i] = 0.0
		broken_at[i] = -1.0
		masses[a] += mat.density * len * 0.5
		masses[b] += mat.density * len * 0.5
	for j in n:
		var p: Vector2i = grid_pts[j]
		px[j] = p.x
		py[j] = p.y
		ox[j] = p.x
		oy[j] = p.y
		vx[j] = 0.0
		vy[j] = 0.0
		rest_x[j] = p.x
		rest_y[j] = p.y
		anchor[j] = 1 if (p.y == 0 and anchors.has(p)) else 0
		inv_m[j] = 0.0 if anchor[j] == 1 else 1.0 / masses[j]
	t = 0.0
	steps = 0
	gx = 0.0
	gy = 0.0
	start_height = standing_height()


func done() -> bool:
	return t >= total_time - 1e-9


## Seconds into the shaking (negative while settling).
func quake_time() -> float:
	return t - SETTLE


func step() -> void:
	var h := STEP / SUB
	var inv_h2 := 1.0 / (h * h)
	# ease gravity in over the first second so the build settles without a jolt
	var grav := G * smoothstep(0.0, 1.0, t)
	var air := 1.0 - AIR_DAMP * h
	for i in m:
		b_force[i] = 0.0
	for s in SUB:
		var ts := t + h * (s + 1)
		var g: Vector2 = quake.offset(ts - SETTLE)
		var dgx: float = g.x - gx
		gx = g.x
		gy = g.y
		# integrate
		for j in n:
			ox[j] = px[j]
			oy[j] = py[j]
			if anchor[j] == 1:
				px[j] = rest_x[j] + gx
				py[j] = rest_y[j] + gy
				continue
			vy[j] -= grav * h
			vx[j] *= air
			vy[j] *= air
			px[j] += vx[j] * h
			py[j] += vy[j] * h
		# beams
		for i in m:
			if b_ok[i] == 0:
				continue
			var a := ba[i]
			var b := bb[i]
			var w := inv_m[a] + inv_m[b]
			if w == 0.0:
				continue
			var dx := px[b] - px[a]
			var dy := py[b] - py[a]
			var len := sqrt(dx * dx + dy * dy)
			if len < 1e-9:
				continue
			var c := len - b_rest[i]
			var alpha := b_alpha[i] * inv_h2
			var dl := -c / (w + alpha)
			var nx := dx / len
			var ny := dy / len
			px[a] -= nx * dl * inv_m[a]
			py[a] -= ny * dl * inv_m[a]
			px[b] += nx * dl * inv_m[b]
			py[b] += ny * dl * inv_m[b]
			b_force[i] += -dl * inv_h2      # + when stretched (tension)
		# ground contact
		for j in n:
			if anchor[j] == 1:
				continue
			if py[j] < gy:
				py[j] = gy
				var slip := (px[j] - ox[j]) - dgx
				px[j] -= slip * FRICTION
		# velocities
		for j in n:
			vx[j] = (px[j] - ox[j]) / h
			vy[j] = (py[j] - oy[j]) / h
	# axial damping + breakage, once per step
	for i in m:
		if b_ok[i] == 0:
			continue
		var f := b_force[i] / SUB
		b_force[i] = f
		var r := stress_ratio(i)
		if r > b_peak[i]:
			b_peak[i] = r
		if r > 1.0:
			b_ok[i] = 0
			broken_at[i] = t + STEP
			continue
		var a := ba[i]
		var b := bb[i]
		var w := inv_m[a] + inv_m[b]
		if w == 0.0:
			continue
		var dx := px[b] - px[a]
		var dy := py[b] - py[a]
		var len := sqrt(dx * dx + dy * dy)
		if len < 1e-9:
			continue
		var nx := dx / len
		var ny := dy / len
		var rv := (vx[b] - vx[a]) * nx + (vy[b] - vy[a]) * ny
		var k := rv * BEAM_DAMP / w
		vx[a] += nx * k * inv_m[a]
		vy[a] += ny * k * inv_m[a]
		vx[b] -= nx * k * inv_m[b]
		vy[b] -= ny * k * inv_m[b]
	t += STEP
	steps += 1


## |force| / limit for beam i in the last step (> 1 snaps). Compression uses the buckling limit.
func stress_ratio(i: int) -> float:
	var f := b_force[i]
	return f / b_strength[i] if f >= 0.0 else -f / b_cstrength[i]


func run_to_end() -> void:
	while not done():
		step()


## Joints still connected to an anchor through intact beams.
func connected() -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(n)
	var adj: Array = []
	adj.resize(n)
	for j in n:
		adj[j] = []
	for i in m:
		if b_ok[i] == 1:
			adj[ba[i]].append(bb[i])
			adj[bb[i]].append(ba[i])
	var stack: Array = []
	for j in n:
		if anchor[j] == 1:
			seen[j] = 1
			stack.append(j)
	while not stack.is_empty():
		var j: int = stack.pop_back()
		for k in adj[j]:
			if seen[k] == 0:
				seen[k] = 1
				stack.append(k)
	return seen


## Height (m above the ground) of the highest joint still attached to an anchor.
func standing_height() -> float:
	var c := connected()
	var best := 0.0
	for j in n:
		if c[j] == 1 and anchor[j] == 0:
			best = maxf(best, py[j] - gy)
	return best


func broken_count() -> int:
	return b_ok.count(0)
