extends RefCounted
## Data tables for the daily challenge generator: quake archetypes, site archetypes,
## soils and engineering modifiers, plus the seeded draw that turns an archetype into a
## concrete quake spec (events, pulses, frequency content) for quake/waveform.gd.
##
## Everything here is pure data + seeded math: same inputs + same RNG state -> same spec.

# ------------------------------------------------------------------ quakes

const QUAKES := ["long_roller", "jackhammer", "near_fault", "double_tap", "vertical", "slow_burner", "broadband"]

## Player-facing name and a one-line read of what the quake does to a structure.
const QUAKE_INFO := {
	"long_roller": {"name": "Long Roller", "tip": "Slow, heavy sways. Tall, bendy towers swing hard."},
	"jackhammer": {"name": "Jackhammer", "tip": "Short and violent rattling. Stiff, squat builds take the hits."},
	"near_fault": {"name": "Fault Pulse", "tip": "Mild shaking, then one huge sideways kick."},
	"double_tap": {"name": "Double Tap", "tip": "A quake, a pause, then a second strong burst."},
	"vertical": {"name": "Vertical Jolt", "tip": "Strong up-and-down shaking. Members get crushed."},
	"slow_burner": {"name": "Slow Burner", "tip": "Moderate shaking that just keeps going."},
	"broadband": {"name": "All-Rounder", "tip": "A bit of everything, slow and fast."},
}

## Seeded parameter ranges per archetype. Frequencies in Hz, times in s, pga in m/s^2.
## h: horizontal band [lo, hi], peak [lo, hi], width (log-gaussian sigma).
## v: vertical band and ratio (peak vertical accel / peak horizontal accel).
const QUAKE_PARAMS := {
	"long_roller": {"mag": [7.0, 7.8], "pga": [3.8, 5.6], "rise": [2.5, 4.0], "strong": [8.0, 12.0], "decay": [4.0, 6.0],
		"h_band": [0.25, 1.6], "h_peak": [0.5, 0.9], "h_width": 0.32, "v_band": [1.0, 4.0], "v_ratio": [0.18, 0.32]},
	"jackhammer": {"mag": [5.7, 6.5], "pga": [5.2, 7.6], "rise": [0.4, 0.8], "strong": [3.2, 5.0], "decay": [1.5, 2.5],
		"h_band": [1.6, 6.5], "h_peak": [2.5, 4.0], "h_width": 0.32, "v_band": [4.0, 10.0], "v_ratio": [0.35, 0.55]},
	"near_fault": {"mag": [6.5, 7.2], "pga": [6.5, 9.5], "rise": [0.8, 1.4], "strong": [4.0, 6.0], "decay": [2.0, 3.0],
		"h_band": [0.8, 4.0], "h_peak": [1.5, 2.5], "h_width": 0.5, "v_band": [3.0, 8.0], "v_ratio": [0.3, 0.45],
		"bg_level": [0.32, 0.45], "pulse_period": [0.8, 1.8]},
	"double_tap": {"mag": [6.4, 7.0], "pga": [4.6, 6.6], "rise": [1.0, 1.5], "strong": [3.0, 4.5], "decay": [1.5, 2.0],
		"h_band": [0.7, 3.5], "h_peak": [1.1, 2.0], "h_width": 0.4, "v_band": [3.0, 8.0], "v_ratio": [0.28, 0.42],
		"lull": [2.5, 4.0], "second": [0.85, 1.0]},
	"vertical": {"mag": [6.0, 6.8], "pga": [5.0, 7.0], "rise": [0.6, 1.0], "strong": [3.5, 5.0], "decay": [2.0, 3.0],
		"h_band": [0.8, 3.5], "h_peak": [1.4, 2.2], "h_width": 0.4, "v_band": [1.5, 6.0], "v_peak": [2.5, 3.5], "v_ratio": [1.1, 1.5]},
	"slow_burner": {"mag": [7.3, 7.9], "pga": [3.2, 4.6], "rise": [3.0, 4.5], "strong": [13.0, 17.0], "decay": [4.0, 5.0],
		"h_band": [0.5, 2.6], "h_peak": [0.9, 1.5], "h_width": 0.42, "v_band": [2.0, 6.0], "v_ratio": [0.22, 0.36]},
	"broadband": {"mag": [6.4, 7.2], "pga": [4.2, 6.5], "rise": [1.2, 2.0], "strong": [5.0, 8.0], "decay": [3.0, 4.0],
		"h_band": [0.3, 6.0], "h_peak": [0.9, 1.8], "h_width": 1.1, "v_band": [2.0, 9.0], "v_ratio": [0.3, 0.5]},
}

