extends RefCounted
## Builds the day's venue from the date seed. Pure data, no validation (validator.gd decides
## whether an attempt is good enough; for_date() in levels.gd re-rolls until it is).
##
## Every venue is laid out with the thrower on the left and then, on some days, mirrored.
## Weekday archetypes introduce one idea each, gently:
##   Mon open        a table or two between you and the target, lots of headroom
##   Tue chandelier  a low ceiling and hanging chandeliers: flatter throws
##   Wed cake        the cake table guards the target (hit it and it's a splat)
##   Thu arch        a curtain wall with a floral arch: throw through the opening
##   Fri balcony     the target waves from a balcony
##   Sat garden      outdoors, no ceiling, a steady breeze
##   Sun bank        a tall divider: lob through the gap or bank it off the ceiling

const L = preload("res://core/level.gd")
const Rng = preload("res://core/rng.gd")

const GEN_VERSION := 1
const LOOKS := 12


static func make(date: String, number: int, seed_value: int, attempt: int, archetype: String) -> Dictionary:
	var rng := Rng.new(seed_value)
	var lv := {
		"v": GEN_VERSION, "date": date, "number": number, "seed": seed_value, "attempt": attempt,
		"archetype": archetype, "theme": "garden" if archetype == "garden" else "ballroom",
		"mirror": false, "w": L.W, "h": L.H, "floor": L.FLOOR, "ceiling": 80, "wind": 0,
		"solids": [], "decor": [], "palette": rng.range_i(0, 5),
	}
	var g := [0]   # next group id (array so helpers can bump it)
	match archetype:
		"open": _open(lv, rng, g)
		"chandelier": _chandelier(lv, rng, g)
		"cake": _cake(lv, rng, g)
		"arch": _arch(lv, rng, g)
		"balcony": _balcony(lv, rng, g)
		"garden": _garden(lv, rng, g)
		_: _bank(lv, rng, g)
	_decor(lv, rng)
	if rng.chance(35):
		L.mirror(lv)
	return lv


# ------------------------------------------------------------------ shared pieces

static func _people(lv: Dictionary, rng: Rng, g: Array, thrower_x: int, target_x: int, target_feet: int) -> void:
	var fl: int = lv.floor
	lv.thrower = {"x": thrower_x, "feet": fl, "face": 1, "look": rng.range_i(0, LOOKS - 1)}
	lv.release = [thrower_x + 16, fl - L.RELEASE_UP]
	var look := rng.range_i(0, LOOKS - 1)
	lv.target = {"x": target_x, "feet": target_feet, "hands": [target_x, target_feet - L.HANDS_UP], "r": L.CATCH_R, "look": look}
	for p in L.guest(target_x, target_feet, _gid(g), look):
		p.role = "target"
		lv.solids.append(p)


static func _gid(g: Array) -> int:
	g[0] += 1
	return g[0]


## Adds pieces only if they keep clear of everything else, the hand and the catch zone.
static func _try_add(lv: Dictionary, pieces: Array, clearance := 6.0) -> bool:
	for p in pieces:
		var b := L.box(p)
		if b[0] < 0 or b[2] > int(lv.w) or b[3] > int(lv.floor):
			return false
		if int(lv.ceiling) >= 0 and b[1] < int(lv.ceiling):
			return false
		for s in lv.solids:
			if int(s.g) == int(p.g):
				continue
			if L.gap(p, s) < clearance:
				return false
		if L.point_dist(float(lv.release[0]), float(lv.release[1]), p) < float(L.BOUQUET_R) + 24.0:
			return false
		if L.point_dist(float(lv.target.hands[0]), float(lv.target.hands[1]), p) < float(lv.target.r) + float(L.BOUQUET_R) + 8.0:
			return false
		# Keep the thrower's body clear too.
		var tx := int(lv.thrower.x)
		if b[2] > tx - 30 and b[0] < tx + 34 and b[3] > int(lv.thrower.feet) - 130:
			return false
	for p in pieces:
		lv.solids.append(p)
	return true


