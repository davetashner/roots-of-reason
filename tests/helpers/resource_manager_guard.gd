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

var _saved_state: Dictionary


func _init() -> void:
	_saved_state = ResourceManager.save_state()


func dispose() -> void:
	ResourceManager.load_state(_saved_state)


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
