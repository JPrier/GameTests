extends GameTest
## The simulation on hand-built rooms: determinism, gravity, every kind of collision, catches.

const P = preload("res://core/physics.gd")
const L = preload("res://core/level.gd")
const U = preload("res://core/units.gd")
const Levels = preload("res://core/levels.gd")


## An empty room with the thrower at the left and the target far right (hands up high).
func room(solids: Array = [], ceiling := 60, target_x := 700, target_hands_y := -1) -> Dictionary:
	var lv := {
		"w": 800, "h": 760, "floor": 700, "ceiling": ceiling, "wind": 0, "mirror": false,
		"release": [100, 588], "thrower": {"x": 84, "feet": 700, "face": 1, "look": 0},
		"target": {"x": target_x, "feet": 700, "hands": [target_x, 568 if target_hands_y < 0 else target_hands_y], "r": 34, "look": 0},
		"solids": solids, "decor": [], "archetype": "open",
	}
	return lv


func test_unit_table():
	assert_eq(U.X.size(), 360, "360 x values")
	assert_eq(U.Y.size(), 360, "360 y values")
	assert_near(U.ux(0), 1.0, 1e-12, "0 deg points right")
	assert_near(U.uy(90), -1.0, 1e-12, "90 deg points up (screen y is down)")
	assert_near(U.ux(180), -1.0, 1e-12, "180 deg points left")
	for a in 360:
		assert_near(U.ux(a) * U.ux(a) + U.uy(a) * U.uy(a), 1.0, 1e-12, "unit length at %d" % a)
	assert_eq(U.ux(-90), U.ux(270), "negative angles wrap")


func test_identical_inputs_identical_flights():
	var lv := Levels.for_date("2026-10-21", 2)
	var c := P.compile(lv)
	for pair in [[40, 60], [75, 90], [12, 100], [150, 40], [-20, 70]]:
		var a := P.simulate(c, pair[0], pair[1], 1)
		var b := P.simulate(P.compile(lv), pair[0], pair[1], 1)
		assert_eq(a.outcome, b.outcome, "outcome")
		assert_eq(a.steps, b.steps, "steps")
		assert_true(a.path == b.path, "every position identical for %s" % str(pair))
		assert_eq(a.hits, b.hits, "hits")


func test_pinned_trajectory():
	# A golden value: if this changes, every published puzzle changes. Update deliberately
	# (and bump GEN_VERSION + rerun tools/precompute.gd) or not at all.
	var r := P.throw(room(), 45, 60, 1)
	var n: int = r.path.size() / 2
	assert_eq(r.outcome, "floor", "lands on the floor")
	var x30: float = r.path[60]
	var y30: float = r.path[61]
	# Free flight for 30 steps (1/4 s): x = 100 + v cos45 t (with a little drag), y follows gravity.
	var v := P.speed_for(60)
	assert_near(x30, 100.0 + v * 0.70710678 * 0.25 * (1.0 - P.DRAG * 0.125), 1.0, "x after 1/4 s (with a touch of drag)")
	assert_near(y30, 588.0 - v * 0.70710678 * 0.25 + 0.5 * P.GRAVITY * 0.0625, 3.0, "y after 1/4 s")
	assert_gt(n, 40, "flies for a while")


func test_gravity_pulls_down_and_drag_slows():
	var r := P.throw(room([], 60), 90, 50, 1)
	var apex := 1e9
	for i in r.path.size() / 2:
		apex = minf(apex, r.path[i * 2 + 1])
	var v := P.speed_for(50)
	var ideal := 588.0 - v * v / (2.0 * P.GRAVITY)
	assert_gt(apex, ideal, "drag keeps the apex a little below the drag-free one")
	assert_lt(apex, ideal + 20.0, "but only a little")
	assert_eq(r.outcome, "floor", "comes back down")
	assert_near(r.end_x, 100.0, 1.0, "straight up comes straight down")