static func _table(lv: Dictionary, rng: Rng, g: Array, x: int, with_chairs := true) -> bool:
	var fl: int = lv.floor
	var w := rng.range_i(84, 136)
	var gid := _gid(g)
	var look := rng.range_i(0, LOOKS - 1)
	var pieces := [L.rect(x - w / 2, fl - 58, w, 58, "table", gid, look)]
	if with_chairs and rng.chance(70):
		pieces.append(L.rect(x - w / 2 - 26, fl - 50, 22, 50, "chair", gid, look))
	if with_chairs and rng.chance(70):
		pieces.append(L.rect(x + w / 2 + 4, fl - 50, 22, 50, "chair", gid, look))
	if _try_add(lv, pieces):
		lv.decor.append({"k": "centerpiece", "x": x, "y": fl - 58, "look": rng.range_i(0, 5)})
		return true
	return false


static func _bystander(lv: Dictionary, rng: Rng, g: Array, x: int, feet := -1) -> bool:
	if feet < 0:
		feet = lv.floor
	return _try_add(lv, L.guest(x, feet, _gid(g), rng.range_i(0, LOOKS - 1)))


static func _balloons(lv: Dictionary, rng: Rng, g: Array, x: int, y: int) -> bool:
	var gid := _gid(g)
	var n := rng.range_i(2, 3)
	var pieces: Array = []
	var r := rng.range_i(17, 21)
	for i in n:
		pieces.append(L.circle(x + (i - (n - 1) / 2) * (r * 2 - 4) + (i % 2) * 3, y - (i % 2) * (r - 2), r, "balloon", gid, rng.range_i(0, 5)))
	if _try_add(lv, pieces, 10.0):
		lv.decor.append({"k": "string", "x": x, "y": y + r, "x2": x + rng.range_i(-10, 10), "y2": mini(int(lv.floor), y + rng.range_i(120, 220))})
		return true
	return false


static func _chandelier_at(lv: Dictionary, rng: Rng, g: Array, x: int, drop: int, r: int) -> bool:
	var ceil_y: int = lv.ceiling
	var p := L.circle(x, ceil_y + drop, r, "chandelier", _gid(g))
	if _try_add(lv, [p], 10.0):
		lv.decor.append({"k": "chain", "x": x, "y": ceil_y, "x2": x, "y2": ceil_y + drop - r})
		return true
	return false


## Random extra clutter between the thrower and the target.
static func _clutter(lv: Dictionary, rng: Rng, g: Array, x0: int, x1: int, tries: int) -> void:
	for i in tries:
		var kind: String = rng.pick(["table", "table", "guest", "balloons", "plant"])
		var x := rng.range_i(x0, x1)
		match kind:
			"table": _table(lv, rng, g, x)
			"guest": _bystander(lv, rng, g, x)
			"balloons": _balloons(lv, rng, g, x, int(lv.floor) - rng.range_i(240, 380))
			"plant":
				var w := rng.range_i(30, 44)
				var h := rng.range_i(50, 90)
				_try_add(lv, [L.rect(x - w / 2, int(lv.floor) - h, w, h, "plant", _gid(g), rng.range_i(0, 5))])


# ------------------------------------------------------------------ archetypes

static func _open(lv: Dictionary, rng: Rng, g: Array) -> void:
	lv.ceiling = rng.range_i(50, 110)
	_people(lv, rng, g, rng.range_i(70, 130), rng.range_i(540, 720), lv.floor)
	_table(lv, rng, g, rng.range_i(300, 460))
	_clutter(lv, rng, g, 220, 600, rng.range_i(1, 3))


