extends Node
## Music and ambience (Game.sound). One music track at a time, crossfaded when it changes; an
## ambience loop under it (rain on the street in duels, the crowd while finding a match, wind on the
## rooftop); stings (victory, defeat) that duck the music while they play.
## Tracks are sounds like any other (assets/sfx: music_menu, music_duel, music_duel_tense,
## music_victory, amb_city_rain, ...), so Sfx finds the recording, downloaded or built in, and a
## generated track dropped into assets/sfx replaces the stand-in. docs/AUDIO_PROMPTS.md lists them.
##   Game.sound.music("duel")   Game.sound.ambience("crowd")   Game.sound.sting("victory", "menu")

const MUSIC_DB := -3.0
const AMBIENCE_DB := 0.0   # (the ambience files sit at about -43 dB RMS, well under the music)
const DUCK_DB := -16.0   # the music under a sting

var _music: Array[AudioStreamPlayer] = []   # two, so one fades in while the other fades out
var _amb: Array[AudioStreamPlayer] = []
var _sting: AudioStreamPlayer
var _now := {"music": "", "amb": ""}
var _use := {"music": 0, "amb": 0}
var _resume := ""   # the track to bring in once the sting is over
var _fades := {}     # player -> the fade running on it (a new fade replaces it)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		_music.append(_player("Music"))
		_amb.append(_player("Ambience"))
	_sting = _player("Music")
	_sting.finished.connect(_sting_done)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


## Crossfade to a track: "menu", "duel", "duel_tense", ... ("" fades the music out).
func music(track: String, fade := 1.6) -> void:
	if track == _now.music and (track == "" or _music[_use.music].playing):
		return
	_now.music = track
	var stream: AudioStream = null
	if track != "":
		stream = _looping("music_" + track)
	_swap(_music, "music", stream, MUSIC_DB, fade)


## The track playing now ("" for none).
func current() -> String:
	return _now.music


## Whether a track has a recording (music_<track>).
func has_track(track: String) -> bool:
	return not Sfx.streams("music_" + track).is_empty()


## Crossfade to an ambience loop: "city_rain", "crowd", "rooftop" ("" fades it out).
func ambience(loop: String, fade := 2.0) -> void:
	if loop == _now.amb:
		return
	_now.amb = loop
	_swap(_amb, "amb", _looping("amb_" + loop) if loop != "" else null, AMBIENCE_DB, fade)


## A music sting over everything ("victory", "defeat"): the music dips while it plays, then comes
## back, or `then` fades in once it's over ("" keeps what was playing).
func sting(name: String, then := "") -> void:
	var options: Array = Sfx.streams("music_" + name)
	if options.is_empty():
		Sfx.play(name)   # (no sting recorded: the short sound of that name)
		if then != "":
			music(then, 2.5)
		return
	_resume = then
	_sting.stream = options[randi() % options.size()]
	_sting.volume_db = MUSIC_DB + 3.0
	_sting.play()
	var p := _music[_use.music]
	if p.playing:
		_fade(p, MUSIC_DB + DUCK_DB, 0.25)


func _sting_done() -> void:
	if _resume != "":
		var track := _resume
		_resume = ""
		music(track, 3.0)
	else:
		var p := _music[_use.music]
		if p.playing:
			_fade(p, MUSIC_DB, 1.5)


## The new stream fades in on the spare player while the old one fades out and stops.
func _swap(players: Array[AudioStreamPlayer], key: String, stream: AudioStream, target_db: float, fade: float) -> void:
	var old := players[_use[key]]
	if old.playing:
		_fade(old, -80.0, fade, true)
	if stream == null:
		return
	_use[key] = 1 - _use[key]
	var p := players[_use[key]]
	_fade(p, -80.0, 0.0)   # (stops a fade-out still running on it from stopping the new track)
	p.stream = stream
	p.volume_db = -80.0
	p.play()
	_fade(p, target_db, fade)


## Fades a player to a volume (then stops it), replacing any fade already running on it.
func _fade(p: AudioStreamPlayer, db: float, secs: float, stop := false) -> void:
	var was: Tween = _fades.get(p)
	if was and was.is_valid():
		was.kill()
	_fades.erase(p)
	if secs <= 0.0:
		return
	var t := _tween()
	t.tween_property(p, "volume_db", db, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN if db < p.volume_db else Tween.EASE_OUT)
	if stop:
		t.tween_callback(p.stop)
	_fades[p] = t


## A looping copy of the named sound (a random one of its recordings), or null.
func _looping(sound: String) -> AudioStream:
	var options: Array = Sfx.streams(sound)
	if options.is_empty():
		return null
	return _looped(options[randi() % options.size()])


static func _looped(s: AudioStream) -> AudioStream:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = true
	return s


## Fades keep their pace in a sped-up or slowed duel.
func _tween() -> Tween:
	return create_tween().set_ignore_time_scale(true)
