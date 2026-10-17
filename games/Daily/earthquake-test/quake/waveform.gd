extends RefCounted
## Ground-motion synthesis for Earthquake Test (generator v2).
##
##   seeded random-phase sinusoids (stochastic signal)
##     -> log-gaussian band shaping + soil gain     (archetypes.gd draws the components)
##     -> per-event envelopes (rise / strong / decay), several events per quake
##     -> optional explicit velocity pulses (near-fault kicks)
##     -> horizontal + vertical components
##     -> normalised so peak horizontal accel == pga, peak vertical == v_ratio * pga
##
## Everything is built in displacement space (each sinusoid's displacement is -a/w^2), so the
## record starts and ends at rest with no drift. The result is sampled at a fixed SAMPLE_HZ;
## acceleration is measured from the sampled displacement by second differences, which is
## what the anchors (interpolated with Catmull-Rom in quake.gd) actually feel.
##
## Also provides an analytic response estimate (no time series needed) that the generator
## uses to score many candidate days quickly.

const SAMPLE_HZ := 120.0
const TRACE_HZ := 60.0
const INTENSITY_HZ := 20.0
const DAMPING := 0.05
## Reference oscillator periods (s): stiff squat builds -> tall flexible towers.
const PERIODS := [0.12, 0.25, 0.45, 0.8, 1.4, 2.4]


static func env(e: Dictionary, t: float) -> float:
	var u := t - float(e.t0)
	var rise := float(e.rise)
	var strong := float(e.strong)
	var decay := float(e.decay)
	if u <= 0.0 or u >= rise + strong + decay:
		return 0.0
	if u < rise:
		var s := u / rise
		return s * s * (3.0 - 2.0 * s)
	if u < rise + strong:
		return 1.0
	var d := (u - rise - strong) / maxf(decay, 0.01)
	return (1.0 - d) * (1.0 - d)


## Displacement of a near-fault pulse (relative units). Odd in time, so it returns to rest.
## Its acceleration peaks at 1.38 * A / s^2; A is chosen so that peak equals `amp`.
static func pulse_disp(pl: Dictionary, t: float) -> float:
	var s := float(pl.period) / 4.0
	var u := (t - float(pl.t)) / s
	if absf(u) > 6.0:
		return 0.0
	var a := float(pl.amp) * s * s / 1.38
	return float(pl.sign) * a * u * exp(-0.5 * u * u)


static func _peak_accel(d: PackedFloat64Array) -> float:
	var fs2 := SAMPLE_HZ * SAMPLE_HZ
	var peak := 0.0
	for i in range(1, d.size() - 1):
		peak = maxf(peak, absf((d[i + 1] - 2.0 * d[i] + d[i - 1]) * fs2))
	return peak


static func _comp_disp(out: PackedFloat64Array, comps: Array, e: Dictionary) -> void:
	var t0 := float(e.t0)
	var t1 := t0 + float(e.rise) + float(e.strong) + float(e.decay)
	var i0 := maxi(0, floori(t0 * SAMPLE_HZ))
	var i1 := mini(out.size() - 1, ceili(t1 * SAMPLE_HZ))
	var n := comps.size()
	var amp := PackedFloat64Array()
	var om := PackedFloat64Array()
	var ph := PackedFloat64Array()
	amp.resize(n)
	om.resize(n)
	ph.resize(n)
	for k in n:
		var c: Array = comps[k]
		om[k] = float(c[1])
		amp[k] = float(c[0]) / (om[k] * om[k])
		ph[k] = float(c[2])
	for i in range(i0, i1 + 1):
		var t := i / SAMPLE_HZ
		var e_t := env(e, t)
		if e_t == 0.0:
			continue
		var s := 0.0
		for k in n:
			s -= amp[k] * sin(om[k] * t + ph[k])
		out[i] = s * e_t