## Archetype checks used by the validator and tests: the synthesized quake's dominant
## horizontal frequency and duration must land in these ranges.
const QUAKE_LIMITS := {
	"long_roller": {"f": [0.3, 1.15], "dur": [14.0, 25.0]},
	"jackhammer": {"f": [1.8, 5.5], "dur": [4.5, 10.0]},
	"near_fault": {"f": [0.4, 3.5], "dur": [7.0, 13.0]},
	"double_tap": {"f": [0.5, 4.0], "dur": [12.0, 22.0]},
	"vertical": {"f": [0.7, 3.5], "dur": [6.0, 11.0]},
	"slow_burner": {"f": [0.55, 2.4], "dur": [19.0, 29.0]},
	"broadband": {"f": [0.4, 4.5], "dur": [9.0, 16.0]},
}

const N_COMPS := 36          # sinusoids per event band (horizontal)
const N_COMPS_V := 16        # vertical

# ------------------------------------------------------------------ soils

const SOILS := ["bedrock", "firm", "soft"]
const SOIL_INFO := {
	"bedrock": {"name": "Bedrock", "tip": "Hard rock keeps the fast, sharp shaking."},
	"firm": {"name": "Firm Ground", "tip": "Ordinary ground. Nothing amplified."},
	"soft": {"name": "Soft Soil", "tip": "Mud amplifies slow sways and draws the shaking out."},
}
const SOIL_WEIGHT := {"bedrock": 0.3, "firm": 0.38, "soft": 0.32}
## How well each soil suits each quake (0..1). Low values are allowed but rarely win.
const SOIL_AFFINITY := {
	"long_roller": {"bedrock": 0.25, "firm": 0.7, "soft": 1.0},
	"jackhammer": {"bedrock": 1.0, "firm": 0.75, "soft": 0.15},
	"near_fault": {"bedrock": 0.8, "firm": 0.9, "soft": 0.55},
	"double_tap": {"bedrock": 0.7, "firm": 0.8, "soft": 0.75},
	"vertical": {"bedrock": 0.9, "firm": 0.85, "soft": 0.35},
	"slow_burner": {"bedrock": 0.4, "firm": 0.8, "soft": 0.95},
	"broadband": {"bedrock": 0.75, "firm": 1.0, "soft": 0.7},
}


## Frequency gain of a soil column. Soft soil resonates near its site frequency and
## filters the fast stuff; bedrock keeps high frequencies and drops the slowest.
static func soil_gain(soil: String, f: float, site_f: float) -> float:
	match soil:
		"bedrock":
			var s := clampf((log(f) - log(0.6)) / (log(3.5) - log(0.6)), 0.0, 1.0)
			return 0.65 + 0.7 * s * s * (3.0 - 2.0 * s)
		"soft":
			var q := (f - site_f) / (0.4 * site_f)
			return (0.7 + 1.6 / (1.0 + q * q)) / (1.0 + pow(f / 3.2, 2.0))
	return 1.0


# ------------------------------------------------------------------ sites

const SITES := ["wide", "narrow", "three_point", "asymmetric", "center_cluster", "split"]
const SITE_INFO := {
	"wide": {"name": "Wide Footing"},
	"narrow": {"name": "Narrow Footing"},
	"three_point": {"name": "Three-Point Footing"},
	"asymmetric": {"name": "Lopsided Footing"},
	"center_cluster": {"name": "Tight Cluster"},
	"split": {"name": "Split Footing"},
}
## Quake x site pairings the curator likes (0..1; missing = 0.6).
const SITE_AFFINITY := {
	"long_roller": {"narrow": 1.0, "wide": 0.75, "center_cluster": 0.8, "three_point": 0.55},
	"jackhammer": {"wide": 0.95, "asymmetric": 0.8, "split": 0.7, "narrow": 0.65},
	"near_fault": {"split": 0.95, "asymmetric": 0.9, "narrow": 0.7, "wide": 0.6},
	"double_tap": {"three_point": 0.85, "wide": 0.7, "center_cluster": 0.75},
	"vertical": {"center_cluster": 0.95, "narrow": 0.85, "three_point": 0.7},
	"slow_burner": {"wide": 0.85, "three_point": 0.85, "split": 0.7},
	"broadband": {"three_point": 0.8, "asymmetric": 0.75, "split": 0.75},
}