static func _chandelier(lv: Dictionary, rng: Rng, g: Array) -> void:
	lv.ceiling = rng.range_i(200, 270)
	_people(lv, rng, g, rng.range_i(70, 120), rng.range_i(560, 730), lv.floor)
	var n := rng.range_i(1, 2)
	for i in n:
		var x := rng.range_i(260, 520) if n == 1 else (rng.range_i(230, 340) if i == 0 else rng.range_i(430, 560))
		_chandelier_at(lv, rng, g, x, rng.range_i(55, 110), rng.range_i(22, 30))
	_table(lv, rng, g, rng.range_i(280, 520))
	_clutter(lv, rng, g, 220, 620, rng.range_i(0, 2))


static func _cake(lv: Dictionary, rng: Rng, g: Array) -> void:
	lv.ceiling = rng.range_i(60, 130)
	var tx := rng.range_i(600, 730)
	_people(lv, rng, g, rng.range_i(70, 130), tx, lv.floor)
	var fl: int = lv.floor
	var cx := tx - rng.range_i(110, 170)
	var gid := _gid(g)
	var tw := rng.range_i(100, 124)
	var top := fl - 60
	var b0 := 64 + rng.range_i(0, 10)
	var pieces := [L.rect(cx - tw / 2, top, tw, 60, "table", gid, 99)]
	var y := top
	var widths := [b0, b0 - 18, b0 - 36]
	var heights := [30, 26, 22]
	var tiers := rng.range_i(2, 3)
	for i in tiers:
		y -= heights[i]
		pieces.append(L.rect(cx - widths[i] / 2, y, widths[i], heights[i], "cake", gid, i))
	if not _try_add(lv, pieces):
		_try_add(lv, [L.rect(cx - 50, top, 100, 60, "table", gid, 99), L.rect(cx - 32, top - 30, 64, 30, "cake", gid, 0)], 2.0)
	lv.decor.append({"k": "topper", "x": cx, "y": y})
	if rng.chance(60):
		_balloons(lv, rng, g, rng.range_i(300, 480), fl - rng.range_i(260, 360))
	_clutter(lv, rng, g, 230, cx - 120, rng.range_i(1, 2))


static func _arch(lv: Dictionary, rng: Rng, g: Array) -> void:
	lv.ceiling = rng.range_i(50, 100)
	var fl: int = lv.floor
	_people(lv, rng, g, rng.range_i(70, 120), rng.range_i(580, 730), fl)
	var px := rng.range_i(330, 450)
	var gap_h := rng.range_i(150, 190)
	var gap_bottom := fl - rng.range_i(70, 210)
	var gap_top := gap_bottom - gap_h
	var gid := _gid(g)
	var ceil_y: int = lv.ceiling
	var pieces := [
		L.rect(px - 13, ceil_y, 26, gap_top - ceil_y, "curtain", gid),
		L.rect(px - 16, gap_bottom, 32, fl - gap_bottom, "plant", gid, 1),
	]
	_try_add(lv, pieces, 2.0)
	lv.decor.append({"k": "arch", "x": px, "y": gap_top, "y2": gap_bottom})
	if rng.chance(50):
		_table(lv, rng, g, rng.range_i(px + 90, int(lv.target.x) - 90), false)
	_clutter(lv, rng, g, 200, px - 70, rng.range_i(0, 2))


static func _balcony(lv: Dictionary, rng: Rng, g: Array) -> void:
	lv.ceiling = rng.range_i(50, 100)
	var fl: int = lv.floor
	var bx := rng.range_i(540, 610)
	var py := rng.range_i(470, 540)
	var gid := _gid(g)
	var pieces := [
		L.rect(bx, py, L.W - bx, 22, "balcony", gid),
		L.rect(bx, py - 32, 10, 32, "railing", gid),
		L.rect(bx + 24, py + 22, 28, fl - py - 22, "pillar", gid),
	]
	lv.solids.append_array(pieces)
	var tx := rng.range_i(bx + 60, mini(bx + 150, L.W - 50))
	_people(lv, rng, g, rng.range_i(70, 130), tx, py)
	if rng.chance(60):
		_chandelier_at(lv, rng, g, rng.range_i(300, bx - 60), rng.range_i(60, 120), rng.range_i(22, 28))
	_table(lv, rng, g, rng.range_i(260, bx - 90))
	if rng.chance(50):
		_bystander(lv, rng, g, rng.range_i(bx + 80, L.W - 40))   # under the balcony
	_clutter(lv, rng, g, 220, bx - 60, rng.range_i(0, 2))


