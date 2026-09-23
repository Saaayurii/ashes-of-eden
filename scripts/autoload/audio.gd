extends Node
## Everything the game makes noise with. One voice pool on the SFX bus and a
## pair of crossfading players on the Music bus — never Master, so the sliders
## in Settings actually reach it.
##
## Callers name a moment, never a file: [code]Audio.play(&"hit")[/code]. What
## that moment sounds like, how loud it is and how deep it sits are decided by
## MIX below, so a sound is retuned in one line here and never re-encoded.
##
## Two kinds of clip live in assets/audio. The real ones are untouched CC0
## sources (tools/audio/build_audio.py, credited in assets/CREDITS.md); the
## generated ones (tools/audio/generate_sfx.py) stand in where no real clip has
## been chosen yet. A name that has both takes the real one, so replacing a
## placeholder is a matter of dropping an .ogg next to it.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
## Enough voices for a busy room; the oldest is stolen once they are all busy.
const VOICES := 14
## Two of the same sound inside this window is one sound: six enemies dying
## together should land as a hit, not as distortion.
const RETRIGGER := 0.04
const MUSIC_FADE := 1.5
## Further than this from the camera, in pixels, a sound is not worth playing;
## closer than NEAR it plays at full level, and in between it fades away.
const EARSHOT := 560.0
const NEAR := 300.0
## However far off it happens, a sound never drops further than this.
const MIN_DISTANCE_DB := -24.0

## Older names kept alive so call sites do not have to care which clip was
## chosen for a moment.
const ALIASES := {
	&"gift": &"gift_pick",
}

## Every track brought to the same measured loudness (-18 LUFS), with the
## gain checked against the file's peak so nothing clips: walking from one
## room into the next must not be a step up or down in volume.
const MUSIC_DB := {
	&"menu": 3.9,
	&"village_night": 3.3,
	&"graveyard": 0.1,
	&"dead_bridge": 2.5,
	&"boss_knight": -5.2,
	&"boss_ophanim": -5.1,
	&"arena": -1.2,
	&"end": -4.1,
	&"ambient_night": -6.0,
}

## sound -> [volume dB, pitch, pitch spread]. Pitch is where the weight comes
## from: the same bell is a critical hit at 1.1 and a boss dying at 0.5. The
## spread is what keeps a sound that fires every half second from turning into
## a machine gun. Levels were measured, not guessed, and are nearly all cuts —
## the sources already peak near full scale. enemy_windup is the exception: a
## quiet source carrying a cue the player is not allowed to miss.
const MIX := {
	# the interface
	&"ui_hover": [-8.0, 1.0, 0.0],
	&"ui_click": [-4.0, 1.0, 0.0],
	&"ui_back": [-3.0, 0.95, 0.0],
	&"ui_pause": [-4.0, 0.85, 0.0],
	&"ui_unpause": [-3.0, 1.05, 0.0],
	&"dialogue_blip": [-10.0, 1.25, 0.12],
	# progress
	&"gift_pick": [-5.0, 1.0, 0.0],
	&"level_up": [-6.0, 1.0, 0.0],
	&"room_clear": [-8.0, 1.0, 0.0],
	&"bell": [-4.0, 1.0, 0.02],
	&"victory": [0.0, 1.0, 0.0],
	&"defeat": [-3.0, 0.8, 0.0],
	&"heal": [-10.0, 1.0, 0.0],
	# the hero
	&"swing": [-6.0, 0.90, 0.07],
	&"dash": [-2.0, 0.90, 0.08],
	&"jump": [-10.0, 1.10, 0.08],
	&"land": [-14.0, 0.95, 0.08],
	&"step": [-10.0, 1.0, 0.10],
	&"player_hurt": [-2.0, 0.90, 0.06],
	&"player_death": [0.0, 0.60, 0.0],
	# the blade landing. Every body answers differently (hit_<material>, and
	# <enemy>_impact where a creature has clips of its own); "hit" is what a
	# blow on anything else — a barrel, a chest — sounds like.
	&"hit": [-8.0, 1.0, 0.09],
	&"hit_crit": [0.0, 1.10, 0.04],
	# one row per material, so a body with no clips of its own is still in balance
	&"hit_flesh": [-5.0, 1.0, 0.07],
	&"hit_cloth": [-5.0, 1.05, 0.07],
	&"hit_mail": [-7.0, 1.0, 0.06],
	&"hit_plate": [-8.0, 0.95, 0.05],
	&"hit_bone": [-6.0, 1.05, 0.07],
	&"hit_feather": [-6.0, 1.15, 0.08],
	&"hit_spirit": [-7.0, 0.95, 0.07],
	&"hit_gold": [-9.0, 1.0, 0.04],
	# the block
	&"block": [-6.0, 1.0, 0.08],
	&"parry": [-2.0, 1.0, 0.03],
	# the enemies
	&"enemy_windup": [14.0, 0.85, 0.05],
	&"enemy_swing": [-6.0, 0.70, 0.07],
	&"enemy_hurt": [-10.0, 1.05, 0.09],
	&"enemy_death": [-6.0, 0.80, 0.07],
	&"boss_death": [0.0, 0.50, 0.0],
	&"projectile": [-8.0, 0.70, 0.08],
	&"beam": [-4.0, 0.55, 0.05],
	&"explode": [-4.0, 0.60, 0.06],
	&"summon": [-2.0, 0.70, 0.05],
	# the world
	&"door_open": [-5.0, 0.85, 0.0],
	&"prop_break": [-4.0, 1.0, 0.08],
}