# ------------------------------------------------------------------ modifiers

const MODIFIERS := ["steel_shortage", "cheap_steel", "timber_shortage", "heavy_top", "aftershock", "min_height"]
## costs: per-material $/m overrides [wood, steel]. Values are applied by the challenge.
const MODIFIER_INFO := {
	"steel_shortage": {"name": "Steel Shortage", "costs": [1.0, 4.0]},
	"cheap_steel": {"name": "Cheap Steel", "costs": [1.0, 2.0]},
	"timber_shortage": {"name": "Timber Shortage", "costs": [2.0, 3.0]},
	"heavy_top": {"name": "Heavy Top"},
	"aftershock": {"name": "Aftershock"},
	"min_height": {"name": "Minimum Height"},
}
## Quake x modifier fit (0..1; missing = 0.6; 0 = never).
const MODIFIER_AFFINITY := {
	"long_roller": {"heavy_top": 1.0, "timber_shortage": 0.8, "aftershock": 0.5, "min_height": 0.8},
	"jackhammer": {"steel_shortage": 0.9, "min_height": 0.95, "aftershock": 0.75},
	"near_fault": {"aftershock": 0.85, "cheap_steel": 0.75, "heavy_top": 0.7},
	"double_tap": {"aftershock": 0.0, "steel_shortage": 0.8, "heavy_top": 0.6},
	"vertical": {"heavy_top": 0.95, "steel_shortage": 0.85, "aftershock": 0.6},
	"slow_burner": {"aftershock": 0.0, "timber_shortage": 0.85, "cheap_steel": 0.8},
	"broadband": {"heavy_top": 0.75, "min_height": 0.75, "aftershock": 0.8},
}
const HEAVY_TOP_KG := 30.0
const PROB_MODIFIER_DAY := 0.3   # a day can carry a modifier only if the day before couldn't


static func affinity(table: Dictionary, quake: String, key: String) -> float:
	return float(table.get(quake, {}).get(key, 0.6))


static func quake_name(id: String) -> String:
	return String(QUAKE_INFO.get(id, {}).get("name", id.capitalize()))


static func soil_name(id: String) -> String:
	return String(SOIL_INFO.get(id, {}).get("name", id.capitalize()))


static func site_name(id: String) -> String:
	return String(SITE_INFO.get(id, {}).get("name", id.capitalize()))


static func modifier_name(id: String) -> String:
	return String(MODIFIER_INFO.get(id, {}).get("name", id.capitalize()))


# ------------------------------------------------------------------ quake spec draw

static func _r(rng: RandomNumberGenerator, range_: Array) -> float:
	return rng.randf_range(float(range_[0]), float(range_[1]))


## Random-phase sinusoids spread log-uniformly over [f_lo, f_hi], shaped by a log-gaussian
## bump at f_peak and by the soil, with a random amplitude jitter per component.
## Each entry: [accel amplitude, omega, phase].
static func band(rng: RandomNumberGenerator, n: int, f_lo: float, f_hi: float, f_peak: float, width: float, soil: String, site_f: float) -> Array:
	var out: Array = []
	var l0 := log(f_lo)
	var l1 := log(f_hi)
	for i in n:
		var u := (i + rng.randf()) / n
		var f := exp(lerpf(l0, l1, u))
		# equal energy per log-frequency step, shaped by the bump, so the dominant frequency
		# sits at f_peak however wide the band is
		var z := log(f / f_peak) / width
		var shape := exp(-0.5 * z * z)
		var amp := sqrt(shape * (l1 - l0) / n) * soil_gain(soil, f, site_f) * rng.randf_range(0.55, 1.45)
		out.append([amp, TAU * f, rng.randf() * TAU])
	return out


static func _event(t0: float, rise: float, strong: float, decay: float, level: float, h: Array, v: Array) -> Dictionary:
	return {"t0": t0, "rise": rise, "strong": strong, "decay": decay, "level": level, "h": h, "v": v}


