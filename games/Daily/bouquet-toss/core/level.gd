extends RefCounted
## Level data: plain, JSON-friendly dictionaries of whole numbers.
##
## {
##   "v": 1, "date": "2026-10-16", "number": 1, "seed": 123, "attempt": 0,
##   "archetype": "cake", "theme": "ballroom" | "garden", "mirror": false,
##   "w": 800, "h": 760, "floor": 700, "ceiling": 90 (or -1 outdoors), "wind": 0 (px/s^2, +right),
##   "release": [x, y],                         where the bouquet leaves the thrower's hands
##   "thrower": {"x": .., "feet": .., "face": 1|-1, "look": n},
##   "target": {"x": .., "feet": .., "hands": [x, y], "r": 34, "look": n},
##   "solids": [{"t": "rect", "x", "y", "w", "h", "k": kind, "g": group, "look": n},
##              {"t": "circle", "x", "y", "r", "k", "g", "look"}],
##   "decor": [{"k": kind, "x", "y", ...}]      drawn only, never collides
##   "solution": {"a": angle, "p": power}       a robust catching throw found by the validator
##   "stats": {...}                             validator metrics (solve rate, routes, ...)
## }
## Solids sharing a group "g" (a table and the cake on it, a guest's body and head) may touch;
## anything else must keep apart.

const W := 800
const H := 760
const FLOOR := 700
const CATCH_R := 34
const BOUQUET_R := 11
const RELEASE_UP := 112        # release point above the thrower's feet
const HANDS_UP := 132          # target's hands above their feet

const GUEST_W := 34
const GUEST_H := 74
const HEAD_R := 16


static func rect(x: int, y: int, w: int, h: int, k: String, g := -1, look := 0) -> Dictionary:
	return {"t": "rect", "x": x, "y": y, "w": w, "h": h, "k": k, "g": g, "look": look}


static func circle(x: int, y: int, r: int, k: String, g := -1, look := 0) -> Dictionary:
	return {"t": "circle", "x": x, "y": y, "r": r, "k": k, "g": g, "look": look}


## A guest standing with feet at `feet`: body box + head.
static func guest(x: int, feet: int, g: int, look: int) -> Array:
	return [
		rect(x - GUEST_W / 2, feet - GUEST_H, GUEST_W, GUEST_H, "guest", g, look),
		circle(x, feet - GUEST_H - HEAD_R + 2, HEAD_R, "guest", g, look),
	]


## Bounding box of a solid as [x0, y0, x1, y1].
static func box(s: Dictionary) -> Array:
	if String(s.t) == "circle":
		return [int(s.x) - int(s.r), int(s.y) - int(s.r), int(s.x) + int(s.r), int(s.y) + int(s.r)]
	return [int(s.x), int(s.y), int(s.x) + int(s.w), int(s.y) + int(s.h)]


## Distance between two solids (0 when they touch or overlap; boxes are compared exactly,
## circles as circles).
static func gap(a: Dictionary, b: Dictionary) -> float:
	var ca := String(a.t) == "circle"
	var cb := String(b.t) == "circle"
	if ca and cb:
		var dx := float(a.x) - float(b.x)
		var dy := float(a.y) - float(b.y)
		return maxf(0.0, sqrt(dx * dx + dy * dy) - float(a.r) - float(b.r))
	if ca or cb:
		var c: Dictionary = a if ca else b
		var r: Dictionary = b if ca else a
		return maxf(0.0, point_rect_dist(float(c.x), float(c.y), r) - float(c.r))
	var ba := box(a)
	var bb := box(b)
	var dx2 := maxf(0.0, maxf(float(ba[0] - bb[2]), float(bb[0] - ba[2])))
	var dy2 := maxf(0.0, maxf(float(ba[1] - bb[3]), float(bb[1] - ba[3])))
	return sqrt(dx2 * dx2 + dy2 * dy2)


## True when two solids share interior (touching edges, like feet on a floor, is fine).
static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	var ca := String(a.t) == "circle"
	var cb := String(b.t) == "circle"
	if ca and cb:
		var dx := float(a.x) - float(b.x)
		var dy := float(a.y) - float(b.y)
		return sqrt(dx * dx + dy * dy) < float(a.r) + float(b.r) - 0.5
	if ca or cb:
		var c: Dictionary = a if ca else b
		var r: Dictionary = b if ca else a
		return point_rect_dist(float(c.x), float(c.y), r) < float(c.r) - 0.5
	var ba := box(a)
	var bb := box(b)
	return ba[0] < bb[2] and bb[0] < ba[2] and ba[1] < bb[3] and bb[1] < ba[3]


static func point_rect_dist(px: float, py: float, r: Dictionary) -> float:
	var cx := clampf(px, float(r.x), float(r.x) + float(r.w))
	var cy := clampf(py, float(r.y), float(r.y) + float(r.h))
	return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))