## Families of sounds that share a mix: the ending decides it when the whole
## name has no row of its own, so a new enemy's clips are balanced from the
## moment they exist. Checked after the exact name and its take number.
const SUFFIX_MIX := {
	&"impact": [-5.0, 1.0, 0.07],
}

var _clips := {}
## Base name -> the clips that can answer to it, for sounds that come in
## several takes (hit_1..hit_3). Asking for "hit" is asking for any of them.
var _variants := {}
var _voices: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _next := 0
var _active := 0
var _track := &""
## The name a room asked for, which may be a playlist rather than a file.
var _requested := &""
## playlist name -> track names; data/music/playlists.json, written by
## tools/audio/fetch_music.py. A room asks for "graveyard" and gets one of them.
var _playlists := {}
var _last_pick := {}
var _last_played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the menu is a paused tree
	_load_clips()
	_load_playlists()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -80.0
		add_child(player)
		_music.append(player)
	# Every Button in the project clicks, without touching a single scene.
	get_tree().node_added.connect(_on_node_added)
	# The cues that belong to the run rather than to any one body: they arrive
	# through the bus, so no system has to know a sound exists to make one.
	EventBus.level_up.connect(func(_level: int) -> void: play(&"level_up"))
	EventBus.ability_acquired.connect(func(_ability: Dictionary) -> void: play(&"gift_pick"))
	EventBus.room_cleared.connect(func(_index: int) -> void: play(&"room_clear"))


## A real clip beats a generated one of the same name, so a placeholder is
## replaced by dropping an .ogg beside it — nothing here has to change.
func _load_clips() -> void:
	for extension in ["wav", "ogg"]:
		for file in DirAccess.get_files_at(SFX_DIR):
			if file.get_extension() != extension:
				continue
			var clip: AudioStream = load(SFX_DIR + file)
			if clip == null:
				continue
			var name := StringName(file.get_basename())
			_clips[name] = clip
			var base := _base_name(file.get_basename())
			if base != name:
				var takes: Array = _variants.get(base, [])
				if not takes.has(name):
					takes.append(name)
				_variants[base] = takes


## "hit_2" is one of the takes of "hit"; "hit_crit" is its own sound. Only a
## trailing number marks a variant.
static func _base_name(file_name: String) -> StringName:
	var cut := file_name.rfind("_")
	if cut <= 0 or not file_name.substr(cut + 1).is_valid_int():
		return StringName(file_name)
	return StringName(file_name.substr(0, cut))


# ------------------------------------------------------------------- sfx ---

## Fire and forget. [param volume_db] trims this one playback against the level
## in MIX, and [param pitch] overrides the random spread (pass 0.0 where the
## pitch carries meaning, as in a chime).
## Whether a clip (or a numbered take of it) exists, for callers that pick
## between a specific sound and a generic fallback.
func has_clip(name: StringName) -> bool:
	return _clip(ALIASES.get(name, name)) != null


func play(name: StringName, volume_db := 0.0, pitch := -1.0) -> void:
	var wanted: StringName = ALIASES.get(name, name)
	var clip := _clip(wanted)
	if clip == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(wanted, -1.0)) < RETRIGGER:
		return
	_last_played[wanted] = now
	var mix: Array = _mix_for(wanted)
	var spread: float = mix[2] if pitch < 0.0 else pitch
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = clip
	voice.volume_db = float(mix[0]) + volume_db
	voice.pitch_scale = maxf(0.05, float(mix[1]) + randf_range(-spread, spread))
	voice.play()


## The same sound, quieter the further it happens from what the player is
## looking at. Out of earshot it is not played at all — an enemy dying on the
## other side of the room is not news.
func play_at(name: StringName, where: Vector2, volume_db := 0.0) -> void:
	if not is_inside_tree():
		play(name, volume_db)
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		play(name, volume_db)
		return
	var distance := where.distance_to(camera.get_screen_center_position())
	if distance > EARSHOT:
		return
	var near := clampf(inverse_lerp(EARSHOT, NEAR, distance), 0.0, 1.0)
	play(name, volume_db + maxf(linear_to_db(maxf(near, 0.0001)), MIN_DISTANCE_DB))