## Draw a full quake spec for an archetype + soil (+ optional aftershock modifier).
static func draw_quake(arch: String, soil: String, modifier: String, rng: RandomNumberGenerator) -> Dictionary:
	var p: Dictionary = QUAKE_PARAMS[arch]
	var site_f := rng.randf_range(0.65, 1.3)
	var soft := soil == "soft"
	var stretch := 1.1 if soft else 1.0          # soft soil draws the shaking out a little
	var spec := {
		"archetype": arch, "soil": soil, "site_f": site_f,
		"magnitude": snappedf(_r(rng, p.mag), 0.1),
		"pga": _r(rng, p.pga) * (0.92 if soft else (1.04 if soil == "bedrock" else 1.0)),
		"v_ratio": _r(rng, p.v_ratio), "events": [], "pulses": [],
	}
	var hb: Array = p.h_band
	var vb: Array = p.v_band
	var f_peak := _r(rng, p.h_peak)
	var v_peak := _r(rng, p.v_peak) if p.has("v_peak") else sqrt(float(vb[0]) * float(vb[1]))
	var rise := _r(rng, p.rise)
	var strong := _r(rng, p.strong) * stretch
	var decay := _r(rng, p.decay) * stretch
	var hw := float(p.h_width)
	var vsoil := "firm" if soil == "soft" else soil   # vertical waves barely see the soft layer
	match arch:
		"near_fault":
			var lvl := _r(rng, p.bg_level)
			spec.events.append(_event(0.0, rise, strong, decay, lvl, band(rng, N_COMPS, hb[0], hb[1], f_peak, hw, soil, site_f), band(rng, N_COMPS_V, vb[0], vb[1], v_peak, 0.5, vsoil, site_f)))
			var total := rise + strong + decay
			var tp := _r(rng, p.pulse_period)
			var sign := 1.0 if rng.randf() < 0.5 else -1.0
			var t1 := rng.randf_range(rise + 0.4, rise + strong * 0.85)
			spec.pulses.append({"t": t1, "period": tp, "amp": 1.0, "sign": sign})
			if rng.randf() < 0.35:   # a smaller rebound pulse
				var t2 := minf(t1 + rng.randf_range(2.0, 3.5), total - 1.0)
				if t2 > t1 + 1.5:
					spec.pulses.append({"t": t2, "period": tp * rng.randf_range(0.7, 0.9), "amp": rng.randf_range(0.55, 0.75), "sign": -sign})
		"double_tap":
			spec.events.append(_event(0.0, rise, strong, decay, 1.0, band(rng, N_COMPS, hb[0], hb[1], f_peak, hw, soil, site_f), band(rng, N_COMPS_V, vb[0], vb[1], v_peak, 0.5, vsoil, site_f)))
			var t2 := rise + strong + decay + _r(rng, p.lull)
			var shift := rng.randf_range(0.6, 0.8) if rng.randf() < 0.5 else rng.randf_range(1.35, 1.7)
			var fp2 := clampf(f_peak * shift, float(hb[0]) * 1.2, float(hb[1]) * 0.85)
			spec.events.append(_event(t2, rng.randf_range(0.5, 1.0), rng.randf_range(2.5, 4.0) * stretch, rng.randf_range(1.5, 2.5) * stretch,
				_r(rng, p.second), band(rng, N_COMPS, hb[0], hb[1], fp2, hw, soil, site_f), band(rng, N_COMPS_V, vb[0], vb[1], v_peak, 0.5, vsoil, site_f)))
		_:
			spec.events.append(_event(0.0, rise, strong, decay, 1.0, band(rng, N_COMPS, hb[0], hb[1], f_peak, hw, soil, site_f), band(rng, N_COMPS_V, vb[0], vb[1], v_peak, 0.5, vsoil, site_f)))
	if modifier == "aftershock":
		var end := _events_end(spec)
		var fpa := clampf(f_peak * rng.randf_range(1.1, 1.5), float(hb[0]), float(hb[1]))
		spec.events.append(_event(end + rng.randf_range(4.0, 6.0), 0.5, rng.randf_range(2.0, 3.0), 1.5, rng.randf_range(0.5, 0.62),
			band(rng, N_COMPS, hb[0], hb[1], fpa, hw, soil, site_f), band(rng, N_COMPS_V, vb[0], vb[1], v_peak, 0.5, vsoil, site_f)))
	spec["duration"] = snappedf(_events_end(spec) + 0.25, 0.05)
	spec["seed"] = rng.randi()
	return spec


static func _events_end(spec: Dictionary) -> float:
	var end := 0.0
	for e in spec.events:
		end = maxf(end, float(e.t0) + float(e.rise) + float(e.strong) + float(e.decay))
	for pl in spec.pulses:
		end = maxf(end, float(pl.t) + float(pl.period) * 1.5)
	return end
