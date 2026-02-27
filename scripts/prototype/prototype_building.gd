extends Node2D
## Prototype building — isometric footprint-aware, targetable by right-click.
## Supports construction state: starts translucent, built by villagers over time.

signal construction_complete(building: Node2D)
signal building_destroyed(building: Node2D)

@export var owner_id: int = 0
var entity_category: String = "own_building"
var building_name: String = ""
var footprint := Vector2i(1, 1)
var grid_pos := Vector2i.ZERO
var hp: int = 0
var max_hp: int = 0
var selected: bool = false

var is_drop_off: bool = false
var drop_off_types: Array[String] = []
var garrison_capacity: int = 0

var under_construction: bool = false
var build_progress: float = 0.0
var last_attacker_id: int = -1
var _build_time: float = 1.0

var _is_ruins: bool = false
var _ruins_timer: float = 0.0
var _ruins_decay_time: float = 120.0
var _ruins_alpha: float = 0.35

var _intact_threshold: float = 0.66
var _damaged_threshold: float = 0.33
var _hp_intact_color: Color = Color(0.2, 0.8, 0.2, 0.9)
var _hp_damaged_color: Color = Color(0.9, 0.8, 0.1, 0.9)
var _hp_critical_color: Color = Color(0.9, 0.2, 0.2, 0.9)

var _garrisoned_units: Array[Node2D] = []
var _garrison_arrow_timer: float = 0.0
var _garrison_config: Dictionary = {}
var _pending_garrison_names: Array[String] = []

var _dog_los_bonus: int = 0

var _combat_config: Dictionary = {}
var _construction_alpha: float = 0.4
var _bar_width: float = 40.0
var _bar_height: float = 5.0
var _bar_offset_y: float = -30.0


func _ready() -> void:
	_load_building_stats()
	_load_construction_config()
	_load_combat_config()
	_load_destruction_config()


func _load_building_stats() -> void:
	if building_name == "":
		return
	var stats: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		stats = DataLoader.get_building_stats(building_name)
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_building_stats"):
			stats = dl.get_building_stats(building_name)
	if stats.is_empty():
		return
	is_drop_off = bool(stats.get("is_drop_off", false))
	garrison_capacity = int(stats.get("garrison_capacity", 0))
	var types: Array = stats.get("drop_off_types", [])
	drop_off_types.clear()
	for t in types:
		drop_off_types.append(str(t))


func _load_construction_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("construction")
	if cfg.is_empty():
		return
	_construction_alpha = float(cfg.get("construction_alpha", _construction_alpha))
	_bar_width = float(cfg.get("progress_bar_width", _bar_width))
	_bar_height = float(cfg.get("progress_bar_height", _bar_height))
	_bar_offset_y = float(cfg.get("progress_bar_offset_y", _bar_offset_y))


func _load_combat_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("combat")
	if not cfg.is_empty():
		_combat_config = cfg
		_garrison_config = cfg.get("garrison", {})


func _load_destruction_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("building_destruction")
	if cfg.is_empty():
		return
	var states: Dictionary = cfg.get("damage_states", {})
	_intact_threshold = float(states.get("intact_threshold", _intact_threshold))
	_damaged_threshold = float(states.get("damaged_threshold", _damaged_threshold))
	var ruins_cfg: Dictionary = cfg.get("ruins", {})
	_ruins_decay_time = float(ruins_cfg.get("decay_time", _ruins_decay_time))
	_ruins_alpha = float(ruins_cfg.get("alpha", _ruins_alpha))
	var bar_cfg: Dictionary = cfg.get("hp_bar", {})
	var intact_arr: Array = bar_cfg.get("intact_color", [])
	if intact_arr.size() == 4:
		_hp_intact_color = _arr_to_color(intact_arr)
	var damaged_arr: Array = bar_cfg.get("damaged_color", [])
	if damaged_arr.size() == 4:
		_hp_damaged_color = _arr_to_color(damaged_arr)
	var critical_arr: Array = bar_cfg.get("critical_color", [])
	if critical_arr.size() == 4:
		_hp_critical_color = _arr_to_color(critical_arr)


func _arr_to_color(arr: Array) -> Color:
	return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))


func take_damage(amount: int, _attacker: Node2D) -> void:
	if _is_ruins:
		return
	if _attacker != null and "owner_id" in _attacker:
		last_attacker_id = _attacker.owner_id
	hp -= amount
	if hp < 0:
		hp = 0
	queue_redraw()
	if hp <= 0:
		_on_destroyed()


