## Save/restore guard for CivBonusManager singleton state in tests.
## Captures state on init, restores on dispose(). Prevents test pollution.
##
## Usage in a GdUnit4 test:
##   const CBMGuard = preload("res://tests/helpers/civ_bonus_manager_guard.gd")
##   var _cbm_guard: RefCounted
##
##   func before_test() -> void:
##       _cbm_guard = CBMGuard.new()
##
##   func after_test() -> void:
##       _cbm_guard.dispose()
extends RefCounted

var _saved_state: Dictionary


func _init() -> void:
	_saved_state = CivBonusManager.save_state()


func dispose() -> void:
	CivBonusManager.load_state(_saved_state)
