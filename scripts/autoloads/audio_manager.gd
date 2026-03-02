extends Node
## Manages audio playback — music with crossfade, positional SFX with stream
## pooling, and non-positional UI sounds. Delegates bus volume control to
## SettingsManager and exposes save_state()/load_state() for serialization.

signal music_changed(track_name: String)
signal sfx_pool_exhausted

## Maximum concurrent SFX streams before new requests are dropped.
const MAX_SFX_STREAMS := 8

## Duration in seconds for music crossfade transitions.
const CROSSFADE_DURATION := 1.5

## Bus name constants matching default_bus_layout.tres.
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambient"
const BUS_UI := "UI"

## Maps friendly bus keys to AudioServer bus names for set_volume().
const _BUS_MAP := {
	"master": BUS_MASTER,
	"music": BUS_MUSIC,
	"sfx": BUS_SFX,
	"ambient": BUS_AMBIENT,
	"ui": BUS_UI,
}

## Currently playing music track name (empty string when silent).
var _current_music_track: String = ""

## The active music player (toggles between _music_player_a / _music_player_b).
var _active_music_player: AudioStreamPlayer = null

## The fading-out music player during crossfade (null when idle).
var _fading_music_player: AudioStreamPlayer = null

## Pre-allocated SFX stream pool.
var _sfx_players: Array[AudioStreamPlayer2D] = []

## Non-positional UI sound player.
var _ui_player: AudioStreamPlayer = null

## Two music players for crossfade support.
var _music_player_a: AudioStreamPlayer = null
var _music_player_b: AudioStreamPlayer = null

## Crossfade tween reference (null when no crossfade is active).
var _crossfade_tween: Tween = null

## Whether the manager is muted (pauses all playback).
var _muted: bool = false


func _ready() -> void:
	_create_music_players()
	_create_sfx_pool()
	_create_ui_player()


## Play a music track by resource path. Crossfades from the current track.
## Pass an empty string to stop music.
func play_music(track_path: String) -> void:
	if track_path == _current_music_track:
		return
	if track_path.is_empty():
		stop_music()
		return
	var stream: AudioStream = load(track_path) if ResourceLoader.exists(track_path) else null
	if stream == null:
		push_warning("AudioManager: Music track not found: %s" % track_path)
		return
	_crossfade_to(stream)
	_current_music_track = track_path
	music_changed.emit(_current_music_track)


## Stop music playback with a fade-out.
func stop_music() -> void:
	if _active_music_player == null or not _active_music_player.playing:
		_current_music_track = ""
		return
	_fade_out(_active_music_player)
	_current_music_track = ""
	music_changed.emit("")


## Return the currently playing music track path (empty if none).
func get_current_music() -> String:
	return _current_music_track


## Play a positional SFX at the given world position.
## Returns true if a stream was available, false if the pool was exhausted.
func play_sfx(sound_path: String, position: Vector2 = Vector2.ZERO) -> bool:
	var stream: AudioStream = load(sound_path) if ResourceLoader.exists(sound_path) else null
	if stream == null:
		push_warning("AudioManager: SFX not found: %s" % sound_path)
		return false
	var player := _get_available_sfx_player()
	if player == null:
		sfx_pool_exhausted.emit()
		return false
	player.stream = stream
	player.position = position
	player.play()
	return true


## Play a non-positional UI sound.
func play_ui_sound(sound_path: String) -> void:
	var stream: AudioStream = load(sound_path) if ResourceLoader.exists(sound_path) else null
	if stream == null:
		push_warning("AudioManager: UI sound not found: %s" % sound_path)
		return
	_ui_player.stream = stream
	_ui_player.play()


## Set volume for a named bus (master, music, sfx, ambient, ui).
## Delegates to SettingsManager which handles persistence and bus routing.
func set_volume(bus_key: String, value: float) -> void:
	match bus_key:
		"master":
			SettingsManager.set_master_volume(value)
		"music":
			SettingsManager.set_music_volume(value)
		"sfx":
			SettingsManager.set_sfx_volume(value)
		"ambient":
			SettingsManager.set_ambient_volume(value)
		"ui":
			SettingsManager.set_ui_volume(value)
		_:
			push_warning("AudioManager: Unknown bus key '%s'" % bus_key)


