## Shared mock pathfinder for tests — all cells passable by default.
## Set _solid_cells to control which cells block movement.
##
## Usage:
##   const MockPathfinder = preload("res://tests/helpers/mock_pathfinder.gd")
##   var pf := MockPathfinder.new()
##   _root.add_child(pf)
extends Node

var _solid_cells: Dictionary = {}


func is_cell_solid(cell: Vector2i) -> bool:
	return _solid_cells.has(cell)


func set_cell_solid(cell: Vector2i, solid: bool) -> void:
	if solid:
		_solid_cells[cell] = true
	else:
		_solid_cells.erase(cell)
