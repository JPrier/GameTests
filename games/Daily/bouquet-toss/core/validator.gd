extends RefCounted
## Decides whether a generated level is fair, by playing it.
##
## 1. Geometry rules (level.gd): nothing overlaps, floats, pokes out, crowds the hand or the
##    catch zone, and the target is far enough away.
## 2. A grid of throws: every 4 degrees over the forward half-circle (plus some backwards
##    angles for wall shots) x every 5% of power. Each catch is a "solve".
## 3. Robustness: a solve only counts as discoverable if nearby throws (+-2 degrees, +-2 power)
##    all catch too, so no level needs a pixel-perfect throw.
## 4. Routes: catches are grouped by what they bounced off first ("direct", "ceiling", ...);
##    more routes = more ways to play it.
## The level's archetype sets the acceptable solve rate (easy days are generous).

const P = preload("res://core/physics.gd")
const L = preload("res://core/level.gd")

const ANGLE_LO := -30
const ANGLE_HI := 210
const ANGLE_STEP := 4
const POWER_LO := 10
const POWER_HI := 100
const POWER_STEP := 5
const ROBUST_DA := 2
const ROBUST_DP := 2
const MAX_ROBUST_CHECKS := 14

## Accepted share of the grid that catches, per archetype: [min, max].
const RATE := {
	"open": [0.018, 0.20], "chandelier": [0.015, 0.14], "cake": [0.013, 0.14],
	"arch": [0.009, 0.10], "balcony": [0.006, 0.10], "garden": [0.008, 0.10], "bank": [0.003, 0.06],
}


## The real angle for a "forward" angle (thrower facing right = forward).
static func actual_angle(level: Dictionary, fwd: int) -> int:
	return posmod(180 - fwd, 360) if bool(level.get("mirror", false)) else posmod(fwd, 360)


static func route_of(res: Dictionary) -> String:
	var hits: Array = res.hits
	return "direct" if hits.is_empty() else String(hits[0])


## Full evaluation. Returns stats (always) with "ok" and "reasons".
static func evaluate(level: Dictionary) -> Dictionary:
	var reasons: Array = L.geometry_errors(level)
	var stats := {"ok": false, "reasons": reasons, "rate": 0.0, "solves": 0, "total": 0,
		"robust": 0, "routes": [], "clusters": 0, "solution": {}}
	if not reasons.is_empty():
		return stats
	var c := P.compile(level)
	var angles: Array = []
	var a := ANGLE_LO
	while a <= ANGLE_HI:
		angles.append(a)
		a += ANGLE_STEP
	var powers: Array = []
	var p := POWER_LO
	while p <= POWER_HI:
		powers.append(p)
		p += POWER_STEP
	var grid: Dictionary = {}      # Vector2i(ai, pi) -> result
	var solves: Array = []
	var routes: Dictionary = {}
	for ai in angles.size():
		for pi in powers.size():
			var res := P.simulate(c, actual_angle(level, angles[ai]), powers[pi])
			if res.outcome == "catch":
				var cell := Vector2i(ai, pi)
				grid[cell] = res
				solves.append({"cell": cell, "fwd": angles[ai], "p": powers[pi], "d": res.catch_d, "route": route_of(res)})
				routes[route_of(res)] = true
	var total := angles.size() * powers.size()
	stats.total = total
	stats.solves = solves.size()
	stats.rate = float(solves.size()) / float(total)
	stats.routes = routes.keys()
	stats.routes.sort()
	stats.clusters = _clusters(grid)
	# Robustness: check the most central solves of each route first.
	solves.sort_custom(func(x, y): return _neighbours(grid, x.cell) > _neighbours(grid, y.cell) or (_neighbours(grid, x.cell) == _neighbours(grid, y.cell) and x.d < y.d))
	var robust: Array = []
	var checked := 0
	for s in solves:
		if checked >= MAX_ROBUST_CHECKS:
			break
		checked += 1
		if _robust(c, level, int(s.fwd), int(s.p)):
			robust.append(s)
	stats.robust = robust.size()
	if not robust.is_empty():
		var best: Dictionary = robust[0]
		for s in robust:
			if float(s.d) < float(best.d):
				best = s
		stats.solution = {"a": actual_angle(level, int(best.fwd)), "p": int(best.p)}
	var rate_ok: Array = RATE.get(String(level.archetype), [0.01, 0.2])
	if solves.is_empty():
		reasons.append("unsolvable")
	elif robust.is_empty():
		reasons.append("only pixel-perfect solutions")
	if stats.rate < float(rate_ok[0]):
		reasons.append("too hard (%.3f)" % stats.rate)
	if stats.rate > float(rate_ok[1]):
		reasons.append("too easy (%.3f)" % stats.rate)
	stats.ok = reasons.is_empty()
	return stats


static func _robust(c: Dictionary, level: Dictionary, fwd: int, p: int) -> bool:
	for da in [-ROBUST_DA, 0, ROBUST_DA]:
		for dp in [-ROBUST_DP, 0, ROBUST_DP]:
			if da == 0 and dp == 0:
				continue
			var pp := clampi(p + dp, 1, 100)
			if P.simulate(c, actual_angle(level, fwd + da), pp).outcome != "catch":
				return false
	return true


static func _neighbours(grid: Dictionary, cell: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if grid.has(cell + d):
			n += 1
	return n


static func _clusters(grid: Dictionary) -> int:
	var seen: Dictionary = {}
	var count := 0
	for cell in grid:
		if seen.has(cell):
			continue
		count += 1
		var stack: Array = [cell]
		seen[cell] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cur + d
				if grid.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
	return count
