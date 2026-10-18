extends RefCounted
## Terrain: the shape of the ground the day's structure stands on (generator v3).
##
## A heightfield sampled every metre across the site (GW + 1 points, centimetres, multiples
## of 50), linear in between. y = 0 is the lowest ground on the site, so heights measured
## from it (the score, the build grid) stay comparable across the board. Each terrain
## archetype is shaped around the day's anchor layout so the feature always matters: a
## ledge always splits the anchors, a hump and a ravine always sit between two of them,
## an outcrop always stands where a structure would want to go.
##
## Anchors sit on the surface. Joints may not touch or go below it, and beams may not pass
## through it (anchors excepted). The ground still moves as one rigid block in the quake.

const U := 100
const GW := 14
const MAX_H := 500                    # cm

const TERRAINS := ["flat", "slope", "ledge", "hump", "ravine", "terraces", "outcrop"]
const TERRAIN_INFO := {
	"flat": {"name": "Level Ground", "tip": "Flat ground."},
	"slope": {"name": "Hillside", "tip": "The ground tilts, so the anchors sit at different heights."},
	"ledge": {"name": "Ledge", "tip": "A raised shelf. Build up high, or span the step."},
	"hump": {"name": "Hump", "tip": "A mound between two anchors. Go over it or build beside it."},
	"ravine": {"name": "Ravine", "tip": "A gap in the ground to bridge or build beside."},
	"terraces": {"name": "Terraces", "tip": "Three anchors on three levels."},
	"outcrop": {"name": "Rock Outcrop", "tip": "A rock spike you have to build around."},
}
## Level ground is kept for v2 days only; every terrain day gets a shape.
const TERRAIN_WEIGHT := {"flat": 0.0, "slope": 1.0, "ledge": 1.0, "hump": 1.0, "ravine": 1.0, "terraces": 1.0, "outcrop": 1.0}
## Extra budget for terrain that takes more material to deal with.
const TERRAIN_BUDGET := {"hump": 5, "ravine": 5, "outcrop": 5}


static func flat() -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(GW + 1)
	h.fill(0)
	return h


static func terrain_name(id: String) -> String:
	return String(TERRAIN_INFO.get(id, {}).get("name", id.capitalize()))


static func _snap(v: float) -> int:
	return clampi(int(round(v / 50.0)) * 50, 0, MAX_H)


## Which archetypes fit an anchor layout (anchor x in whole metres, sorted).
static func applicable(arch: String, xs: Array) -> bool:
	var gaps: Array = []
	for i in range(1, xs.size()):
		gaps.append(int(xs[i]) - int(xs[i - 1]))
	match arch:
		"hump":
			return gaps.max() >= 4
		"ravine":
			return gaps.max() >= 4 or (xs.size() == 3 and gaps.min() >= 2)
		"terraces":
			return xs.size() == 3 and gaps.min() >= 2
		"outcrop":
			return _outcrop_spots(xs).size() > 0
		"ledge":
			return gaps.max() >= 2
	return true


## Places a 2 m wide rock can stand: clear of every anchor by 2 m and inside the site.
static func _outcrop_spots(xs: Array) -> Array:
	var out: Array = []
	for p in range(2, GW - 2):
		var ok := true
		for x in xs:
			if int(x) >= p - 2 and int(x) <= p + 3:   # pillar on p, p+1; its slopes reach p-1, p+2
				ok = false
		# only between the outer anchors, or just beside them: it has to be in the way
		if ok and p >= int(xs[0]) - 4 and p + 1 <= int(xs[-1]) + 4:
			out.append(p)
	return out


## Heights (cm) for an archetype around anchors at whole-metre xs (sorted).
static func make(arch: String, xs: Array, rng: RandomNumberGenerator) -> PackedInt32Array:
	var h := flat()
	var n := xs.size()
	match arch:
		"slope":
			var rise := rng.randf_range(200.0, 400.0)
			var up_right := rng.randf() < 0.5
			for x in GW + 1:
				var f := float(x) / GW
				h[x] = int(round(rise * (f if up_right else 1.0 - f)))
		"ledge":
			# step up between two neighbouring anchors; the side with fewer anchors is the shelf
			var cand: Array = []
			for i in n - 1:
				if int(xs[i + 1]) - int(xs[i]) >= 2:
					cand.append(i)
			var i: int = cand[rng.randi_range(0, cand.size() - 1)]
			var lo: int = xs[i]
			var hi: int = xs[i + 1]
			var s := rng.randi_range(lo, hi - 1)          # ground rises from s to s + 1
			var rise := _snap(rng.randf_range(200.0, 320.0))
			var right_high := (n - 1 - i) <= (i + 1) if n == 3 else rng.randf() < 0.5
			for x in GW + 1:
				var high := x >= s + 1 if right_high else x <= s
				h[x] = rise if high else 0
		"hump":
			var best := 0
			for i in n - 1:
				if int(xs[i + 1]) - int(xs[i]) > int(xs[best + 1]) - int(xs[best]):
					best = i
			var a: int = xs[best]
			var b: int = xs[best + 1]
			var peak := rng.randf_range(200.0, 350.0)
			var c := (a + b) / 2.0
			var half := (b - a) / 2.0
			for x in range(a + 1, b):
				var u := absf(x - c) / half
				h[x] = _snap(peak * (1.0 - u * u) + 25.0)
		"ravine":
			var rim := _snap(rng.randf_range(250.0, 380.0))
			h.fill(rim)
			var lo: int
			var hi: int
			if n == 3 and int(xs[1]) - int(xs[0]) >= 2 and int(xs[2]) - int(xs[1]) >= 2 and (rng.randf() < 0.5 or int(xs[2]) - int(xs[0]) < 8):
				lo = xs[0]   # the middle anchor stands at the bottom
				hi = xs[2]
			else:
				var best := 0
				for i in n - 1:
					if int(xs[i + 1]) - int(xs[i]) > int(xs[best + 1]) - int(xs[best]):
						best = i
				lo = xs[best]
				hi = xs[best + 1]
			for x in range(lo + 1, hi):
				h[x] = 0
		"terraces":
			var levels := [0, _snap(rng.randf_range(130.0, 180.0)), 0]
			levels[2] = _snap(float(levels[1]) * 2.0)
			if rng.randf() < 0.5:
				levels.reverse()
			var s1 := rng.randi_range(int(xs[0]), int(xs[1]) - 1)
			var s2 := rng.randi_range(int(xs[1]), int(xs[2]) - 1)
			for x in GW + 1:
				h[x] = levels[0] if x <= s1 else (levels[1] if x <= s2 else levels[2])
		"outcrop":
			var spots := _outcrop_spots(xs)
			# prefer a rock between the anchors
			var inside: Array = spots.filter(func(p): return p > int(xs[0]) and p + 1 < int(xs[-1]))
			var pool: Array = inside if not inside.is_empty() and rng.randf() < 0.8 else spots
			var p: int = pool[rng.randi_range(0, pool.size() - 1)]
			var top := _snap(rng.randf_range(300.0, 480.0))
			h[p] = top
			h[p + 1] = _snap(float(top) * rng.randf_range(0.6, 1.0))
	return h


