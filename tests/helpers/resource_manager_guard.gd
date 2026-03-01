## Save/restore guard for ResourceManager singleton state in tests.
## Captures state on init, restores on dispose(). Prevents test pollution.
##
## Usage in a GdUnit4 test:
##   const RMGuard = preload("res://tests/helpers/resource_manager_guard.gd")
##   var _rm_guard: RefCounted
##
##   func before_test() -> void:
##       _rm_guard = RMGuard.new()
##
##   func after_test() -> void:
##       _rm_guard.dispose()
extends RefCounted

var _saved_stockpiles: Dictionary
var _saved_corruption_rates: Dictionary


func _init() -> void:
	_saved_stockpiles = ResourceManager._stockpiles.duplicate(true)
	if "_corruption_rates" in ResourceManager:
		_saved_corruption_rates = ResourceManager._corruption_rates.duplicate(true)


func dispose() -> void:
	ResourceManager._stockpiles = _saved_stockpiles.duplicate(true)
	if "_corruption_rates" in ResourceManager:
		ResourceManager._corruption_rates = _saved_corruption_rates.duplicate(true)


## Convenience: init player with specific resource amounts.
static func give_resources(
	player_id: int,
	food: int = 0,
	wood: int = 0,
	stone: int = 0,
	gold: int = 0,
	knowledge: int = 0,
) -> void:
	(
		ResourceManager
		. init_player(
			player_id,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: wood,
				ResourceManager.ResourceType.STONE: stone,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: knowledge,
			}
		)
	)
