extends GdUnitTestSuite
## Tests for GameUtils static utility functions.
##
## get_autoload() requires a live scene tree for positive-path tests.
## We focus on:
##   • cache clearing (clear_autoload_cache)
##   • cache hit vs miss behaviour via the public static cache dictionary
##   • get_game_delta fallback when GameManager is absent
##   • dl_settings fallback when DataLoader is absent


func after_test() -> void:
	# Always reset the cache between tests so static state does not bleed.
	GameUtils.clear_autoload_cache()


# --- clear_autoload_cache ---


func test_clear_autoload_cache_empties_dictionary() -> void:
	# Manually populate the cache, then verify clear() empties it.
	var temp_node := Node.new()
	add_child(temp_node)
	GameUtils._autoload_cache["FakeNode"] = temp_node
	GameUtils.clear_autoload_cache()
	assert_int(GameUtils._autoload_cache.size()).is_equal(0)
	temp_node.queue_free()


func test_clear_autoload_cache_is_idempotent() -> void:
	# Clearing an already-empty cache must not error.
	GameUtils.clear_autoload_cache()
	GameUtils.clear_autoload_cache()
	assert_int(GameUtils._autoload_cache.size()).is_equal(0)


# --- Cache hit: valid entry is returned without re-lookup ---


func test_cache_hit_returns_same_node_reference() -> void:
	# Inject a live node into the cache directly, then confirm get_autoload
	# returns that exact reference (cache hit path).
	var fake_node := Node.new()
	add_child(fake_node)
	GameUtils._autoload_cache["FakeAutoload"] = fake_node
	var result: Node = GameUtils.get_autoload("FakeAutoload")
	assert_object(result).is_same(fake_node)
	fake_node.queue_free()


# --- Cache miss for missing key returns null (no scene tree root available) ---


func test_cache_miss_unknown_key_returns_null() -> void:
	# "NonExistentAutoload" is not in the cache and not in the tree.
	var result: Node = GameUtils.get_autoload("NonExistentAutoload")
	assert_object(result).is_null()


# NOTE: The stale-cache-entry eviction path (line 18 of game_utils.gd) cannot
# be safely tested in Godot 4.6.  Reading a freed Object into a typed Node
# variable (`var cached: Node = dict[key]`) crashes the engine before
# `is_instance_valid` can run.  Eviction coverage is omitted until the
# source is updated to use `_autoload_cache.get(autoload_name)` (untyped)
# before the validity check.

# --- get_game_delta fallback ---


func test_get_game_delta_returns_raw_delta_when_no_game_manager() -> void:
	# When GameManager is not available, delta must pass through unchanged.
	# Clear cache to ensure no stale GameManager entry.
	GameUtils.clear_autoload_cache()
	var delta := 0.016
	var result := GameUtils.get_game_delta(delta)
	assert_float(result).is_equal(delta)


func test_get_game_delta_zero_delta() -> void:
	GameUtils.clear_autoload_cache()
	assert_float(GameUtils.get_game_delta(0.0)).is_equal(0.0)


func test_get_game_delta_large_delta() -> void:
	GameUtils.clear_autoload_cache()
	var delta := 10.0
	assert_float(GameUtils.get_game_delta(delta)).is_equal(delta)


# --- dl_settings fallback ---


func test_dl_settings_returns_empty_dict_when_no_data_loader() -> void:
	# When DataLoader autoload is absent, dl_settings must return an empty dict.
	GameUtils.clear_autoload_cache()
	var result := GameUtils.dl_settings("nonexistent_setting")
	assert_dict(result).is_empty()