func test_floor_bounce_loses_energy_and_rests():
	var r := P.throw(room(), 0, 1, 1)   # a gentle push, drops to the floor
	assert_eq(r.outcome, "floor", "rests on the floor")
	assert_near(r.end_y, 700.0 - P.RADIUS, 0.5, "resting on top of the floor")
	assert_gt(r.bounces, 0, "it bounced")
	var heights: Array = []
	var going_up := false
	var prev: float = r.path[1]
	for i in range(1, r.path.size() / 2):
		var y: float = r.path[i * 2 + 1]
		if y < prev and not going_up:
			going_up = true
		elif y > prev and going_up:
			heights.append(prev)
			going_up = false
		prev = y
	for i in range(1, heights.size()):
		assert_gt(heights[i], heights[i - 1], "each bounce peaks lower (y grows downward)")


func test_wall_bounce_reverses():
	var r := P.throw(room([], 60, 700), 180, 80, 1)    # throw backwards into the left wall
	var min_x := 1e9
	for i in r.path.size() / 2:
		min_x = minf(min_x, r.path[i * 2])
	assert_lt(min_x, P.RADIUS + 6.0, "reaches the wall")
	assert_true(min_x >= P.RADIUS - 0.5, "but never into it")
	assert_gt(r.end_x, min_x + 20.0, "bounced back off it")
	assert_true(r.hits.has("wall"), "recorded the wall")


func test_ceiling_blocks():
	var r := P.throw(room([], 300), 90, 100, 1)
	for i in r.path.size() / 2:
		assert_true(r.path[i * 2 + 1] >= 300.0 + P.RADIUS - 0.5, "never above the ceiling")
	assert_true(r.hits.has("ceiling"), "hit the ceiling")


func test_no_tunnelling_through_thin_walls():
	# An 8 px pillar (the thinnest the generator allows) at full power and a flat angle.
	for a in [0, 5, 10, 20]:
		var lv := room([L.rect(400, 300, 8, 400, "pillar")], 60, 700)
		var r := P.throw(lv, a, 100, 1)
		for i in r.path.size() / 2:
			var x: float = r.path[i * 2]
			var y: float = r.path[i * 2 + 1]
			assert_false(x > 408.0 + P.RADIUS and y > 300.0, "went through the pillar at %d deg" % a)


func test_balloon_is_bouncy_and_cake_splats():
	var balloon := room([L.circle(240, 600, 22, "balloon")])
	var rb := P.throw(balloon, 5, 40, 1)
	assert_true(rb.hits.has("balloon"), "hits the balloon")
	var min_x := 1e9
	for i in rb.path.size() / 2:
		min_x = minf(min_x, rb.path[i * 2])
	assert_lt(rb.end_x, 200.0, "the balloon sends it flying back the way it came")
	var cake := room([L.rect(300, 520, 60, 180, "cake")])
	var rc := P.throw(cake, 0, 40, 1)
	assert_eq(rc.outcome, "splat", "the cake ends the throw")


func test_rests_on_a_table():
	var lv := room([L.rect(300, 642, 140, 58, "table")])
	var hit := false
	for p in range(10, 60):
		var r := P.throw(lv, 60, p)
		if r.outcome == "rest":
			hit = true
			assert_near(r.end_y, 642.0 - P.RADIUS, 1.0, "sitting on the table top")
			break
	assert_true(hit, "some throw comes to rest on the table")


func test_catch_detection_and_accuracy():
	var lv := room([], 60, 500, 588)    # hands level with the release point, 400 px away
	var caught := 0
	var best := 1e9
	for p in range(1, 101):
		for a in range(0, 70):
			var r := P.throw(lv, a, p)
			if r.outcome == "catch":
				caught += 1
				best = minf(best, r.catch_d)
				assert_true(r.catch_d <= 34.0, "catch inside the zone")
	assert_gt(caught, 10, "plenty of catching throws")
	assert_lt(best, 6.0, "some throws hit dead centre")


