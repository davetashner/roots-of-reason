extends RefCounted
## Faction/type entity registry for O(1) lookups by owner_id and entity_category.
## Replaces O(N) scene-tree scanning in AI brains (ai_military, ai_economy, etc.).
## Complementary to SpatialIndex, which handles position-based queries.

# Primary indices: owner_id -> Array[Node2D], entity_category -> Array[Node2D]
var _by_owner: Dictionary = {}
var _by_category: Dictionary = {}
# Composite index: "owner_id:category" -> Array[Node2D]
var _by_owner_and_category: Dictionary = {}
# Reverse lookup to prevent double-registration and enable fast unregister
var _registered: Dictionary = {}  # entity -> true


func register(entity: Node2D) -> void:
	if entity in _registered:
		return
	_registered[entity] = true
	var owner_id: int = int(entity.owner_id) if "owner_id" in entity else -1
	var category: String = _resolve_category(entity)
	# Index by owner
	if not _by_owner.has(owner_id):
		_by_owner[owner_id] = [] as Array[Node2D]
	_by_owner[owner_id].append(entity)
	# Index by category
	if category != "":
		if not _by_category.has(category):
			_by_category[category] = [] as Array[Node2D]
		_by_category[category].append(entity)
	# Composite index
	var composite_key: String = _composite_key(owner_id, category)
	if not _by_owner_and_category.has(composite_key):
		_by_owner_and_category[composite_key] = [] as Array[Node2D]
	_by_owner_and_category[composite_key].append(entity)


func unregister(entity: Node2D) -> void:
	if entity not in _registered:
		return
	_registered.erase(entity)
	var owner_id: int = int(entity.owner_id) if "owner_id" in entity else -1
	var category: String = _resolve_category(entity)
	# Remove from owner index
	if _by_owner.has(owner_id):
		_by_owner[owner_id].erase(entity)
		if _by_owner[owner_id].is_empty():
			_by_owner.erase(owner_id)
	# Remove from category index
	if category != "" and _by_category.has(category):
		_by_category[category].erase(entity)
		if _by_category[category].is_empty():
			_by_category.erase(category)
	# Remove from composite index
	var composite_key: String = _composite_key(owner_id, category)
	if _by_owner_and_category.has(composite_key):
		_by_owner_and_category[composite_key].erase(entity)
		if _by_owner_and_category[composite_key].is_empty():
			_by_owner_and_category.erase(composite_key)


func is_registered(entity: Node2D) -> bool:
	return entity in _registered


func get_by_owner(owner_id: int) -> Array[Node2D]:
	if _by_owner.has(owner_id):
		return _by_owner[owner_id]
	return [] as Array[Node2D]


func get_by_category(category: String) -> Array[Node2D]:
	if _by_category.has(category):
		return _by_category[category]
	return [] as Array[Node2D]


func get_by_owner_and_category(owner_id: int, category: String) -> Array[Node2D]:
	var key: String = _composite_key(owner_id, category)
	if _by_owner_and_category.has(key):
		return _by_owner_and_category[key]
	return [] as Array[Node2D]


func get_count() -> int:
	return _registered.size()


func get_count_by_owner(owner_id: int) -> int:
	if _by_owner.has(owner_id):
		return _by_owner[owner_id].size()
	return 0


func get_count_by_owner_and_category(owner_id: int, category: String) -> int:
	var key: String = _composite_key(owner_id, category)
	if _by_owner_and_category.has(key):
		return _by_owner_and_category[key].size()
	return 0


func clear() -> void:
	_by_owner.clear()
	_by_category.clear()
	_by_owner_and_category.clear()
	_registered.clear()


func _resolve_category(entity: Node2D) -> String:
	# Units have unit_category (military, villager, etc.)
	if "unit_category" in entity and str(entity.unit_category) != "":
		return str(entity.unit_category)
	# Buildings have building_name
	if "building_name" in entity:
		return "building"
	# Fallback to entity_category if set
	if "entity_category" in entity and str(entity.entity_category) != "":
		return str(entity.entity_category)
	return ""


func _composite_key(owner_id: int, category: String) -> String:
	return "%d:%s" % [owner_id, category]
