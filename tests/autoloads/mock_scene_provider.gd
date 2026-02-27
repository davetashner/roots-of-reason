extends Node
## Mock scene provider for SaveManager tests.


func save_state() -> Dictionary:
	return {"test_key": "test_value"}


func load_state(_data: Dictionary) -> void:
	pass