func _on_destroyed() -> void:
	ungarrison_all()
	_is_ruins = true
	entity_category = "ruins"
	building_destroyed.emit(self)
	_ruins_timer = 0.0
	set_process(true)
	queue_redraw()


func get_damage_state() -> String:
	if max_hp <= 0:
		return "intact"
	var ratio: float = float(hp) / float(max_hp)
	if ratio > _intact_threshold:
		return "intact"
	if ratio > _damaged_threshold:
		return "damaged"
	return "critical"


func _process(delta: float) -> void:
	var game_delta: float = delta
	if GameManager.has_method("get_game_delta"):
		game_delta = GameManager.get_game_delta(delta)
	if _is_ruins:
		_ruins_timer += game_delta
		if _ruins_timer >= _ruins_decay_time:
			queue_free()
		return
	if not _garrisoned_units.is_empty():
		_tick_garrison_arrows(game_delta)


func get_entity_category() -> String:
	if _is_ruins:
		return "ruins"
	if under_construction:
		return "construction_site"
	return entity_category


func set_dog_los_bonus(bonus: int) -> void:
	_dog_los_bonus = bonus


func get_los() -> int:
	return _dog_los_bonus


func apply_build_work(amount: float) -> void:
	if not under_construction:
		return
	build_progress = clampf(build_progress + amount, 0.0, 1.0)
	hp = int(build_progress * max_hp)
	queue_redraw()
	if build_progress >= 1.0 - 0.001:
		_complete_construction()


func _complete_construction() -> void:
	under_construction = false
	hp = max_hp
	build_progress = 1.0
	queue_redraw()
	construction_complete.emit(self)


func select() -> void:
	selected = true
	queue_redraw()


func deselect() -> void:
	selected = false
	queue_redraw()


func is_point_inside(point: Vector2) -> bool:
	# Check if point falls within any footprint cell's isometric diamond
	var local_point := point - global_position
	for x in footprint.x:
		for y in footprint.y:
			var cell_center := IsoUtils.grid_to_screen(Vector2(x, y))
			var offset := local_point - cell_center
			# Isometric diamond test: |ox/hw| + |oy/hh| <= 1
			var nx := absf(offset.x) / IsoUtils.HALF_W
			var ny := absf(offset.y) / IsoUtils.HALF_H
			if nx + ny <= 1.0:
				return true
	return false


func _draw() -> void:
	if _is_ruins:
		_draw_ruins()
		return
	var color: Color
	if owner_id == 0:
		color = Color(0.2, 0.5, 1.0)
	else:
		color = Color(0.8, 0.2, 0.2)
	var damage_state := ""
	if under_construction:
		color.a = _construction_alpha
	else:
		damage_state = get_damage_state()
		if damage_state == "damaged":
			color = color.darkened(0.2)
		elif damage_state == "critical":
			color = color.darkened(0.4)
			color.a = 0.7
	# Draw isometric diamonds for each footprint cell
	for x in footprint.x:
		for y in footprint.y:
			var offset := IsoUtils.grid_to_screen(Vector2(x, y))
			_draw_iso_cell(offset, color)
	# Draw crack overlay on damaged/critical cells
	if damage_state == "damaged" or damage_state == "critical":
		for x in footprint.x:
			for y in footprint.y:
				var offset := IsoUtils.grid_to_screen(Vector2(x, y))
				_draw_crack_overlay(offset, damage_state)
	# Selection highlight
	if selected:
		_draw_selection_outline()
	# Progress bar during construction
	if under_construction:
		_draw_progress_bar()
	# HP bar when damaged (not under construction)
	elif max_hp > 0 and hp < max_hp:
		_draw_hp_bar()


func _draw_progress_bar() -> void:
	var bar_pos := Vector2(-_bar_width / 2.0, _bar_offset_y)
	var bar_size := Vector2(_bar_width, _bar_height)
	BarDrawer.draw_bar(self, bar_pos, bar_size, build_progress, Color(0.2, 0.8, 0.2, 0.9))


func _draw_hp_bar() -> void:
	var ratio: float = float(hp) / float(max_hp)
	var hp_color: Color
	if ratio > _intact_threshold:
		hp_color = _hp_intact_color
	elif ratio > _damaged_threshold:
		hp_color = _hp_damaged_color
	else:
		hp_color = _hp_critical_color
	var bar_pos := Vector2(-_bar_width / 2.0, _bar_offset_y)
	var bar_size := Vector2(_bar_width, _bar_height)
	BarDrawer.draw_bar(self, bar_pos, bar_size, ratio, hp_color)


