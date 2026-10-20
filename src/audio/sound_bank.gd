class_name SoundBank
extends Node
## Procedural sound effects: every AudioStreamWAV is synthesised at boot from
## a seeded generator, so the game ships no audio files. Looping ambiences
## (rumble, hiss) play on dedicated players; one-shots share a pool.

const RATE := 22050

var streams: Dictionary = {}       # id -> AudioStreamWAV
var _loops: Dictionary = {}        # id -> AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var master_volume_db: float = -6.0


func _ready() -> void:
	_rng.seed = 12345
	streams["deep_rumble"] = _make(_rumble(3.0), true)
	streams["gas_hiss"] = _make(_hiss(2.0), true)
	streams["bubbles"] = _make(_bubbles(1.2), false)
	streams["birds_scatter"] = _make(_birds(1.4), false)
	streams["ui_blip"] = _make(_blip(0.07, 880.0), false)
	streams["ui_low"] = _make(_blip(0.12, 220.0), false)
	streams["dig"] = _make(_thud(0.12), false)
	streams["place"] = _make(_blip(0.05, 330.0), false)
	streams["heartbeat"] = _make(_thud(0.25), false)
	streams["footstep"] = _make(_thud(0.5), false)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = master_volume_db
		add_child(p)
		_pool.append(p)


func play(id: String, loop: bool = false, volume_db: float = 0.0) -> void:
	var s: AudioStreamWAV = streams.get(id)
	if s == null:
		return
	if loop:
		if _loops.has(id):
			return
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = master_volume_db + volume_db
		add_child(p)
		p.play()
		_loops[id] = p
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = master_volume_db + volume_db
			p.play()
			return
	_pool[0].stream = s
	_pool[0].play()


func stop(id: String) -> void:
	var p: AudioStreamPlayer = _loops.get(id)
	if p != null:
		p.stop()
		p.queue_free()
		_loops.erase(id)


func stop_all_loops() -> void:
	for id in _loops.keys():
		stop(id)


func set_loop_volume(id: String, volume_db: float) -> void:
	var p: AudioStreamPlayer = _loops.get(id)
	if p != null:
		p.volume_db = master_volume_db + volume_db


# ---- synthesis ----

func _make(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _rumble(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	var lp := 0.0
	for i in n:
		brown += (_rng.randf() * 2.0 - 1.0) * 0.02
		brown *= 0.998
		lp += (brown - lp) * 0.05
		# slow throb
		var throb := 0.6 + 0.4 * sin(float(i) / RATE * TAU * 0.7)
		out[i] = lp * 6.0 * throb
	return _crossfade_loop(out, int(0.2 * RATE))


func _hiss(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.35
		out[i] = lp * 0.35
	return _crossfade_loop(out, int(0.1 * RATE))


func _bubbles(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for b in 9:
		var start := _rng.randi_range(0, n - int(0.12 * RATE))
		var f := _rng.randf_range(300.0, 900.0)
		var len := int(_rng.randf_range(0.05, 0.11) * RATE)
		for i in len:
			var t := float(i) / RATE
			var env := exp(-t * 35.0)
			var freq := f * (1.0 + t * 6.0)   # rising pitch like a bubble
			out[start + i] += sin(t * TAU * freq) * env * 0.5
	return out


func _birds(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for b in 7:
		var start := _rng.randi_range(0, n - int(0.2 * RATE))
		var f0 := _rng.randf_range(1800.0, 3200.0)
		var len := int(0.12 * RATE)
		for i in len:
			var t := float(i) / RATE
			var env := sin(PI * t / 0.12)
			out[start + i] += sin(t * TAU * (f0 + 1200.0 * sin(t * 40.0))) * env * 0.25
	# wing flutter: bursts of noise
	for k in 12:
		var start := _rng.randi_range(0, n - int(0.04 * RATE))
		for i in int(0.03 * RATE):
			out[start + i] += (_rng.randf() * 2.0 - 1.0) * 0.12
	return out


func _blip(seconds: float, freq: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := 1.0 - t / seconds
		out[i] = (1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0) * 0.25 * env
	return out


func _thud(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 18.0)
		out[i] = sin(t * TAU * (90.0 - t * 200.0)) * env * 0.8 + (_rng.randf() * 2.0 - 1.0) * env * 0.1
	return out


static func _crossfade_loop(s: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := s.size()
	for i in fade:
		var a := float(i) / float(fade)
		s[n - fade + i] = s[n - fade + i] * (1.0 - a) + s[i] * a
	return s
