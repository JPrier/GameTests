extends RefCounted
## Validity checks for daily challenges. problems() runs on every candidate (cheap: no
## time series); quake_problems() checks a synthesized record and is run by the tests,
## the fuzz suite and the calibration tool over thousands of days.

const Arch = preload("res://challenge/archetypes.gd")
const Site = preload("res://site/site_generator.gd")
const Terrain = preload("res://site/terrain.gd")

const BUDGET_RANGE := [40, 75]
const PGA_RANGE := [1.8, 11.0]         # m/s^2
const MAX_DISP := 1.3                  # m, peak ground displacement
const MAX_END_DISP := 0.01             # m, the ground must come back to rest
const AFTERSHOCK_EXTRA := 11.0         # s an aftershock may add to an archetype's duration


static func _finite(x: float) -> bool:
	return not (is_nan(x) or is_inf(x))


## Reasons a candidate challenge is invalid ([] = valid).
static func problems(c) -> PackedStringArray:
	var out := PackedStringArray()
	var site := Site.problem(c.anchors.map(func(a): return Vector2i(a.x, 0)))
	if site != "":
		out.append("site: " + site)
	var ground := Terrain.problem(c.ground(), c.anchors)
	if ground != "":
		out.append("terrain: " + ground)
	if c.budget < BUDGET_RANGE[0] or c.budget > BUDGET_RANGE[1]:
		out.append("budget %d out of range" % c.budget)
	if c.is_legacy():
		return out
	var q: Dictionary = c.quake_spec
	var lim: Dictionary = Arch.QUAKE_LIMITS[c.quake_archetype]
	var dur := float(q.duration)
	var extra := AFTERSHOCK_EXTRA if c.modifier == "aftershock" else 0.0
	if not _finite(dur) or dur < lim.dur[0] or dur > lim.dur[1] + extra:
		out.append("duration %.1f outside %s" % [dur, str(lim.dur)])
	var f := float(c.metrics.get("dominant_hz", 0.0))
	if not _finite(f) or f < lim.f[0] or f > lim.f[1]:
		out.append("dominant %.2f Hz outside %s" % [f, str(lim.f)])
	var pga := float(q.pga)
	if not _finite(pga) or pga < PGA_RANGE[0] or pga > PGA_RANGE[1]:
		out.append("pga %.2f out of range" % pga)
	if float(c.metrics.get("disp", 0.0)) > MAX_DISP * 0.85:
		out.append("ground displacement too large (%.2f m)" % float(c.metrics.disp))
	if float(q.v_ratio) > 1.6 or float(q.v_ratio) <= 0.0:
		out.append("vertical ratio %.2f" % float(q.v_ratio))
	for x in c.metrics.get("psa", PackedFloat32Array()):
		if not _finite(x) or x <= 0.0:
			out.append("bad response estimate")
			break
	if c.modifier != "" and Arch.affinity(Arch.MODIFIER_AFFINITY, c.quake_archetype, c.modifier) <= 0.0:
		out.append("modifier %s doesn't fit %s" % [c.modifier, c.quake_archetype])
	if c.min_height() > 11.0:
		out.append("minimum height too high")
	for m in c.mat_costs:
		if float(m) <= 0.0:
			out.append("free material")
	return out


## Reasons a synthesized quake record is unusable ([] = fine).
static func quake_problems(quake, arch: String, modifier := "") -> PackedStringArray:
	var out := PackedStringArray()
	var target := float(quake.spec.pga)
	if not _finite(quake.pga) or absf(quake.pga - target) > target * 0.02:
		out.append("pga %.3f != target %.3f" % [quake.pga, target])
	if not _finite(quake.max_disp) or quake.max_disp > MAX_DISP:
		out.append("ground moves %.2f m" % quake.max_disp)
	if not _finite(quake.end_disp) or quake.end_disp > MAX_END_DISP:
		out.append("ground drifts %.3f m" % quake.end_disp)
	for arr in [quake.dx, quake.dy, quake.trace, quake.trace_v]:
		for x in arr:
			if not _finite(x):
				out.append("NaN/inf sample")
				return out
	var lim: Dictionary = Arch.QUAKE_LIMITS[arch]
	var extra := AFTERSHOCK_EXTRA if modifier == "aftershock" else 0.0
	if quake.duration < lim.dur[0] or quake.duration > lim.dur[1] + extra:
		out.append("duration")
	if quake.dominant_hz < lim.f[0] or quake.dominant_hz > lim.f[1]:
		out.append("dominant frequency %.2f" % quake.dominant_hz)
	return out
