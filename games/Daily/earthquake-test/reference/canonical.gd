extends RefCounted
## Canonical reference structures. Not player-visible solutions: a fixed family of typical
## designs (tall wood tower, steel tower, wide frame, A-frame, squat steel block, ...) that
## the calibration tool and tests run through the real solver to characterise a day.
## A good day spreads their results; a bad one treats every design about the same.
##
## Each structure is a triangulated truss filling a simple outline: rows of joints every
## `story` metres, joints <= NODE_GAP apart inside the outline's width at that height,
## horizontals within a row, and each joint tied to the joints below it (both diagonals for
## "x" bracing, one alternating diagonal for "single"). Row 0 is the anchors it stands on.
## Outline: starts at the base span and narrows by `taper` m per side per metre of height
## (never faster than the legs can reach) until it is `width` wide (-1 = the base span,
## 0 = a point), drifting sideways by `lean` m per metre. Rows are added until the next
## one would break the day's budget (or a height cap).

const Sim = preload("res://quake_sim.gd")
const Terrain = preload("res://site/terrain.gd")

const U := 100
const GH := 18.0
const MAX_LEN := 3.1
const LINK := 2.4
const NODE_GAP := 1.7
const BASE_TAPER := 0.65

## base: "pair" = the closest pair of anchors, "all" = every anchor.
## mat: [legs, diagonals, horizontals] (0 wood, 1 steel); steel_below: legs steel below this height.
const STRUCTS := {
	"wood_tower": {"name": "tall wood tower", "base": "pair", "width": 1.7, "story": 1.5, "bracing": "x", "mat": [0, 0, 0]},
	"steel_tower": {"name": "tall steel tower", "base": "pair", "width": 1.2, "story": 2.0, "bracing": "x", "mat": [1, 1, 1]},
	"wide_frame": {"name": "wide braced frame", "base": "all", "width": -1.0, "story": 2.0, "bracing": "x", "mat": [0, 0, 0]},
	"a_frame": {"name": "A-frame", "base": "all", "width": 0.0, "taper": 0.45, "story": 1.6, "bracing": "x", "mat": [0, 0, 0]},
	"squat_steel": {"name": "squat steel block", "base": "pair", "width": -1.0, "story": 1.5, "bracing": "x", "mat": [1, 1, 1], "cap": 3.0},
	"steel_spine": {"name": "steel spine", "base": "pair", "width": 1.0, "story": 1.5, "bracing": "x", "mat": [1, 0, 0]},
	"lattice": {"name": "flexible lattice", "base": "pair", "width": 1.7, "story": 2.2, "bracing": "single", "mat": [0, 0, 0]},
	"lean_tower": {"name": "leaning tower", "base": "pair", "width": 1.7, "story": 1.6, "bracing": "x", "mat": [0, 0, 0], "lean": 0.25},
	"mixed_tower": {"name": "steel-base tower", "base": "pair", "width": 1.7, "story": 1.6, "bracing": "x", "mat": [0, 0, 0], "steel_below": 5.0},
	"pyramid": {"name": "pyramid", "base": "all", "width": 1.0, "taper": 0.25, "story": 1.6, "bracing": "x", "mat": [0, 0, 0]},
}
const IDS := ["wood_tower", "steel_tower", "wide_frame", "a_frame", "squat_steel", "steel_spine", "lattice", "lean_tower", "mixed_tower", "pyramid"]


## The anchors a structure stands on: all of them, or the closest pair (by distance).
static func _base(anchors: Array, mode: String) -> Array:
	if mode == "all" or anchors.size() <= 2:
		return anchors.duplicate()
	var best := 0
	for i in range(1, anchors.size() - 1):
		if _d(anchors[i], anchors[i + 1]) < _d(anchors[best], anchors[best + 1]):
			best = i
	return [anchors[best], anchors[best + 1]]


static func _row(center: float, width: float) -> Array:
	if width < 0.5:
		return [center]
	var n := maxi(2, ceili(width / NODE_GAP - 0.01) + 1)
	var out: Array = []
	for i in n:
		out.append(center - width / 2.0 + width * i / (n - 1))
	return out


static func _pt(x: float, y: float) -> Vector2i:
	return Vector2i(roundi(x * 10.0) * 10, roundi(y * 10.0) * 10)


static func _d(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b)) / U


