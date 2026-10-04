extends RefCounted
## Today's earthquake: a seeded ground-motion record shared by every player.
## offset(t) gives the ground displacement (metres) t seconds into the shaking.
## Built as a few sinusoids in acceleration space under an envelope (ramp, strong
## shaking, decay), then scaled so its peak ground acceleration matches the magnitude.

const SAMPLE_HZ := 60.0

var magnitude := 6.5
var duration := 12.0
var pga := 4.0                 # peak ground acceleration, m/s^2
var dominant_hz := 1.5
var rise := 2.0
var strong := 5.0
var decay := 2.0
var hx: Array = []             # horizontal components: [amp, omega, phase]
var hy: Array = []             # vertical components
var scale := 1.0
var trace := PackedFloat32Array()   # horizontal accel samples (normalised -1..1) for the seismograph


func make(seed_text: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("quake:" + seed_text).hash()
	magnitude = snappedf(rng.randf_range(6.0, 7.6), 0.1)
	var k := (magnitude - 6.0) / 1.6               # 0..1
	pga = lerpf(3.0, 7.0, k)                         # ~0.3 g .. 0.7 g
	duration = snappedf(lerpf(9.0, 15.0, k) + rng.randf_range(-1.0, 1.0), 0.5)
	rise = rng.randf_range(1.0, 2.5)
	strong = rng.randf_range(0.35, 0.55) * duration
	decay = duration - rise - strong
	dominant_hz = snappedf(rng.randf_range(0.5, 2.0), 0.1)
	hx.clear()
	hy.clear()
	hx.append([1.0, TAU * dominant_hz, rng.randf() * TAU])
	for i in 3:
		hx.append([rng.randf_range(0.2, 0.55), TAU * rng.randf_range(0.4, 3.5), rng.randf() * TAU])
	for i in 2:
		hy.append([rng.randf_range(0.5, 1.0), TAU * rng.randf_range(2.0, 6.0), rng.randf() * TAU])
	# normalise so peak horizontal acceleration == pga
	scale = 1.0
	var peak := 0.0
	var samples := int(duration * SAMPLE_HZ)
	var raw := PackedFloat32Array()
	raw.resize(samples)
	for s in samples:
		var a := _accel(hx, s / SAMPLE_HZ)
		raw[s] = a
		peak = maxf(peak, absf(a))
	scale = pga / maxf(peak, 1e-6)
	trace = PackedFloat32Array()
	trace.resize(samples)
	for s in samples:
		trace[s] = raw[s] / peak


func envelope(t: float) -> float:
	if t <= 0.0 or t >= duration:
		return 0.0
	if t < rise:
		var u := t / rise
		return u * u * (3.0 - 2.0 * u)
	if t < rise + strong:
		return 1.0
	var d := (t - rise - strong) / maxf(decay, 0.01)
	return pow(1.0 - clampf(d, 0.0, 1.0), 2.0)


## Acceleration of a component set (unscaled), including the envelope.
func _accel(comps: Array, t: float) -> float:
	var e := envelope(t)
	if e == 0.0:
		return 0.0
	var s := 0.0
	for c in comps:
		s += c[0] * sin(c[1] * t + c[2])
	return s * e


## Ground displacement at t. Each component's displacement is -accel/omega^2, which keeps
## low frequencies from drifting off-screen while preserving the acceleration character.
func offset(t: float) -> Vector2:
	var e := envelope(t)
	if e == 0.0:
		return Vector2.ZERO
	var x := 0.0
	for c in hx:
		x -= c[0] * sin(c[1] * t + c[2]) / (c[1] * c[1])
	var y := 0.0
	for c in hy:
		y -= c[0] * sin(c[1] * t + c[2]) / (c[1] * c[1])
	return Vector2(x * e * scale, y * e * scale * 0.3)


## Normalised shaking intensity at t (0..1) for UI.
func intensity(t: float) -> float:
	return envelope(t)


func describe() -> String:
	return "M%.1f · %ds · %.1f Hz" % [magnitude, int(round(duration)), dominant_hz]