static func _garden(lv: Dictionary, rng: Rng, g: Array) -> void:
	lv.ceiling = -1
	var fl: int = lv.floor
	var wind := rng.range_i(25, 80)
	lv.wind = wind if rng.chance(50) else -wind
	_people(lv, rng, g, rng.range_i(80, 140), rng.range_i(560, 720), fl)
	for i in rng.range_i(1, 3):
		var w := rng.range_i(60, 130)
		var h := rng.range_i(40, 100)
		var x := rng.range_i(240, 560)
		_try_add(lv, [L.rect(x - w / 2, fl - h, w, h, "hedge", _gid(g), rng.range_i(0, 5))], 10.0)
	if rng.chance(70):
		var x2 := rng.range_i(250, 540)
		var ph := rng.range_i(220, 320)
		if _try_add(lv, [L.rect(x2 - 5, fl - ph, 10, ph, "pillar", _gid(g), 2)], 10.0):
			lv.decor.append({"k": "lamp", "x": x2, "y": fl - ph})
	if rng.chance(60):
		_balloons(lv, rng, g, rng.range_i(280, 520), fl - rng.range_i(260, 380))
	_clutter(lv, rng, g, 230, 560, rng.range_i(0, 2))


static func _bank(lv: Dictionary, rng: Rng, g: Array) -> void:
	lv.ceiling = rng.range_i(70, 130)
	var fl: int = lv.floor
	var ceil_y: int = lv.ceiling
	_people(lv, rng, g, rng.range_i(70, 120), rng.range_i(580, 730), fl)
	var px := rng.range_i(340, 460)
	var gid := _gid(g)
	if rng.chance(60):
		# Divider standing up from the floor: lob through the gap or bounce off the ceiling.
		var gap := rng.range_i(190, 250)
		_try_add(lv, [L.rect(px - 14, ceil_y + gap, 28, fl - ceil_y - gap, "pillar", gid)], 2.0)
		lv.decor.append({"k": "banner", "x": px, "y": ceil_y + gap})
	else:
		# Banner hanging from the ceiling: skim underneath it.
		var gap2 := rng.range_i(190, 240)
		_try_add(lv, [L.rect(px - 13, ceil_y, 26, fl - gap2 - ceil_y, "curtain", gid)], 2.0)
	_clutter(lv, rng, g, 200, px - 80, rng.range_i(0, 2))
	if rng.chance(60):
		_table(lv, rng, g, rng.range_i(px + 90, int(lv.target.x) - 80), false)


# ------------------------------------------------------------------ decoration (never collides)

static func _decor(lv: Dictionary, rng: Rng) -> void:
	if String(lv.theme) == "garden":
		for i in rng.range_i(2, 4):
			lv.decor.push_front({"k": "cloud", "x": rng.range_i(40, 760), "y": rng.range_i(60, 240), "s": rng.range_i(0, 3)})
		for i in rng.range_i(2, 4):
			lv.decor.push_front({"k": "tree", "x": rng.range_i(0, 800), "y": int(lv.floor), "s": rng.range_i(0, 3)})
		return
	var ceil_y: int = lv.ceiling
	var fl: int = lv.floor
	for i in rng.range_i(1, 3):
		lv.decor.push_front({"k": "window", "x": rng.range_i(60, 680), "y": maxi(ceil_y + 40, fl - 420), "s": rng.range_i(0, 2)})
	lv.decor.push_front({"k": "lights", "y": ceil_y + rng.range_i(18, 40), "s": rng.range_i(0, 3)})
	if rng.chance(50):
		lv.decor.push_front({"k": "bunting", "y": ceil_y + rng.range_i(50, 90), "s": rng.range_i(0, 3)})
