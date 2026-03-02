extends GdUnitTestSuite
## Tests for audio_manager.gd — music crossfade, SFX pooling, UI sounds,
## volume delegation to SettingsManager, and save/load serialization.


func before_test() -> void:
	AudioManager.reset()


func after_test() -> void:
	AudioManager.reset()


# -- Music ------------------------------------------------------------------


func test_initial_music_is_empty() -> void:
	assert_str(AudioManager.get_current_music()).is_empty()


func test_play_music_sets_current_track() -> void:
	# play_music with a non-existent path logs a warning but should not crash
	# and should NOT update the current track since the resource doesn't exist.
	AudioManager.play_music("res://nonexistent_track.ogg")
	assert_str(AudioManager.get_current_music()).is_empty()


func test_stop_music_clears_current_track() -> void:
	AudioManager._current_music_track = "res://fake_track.ogg"
	AudioManager.stop_music()
	assert_str(AudioManager.get_current_music()).is_empty()


func test_play_music_same_track_is_noop() -> void:
	AudioManager._current_music_track = "res://same_track.ogg"
	# Playing the same track should not trigger a crossfade
	AudioManager.play_music("res://same_track.ogg")
	assert_str(AudioManager.get_current_music()).is_equal("res://same_track.ogg")


func test_play_music_empty_string_stops() -> void:
	AudioManager._current_music_track = "res://some_track.ogg"
	AudioManager.play_music("")
	assert_str(AudioManager.get_current_music()).is_empty()


# -- SFX Pool ---------------------------------------------------------------


func test_sfx_pool_has_correct_size() -> void:
	assert_int(AudioManager._sfx_players.size()).is_equal(AudioManager.MAX_SFX_STREAMS)


func test_initial_active_sfx_count_is_zero() -> void:
	assert_int(AudioManager.get_active_sfx_count()).is_equal(0)


func test_play_sfx_invalid_path_returns_false() -> void:
	var result := AudioManager.play_sfx("res://nonexistent_sfx.ogg")
	assert_bool(result).is_false()


func test_sfx_players_use_correct_bus() -> void:
	for player: AudioStreamPlayer2D in AudioManager._sfx_players:
		assert_str(player.bus).is_equal(AudioManager.BUS_SFX)


# -- UI Sound ---------------------------------------------------------------


func test_ui_player_uses_correct_bus() -> void:
	assert_str(AudioManager._ui_player.bus).is_equal(AudioManager.BUS_UI)


func test_play_ui_sound_invalid_path_does_not_crash() -> void:
	# Should log a warning but not crash
	AudioManager.play_ui_sound("res://nonexistent_ui.ogg")
	assert_str(AudioManager._ui_player.bus).is_equal(AudioManager.BUS_UI)


# -- Volume Delegation ------------------------------------------------------


func test_set_volume_master_delegates_to_settings() -> void:
	AudioManager.set_volume("master", 0.5)
	assert_float(SettingsManager.get_master_volume()).is_equal_approx(0.5, 0.01)
	# Restore default
	SettingsManager.set_master_volume(1.0)


func test_set_volume_music_delegates_to_settings() -> void:
	AudioManager.set_volume("music", 0.3)
	assert_float(SettingsManager.get_music_volume()).is_equal_approx(0.3, 0.01)
	# Restore default
	SettingsManager.set_music_volume(0.8)


func test_set_volume_sfx_delegates_to_settings() -> void:
	AudioManager.set_volume("sfx", 0.6)
	assert_float(SettingsManager.get_sfx_volume()).is_equal_approx(0.6, 0.01)
	# Restore default
	SettingsManager.set_sfx_volume(1.0)


func test_set_volume_ambient_delegates_to_settings() -> void:
	AudioManager.set_volume("ambient", 0.4)
	assert_float(SettingsManager.get_ambient_volume()).is_equal_approx(0.4, 0.01)
	# Restore default
	SettingsManager.set_ambient_volume(0.7)


func test_set_volume_ui_delegates_to_settings() -> void:
	AudioManager.set_volume("ui", 0.9)
	assert_float(SettingsManager.get_ui_volume()).is_equal_approx(0.9, 0.01)
	# Restore default
	SettingsManager.set_ui_volume(1.0)


func test_get_volume_returns_settings_value() -> void:
	SettingsManager.set_music_volume(0.42)
	assert_float(AudioManager.get_volume("music")).is_equal_approx(0.42, 0.01)
	# Restore default
	SettingsManager.set_music_volume(0.8)


func test_get_volume_unknown_bus_returns_zero() -> void:
	assert_float(AudioManager.get_volume("bogus")).is_equal(0.0)


# -- Save / Load ------------------------------------------------------------


func test_save_state_captures_current_track() -> void:
	AudioManager._current_music_track = "res://music/battle.ogg"
	var state := AudioManager.save_state()
	assert_str(str(state.get("current_music_track", ""))).is_equal("res://music/battle.ogg")


func test_save_state_captures_muted() -> void:
	AudioManager._muted = true
	var state := AudioManager.save_state()
	assert_bool(bool(state.get("muted", false))).is_true()


func test_load_state_restores_muted() -> void:
	var state := {"muted": true, "current_music_track": ""}
	AudioManager.load_state(state)
	assert_bool(AudioManager._muted).is_true()


func test_load_state_empty_track_stops_music() -> void:
	AudioManager._current_music_track = "res://music/ambient.ogg"
	var state := {"muted": false, "current_music_track": ""}
	AudioManager.load_state(state)
	assert_str(AudioManager.get_current_music()).is_empty()


func test_save_load_roundtrip() -> void:
	AudioManager._current_music_track = "res://music/theme.ogg"
	AudioManager._muted = true
	var state := AudioManager.save_state()
	AudioManager.reset()
	assert_str(AudioManager.get_current_music()).is_empty()
	assert_bool(AudioManager._muted).is_false()
	# load_state will try to play the track — it won't exist, so track stays empty.
	# But muted should restore.
	AudioManager.load_state(state)
	assert_bool(AudioManager._muted).is_true()


# -- Reset ------------------------------------------------------------------


func test_reset_clears_state() -> void:
	AudioManager._current_music_track = "res://music/test.ogg"
	AudioManager._muted = true
	AudioManager.reset()
	assert_str(AudioManager.get_current_music()).is_empty()
	assert_bool(AudioManager._muted).is_false()


# -- Music Players ----------------------------------------------------------


func test_music_players_use_correct_bus() -> void:
	assert_str(AudioManager._music_player_a.bus).is_equal(AudioManager.BUS_MUSIC)
	assert_str(AudioManager._music_player_b.bus).is_equal(AudioManager.BUS_MUSIC)


# -- Constants --------------------------------------------------------------


func test_max_sfx_streams_is_eight() -> void:
	assert_int(AudioManager.MAX_SFX_STREAMS).is_equal(8)


func test_bus_map_has_all_keys() -> void:
	assert_bool(AudioManager._BUS_MAP.has("master")).is_true()
	assert_bool(AudioManager._BUS_MAP.has("music")).is_true()
	assert_bool(AudioManager._BUS_MAP.has("sfx")).is_true()
	assert_bool(AudioManager._BUS_MAP.has("ambient")).is_true()
	assert_bool(AudioManager._BUS_MAP.has("ui")).is_true()