# ------------------------------------------------------------------ queries (all in cm)

## Surface height (cm) at x (cm). Linear between the metre samples; flat beyond the site.
static func height_at(h: PackedInt32Array, x: float) -> float:
	if h.is_empty():
		return 0.0
	var fx := clampf(x / U, 0.0, float(h.size() - 1))
	var i := mini(floori(fx), h.size() - 2)
	return lerpf(float(h[i]), float(h[i + 1]), fx - i)


## Put anchors (whole metres) on the surface.
static func place(h: PackedInt32Array, anchors: Array) -> Array:
	return anchors.map(func(a): return Vector2i(a.x, int(round(height_at(h, a.x)))))


## True when point p (cm) is on or below the ground.
static func grounded(h: PackedInt32Array, p: Vector2i) -> bool:
	return float(p.y) <= height_at(h, p.x) + 1.0


## True when the beam a-b stays above the ground (an anchor end may touch it).
static func clear(h: PackedInt32Array, a: Vector2i, b: Vector2i, a_anchor := false, b_anchor := false) -> bool:
	if not a_anchor and grounded(h, a):
		return false
	if not b_anchor and grounded(h, b):
		return false
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	if x1 == x0:
		return true
	# the gap between a straight beam and a piecewise-linear ground is smallest at a
	# breakpoint or an end, so checking the metre marks in between is exact
	for m in range(floori(x0 / float(U)) + 1, ceili(x1 / float(U))):
		var x := m * U
		if x <= x0 or x >= x1:
			continue
		var y := lerpf(a.y, b.y, float(x - a.x) / float(b.x - a.x))
		if y <= float(h[clampi(m, 0, h.size() - 1)]) + 2.0:
			return false
	return true


## Shape features for fingerprints: relief (m), anchor height spread (m), obstacle height (m).
static func features(h: PackedInt32Array, anchors: Array) -> Dictionary:
	var lo := 1 << 30
	var hi := -(1 << 30)
	for v in h:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	var alo := 1 << 30
	var ahi := -(1 << 30)
	for a in anchors:
		alo = mini(alo, a.y)
		ahi = maxi(ahi, a.y)
	# highest ground between the outer anchors above the line joining them
	var obstacle := 0.0
	var a0: Vector2i = anchors[0]
	var a1: Vector2i = anchors[-1]
	for m in range(a0.x / U + 1, a1.x / U):
		var line := lerpf(a0.y, a1.y, float(m * U - a0.x) / float(a1.x - a0.x))
		obstacle = maxf(obstacle, float(h[m]) - line)
	return {"relief": (hi - lo) / 100.0, "anchor_spread": (ahi - alo) / 100.0, "obstacle": obstacle / 100.0}


## "" when the terrain + anchors are buildable, else the reason.
static func problem(h: PackedInt32Array, anchors: Array) -> String:
	if h.size() != GW + 1:
		return "terrain has %d samples" % h.size()
	var lo := 1 << 30
	for v in h:
		if v < 0 or v > MAX_H:
			return "terrain height %d out of range" % v
		lo = mini(lo, v)
	if lo != 0:
		return "lowest ground isn't at 0"
	for a in anchors:
		if absf(float(a.y) - height_at(h, a.x)) > 1.0:
			return "anchor off the surface"
		# room to build: the point 1 m above each anchor is clear of the ground
		if grounded(h, a + Vector2i(0, U)):
			return "anchor buried"
		for d in [-U, U]:
			if a.x + d >= 0 and a.x + d <= GW * U and height_at(h, a.x + d) > a.y + 300:
				return "anchor in a pit"
	return ""