## Exact name first, then the name without its take number, then the family
## it ends in (hit_plate_2 -> hit_plate -> impact), then a flat default.
func _mix_for(name: StringName) -> Array:
	if MIX.has(name):
		return MIX[name]
	var base := _base_name(str(name))
	if MIX.has(base):
		return MIX[base]
	var tail := str(base).get_slice("_", str(base).get_slice_count("_") - 1)
	return SUFFIX_MIX.get(StringName(tail), [0.0, 1.0, 0.08])


## One clip for a name: the clip itself, or one of its takes at random.
func _clip(name: StringName) -> AudioStream:
	var takes: Array = _variants.get(name, [])
	if not takes.is_empty():
		return _clips.get(takes[randi() % takes.size()])
	return _clips.get(name)


# ----------------------------------------------------------------- music ---

## Crossfades to a track. Asking for the one already playing does nothing, on
## purpose: that is what carries a track across a scene change unbroken. An
## empty name is silence.
func music(track: StringName, fade := MUSIC_FADE) -> void:
	if track == _requested and track != &"":
		return  # same room mood as before: keep whatever is playing
	_requested = track
	track = _pick(track)
	if track == _track:
		return
	_track = track
	_fade(_music[_active], -80.0, fade, true)
	if track == &"":
		return
	var stream := _music_stream(track)
	if stream == null:
		return
	_active = 1 - _active
	var player := _music[_active]
	player.stream = stream
	player.volume_db = -80.0
	player.play()
	_fade(player, float(MUSIC_DB.get(track, 0.0)), fade, false)


func stop_music(fade := MUSIC_FADE) -> void:
	music(&"", fade)


func _load_playlists() -> void:
	var path := "res://data/music/playlists.json"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.has("playlists"):
		# A build may carry only part of the library (the Web one leaves the
		# mp3s out): a playlist keeps the tracks that are actually there, and one
		# left empty is dropped, so the mood falls back to its own .ogg.
		for mood in parsed.playlists:
			var present: Array = parsed.playlists[mood].filter(_has_music)
			if not present.is_empty():
				_playlists[mood] = present


## A playlist name becomes one of its tracks, never the one played last time;
## a plain track name passes through untouched.
func _pick(name: StringName) -> StringName:
	# Only what this build actually carries: mobile and Web exports keep a
	# light subset of the library (tools/export/music_filters.py), so a
	# playlist shrinks to what is there instead of choosing silence.
	var options: Array = _playlists.get(str(name), []).filter(_track_exists)
	if options.is_empty():
		return name
	var choice: String = options[randi() % options.size()]
	if options.size() > 1 and choice == str(_last_pick.get(str(name), "")):
		choice = options[(options.find(choice) + 1 + randi() % (options.size() - 1)) % options.size()]
	_last_pick[str(name)] = choice
	return StringName(choice)


## What is playing right now, for scenes that would rather leave the music
## alone than restart it, and for the tests.
func current_music() -> StringName:
	return _track


## The generated bed, kept as its own call because it is not a room's music:
## it is what plays where no track has been chosen.
func play_ambient() -> void:
	music(&"ambient_night")


func stop_ambient(fade := 1.0) -> void:
	if _track == &"ambient_night":
		stop_music(fade)


## Whether a track is in this build at all, without loading it.
func _has_music(track: String) -> bool:
	for extension: String in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(MUSIC_DIR + track + extension):
			return true
	return false


## Music loops; the import settings that would say so are not in the repository
## (.import is gitignored), so every track is told to loop here instead.
func _track_exists(track) -> bool:
	for extension: String in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(MUSIC_DIR + str(track) + extension):
			return true
	return false


func _music_stream(track: StringName) -> AudioStream:
	for extension: String in [".ogg", ".mp3", ".wav"]:
		var path := MUSIC_DIR + str(track) + extension
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true  # the fetched library (tools/audio/fetch_music.py)
		elif stream is AudioStreamWAV:
			# Written as one seamless cycle (tools/audio/generate_sfx.py).
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = 0
		return stream
	push_warning("[Audio] missing music '%s'" % track)
	return null


func _fade(player: AudioStreamPlayer, to_db: float, time: float, stop_after: bool) -> void:
	if player.has_meta("fade"):
		var running: Variant = player.get_meta("fade")
		if running is Tween and (running as Tween).is_valid():
			(running as Tween).kill()
	if time <= 0.0 or not player.playing:
		player.volume_db = to_db
		if stop_after:
			player.stop()
		return
	var tween := create_tween()
	player.set_meta("fade", tween)
	tween.tween_property(player, "volume_db", to_db, time)
	if stop_after:
		tween.tween_callback(player.stop)


# -------------------------------------------------------------------- ui ---

func _on_node_added(node: Node) -> void:
	var button := node as Button
	if button == null or button.pressed.is_connected(_click):
		return
	button.pressed.connect(_click)
	button.mouse_entered.connect(_hover)
	button.focus_entered.connect(_hover)


func _click() -> void:
	play(&"ui_click", -6.0)


func _hover() -> void:
	play(&"ui_hover")
