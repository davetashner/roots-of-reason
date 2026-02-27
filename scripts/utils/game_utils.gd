class_name GameUtils
extends RefCounted
## Shared utility functions that eliminate duplicated autoload-lookup patterns.
##
## Every method returns a safe fallback (empty Dictionary, null, or raw delta)
## when the backing autoload is unavailable — e.g. during unit-tests.


## Return the autoload [Node] registered under [param autoload_name], or
## [code]null[/code] when running outside the full scene tree.
static func get_autoload(autoload_name: String) -> Node:
	if is_instance_valid(Engine.get_main_loop()):
		return Engine.get_main_loop().root.get_node_or_null(autoload_name)
	return null


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