## Build a canonical design for a site. Returns {design: [{a, b, m}], height: m, cost: $}.
## On terrain days rows start above the highest base anchor, joints under the ground are
## dropped and beams that would cut through it are skipped.
static func build(id: String, anchors: Array, budget: float, mat_costs: Array, ground := PackedInt32Array()) -> Dictionary:
	var s: Dictionary = STRUCTS[id]
	var gnd := ground if not ground.is_empty() else Terrain.flat()
	var base_pts := _base(anchors, String(s.base))
	var base: Array = base_pts.map(func(a): return float(a.x) / U)
	var y0 := 0.0
	for a in base_pts:
		y0 = maxf(y0, a.y / float(U))
	var x0: float = base[0]
	var x1: float = base[-1]
	var target := (x1 - x0) if float(s.width) < 0.0 else float(s.width)
	var taper := float(s.get("taper", BASE_TAPER))
	var story := float(s.story)
	var cap := float(s.get("cap", GH))
	var lean := float(s.get("lean", 0.0))
	var design: Array = []
	var keys := {}
	var cost := 0.0
	var lower: Array = base_pts.duplicate()
	var is_anchor := {}
	for a in anchors:
		is_anchor[a] = true
	var width := x1 - x0
	var center := (x0 + x1) / 2.0
	var height := 0.0
	var k := 0
	while true:
		k += 1
		var y := y0 + k * story
		if k * story > cap + 1e-6 or y > GH - 0.5:
			break
		var shrink := minf(taper, BASE_TAPER) * story * 2.0
		width = maxf(target, width - shrink) if width > target else minf(target, width + 2.0)
		center += lean * story
		var upper: Array = _row(center, width).map(func(x): return _pt(x, y)).filter(func(p): return not Terrain.grounded(gnd, p + Vector2i(0, -40)))
		if upper.is_empty():
			break
		var row_beams: Array = []
		var linked := {}
		var reached := 0
		for i in upper.size():
			var u: Vector2i = upper[i]
			var near := lower.duplicate()
			near.sort_custom(func(a, b): return _d(a, u) < _d(b, u) or (_d(a, u) == _d(b, u) and a.x < b.x))
			var got := 0
			for j in near.size():
				var l: Vector2i = near[j]
				var dist := _d(l, u)
				if dist > MAX_LEN:
					break
				if not Terrain.clear(gnd, l, u, is_anchor.has(l), false):
					continue
				var want := false
				if s.bracing == "x":
					want = dist <= LINK or got < 2
				else:   # single: the nearest joint, plus one diagonal on alternate joints
					want = got == 0 or (got == 1 and (i + k) % 2 == 0)
				if want:
					row_beams.append([l, u])
					linked[l] = true
					got += 1
			if got > 0:
				reached += 1
		if reached == 0:
			break
		for l in lower:
			if linked.has(l):
				continue
			var best: Vector2i = upper[0]
			for u in upper:
				if _d(u, l) < _d(best, l):
					best = u
			if _d(best, l) <= MAX_LEN and Terrain.clear(gnd, l, best, is_anchor.has(l), false):
				row_beams.append([l, best])
		for i in range(1, upper.size()):
			if Terrain.clear(gnd, upper[i - 1], upper[i]):
				row_beams.append([upper[i - 1], upper[i]])
		# materials + cost of the whole row; stop before overspending
		var add: Array = []
		var row_cost := 0.0
		for pr in row_beams:
			var a: Vector2i = pr[0]
			var b: Vector2i = pr[1]
			if a == b:
				continue
			var key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
			if keys.has(key):
				continue
			keys[key] = false
			var dx := absf(b.x - a.x)
			var dy := absf(b.y - a.y)
			var role := 2 if dy == 0.0 else (0 if dx < 0.35 * dy else 1)
			var m: int = s.mat[role]
			if s.has("steel_below") and role == 0 and maxf(a.y, b.y) / float(U) <= float(s.steel_below):
				m = 1
			row_cost += _d(a, b) * float(mat_costs[m])
			add.append({"a": a, "b": b, "m": m, "key": key})
		if cost + row_cost > budget + 1e-6:
			break
		cost += row_cost
		for bd in add:
			design.append({"a": bd.a, "b": bd.b, "m": bd.m})
		height = y
		lower = upper
		if upper.size() == 1:   # apex
			break
	return {"design": design, "height": height, "cost": cost}


## Run one design through the solver. Metrics: standing height, beams surviving, first
## failure time, max sway of the top joint, collapse (less than a third left standing).
static func run(design: Array, anchors: Array, quake, top_mass := 0.0, ground := PackedInt32Array()) -> Dictionary:
	var out := {"built": 0.0, "standing": 0.0, "survive": 1.0, "first_fail": -1.0, "max_sway": 0.0,
		"collapse": true, "unstable": false, "beams": design.size()}
	if design.is_empty():
		return out
	var sim := Sim.new()
	sim.setup(design, anchors, quake, 1.0 / U, {"top_mass": top_mass, "terrain": ground})
	out.built = sim.start_height
	var top := 0
	for j in sim.n:
		if sim.rest_y[j] > sim.rest_y[top]:
			top = j
	while not sim.done():
		sim.step()
		if out.first_fail < 0.0 and sim.broken_count() > 0:
			out.first_fail = sim.quake_time()
		if sim.b_ok.count(0) < sim.m:
			out.max_sway = maxf(out.max_sway, absf(sim.px[top] - sim.rest_x[top] - sim.gx))
		if sim.steps % 30 == 0:
			for j in sim.n:
				if is_nan(sim.px[j]) or is_nan(sim.py[j]) or absf(sim.px[j]) > 200.0 or absf(sim.py[j]) > 200.0:
					out.unstable = true
					break
			if out.unstable:
				break
	out.standing = sim.standing_height()
	out.survive = 1.0 - float(sim.broken_count()) / maxf(sim.m, 1)
	out.collapse = out.standing < out.built / 3.0
	return out


## Build + run every canonical structure for a challenge. Returns {id: metrics + height}.
static func evaluate(c, ids: Array = IDS) -> Dictionary:
	var q = c.make_quake()
	var out := {}
	for id in ids:
		var b := build(id, c.anchors, float(c.budget), c.mat_costs, c.ground())
		var r := run(b.design, c.anchors, q, c.top_mass(), c.ground())
		r["cost"] = b.cost
		out[id] = r
	return out
