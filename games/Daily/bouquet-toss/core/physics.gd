extends RefCounted
## Deterministic bouquet physics. No rendering, no engine physics, no trig.
##
## A throw is two integers: angle (whole degrees, 0 = right, 90 = up) and power (1..100).
## Everything runs on 64-bit floats using only + - * / and sqrt (all exactly specified by
## IEEE 754, so identical on every browser and device), with a fixed timestep, fixed
## substep rule and a fixed shape order. Same level + same two integers = same flight.
##
## Level geometry is whole pixels in a W x H world, y pointing down (see level.gd).

const Units = preload("res://core/units.gd")

const DT := 1.0 / 120.0
const GRAVITY := 1500.0          # px/s^2
const DRAG := 0.12               # linear air drag, 1/s
const RADIUS := 11.0             # bouquet radius
const SPEED_MIN := 240.0
const SPEED_PER_POWER := 10.0    # power 100 -> 1240 px/s
const MAX_STEP_MOVE := 5.0       # substep so the bouquet never moves more than this per substep
const MAX_STEPS := 840           # 7 seconds
const REST_SPEED := 32.0
const REST_STEPS := 30
const LOUD_IMPACT := 70.0        # impacts slower than this are not reported as events
const OUT_MARGIN := 80.0
const CATCH_SPEED := 1000.0      # faster than this and the guest fumbles it

## Bounce (restitution) and friction per kind of surface.
const MATERIAL := {
	"wall": [0.5, 0.10], "floor": [0.32, 0.30], "ceiling": [0.45, 0.05],
	"table": [0.35, 0.25], "chair": [0.4, 0.2], "guest": [0.3, 0.3], "thrower": [0.3, 0.3],
	"balloon": [0.92, 0.0], "chandelier": [0.5, 0.1], "arch": [0.5, 0.1], "curtain": [0.08, 0.6],
	"hedge": [0.2, 0.5], "railing": [0.45, 0.1], "balcony": [0.35, 0.25], "plant": [0.25, 0.4],
	"speaker": [0.55, 0.1], "pillar": [0.5, 0.1], "cake": [0.0, 1.0],
}

## Surfaces that end the throw on contact.
const SPLAT := {"cake": true}

const SHAPE_RECT := 0
const SHAPE_CIRCLE := 1


static func speed_for(power: int) -> float:
	return SPEED_MIN + float(clampi(power, 1, 100)) * SPEED_PER_POWER


static func launch_velocity(angle: int, power: int) -> Array:
	var s := speed_for(power)
	return [Units.ux(angle) * s, Units.uy(angle) * s]


## Flattens a level dictionary into arrays the inner loop can read quickly.
## Shapes keep the level's order, which fixes the collision order.
static func compile(level: Dictionary) -> Dictionary:
	var kinds: Array = []
	var shape: PackedInt32Array = []
	var a: PackedFloat64Array = []   # rect: x0 y0 x1 y1   circle: cx cy r 0
	var bb: PackedFloat64Array = []  # expanded bounding box: x0 y0 x1 y1
	var mat: PackedFloat64Array = [] # restitution, friction
	var w := float(level.w)
	var h := float(level.h)
	var fl := float(level.floor)
	var solids: Array = []
	# Room bounds first (floor; walls and ceiling only indoors), then the level's solids.
	var indoors := int(level.get("ceiling", -1)) >= 0
	solids.append({"t": "rect", "x": -200, "y": int(level.floor), "w": int(level.w) + 400, "h": 400, "k": "floor"})
	if indoors:
		solids.append({"t": "rect", "x": -200, "y": -2000, "w": 200, "h": 4000, "k": "wall"})
		solids.append({"t": "rect", "x": int(level.w), "y": -2000, "w": 200, "h": 4000, "k": "wall"})
		solids.append({"t": "rect", "x": -200, "y": -400, "w": int(level.w) + 400, "h": 400 + int(level.ceiling), "k": "ceiling"})
	for s in level.solids:
		solids.append(s)
	var r := RADIUS
	for s in solids:
		var k := String(s.get("k", "wall"))
		var m: Array = MATERIAL.get(k, [0.4, 0.2])
		kinds.append(k)
		mat.append(float(m[0]))
		mat.append(float(m[1]))
		if String(s.t) == "circle":
			shape.append(SHAPE_CIRCLE)
			var cx := float(s.x)
			var cy := float(s.y)
			var cr := float(s.r)
			a.append_array([cx, cy, cr, 0.0])
			bb.append_array([cx - cr - r, cy - cr - r, cx + cr + r, cy + cr + r])
		else:
			shape.append(SHAPE_RECT)
			var x0 := float(s.x)
			var y0 := float(s.y)
			var x1 := x0 + float(s.w)
			var y1 := y0 + float(s.h)
			a.append_array([x0, y0, x1, y1])
			bb.append_array([x0 - r, y0 - r, x1 + r, y1 + r])
	var outdoors := int(level.get("ceiling", -1)) < 0
	return {
		"kinds": kinds, "shape": shape, "a": a, "bb": bb, "mat": mat, "n": shape.size(),
		"start_x": float(level.release[0]), "start_y": float(level.release[1]),
		"hand_x": float(level.target.hands[0]), "hand_y": float(level.target.hands[1]),
		"catch_r": float(level.target.r), "wind": float(level.get("wind", 0)),
		"w": w, "h": h, "floor": fl, "outdoors": outdoors,
	}