## Synthesize the sampled record. Returns {dx, dy (PackedFloat64Array metres),
## trace_h, trace_v (PackedFloat32Array, velocity normalised so |h| peak == 1, v peak == v_ratio),
## intensity (PackedFloat32Array 0..1 at INTENSITY_HZ), pga, pga_v, pgv, pgv_v, max_disp, end_disp}.
static func synthesize(spec: Dictionary) -> Dictionary:
	var duration := float(spec.duration)
	var n := ceili(duration * SAMPLE_HZ) + 2
	var dx := PackedFloat64Array()
	var dy := PackedFloat64Array()
	dx.resize(n)
	dy.resize(n)
	var tmp := PackedFloat64Array()
	tmp.resize(n)
	for e in spec.events:
		# horizontal: each event normalised to its own relative level before mixing
		tmp.fill(0.0)
		_comp_disp(tmp, e.h, e)
		var pk := _peak_accel(tmp)
		if pk > 1e-9:
			var k := float(e.level) / pk
			for i in n:
				dx[i] += tmp[i] * k
		tmp.fill(0.0)
		_comp_disp(tmp, e.v, e)
		pk = _peak_accel(tmp)
		if pk > 1e-9:
			var kv := float(e.level) / pk
			for i in n:
				dy[i] += tmp[i] * kv
	for pl in spec.pulses:
		var a := float(pl.t) - float(pl.period) * 1.6
		var b := float(pl.t) + float(pl.period) * 1.6
		for i in range(maxi(0, floori(a * SAMPLE_HZ)), mini(n, ceili(b * SAMPLE_HZ) + 1)):
			dx[i] += pulse_disp(pl, i / SAMPLE_HZ)
	# normalise
	var pga := float(spec.pga)
	var ph := _peak_accel(dx)
	var sh := pga / maxf(ph, 1e-9)
	var pv := _peak_accel(dy)
	var sv := pga * float(spec.v_ratio) / maxf(pv, 1e-9)
	var max_disp := 0.0
	for i in n:
		dx[i] *= sh
		dy[i] *= sv
		max_disp = maxf(max_disp, maxf(absf(dx[i]), absf(dy[i])))
	# traces for the seismograph: ground velocity (like a real seismometer), downsampled and
	# normalised so the horizontal peak is 1. Velocity shows a slow roll as big, broad waves,
	# a fault pulse as one huge swing and a jackhammer as a short dense buzz.
	var fs2 := SAMPLE_HZ * SAMPLE_HZ
	var step := int(round(SAMPLE_HZ / TRACE_HZ))
	var tn := int((n - 2) / step)
	var trace_h := PackedFloat32Array()
	var trace_v := PackedFloat32Array()
	trace_h.resize(tn)
	trace_v.resize(tn)
	var pgv := 0.0
	var pgv_v := 0.0
	for i in range(0, n - 1):
		pgv = maxf(pgv, absf(dx[i + 1] - dx[i]) * SAMPLE_HZ)
		pgv_v = maxf(pgv_v, absf(dy[i + 1] - dy[i]) * SAMPLE_HZ)
	for j in tn:
		var i := clampi(j * step, 0, n - 2)
		trace_h[j] = (dx[i + 1] - dx[i]) * SAMPLE_HZ / maxf(pgv, 1e-9)
		# vertical: its own shape, sized by how strong it is next to the horizontal shaking
		trace_v[j] = (dy[i + 1] - dy[i]) * SAMPLE_HZ / maxf(pgv_v, 1e-9) * minf(float(spec.v_ratio), 1.2)
	# intensity: smoothed |accel| envelope (horizontal + vertical), normalised to 1
	var istep := int(round(SAMPLE_HZ / INTENSITY_HZ))
	var inn := int(n / istep) + 1
	var inten := PackedFloat32Array()
	inten.resize(inn)
	var best := 0.0
	for j in inn:
		var acc := 0.0
		var cnt := 0
		for i in range(maxi(1, j * istep - istep * 3), mini(n - 1, j * istep + istep * 3)):
			var ax := (dx[i + 1] - 2.0 * dx[i] + dx[i - 1]) * fs2
			var ay := (dy[i + 1] - 2.0 * dy[i] + dy[i - 1]) * fs2
			acc += ax * ax + ay * ay
			cnt += 1
		var v := sqrt(acc / maxf(cnt, 1))
		inten[j] = v
		best = maxf(best, v)
	for j in inn:
		inten[j] = inten[j] / maxf(best, 1e-9)
	return {
		"dx": dx, "dy": dy, "trace_h": trace_h, "trace_v": trace_v, "intensity": inten,
		"pga": _peak_accel(dx), "pga_v": _peak_accel(dy), "pgv": pgv, "pgv_v": pgv_v, "max_disp": max_disp,
		"end_disp": maxf(absf(dx[n - 1]), absf(dy[n - 1])),
	}


# ------------------------------------------------------------------ analytic estimates

## Steady-state |displacement / accel| of a damped oscillator (w0) driven at w.
static func _h2(w0: float, w: float, z: float) -> float:
	var a := w0 * w0 - w * w
	var b := 2.0 * z * w0 * w
	return 1.0 / (a * a + b * b)