func _draw_iso_cell(offset: Vector2, color: Color) -> void:
	var hw := IsoUtils.HALF_W
	var hh := IsoUtils.HALF_H
	var points := PackedVector2Array(
		[
			offset + Vector2(0, -hh),
			offset + Vector2(hw, 0),
			offset + Vector2(0, hh),
			offset + Vector2(-hw, 0),
		]
	)
	draw_colored_polygon(points, color)
	var line_color := Color(color, 1.0).darkened(0.3)
	draw_line(points[0], points[1], line_color, 2.0)
	draw_line(points[1], points[2], line_color, 2.0)
	draw_line(points[2], points[3], line_color, 2.0)
	draw_line(points[3], points[0], line_color, 2.0)


func _draw_ruins() -> void:
	var ruins_color := Color(0.4, 0.4, 0.4, _ruins_alpha)
	var hw := IsoUtils.HALF_W
	var hh := IsoUtils.HALF_H
	for x in footprint.x:
		for y in footprint.y:
			var offset := IsoUtils.grid_to_screen(Vector2(x, y))
			var points := PackedVector2Array(
				[
					offset + Vector2(0, -hh),
					offset + Vector2(hw, 0),
					offset + Vector2(0, hh),
					offset + Vector2(-hw, 0),
				]
			)
			draw_line(points[0], points[1], ruins_color, 1.5)
			draw_line(points[1], points[2], ruins_color, 1.5)
			draw_line(points[2], points[3], ruins_color, 1.5)
			draw_line(points[3], points[0], ruins_color, 1.5)


func _draw_crack_overlay(offset: Vector2, state: String) -> void:
	var hw := IsoUtils.HALF_W
	var hh := IsoUtils.HALF_H
	var crack_alpha: float = 0.4 if state == "damaged" else 0.7
	var crack_color := Color(0.1, 0.1, 0.1, crack_alpha)
	# Diagonal crack lines across the cell
	draw_line(offset + Vector2(-hw * 0.3, -hh * 0.5), offset + Vector2(hw * 0.4, hh * 0.3), crack_color, 1.5)
	draw_line(offset + Vector2(hw * 0.1, -hh * 0.4), offset + Vector2(-hw * 0.2, hh * 0.5), crack_color, 1.5)


func _draw_selection_outline() -> void:
	var hw := IsoUtils.HALF_W
	var hh := IsoUtils.HALF_H
	# Corners of the bounding iso region
	var top := IsoUtils.grid_to_screen(Vector2(0, 0)) + Vector2(0, -hh)
	var right := IsoUtils.grid_to_screen(Vector2(footprint.x - 1, 0)) + Vector2(hw, 0)
	var bottom := IsoUtils.grid_to_screen(Vector2(footprint.x - 1, footprint.y - 1)) + Vector2(0, hh)
	var left := IsoUtils.grid_to_screen(Vector2(0, footprint.y - 1)) + Vector2(-hw, 0)
	var highlight := Color(1.0, 1.0, 0.3, 0.8)
	draw_line(top, right, highlight, 2.0)
	draw_line(right, bottom, highlight, 2.0)
	draw_line(bottom, left, highlight, 2.0)
	draw_line(left, top, highlight, 2.0)


## -- Garrison System --


func garrison_unit(unit: Node2D) -> bool:
	if not can_garrison():
		return false
	if unit in _garrisoned_units:
		return false
	_garrisoned_units.append(unit)
	unit.visible = false
	unit.set_process(false)
	return true


func ungarrison_all() -> Array[Node2D]:
	var ejected: Array[Node2D] = []
	var radius: float = float(_garrison_config.get("ungarrison_radius_tiles", 2)) * 64.0
	var count := _garrisoned_units.size()
	for i in count:
		var unit: Node2D = _garrisoned_units[i]
		if not is_instance_valid(unit):
			continue
		# Place units in a circle around the building
		var angle := TAU * float(i) / float(maxi(count, 1))
		var offset := Vector2(cos(angle), sin(angle)) * radius
		unit.global_position = global_position + offset
		unit.visible = true
		unit.set_process(true)
		ejected.append(unit)
	_garrisoned_units.clear()
	return ejected


func get_garrisoned_count() -> int:
	# Clean up freed units
	var i := _garrisoned_units.size() - 1
	while i >= 0:
		if not is_instance_valid(_garrisoned_units[i]):
			_garrisoned_units.remove_at(i)
		i -= 1
	return _garrisoned_units.size()


