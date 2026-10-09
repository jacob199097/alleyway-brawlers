extends Node
## Game sounds. Until real audio exists they are synthesised at startup; drop a file at
## res://assets/sfx/<name>.wav or .ogg and it is used instead.
##   Sfx.play("slam")   Sfx.play("draw", 1.1)   Sfx.play("hit", 1.0, -3.0)

const RATE := 22050
const VOICES := 12

var volume_db := -3.0
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)


func play(sound: String, pitch := 1.0, gain_db := 0.0) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db + gain_db
	p.play()


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var stream: AudioStream = null
	for ext in ["wav", "ogg"]:
		var path := "res://assets/sfx/%s.%s" % [sound, ext]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	if stream == null and has_method("_r_" + sound):
		stream = call("_r_" + sound)
	_streams[sound] = stream
	return stream


# ── Synthesis ────────────────────────────────────────────────────────────────
# Each recipe renders one sound: fn(t, st) -> sample, where st carries filter/phase state.

func _render(duration: float, fn: Callable) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var st := {"lp": 0.0, "ph": 0.0, "ph2": 0.0}
	for i in n:
		var t := float(i) / RATE
		var v: float = fn.call(t, st)
		# short fade-out so nothing clicks at the end
		v *= clampf((duration - t) * 60.0, 0.0, 1.0)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


static func _noise(st: Dictionary, smooth: float) -> float:
	st.lp += ((randf() * 2.0 - 1.0) - st.lp) * smooth
	return st.lp


static func _sweep(st: Dictionary, freq: float) -> float:
	st.ph += TAU * freq / RATE
	return sin(st.ph)


func _r_draw() -> AudioStream:
	return _render(0.16, func(t, st): return _noise(st, lerpf(0.04, 0.5, t / 0.16)) * sin(PI * t / 0.16) * 0.55)


func _r_flip() -> AudioStream:
	return _render(0.08, func(t, st): return _noise(st, 0.35) * exp(-t * 50.0) * 0.6)


func _r_set() -> AudioStream:
	return _render(0.18, func(t, st): return _noise(st, 0.15) * exp(-t * 30.0) * 0.7 + _sweep(st, 180.0) * exp(-t * 40.0) * 0.4)


func _r_slam() -> AudioStream:
	return _render(0.4, func(t, st):
		return _sweep(st, lerpf(150.0, 45.0, minf(t / 0.25, 1.0))) * exp(-t * 9.0) * 0.9 \
			+ _noise(st, 0.3) * exp(-t * 28.0) * 0.6)


func _r_heavy() -> AudioStream:
	return _render(0.9, func(t, st):
		return _sweep(st, lerpf(110.0, 28.0, minf(t / 0.5, 1.0))) * exp(-t * 4.0) * 1.0 \
			+ _noise(st, 0.12) * exp(-t * 6.0) * 0.6)


func _r_whoosh() -> AudioStream:
	return _render(0.26, func(t, st): return _noise(st, lerpf(0.02, 0.45, t / 0.26)) * sin(PI * t / 0.26) * 0.8)


func _r_hit() -> AudioStream:
	return _render(0.3, func(t, st):
		return _noise(st, 0.6) * exp(-t * 22.0) * 0.8 + _sweep(st, lerpf(160.0, 60.0, t / 0.3)) * exp(-t * 12.0) * 0.7)


func _r_down() -> AudioStream:
	return _render(0.4, func(t, st):
		return _sweep(st, lerpf(240.0, 90.0, t / 0.4)) * exp(-t * 7.0) * 0.6 + _noise(st, 0.2) * exp(-t * 18.0) * 0.4)


func _r_ko() -> AudioStream:
	return _render(0.7, func(t, st):
		var crunch := _noise(st, 0.55) * exp(-t * 7.0) * 0.75
		st.ph2 += TAU * lerpf(320.0, 50.0, t / 0.7) / RATE
		return crunch + signf(sin(st.ph2)) * exp(-t * 5.0) * 0.18)


func _r_damage() -> AudioStream:
	return _render(0.55, func(t, st):
		return _sweep(st, 70.0) * exp(-t * 5.0) * 0.9 + _noise(st, 0.1) * exp(-t * 8.0) * 0.5)


func _r_effect() -> AudioStream:
	return _render(0.6, func(t, st):
		return (sin(TAU * 880.0 * t) + sin(TAU * 1320.0 * t) * 0.6) * exp(-t * 6.0) * 0.28 \
			+ sin(TAU * 1760.0 * t) * exp(-t * 12.0) * 0.12)


func _r_ambush() -> AudioStream:
	return _render(0.7, func(t, st):
		var saw := fmod(t * 220.0, 1.0) * 2.0 - 1.0 + fmod(t * 233.0, 1.0) * 2.0 - 1.0
		return saw * minf(t * 50.0, 1.0) * exp(-t * 4.0) * 0.22 + _noise(st, 0.4) * exp(-t * 20.0) * 0.4)


func _r_promote() -> AudioStream:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	return _render(1.1, func(t, st):
		var v := 0.0
		for i in notes.size():
			var t0: float = t - i * 0.08
			if t0 > 0.0:
				v += sin(TAU * notes[i] * t0) * exp(-t0 * 3.5) * 0.18
		return v + sin(TAU * 2093.0 * t) * (0.5 + 0.5 * sin(t * 40.0)) * exp(-t * 3.0) * 0.06)


func _r_phase() -> AudioStream:
	return _render(0.08, func(t, st): return sin(TAU * 1400.0 * t) * exp(-t * 55.0) * 0.4)


func _r_turn() -> AudioStream:
	return _render(0.55, func(t, st):
		var f: float = 392.0 if t < 0.16 else 523.25
		var tt: float = t if t < 0.16 else t - 0.16
		return (sin(TAU * f * t) + sin(TAU * f * 2.0 * t) * 0.3) * minf(tt * 80.0, 1.0) * exp(-tt * 6.0) * 0.3)


func _r_click() -> AudioStream:
	return _render(0.04, func(t, st): return sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.4)


func _r_victory() -> AudioStream:
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	return _render(1.8, func(t, st):
		var v := 0.0
		for i in notes.size():
			var t0: float = t - i * 0.12
			if t0 > 0.0:
				v += sin(TAU * notes[i] * t0) * exp(-t0 * 1.6) * 0.14
		return v)


func _r_defeat() -> AudioStream:
	var notes := [392.0, 311.13, 261.63, 196.0]
	return _render(1.8, func(t, st):
		var v := 0.0
		for i in notes.size():
			var t0: float = t - i * 0.22
			if t0 > 0.0:
				v += sin(TAU * notes[i] * t0) * exp(-t0 * 1.8) * 0.18
		return v)
