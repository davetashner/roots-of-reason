class_name CommandHandler
extends RefCounted
## Base class for pluggable command handlers.
## Subclasses override can_handle() and execute() to process specific command types.


## Return true if this handler should process the given command.
func can_handle(_cmd: String, _target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return false


## Execute the command on the selected units. Return true if handled.
func execute(_cmd: String, _target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return false
