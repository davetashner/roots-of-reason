## Save/restore guard for GameManager singleton state in tests.
## Captures state on init, restores on dispose(). Prevents test pollution.
##
## Usage in a GdUnit4 test:
##   const GMGuard = preload("res://tests/helpers/game_manager_guard.gd")
##   var _gm_guard: RefCounted
##
##   func before_test() -> void:
##       _gm_guard = GMGuard.new()
##
##   func after_test() -> void:
##       _gm_guard.dispose()
extends RefCounted

var _saved_state: Dictionary


func _init() -> void:
	_saved_state = GameManager.save_state()


func dispose() -> void:
	GameManager.load_state(_saved_state)
