extends RefCounted
## Compact fingerprint of a daily challenge and a novelty metric between days.
##
## The vector mixes categorical identity (quake / site / soil / modifier one-hots) with the
## continuous character of the day (intensity, duration, frequency, vertical share, pulse,
## site shape, budget, and the reference-oscillator response vector). Distance is plain
## Euclidean; identical challenges are at 0, two days with different everything are ~2.

const Arch = preload("res://challenge/archetypes.gd")
const Site = preload("res://site/site_generator.gd")
const Waveform = preload("res://quake/waveform.gd")

const W_QUAKE := 0.5
const W_SITE := 0.4
const W_SOIL := 0.3
const W_MOD := 0.35
const W_RESP := 0.5


static func _onehot(out: PackedFloat32Array, keys: Array, key: String, w: float) -> void:
	for k in keys:
		out.append(w if k == key else 0.0)


## Fingerprint parts: quake spec + site + budget + modifier + analytic metrics.
static func make(quake_arch: String, spec: Dictionary, site_arch: String, anchors: Array, soil: String,
		budget: int, modifier: String, metrics: Dictionary) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	_onehot(v, Arch.QUAKES, quake_arch, W_QUAKE)
	_onehot(v, Arch.SITES, site_arch, W_SITE)
	_onehot(v, Arch.SOILS, soil, W_SOIL)
	_onehot(v, [""] + Arch.MODIFIERS, modifier, W_MOD)
	var f := Site.features(anchors)
	var pulse := 0.0
	var pulse_t := 0.0
	var top := 0.0
	for e in spec.events:
		top = maxf(top, float(e.level))
	for p in spec.pulses:
		if float(p.amp) > pulse:
			pulse = float(p.amp)
			pulse_t = float(p.t) / float(spec.duration)
	v.append(float(spec.pga) / 8.0)
	v.append(float(spec.duration) / 30.0)
	v.append(log(float(metrics.get("dominant_hz", 1.0))) / log(2.0) / 4.0)
	v.append(float(spec.v_ratio) / 1.5)
	v.append(0.5 * pulse / maxf(top, pulse))
	v.append(0.5 * pulse_t)
	v.append(float(spec.events.size() - 1) * 0.25)
	v.append(float(f.spread) / 10.0)
	v.append(float(f.asym))
	v.append(float(f.count - 2) * 0.4)
	v.append(float(budget) / 70.0)
	var psa: PackedFloat32Array = metrics.get("psa", PackedFloat32Array())
	for x in psa:
		v.append(W_RESP * clampf(x / 3.0, 0.0, 1.5))
	return v


static func distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return 2.0
	var s := 0.0
	for i in a.size():
		var d := a[i] - b[i]
		s += d * d
	return sqrt(s)


## Smallest distance from `fp` to any of `refs` (2.0 when there are none).
static func novelty(fp: PackedFloat32Array, refs: Array) -> float:
	var best := 2.0
	for r in refs:
		best = minf(best, distance(fp, r))
	return best