func test_too_fast_is_fumbled():
	var lv := room([], 60, 500, 588)
	var fumbles := 0
	for a in range(0, 21):              # 1240 px/s lasers at the hands
		var r := P.throw(lv, a, 100, 1)
		assert_ne(r.outcome, "catch", "too fast to catch at %d deg" % a)
		if r.outcome == "fumble":
			fumbles += 1
			assert_true(r.hits.has("fumble"), "recorded")
	assert_gt(fumbles, 0, "some lasers reach the hands and get fumbled")
	var slow := false
	for p in range(1, 101):
		if P.throw(lv, 20, p).outcome == "catch":
			slow = true
	assert_true(slow, "a softer arc to the same spot is caught")


func test_outdoors_can_fly_away_and_wind_pushes():
	var lv := room([], -1)
	assert_eq(P.throw(lv, 30, 100).outcome, "out", "no walls outdoors")
	var calm := P.throw(lv, 90, 40)
	lv.wind = 80
	var windy := P.throw(lv, 90, 40)
	assert_gt(windy.end_x, calm.end_x + 10.0, "wind to the right pushes right")


func test_preview_stops_early_and_matches_full_flight():
	var lv := room()
	var c := P.compile(lv)
	var full := P.simulate(c, 50, 70, 3)
	var prev := P.simulate(c, 50, 70, 3, 30, true)
	assert_eq(prev.outcome, "preview", "preview outcome")
	for i in prev.path.size():
		assert_eq(prev.path[i], full.path[i], "preview follows the real path exactly")


const GOLDEN := ["splat:51:f3b8375f", "floor:200:f7f8f068", "rest:284:c7b80c0b", "floor:285:9dc7dca5",
	"floor:219:08df096f", "floor:227:e90f63d2", "floor:198:ad6834ff", "floor:101:9845433b",
	"floor:138:b4171c0b", "floor:193:34a5f39f", "floor:201:df10d292", "out:172:4c81cb21",
	"floor:247:88325214", "out:84:6c908fdb", "out:36:d7b350b8", "floor:104:1ba44a61"]


func test_same_flights_on_every_platform():
	# Pinned bit-for-bit. Passing natively and with `gck test --browser` (WebAssembly in a real
	# browser) shows identical inputs give identical flights across runtimes. If a deliberate
	# physics change breaks this, regenerate with tools/checksums.gd, bump GEN_VERSION and
	# rerun tools/precompute.gd.
	var got := golden_checksums()
	for i in GOLDEN.size():
		assert_eq(got[i], GOLDEN[i], "flight %d" % i)


## Every position of a set of throws through a busy room and a generated venue, hashed.
## The same numbers must come out natively and in every browser (run `gck test --browser`).
static func golden_checksums() -> Array:
	const Gen = preload("res://core/generator.gd")
	const Rng = preload("res://core/rng.gd")
	var busy := {
		"w": 800, "h": 760, "floor": 700, "ceiling": 120, "wind": 0, "mirror": false,
		"release": [100, 588], "thrower": {"x": 84, "feet": 700, "face": 1, "look": 0},
		"target": {"x": 690, "feet": 700, "hands": [690, 568], "r": 34, "look": 0},
		"solids": [L.rect(260, 642, 120, 58, "table"), L.circle(330, 380, 26, "chandelier"),
			L.circle(470, 520, 20, "balloon"), L.rect(540, 300, 24, 260, "curtain"), L.rect(600, 640, 60, 60, "cake")],
		"decor": [], "archetype": "open",
	}
	var venue := Gen.make("2026-11-11", 27, 123456789, 0, "garden")
	var out: Array = []
	for lv in [busy, venue]:
		var c := P.compile(lv)
		for pair in [[10, 100], [35, 80], [48, 62], [63, 90], [80, 55], [120, 70], [160, 95], [200, 40]]:
			var r := P.simulate(c, pair[0], pair[1], 1)
			var bytes: PackedByteArray = (r.path as PackedFloat64Array).to_byte_array()
			out.append("%s:%d:%08x" % [r.outcome, r.steps, Rng.hash_str(Marshalls.raw_to_base64(bytes))])
	return out
