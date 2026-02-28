extends RefCounted
## Pure logic class for computing formation slot offsets and speed synchronization.
## No scene tree dependency — used by prototype_input and pathfinding_grid.

enum FormationType { LINE, BOX, STAGGERED }

const DEFAULT_SPACING: float = 40.0

var spacing: float = DEFAULT_SPACING
var speed_sync: bool = true


static func type_from_string(s: String) -> FormationType:
	match s:
		"line":
			return FormationType.LINE
		"box":
			return FormationType.BOX
		_:
			return FormationType.STAGGERED


static func type_to_string(t: FormationType) -> String:
	match t:
		FormationType.LINE:
			return "line"
		FormationType.BOX:
			return "box"
		_:
			return "staggered"


func get_offsets(type: FormationType, count: int, facing: Vector2 = Vector2.RIGHT) -> Array[Vector2]:
	if count <= 0:
		return []
	if count == 1:
		return [Vector2.ZERO]
	match type:
		FormationType.LINE:
			return _line_offsets(count, facing)
		FormationType.BOX:
			return _box_offsets(count, facing)
		_:
			return _staggered_offsets(count, facing)


func get_formation_speed(units: Array) -> float:
	var min_speed := INF
	for unit in units:
		var spd: float = 0.0
		if unit.has_method("get_move_speed"):
			spd = unit.get_move_speed()
		elif "MOVE_SPEED" in unit:
			spd = float(unit.MOVE_SPEED)
		else:
			spd = 105.0
		if spd < min_speed:
			min_speed = spd
	if min_speed == INF:
		return 105.0
	return min_speed


func _line_offsets(count: int, facing: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	# Units side-by-side perpendicular to facing
	var perp := Vector2(-facing.y, facing.x).normalized()
	var half := (count - 1) / 2.0
	for i in count:
		result.append(perp * (float(i) - half) * spacing)
	return result


func _box_offsets(count: int, facing: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var cols := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(cols)))
	var perp := Vector2(-facing.y, facing.x).normalized()
	var back := -facing.normalized()
	var col_half := (cols - 1) / 2.0
	var placed := 0
	for row in rows:
		for col in cols:
			if placed >= count:
				break
			var offset := perp * (float(col) - col_half) * spacing + back * float(row) * spacing
			result.append(offset)
			placed += 1
	return result


func _staggered_offsets(count: int, facing: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var cols := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(cols)))
	var perp := Vector2(-facing.y, facing.x).normalized()
	var back := -facing.normalized()
	var col_half := (cols - 1) / 2.0
	var placed := 0
	for row in rows:
		var stagger := 0.0
		if row % 2 == 1:
			stagger = 0.5
		for col in cols:
			if placed >= count:
				break
			var offset := perp * (float(col) - col_half + stagger) * spacing + back * float(row) * spacing
			result.append(offset)
			placed += 1
	return result


static func assign_slots_sorted(
	unit_positions: Array[Vector2], slots: Array[Vector2], facing: Vector2 = Vector2.RIGHT
) -> Array[Vector2]:
	## Assign unit positions to formation slots using sorted greedy matching.
	## Projects both onto the facing axis, sorts, and matches in order.
	## O(n log n) via sorting instead of O(n²) brute-force.
	var n := unit_positions.size()
	if n == 0:
		return []
	var s := slots.size()
	if s == 0:
		var empty: Array[Vector2] = []
		empty.resize(n)
		return empty

	# Project onto facing direction for 1D sorting
	var axis := facing.normalized()
	if axis.length() < 0.1:
		axis = Vector2.RIGHT

	# Build indexed arrays for sorting
	var unit_pairs: Array = []  # [[projection, original_index], ...]
	for i in n:
		unit_pairs.append([unit_positions[i].dot(axis), i])

	var slot_pairs: Array = []  # [[projection, original_index], ...]
	for j in s:
		slot_pairs.append([slots[j].dot(axis), j])

	# Sort both by projection (ascending)
	unit_pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	slot_pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	# Greedy 1-to-1 assignment in sorted order
	var result: Array[Vector2] = []
	result.resize(n)
	var slot_count := mini(n, s)
	for k in slot_count:
		var unit_idx: int = int(unit_pairs[k][1])
		var slot_idx: int = int(slot_pairs[k][1])
		result[unit_idx] = slots[slot_idx]

	# If more units than slots, assign extras to last slot
	if n > s:
		var last_slot: Vector2 = slots[int(slot_pairs[s - 1][1])]
		for k in range(s, n):
			var unit_idx: int = int(unit_pairs[k][1])
			result[unit_idx] = last_slot

	return result
