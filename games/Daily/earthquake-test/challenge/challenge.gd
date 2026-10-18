extends RefCounted
## DailyChallenge: everything that defines one day's puzzle, built once by generator.gd.
## Same date + same generator version -> the same challenge on every device.
##
## The quake's sampled record is synthesized lazily (make_quake) because the generator
## scores many candidate days from the cheap analytic estimate alone.

const Arch = preload("res://challenge/archetypes.gd")
const Quake = preload("res://quake/quake.gd")
const QuakeV1 = preload("res://quake/quake_v1.gd")
const Terrain = preload("res://site/terrain.gd")

var date := ""
var version := 2
var rng_seed := 0                     # seed of the winning candidate
var candidate := -1               # which candidate won (-1: fallback / legacy)
var fallback := false
var quake_archetype := ""         # "" for legacy days
var quake_spec := {}              # archetypes.draw_quake() output (v2)
var site_archetype := ""
var suggested_site := ""          # the plan's site for the day (the curator may override)
var anchors: Array = []           # Vector2i, cm, standing on the terrain
var terrain_archetype := ""       # "" before v3 (flat ground)
var terrain := PackedInt32Array() # heights (cm) every metre, site/terrain.gd; empty = flat
var soil := ""
var budget := 50
var modifier := ""                # "" = normal day
var modifier_params := {}         # e.g. {min_height: 5.0} {top_mass: 30.0}
var mat_costs: Array = [1.0, 3.0] # $/m per Sim.Mat
var metrics := {}                 # difficulty, spread, psa, energy, dominant_hz
var novelty := -1.0               # fingerprint distance to the nearest earlier day in its run
var score := 0.0                  # selection score
var rejected := 0                 # candidates rejected as invalid
var fingerprint := PackedFloat32Array()
var _quake = null


func is_legacy() -> bool:
	return version == 1


func make_quake():
	if _quake != null:
		return _quake
	if is_legacy():
		_quake = QuakeV1.new()
		_quake.make(date)
	else:
		_quake = Quake.new()
		_quake.make_from_spec(quake_spec)
	return _quake


func mat_cost(m: int) -> float:
	return float(mat_costs[m])


func top_mass() -> float:
	return float(modifier_params.get("top_mass", 0.0))


func min_height() -> float:
	return float(modifier_params.get("min_height", 0.0))


## Ground heights (cm) every metre; flat for days before terrain.
func ground() -> PackedInt32Array:
	return terrain if not terrain.is_empty() else Terrain.flat()


func terrain_name() -> String:
	return Terrain.terrain_name(terrain_archetype if terrain_archetype != "" else "flat")


func quake_name() -> String:
	return Arch.quake_name(quake_archetype) if quake_archetype != "" else ""


## Player-facing description of today's condition, or "" on a normal day.
func modifier_text() -> String:
	match modifier:
		"steel_shortage", "cheap_steel":
			return "Steel costs $%s/m today" % _money(mat_costs[1])
		"timber_shortage":
			return "Wood costs $%s/m today" % _money(mat_costs[0])
		"heavy_top":
			return "A %d kg weight rides on your highest joint" % int(top_mass())
		"aftershock":
			return "A second, smaller quake follows a few seconds later"
		"min_height":
			return "Build up to the %s m line before the quake can start" % _money(min_height())
	return ""


static func _money(v: float) -> String:
	return ("%d" % int(v)) if is_equal_approx(v, round(v)) else ("%.2f" % v).trim_suffix("0")


## JSON-safe summary for tests, debugging and calibration (quake components summarised).
func to_dict() -> Dictionary:
	var d := {
		"date": date, "version": version, "seed": rng_seed, "candidate": candidate, "fallback": fallback,
		"quake": quake_archetype, "soil": soil, "site": site_archetype,
		"anchors": anchors.map(func(a): return a.x), "budget": budget,
		"terrain": terrain_archetype, "ground": Array(terrain), "anchor_y": anchors.map(func(a): return a.y),
		"modifier": modifier, "modifier_params": modifier_params, "mat_costs": mat_costs,
		"novelty": snappedf(novelty, 0.0001), "score": snappedf(score, 0.0001), "rejected": rejected,
	}
	if not is_legacy():
		var q := quake_spec
		d["magnitude"] = q.magnitude
		d["pga"] = snappedf(float(q.pga), 0.0001)
		d["duration"] = q.duration
		d["v_ratio"] = snappedf(float(q.v_ratio), 0.0001)
		d["events"] = q.events.map(func(e): return [snappedf(e.t0, 0.001), snappedf(e.level, 0.001), e.h.size()])
		d["pulses"] = q.pulses.map(func(p): return [snappedf(p.t, 0.001), snappedf(p.period, 0.001), p.amp, p.sign])
		d["spec_hash"] = str(q).hash()
		var m := {}
		for k in metrics:
			var v = metrics[k]
			m[k] = Array(v).map(func(x): return snappedf(x, 0.0001)) if v is PackedFloat32Array else (snappedf(v, 0.0001) if v is float else v)
		d["metrics"] = m
	return d
