extends RefCounted
## A day's earthquake (generator v2): a sampled ground-motion record shared by every player.
## Same interface the solver and UI use for legacy quakes (quake_v1.gd):
##   offset(t)    ground displacement (m) t seconds into the shaking
##   intensity(t) 0..1 shaking level for UI / visual exaggeration
##   trace        horizontal ground velocity samples (normalised -1..1) for the seismograph
## Built once from a spec by waveform.gd; after that there is no randomness at all.

const Waveform = preload("res://quake/waveform.gd")
const Arch = preload("res://challenge/archetypes.gd")

var spec := {}
var archetype := ""
var soil := ""
var magnitude := 6.5
var duration := 12.0
var pga := 4.0                       # m/s^2, peak horizontal ground acceleration
var pga_v := 1.0                     # m/s^2, peak vertical
var pgv := 0.5                       # m/s, peak horizontal ground velocity
var dominant_hz := 1.5
var max_disp := 0.0
var end_disp := 0.0
var dx := PackedFloat64Array()
var dy := PackedFloat64Array()
var trace := PackedFloat32Array()
var trace_v := PackedFloat32Array()
var _inten := PackedFloat32Array()


func make_from_spec(s: Dictionary) -> void:
	spec = s
	archetype = String(s.archetype)
	soil = String(s.soil)
	magnitude = float(s.magnitude)
	duration = float(s.duration)
	var w := Waveform.synthesize(s)
	dx = w.dx
	dy = w.dy
	trace = w.trace_h
	trace_v = w.trace_v
	_inten = w.intensity
	pga = float(w.pga)
	pga_v = float(w.pga_v)
	pgv = float(w.pgv)
	max_disp = float(w.max_disp)
	end_disp = float(w.end_disp)
	dominant_hz = snappedf(Waveform.dominant_hz(s), 0.05)


static func _cr(d: PackedFloat64Array, t: float, hz: float) -> float:
	var x := t * hz
	var i := floori(x)
	var n := d.size()
	if i < 0 or i >= n - 1:
		return 0.0
	var f := x - i
	var p0 := d[maxi(i - 1, 0)]
	var p1 := d[i]
	var p2 := d[i + 1]
	var p3 := d[mini(i + 2, n - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f)


## Ground displacement at t (metres). Zero before and after the record.
func offset(t: float) -> Vector2:
	if t <= 0.0 or t >= duration:
		return Vector2.ZERO
	return Vector2(_cr(dx, t, Waveform.SAMPLE_HZ), _cr(dy, t, Waveform.SAMPLE_HZ))


func intensity(t: float) -> float:
	if t <= 0.0 or t >= duration or _inten.is_empty():
		return 0.0
	var x := t * Waveform.INTENSITY_HZ
	var i := clampi(floori(x), 0, _inten.size() - 2)
	return clampf(lerpf(_inten[i], _inten[i + 1], x - i), 0.0, 1.0)


func display_name() -> String:
	return Arch.quake_name(archetype)


func describe() -> String:
	return "M%.1f · %ds · %s" % [magnitude, int(round(duration)), display_name()]