## Get volume for a named bus (master, music, sfx, ambient, ui).
func get_volume(bus_key: String) -> float:
	match bus_key:
		"master":
			return SettingsManager.get_master_volume()
		"music":
			return SettingsManager.get_music_volume()
		"sfx":
			return SettingsManager.get_sfx_volume()
		"ambient":
			return SettingsManager.get_ambient_volume()
		"ui":
			return SettingsManager.get_ui_volume()
		_:
			push_warning("AudioManager: Unknown bus key '%s'" % bus_key)
			return 0.0


## Return the number of SFX streams currently playing.
func get_active_sfx_count() -> int:
	var count := 0
	for player: AudioStreamPlayer2D in _sfx_players:
		if player.playing:
			count += 1
	return count


## Stop all audio playback.
func stop_all() -> void:
	stop_music()
	for player: AudioStreamPlayer2D in _sfx_players:
		player.stop()
	_ui_player.stop()


## Reset manager to default state (for test cleanup).
func reset() -> void:
	stop_all()
	_current_music_track = ""
	_muted = false
	if _crossfade_tween != null:
		_crossfade_tween.kill()
		_crossfade_tween = null


## Serialize playback state for save games.
func save_state() -> Dictionary:
	return {
		"current_music_track": _current_music_track,
		"muted": _muted,
	}


## Restore playback state from a save game.
func load_state(data: Dictionary) -> void:
	_muted = bool(data.get("muted", false))
	var track: String = str(data.get("current_music_track", ""))
	if not track.is_empty():
		play_music(track)
	else:
		stop_music()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------


func _create_music_players() -> void:
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.bus = BUS_MUSIC
	_music_player_a.name = "MusicPlayerA"
	add_child(_music_player_a)

	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = BUS_MUSIC
	_music_player_b.name = "MusicPlayerB"
	add_child(_music_player_b)

	_active_music_player = _music_player_a


func _create_sfx_pool() -> void:
	for i: int in MAX_SFX_STREAMS:
		var player := AudioStreamPlayer2D.new()
		player.bus = BUS_SFX
		player.name = "SFXPlayer%d" % i
		add_child(player)
		_sfx_players.append(player)


func _create_ui_player() -> void:
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = BUS_UI
	_ui_player.name = "UIPlayer"
	add_child(_ui_player)


func _get_available_sfx_player() -> AudioStreamPlayer2D:
	for player: AudioStreamPlayer2D in _sfx_players:
		if not player.playing:
			return player
	return null


func _crossfade_to(new_stream: AudioStream) -> void:
	# Kill any in-progress crossfade
	if _crossfade_tween != null:
		_crossfade_tween.kill()
		_crossfade_tween = null

	# Determine which player is the new target
	var new_player: AudioStreamPlayer
	if _active_music_player == _music_player_a:
		new_player = _music_player_b
	else:
		new_player = _music_player_a

	# Start the new track at silent volume
	new_player.stream = new_stream
	new_player.volume_db = -80.0
	new_player.play()

	# Create crossfade tween
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)

	# Fade in the new player
	_crossfade_tween.tween_property(new_player, "volume_db", 0.0, CROSSFADE_DURATION)

	# Fade out the old player
	if _active_music_player.playing:
		_fading_music_player = _active_music_player
		_crossfade_tween.tween_property(_active_music_player, "volume_db", -80.0, CROSSFADE_DURATION)
		_crossfade_tween.chain().tween_callback(_on_fade_out_complete.bind(_fading_music_player))

	_active_music_player = new_player


func _fade_out(player: AudioStreamPlayer) -> void:
	if _crossfade_tween != null:
		_crossfade_tween.kill()
	_crossfade_tween = create_tween()
	_crossfade_tween.tween_property(player, "volume_db", -80.0, CROSSFADE_DURATION)
	_crossfade_tween.tween_callback(player.stop)


func _on_fade_out_complete(player: AudioStreamPlayer) -> void:
	player.stop()
	_fading_music_player = null