func can_garrison() -> bool:
	if garrison_capacity <= 0:
		return false
	if _is_ruins:
		return false
	if under_construction:
		return false
	return get_garrisoned_count() < garrison_capacity


func _tick_garrison_arrows(game_delta: float) -> void:
	if get_garrisoned_count() <= 0:
		return
	_garrison_arrow_timer += game_delta
	var interval: float = float(_garrison_config.get("arrow_interval", 2.0))
	if _garrison_arrow_timer < interval:
		return
	_garrison_arrow_timer = 0.0
	# Find nearest hostile in range
	var arrow_range: float = float(_garrison_config.get("arrow_range_tiles", 6)) * 64.0
	var target := _find_nearest_hostile(arrow_range)
	if target == null:
		return
	# Deal arrow damage
	var arrow_damage: int = int(_garrison_config.get("arrow_damage", 5))
	var total_damage: int = arrow_damage * get_garrisoned_count()
	if target.has_method("take_damage"):
		target.take_damage(total_damage, self)
	elif "hp" in target:
		target.hp -= total_damage
		if target.hp < 0:
			target.hp = 0
	# Spawn projectile VFX
	var vfx_parent := get_parent()
	if vfx_parent != null:
		CombatVisual.spawn_projectile(vfx_parent, global_position, target.global_position, _combat_config)
		if _combat_config.get("show_damage_numbers", true):
			CombatVisual.spawn_damage_number(
				vfx_parent, target.global_position + Vector2(0, -20), total_damage, _combat_config
			)


func _find_nearest_hostile(max_range: float) -> Node2D:
	var root := get_parent()
	if root == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for child in root.get_children():
		if child == self:
			continue
		if not (child is Node2D):
			continue
		if not CombatResolver.is_hostile(self, child):
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = global_position.distance_to(child.global_position)
		if dist > max_range:
			continue
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func resolve_garrison(scene_root: Node) -> void:
	for unit_name in _pending_garrison_names:
		var unit := scene_root.get_node_or_null(unit_name)
		if unit is Node2D:
			garrison_unit(unit)
	_pending_garrison_names.clear()


func save_state() -> Dictionary:
	var garrisoned_names: Array[String] = []
	for unit in _garrisoned_units:
		if is_instance_valid(unit):
			garrisoned_names.append(str(unit.name))
	return {
		"building_name": building_name,
		"grid_pos": [grid_pos.x, grid_pos.y],
		"owner_id": owner_id,
		"hp": hp,
		"max_hp": max_hp,
		"under_construction": under_construction,
		"build_progress": build_progress,
		"build_time": _build_time,
		"is_drop_off": is_drop_off,
		"drop_off_types": drop_off_types,
		"last_attacker_id": last_attacker_id,
		"is_ruins": _is_ruins,
		"ruins_timer": _ruins_timer,
		"garrison_capacity": garrison_capacity,
		"garrisoned_units": garrisoned_names,
		"dog_los_bonus": _dog_los_bonus,
	}


func load_state(data: Dictionary) -> void:
	building_name = str(data.get("building_name", ""))
	var pos_arr: Array = data.get("grid_pos", [0, 0])
	grid_pos = Vector2i(int(pos_arr[0]), int(pos_arr[1]))
	owner_id = int(data.get("owner_id", 0))
	hp = int(data.get("hp", 0))
	max_hp = int(data.get("max_hp", 0))
	under_construction = bool(data.get("under_construction", false))
	build_progress = float(data.get("build_progress", 0.0))
	_build_time = float(data.get("build_time", 1.0))
	is_drop_off = bool(data.get("is_drop_off", false))
	var types: Array = data.get("drop_off_types", [])
	drop_off_types.clear()
	for t in types:
		drop_off_types.append(str(t))
	last_attacker_id = int(data.get("last_attacker_id", -1))
	_is_ruins = bool(data.get("is_ruins", false))
	_ruins_timer = float(data.get("ruins_timer", 0.0))
	garrison_capacity = int(data.get("garrison_capacity", 0))
	_dog_los_bonus = int(data.get("dog_los_bonus", 0))
	_pending_garrison_names.clear()
	var g_names: Array = data.get("garrisoned_units", [])
	for n in g_names:
		_pending_garrison_names.append(str(n))
	if _is_ruins:
		entity_category = "ruins"
		set_process(true)
	queue_redraw()
