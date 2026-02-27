class_name GameUtils
extends RefCounted
## Shared utility functions that eliminate duplicated autoload-lookup patterns.
##
## Every method returns a safe fallback (empty Dictionary, null, or raw delta)
## when the backing autoload is unavailable — e.g. during unit-tests.

## Cached autoload references — looked up once, reused forever.
## Autoloads never change at runtime so invalidation is unnecessary.
static var _autoload_cache: Dictionary = {}


## Return the autoload [Node] registered under [param autoload_name], or
## [code]null[/code] when running outside the full scene tree.
## Results are cached after the first lookup to avoid per-frame tree traversal.
static func get_autoload(autoload_name: String) -> Node:
	if _autoload_cache.has(autoload_name):
		var cached: Node = _autoload_cache[autoload_name]
		if is_instance_valid(cached):
			return cached
		# Stale entry — remove and re-lookup
		_autoload_cache.erase(autoload_name)
	if is_instance_valid(Engine.get_main_loop()):
		var node: Node = Engine.get_main_loop().root.get_node_or_null(autoload_name)
		if node != null:
			_autoload_cache[autoload_name] = node
		return node
	return null


## Clear the autoload cache.  Only needed in tests that swap scene trees.
static func clear_autoload_cache() -> void:
	_autoload_cache.clear()


## Scale [param delta] by the game-clock speed.  Falls back to the raw
## [param delta] when [code]GameManager[/code] is not available.
static func get_game_delta(delta: float) -> float:
	if Engine.has_singleton("GameManager"):
		return GameManager.get_game_delta(delta)
	var gm: Node = get_autoload("GameManager")
	if gm and gm.has_method("get_game_delta"):
		return gm.get_game_delta(delta)
	return delta


## Fetch a settings dictionary from [code]DataLoader[/code].
## Returns an empty [Dictionary] when the autoload is missing.
static func dl_settings(id: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_settings(id)
	var dl: Node = get_autoload("DataLoader")
	if dl and dl.has_method("get_settings"):
		return dl.get_settings(id)
	return {}