## Estimated peak pseudo-acceleration response / pga for each reference period, plus
## sustained-loading "energy" per period. Cheap (no time series), used to score candidates.
## Returns {psa: PackedFloat32Array, energy: PackedFloat32Array, dominant_hz: float, v_ratio}.
static func estimate(spec: Dictionary) -> Dictionary:
	var np := PERIODS.size()
	var psa := PackedFloat32Array()
	var energy := PackedFloat32Array()
	psa.resize(np)
	energy.resize(np)
	for j in np:
		var w0 := TAU / float(PERIODS[j])
		var f0 := 1.0 / float(PERIODS[j])
		var best := 0.0
		var en := 0.0
		for e in spec.events:
			var ds := float(e.strong) + 0.5 * (float(e.rise) + float(e.decay))
			# short shaking can't build full resonance: raise the effective damping
			var z := DAMPING + 1.0 / (PI * f0 * ds)
			var num := 0.0
			var den := 0.0
			for c in e.h:
				var a2 := float(c[0]) * float(c[0])
				num += a2 * _h2(w0, float(c[1]), z)
				den += a2
			var amp := float(e.level) * w0 * w0 * sqrt(num / maxf(den, 1e-12))
			best = maxf(best, amp)
			en += amp * amp * ds
		for pl in spec.pulses:
			var r := float(PERIODS[j]) / float(pl.period)
			var g := exp(-0.5 * pow(log(r / 0.7) / 0.55, 2.0))
			var amp := float(pl.amp) * (1.0 + 1.1 * g) / (1.0 + pow(r / 1.6, 2.0))
			best = maxf(best, amp)
			en += amp * amp * float(pl.period)
		psa[j] = best
		energy[j] = en
	# peak displacement per unit pga: rms displacement / rms accel of each event's band
	var disp := 0.0
	for e in spec.events:
		var num := 0.0
		var den := 0.0
		for c in e.h:
			var a2 := float(c[0]) * float(c[0])
			num += a2 / pow(float(c[1]), 4.0)
			den += a2
		disp = maxf(disp, float(e.level) * sqrt(num / maxf(den, 1e-12)) * 1.25)
	for pl in spec.pulses:
		var s := float(pl.period) / 4.0
		disp = maxf(disp, float(pl.amp) * s * s / 1.38 * exp(-0.5))
	# normalise relative to the strongest event/pulse (the record's peak maps to pga)
	var top := 0.0
	for e in spec.events:
		top = maxf(top, float(e.level))
	for pl in spec.pulses:
		top = maxf(top, float(pl.amp))
	for j in np:
		psa[j] = psa[j] / maxf(top, 1e-9)
		energy[j] = energy[j] / maxf(top * top, 1e-9)
	return {"psa": psa, "energy": energy, "dominant_hz": dominant_hz(spec), "disp_per_pga": disp / maxf(top, 1e-9)}


## Frequency (Hz) carrying the most horizontal acceleration energy (1/6-octave bins).
static func dominant_hz(spec: Dictionary) -> float:
	var bins := {}
	for e in spec.events:
		var den := 0.0
		for c in e.h:
			den += float(c[0]) * float(c[0])
		for c in e.h:
			var f := float(c[1]) / TAU
			var b := int(floor(log(f) / log(2.0) * 6.0))
			bins[b] = float(bins.get(b, 0.0)) + float(e.level) * float(e.level) * float(c[0]) * float(c[0]) / maxf(den, 1e-12)
	for pl in spec.pulses:
		var b := int(floor(log(1.0 / float(pl.period)) / log(2.0) * 6.0))
		bins[b] = float(bins.get(b, 0.0)) + float(pl.amp) * float(pl.amp) * 0.5
	var best_b := 0
	var best := -1.0
	var keys := bins.keys()
	keys.sort()
	for b in keys:
		# smooth over neighbours so one lucky component doesn't decide it
		var v := float(bins.get(b - 1, 0.0)) * 0.5 + float(bins[b]) + float(bins.get(b + 1, 0.0)) * 0.5
		if v > best:
			best = v
			best_b = b
	return pow(2.0, (best_b + 0.5) / 6.0)


# ------------------------------------------------------------------ time-domain check

## Peak pseudo-acceleration of a damped oscillator under a sampled ground displacement
## (Newmark average acceleration). Used by calibration/tests to check estimate().
static func response_spectrum(dx: PackedFloat64Array, periods: Array = PERIODS, z := DAMPING) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(periods.size())
	var dt := 1.0 / SAMPLE_HZ
	var n := dx.size()
	for j in periods.size():
		var w := TAU / float(periods[j])
		var k := w * w
		var c := 2.0 * z * w
		var u := 0.0
		var v := 0.0
		var ag := 0.0
		var a := 0.0
		var peak := 0.0
		var keff := k + 2.0 * c / dt + 4.0 / (dt * dt)
		for i in range(1, n - 1):
			var ag1 := (dx[i + 1] - 2.0 * dx[i] + dx[i - 1]) / (dt * dt)
			var p := -ag1 + (4.0 / (dt * dt) * u + 4.0 / dt * v + a) + c * (2.0 / dt * u + v)
			var u1 := p / keff
			var v1 := 2.0 / dt * (u1 - u) - v
			var a1 := 4.0 / (dt * dt) * (u1 - u) - 4.0 / dt * v - a
			u = u1
			v = v1
			a = a1
			ag = ag1
			peak = maxf(peak, absf(u))
		out[j] = peak * k
	return out