## Simulates one throw from start to finish.
##   record:     store the position every `record` steps (0 = none). Positions are per step.
##   max_steps:  stop early (used by the aim preview); -1 = full flight.
##   stop_on_hit: stop at the first contact (aim preview).
## Returns {outcome, steps, catch_d (how far the flight line passes from the hands' centre), catch_x, catch_y, bounces, hits: Array of kinds hit in
## order, path: PackedFloat64Array x,y pairs, events: [{s, k, x, y, v}], end_x, end_y}.
## outcome: "catch", "splat", "fumble" (arrived too fast, bounced off the hands), "floor",
## "rest", "out", "timeout", "preview".
static func simulate(c: Dictionary, angle: int, power: int, record := 0, max_steps := -1, stop_on_hit := false) -> Dictionary:
	var vel := launch_velocity(angle, power)
	var vx: float = vel[0]
	var vy: float = vel[1]
	var x: float = c.start_x
	var y: float = c.start_y
	var n: int = c.n
	var shape: PackedInt32Array = c.shape
	var a: PackedFloat64Array = c.a
	var bb: PackedFloat64Array = c.bb
	var mat: PackedFloat64Array = c.mat
	var kinds: Array = c.kinds
	var hx: float = c.hand_x
	var hy: float = c.hand_y
	var cr: float = c.catch_r
	var cr2 := cr * cr
	var wind: float = c.wind
	var w: float = c.w
	var h: float = c.h
	var r := RADIUS
	var path: PackedFloat64Array = []
	var events: Array = []
	var hits: Array = []
	var bounces := 0
	var slow := 0
	var outcome := "timeout"
	var fumbled := false
	var catch_d := -1.0
	var catch_x := 0.0
	var catch_y := 0.0
	var steps := 0
	var limit := MAX_STEPS if max_steps < 0 else mini(max_steps, MAX_STEPS)
	if record > 0:
		path.append(x)
		path.append(y)
	var done := false
	while steps < limit and not done:
		steps += 1
		var speed := sqrt(vx * vx + vy * vy)
		var sub := 1 + int(speed * DT / MAX_STEP_MOVE)
		var sdt := DT / float(sub)
		var touched := false
		var touched_floor := false
		for _k in sub:
			var px := x
			var py := y
			vy += GRAVITY * sdt
			vx += wind * sdt
			var damp := 1.0 - DRAG * sdt
			vx *= damp
			vy *= damp
			x += vx * sdt
			y += vy * sdt
			# Catch: closest point of this substep's movement to the target's hands.
			var dx := x - px
			var dy := y - py
			var seg2 := dx * dx + dy * dy
			var t := 0.0
			if seg2 > 0.0:
				t = clampf(((hx - px) * dx + (hy - py) * dy) / seg2, 0.0, 1.0)
			var qx := px + dx * t
			var qy := py + dy * t
			var ddx := qx - hx
			var ddy := qy - hy
			var d2 := ddx * ddx + ddy * ddy
			if d2 <= cr2 and not fumbled:
				var sp := sqrt(vx * vx + vy * vy)
				if sp > CATCH_SPEED:
					# Too hot to handle: it pops off their hands and the throw carries on.
					fumbled = true
					x = qx
					y = qy
					vx = -vx * 0.25
					vy = -absf(vy) * 0.25 - 160.0
					if record > 0:
						events.append({"s": steps, "k": "fumble", "x": x, "y": y, "v": sp})
					hits.append("fumble")
					continue
				outcome = "catch"
				# Accuracy: how close its line of flight passes to the centre of the hands
				# (0 = dead centre), not where it first crossed the edge of the zone.
				catch_d = minf(sqrt(d2), absf((hx - qx) * vy - (hy - qy) * vx) / maxf(sp, 0.000001))
				catch_x = qx
				catch_y = qy
				x = qx
				y = qy
				done = true
				break
			# Collisions, in shape order.
			for i in n:
				var b := i * 4
				if x < bb[b] or x > bb[b + 2] or y < bb[b + 1] or y > bb[b + 3]:
					continue
				var nx := 0.0
				var ny := 0.0
				var pen := 0.0
				if shape[i] == SHAPE_CIRCLE:
					var ox := x - a[b]
					var oy := y - a[b + 1]
					var rr := a[b + 2] + r
					var o2 := ox * ox + oy * oy
					if o2 >= rr * rr:
						continue
					var od := sqrt(o2)
					if od > 0.000001:
						nx = ox / od
						ny = oy / od
					else:
						ny = -1.0
					pen = rr - od
				else:
					var x0 := a[b]
					var y0 := a[b + 1]
					var x1 := a[b + 2]
					var y1 := a[b + 3]
					var cx := clampf(x, x0, x1)
					var cy := clampf(y, y0, y1)
					var ox := x - cx
					var oy := y - cy
					var o2 := ox * ox + oy * oy
					if o2 >= r * r:
						continue
					if o2 > 0.0:
						var od := sqrt(o2)
						nx = ox / od
						ny = oy / od
						pen = r - od
					else:
						# Centre inside the box: push out through the nearest face.
						var dl := x - x0
						var dr := x1 - x
						var dt_ := y - y0
						var db := y1 - y
						var m := dl
						nx = -1.0
						ny = 0.0
						if dr < m:
							m = dr
							nx = 1.0
							ny = 0.0
						if dt_ < m:
							m = dt_
							nx = 0.0
							ny = -1.0
						if db < m:
							m = db
							nx = 0.0
							ny = 1.0
						pen = m + r
				x += nx * pen
				y += ny * pen
				var vn := vx * nx + vy * ny
				var k: String = kinds[i]
				touched = true
				if k == "floor":
					touched_floor = true
				if vn < 0.0:
					if record > 0 and -vn > LOUD_IMPACT:
						events.append({"s": steps, "k": k, "x": x, "y": y, "v": -vn})
					if -vn > LOUD_IMPACT:
						if hits.is_empty() or hits[hits.size() - 1] != k:
							hits.append(k)
						bounces += 1
					if SPLAT.has(k):
						outcome = "splat"
						vx = 0.0
						vy = 0.0
						done = true
						break
					var e := mat[i * 2]
					var f := mat[i * 2 + 1]
					var tx := vx - vn * nx
					var ty := vy - vn * ny
					tx *= 1.0 - f
					ty *= 1.0 - f
					vx = tx - e * vn * nx
					vy = ty - e * vn * ny
				if stop_on_hit:
					outcome = "preview"
					done = true
					break
			if done:
				break
			if x < -OUT_MARGIN or x > w + OUT_MARGIN or y > h + OUT_MARGIN or y < -1500.0:
				outcome = "out"
				done = true
				break
		if record > 0 and (steps % record == 0 or done):
			path.append(x)
			path.append(y)
		if done:
			break
		var sp2 := vx * vx + vy * vy
		if touched and sp2 < REST_SPEED * REST_SPEED:
			slow += 1
			if slow >= REST_STEPS:
				outcome = "floor" if touched_floor else "rest"
				break
		else:
			slow = 0
	if max_steps >= 0 and outcome == "timeout":
		outcome = "preview"
	if fumbled and outcome in ["floor", "rest", "out", "timeout"]:
		outcome = "fumble"
	return {
		"outcome": outcome, "steps": steps, "catch_d": catch_d, "catch_x": catch_x, "catch_y": catch_y,
		"bounces": bounces, "hits": hits, "path": path, "events": events, "end_x": x, "end_y": y,
	}


## Convenience for tests and tools: compile + simulate.
static func throw(level: Dictionary, angle: int, power: int, record := 0) -> Dictionary:
	return simulate(compile(level), angle, power, record)