static func point_dist(px: float, py: float, s: Dictionary) -> float:
	if String(s.t) == "circle":
		return maxf(0.0, sqrt((px - float(s.x)) ** 2 + (py - float(s.y)) ** 2) - float(s.r))
	return point_rect_dist(px, py, s)


## Mirrors a level left-right in place (x -> W - x).
static func mirror(level: Dictionary) -> void:
	var w := int(level.w)
	for s in level.solids:
		if String(s.t) == "circle":
			s.x = w - int(s.x)
		else:
			s.x = w - int(s.x) - int(s.w)
	for d in level.decor:
		if d.has("x"):
			d.x = w - int(d.x) - int(d.get("w", 0))
		if d.has("x2"):
			d.x2 = w - int(d.x2)
	level.release = [w - int(level.release[0]), int(level.release[1])]
	level.thrower.x = w - int(level.thrower.x)
	level.thrower.face = -int(level.thrower.face)
	level.target.x = w - int(level.target.x)
	level.target.hands = [w - int(level.target.hands[0]), int(level.target.hands[1])]
	level.wind = -int(level.get("wind", 0))
	level.mirror = not bool(level.get("mirror", false))


## Every rule a level's geometry must satisfy. Empty = fine.
static func geometry_errors(level: Dictionary) -> Array:
	var errs: Array = []
	var w := int(level.w)
	var fl := int(level.floor)
	var ceil_y := int(level.get("ceiling", -1))
	var top := ceil_y if ceil_y >= 0 else -400
	var solids: Array = level.solids
	var tg: Dictionary = level.target
	var hx := float(tg.hands[0])
	var hy := float(tg.hands[1])
	var rx := float(level.release[0])
	var ry := float(level.release[1])
	var target_group := -2
	for s in solids:
		if String(s.k) == "guest" and String(s.get("role", "")) == "target":
			target_group = int(s.g)
	for i in solids.size():
		var s: Dictionary = solids[i]
		for key in s:
			if typeof(s[key]) == TYPE_FLOAT and float(s[key]) != floor(float(s[key])):
				errs.append("solid %d has a fractional %s" % [i, key])
		var b := box(s)
		if b[0] < 0 or b[2] > w:
			errs.append("solid %d (%s) leaves the room sideways" % [i, s.k])
		if b[3] > fl:
			errs.append("solid %d (%s) sinks into the floor" % [i, s.k])
		if b[1] < top:
			errs.append("solid %d (%s) pokes through the ceiling" % [i, s.k])
		if String(s.t) == "rect" and (int(s.w) < 8 or int(s.h) < 8):
			errs.append("solid %d (%s) is thinner than 8 px (could be tunnelled)" % [i, s.k])
		if String(s.t) == "circle" and int(s.r) < 6:
			errs.append("solid %d (%s) is smaller than 6 px" % [i, s.k])
		for j in range(i + 1, solids.size()):
			var o: Dictionary = solids[j]
			if int(s.g) >= 0 and int(s.g) == int(o.g):
				continue
			if overlaps(s, o):
				errs.append("solids %d (%s) and %d (%s) overlap" % [i, s.k, j, o.k])
		if point_dist(rx, ry, s) < float(BOUQUET_R) + 18.0:
			errs.append("solid %d (%s) crowds the throwing hand" % [i, s.k])
		if int(s.g) != target_group and point_dist(hx, hy, s) < float(level.target.r) + float(BOUQUET_R) + 2.0:
			errs.append("solid %d (%s) blocks the catch zone" % [i, s.k])
	if hy - float(level.target.r) - float(BOUQUET_R) < float(top) + 4.0:
		errs.append("catch zone touches the ceiling")
	if ry - float(BOUQUET_R) < float(top) + 4.0:
		errs.append("release point touches the ceiling")
	if absf(hx - rx) < 260.0:
		errs.append("target too close to the thrower")
	# Feet must stand on something: the floor or the top of a solid.
	for who in [level.thrower, tg]:
		var feet := int(who.feet)
		if feet != fl:
			var supported := false
			for s in solids:
				if String(s.t) == "rect" and int(s.y) == feet and int(s.x) <= int(who.x) and int(s.x) + int(s.w) >= int(who.x):
					supported = true
			if not supported:
				errs.append("someone is floating at x=%d" % int(who.x))
	return errs


## JSON turns every number into a float; bring whole numbers back to int.
static func normalize(v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = normalize(v[k])
		return out
	if v is Array:
		var arr := []
		for x in v:
			arr.append(normalize(x))
		return arr
	if typeof(v) == TYPE_FLOAT and v == floor(v) and absf(v) < 1e15:
		return int(v)
	return v


static func to_json(level: Dictionary) -> String:
	return JSON.stringify(level, "", true)


static func from_json(s: String) -> Dictionary:
	var d = JSON.parse_string(s)
	return normalize(d) if d is Dictionary else {}
