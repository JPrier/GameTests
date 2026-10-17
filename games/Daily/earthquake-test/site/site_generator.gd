extends RefCounted
## Site archetypes: families of anchor layouts on the flat build site. Each archetype fixes
## the *shape* (how many anchors, how the gaps relate) and the seed picks the exact
## layout within it, so a "Wide" day always reads as wide but never repeats exactly.
##
## Anchors are build points in centimetres on y = 0, on whole metres, inside [X_MIN, X_MAX].

const U := 100
const X_MIN := 2
const X_MAX := 12
const MIN_GAP := 2


static func make(arch: String, rng: RandomNumberGenerator) -> Array:
	var xs: Array = []
	var mirror := rng.randf() < 0.5
	match arch:
		"wide":
			var gap := rng.randi_range(8, 10)
			var start := clampi(7 - gap / 2 + rng.randi_range(-1, 1), X_MIN, X_MAX - gap)
			xs = [start, start + gap]
		"narrow":
			var gap := rng.randi_range(2, 3)
			var start := clampi(rng.randi_range(5, 8) - gap / 2, X_MIN, X_MAX - gap)
			xs = [start, start + gap]
		"three_point":
			var g1 := rng.randi_range(3, 5)
			var g2 := clampi(g1 + rng.randi_range(-1, 1), 3, 5)
			var start := clampi(7 - (g1 + g2) / 2 + rng.randi_range(-1, 1), X_MIN, X_MAX - g1 - g2)
			xs = [start, start + g1, start + g1 + g2]
		"asymmetric":
			# a tight pair hugging one side, the third anchor a wider step away
			var g1 := rng.randi_range(2, 3)
			var g2 := rng.randi_range(4, 6)
			var start := X_MIN + rng.randi_range(0, 1)
			xs = [start, start + g1, start + g1 + g2]
		"center_cluster":
			var g1 := 2
			var g2 := rng.randi_range(2, 3)
			var start := clampi(7 - (g1 + g2) / 2 + rng.randi_range(-1, 1), X_MIN, X_MAX - g1 - g2)
			xs = [start, start + g1, start + g1 + g2]
		"split":
			var g2 := rng.randi_range(7, 8)
			var start := clampi(X_MIN + rng.randi_range(0, 1), X_MIN, X_MAX - 2 - g2)
			xs = [start, start + 2, start + 2 + g2]
		_:
			xs = [5, 9]
	if mirror:   # reflect about the middle of the site
		xs = xs.map(func(x): return X_MIN + X_MAX - int(x))
		xs.sort()
	var anchors: Array = []
	for x in xs:
		anchors.append(Vector2i(int(x) * U, 0))
	return anchors


## "" when the layout is buildable, else the reason.
static func problem(anchors: Array) -> String:
	if anchors.size() < 2 or anchors.size() > 3:
		return "need 2-3 anchors"
	var prev := -1000
	for a in anchors:
		var p: Vector2i = a
		if p.y != 0:
			return "anchor off the ground"
		if p.x % U != 0:
			return "anchor off the metre grid"
		var x := p.x / U
		if x < X_MIN or x > X_MAX:
			return "anchor outside the site"
		if x - prev < MIN_GAP:
			return "anchors too close or unsorted"
		prev = x
	return ""


## Shape features for fingerprints: spread (m), asymmetry 0..1, count, smallest gap (m).
static func features(anchors: Array) -> Dictionary:
	var xs: Array = anchors.map(func(a): return float(a.x) / U)
	var spread: float = xs[-1] - xs[0]
	var asym := 0.0
	var min_gap := spread
	if xs.size() == 3:
		var g1: float = xs[1] - xs[0]
		var g2: float = xs[2] - xs[1]
		asym = absf(g1 - g2) / maxf(g1 + g2, 1e-6)
		min_gap = minf(g1, g2)
	var center: float = (xs[0] + xs[-1]) / 2.0
	return {"spread": spread, "asym": asym, "count": xs.size(), "min_gap": min_gap,
		"offset": absf(center - (X_MIN + X_MAX) / 2.0)}
