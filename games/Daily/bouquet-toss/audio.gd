extends Node
## Tiny synthesized sound kit (no audio files to download): whoosh, thunk, boing, splat,
## a catch chime, an aim tick and a little fanfare. Sounds are made once at start-up.

const RATE := 22050

var enabled := true
var _streams: Dictionary = {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# Build the sounds after the first frames are on screen so start-up stays instant.
	await get_tree().process_frame
	await get_tree().process_frame
	build()


func build() -> void:
	if not _streams.is_empty():
		return
	_streams.whoosh = _make(0.32, func(t, d): return _noise() * _env(t, d, 0.05) * 0.35 * (0.4 + 0.6 * sin(PI * t / d)))
	_streams.thunk = _make(0.16, func(t, d): return sin(TAU * (150.0 - 260.0 * t) * t) * _env(t, d, 0.005) * 0.7)
	_streams.tap = _make(0.09, func(t, d): return (sin(TAU * 520.0 * t) * 0.5 + _noise() * 0.2) * _env(t, d, 0.002) * 0.45)
	_streams.boing = _make(0.3, func(t, d): return sin(TAU * (300.0 + 500.0 * t) * t) * _env(t, d, 0.005) * 0.45)
	_streams.splat = _make(0.35, func(t, d): return (_noise() * 0.7 + sin(TAU * 90.0 * t) * 0.5) * _env(t, d, 0.003) * 0.6)
	_streams.tick = _make(0.03, func(t, d): return sin(TAU * 1400.0 * t) * _env(t, d, 0.001) * 0.18)
	_streams.chime = _make(0.9, func(t, d): return _notes(t, [784.0, 988.0, 1175.0, 1568.0], 0.09) * 0.38)
	_streams.fanfare = _make(1.1, func(t, d): return _notes(t, [523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0], 0.12) * 0.3)
	_streams.miss = _make(0.4, func(t, d): return sin(TAU * (330.0 - 120.0 * t) * t) * _env(t, d, 0.01) * 0.25)


func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not enabled or not _streams.has(name):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func _noise() -> float:
	return randf() * 2.0 - 1.0


func _env(t: float, d: float, attack: float) -> float:
	var a := clampf(t / attack, 0.0, 1.0)
	var r := clampf(1.0 - t / d, 0.0, 1.0)
	return a * r * r


func _notes(t: float, freqs: Array, step: float) -> float:
	var out := 0.0
	for i in freqs.size():
		var t0 := i * step
		if t < t0:
			break
		var lt := t - t0
		out += sin(TAU * float(freqs[i]) * lt) * exp(-lt * 6.0) * 0.6 + sin(TAU * float(freqs[i]) * 2.0 * lt) * exp(-lt * 9.0) * 0.15
	return out


func _make(seconds: float, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := clampf(float(fn.call(t, seconds)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
