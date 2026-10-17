extends RefCounted
## Generator v1, frozen. Days before generator.CUTOVER were played with this, so they keep
## exactly the site, budget and quake they had (and saved designs still line up).

const Challenge = preload("res://challenge/challenge.gd")

const U := 100
const GW := 14


static func make(d: String) -> RefCounted:
	var c := Challenge.new()
	c.date = d
	c.version = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = ("site:" + d).hash()
	c.rng_seed = ("site:" + d).hash()
	c.budget = rng.randi_range(8, 13) * 5
	var count := rng.randi_range(2, 3)
	var tries_left := 200
	while c.anchors.size() < count and tries_left > 0:
		tries_left -= 1
		var x := rng.randi_range(2, GW - 2)
		var ok := true
		for a in c.anchors:
			if absi(a.x / U - x) < 2:
				ok = false
		if ok:
			c.anchors.append(Vector2i(x * U, 0))
	c.anchors.sort_custom(func(a, b): return a.x < b.x)
	c.mat_costs = [1.0, 3.0]
	return c
