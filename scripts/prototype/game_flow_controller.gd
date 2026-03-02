extends RefCounted
## Manages game state transitions, victory/defeat flow, and runtime event handling.
## Extracted from prototype_main.gd to separate flow control from bootstrapping.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const TradeCartAIScript := preload("res://scripts/prototype/trade_cart_ai.gd")
const DogAIScript := preload("res://scripts/fauna/dog_ai.gd")

## Reference to the root scene node (prototype_main).
var _root: Node2D = null
## Reference to the bootstrapper for delegated helpers.
var _bootstrapper: RefCounted = null


func setup(root: Node2D, bootstrapper: RefCounted) -> void:
	_root = root
	_bootstrapper = bootstrapper


# -- Victory / defeat flow --------------------------------------------------


func on_player_defeated(player_id: int) -> void:
	if player_id == 0 and _root._victory_screen != null:
		_root._victory_screen.show_defeat("All Town Centers Lost")


func on_player_victorious(player_id: int, condition: String) -> void:
	if player_id == 0 and _root._victory_screen != null:
		var result: Dictionary = _root._victory_manager.get_game_result()
		var label: String = result.get("condition_label", condition)
		_root._victory_screen.show_victory(label)


func on_victory_stats_pressed() -> void:
	if _root._postgame_stats_screen == null or _root._game_stats_tracker == null:
		return
	_root._postgame_stats_screen.show_stats(
		_root._game_stats_tracker.get_all_stats(), _root._game_stats_tracker.get_game_time()
	)


func on_victory_tech_completed(player_id: int, tech_id: String) -> void:
	if player_id == 0 and _root._singularity_cinematic != null:
		_root._pending_victory_tech = [player_id, tech_id]
		_root.get_tree().paused = true
		_root._singularity_cinematic.process_mode = Node.PROCESS_MODE_ALWAYS
		_root._singularity_cinematic.play_cinematic()
		_root._singularity_cinematic.cinematic_complete.connect(on_singularity_cinematic_complete, CONNECT_ONE_SHOT)
	else:
		_root._victory_manager.on_victory_tech_completed(player_id, tech_id)


func on_singularity_cinematic_complete() -> void:
	_root.get_tree().paused = false
	if not _root._pending_victory_tech.is_empty():
		var pid: int = int(_root._pending_victory_tech[0])
		var tid: String = str(_root._pending_victory_tech[1])
		_root._pending_victory_tech = []
		_root._victory_manager.on_victory_tech_completed(pid, tid)


func on_agi_core_built(player_id: int) -> void:
	if player_id == 0 and _root._singularity_cinematic != null:
		_root.get_tree().paused = true
		_root._singularity_cinematic.process_mode = Node.PROCESS_MODE_ALWAYS
		_root._singularity_cinematic.play_cinematic()
		_root._singularity_cinematic.cinematic_complete.connect(
			func() -> void:
				_root.get_tree().paused = false
				_root._victory_manager._trigger_victory(player_id, "singularity"),
			CONNECT_ONE_SHOT,
		)
	else:
		_root._victory_manager._trigger_victory(player_id, "singularity")


func on_wonder_countdown_started(_player_id: int, duration: float) -> void:
	if _root._notification_panel == null:
		return
	var minutes: int = int(duration) / 60
	_root._notification_panel.notify("A Wonder has been completed! %d minutes remain." % minutes, "alert")


func on_wonder_countdown_cancelled(_player_id: int) -> void:
	if _root._notification_panel == null:
		return
	_root._notification_panel.notify("Wonder destroyed! Countdown cancelled.", "alert")


# -- Entity lifecycle events -------------------------------------------------


func on_building_placed(building: Node2D) -> void:
	_root._entity_registry.register(building)
	if _root._input_handler != null and _root._input_handler.has_method("register_unit"):
		_root._input_handler.register_unit(building)
	if building.has_signal("construction_complete"):
		building.construction_complete.connect(on_building_construction_complete)
	if building.has_signal("building_destroyed"):
		building.building_destroyed.connect(on_building_destroyed)
	var idle_unit := find_nearest_idle_unit(building.global_position)
	if idle_unit != null and idle_unit.has_method("assign_build_target"):
		idle_unit.assign_build_target(building)


func on_building_construction_complete(building: Node2D) -> void:
	if _root._population_manager != null and "owner_id" in building:
		_root._population_manager.register_building(building, building.owner_id)
	if _root._game_stats_tracker != null and "owner_id" in building and "building_name" in building:
		_root._game_stats_tracker.record_building_built(building.owner_id, building.building_name)
	_bootstrapper.try_attach_production_queue(building)
	_apply_building_effects(building)


func on_building_destroyed(building: Node2D) -> void:
	_remove_building_effects(building)
	_root._entity_registry.unregister(building)
	if _root._population_manager != null and "owner_id" in building:
		_root._population_manager.unregister_building(building, building.owner_id)
	if _root._game_stats_tracker != null and "owner_id" in building:
		_root._game_stats_tracker.record_building_lost(building.owner_id)
	if _root._target_detector != null:
		_root._target_detector.unregister_entity(building)
	if _root._pathfinder != null and "grid_pos" in building and "footprint" in building:
		var cells := BuildingValidator.get_footprint_cells(building.grid_pos, building.footprint)
		for cell in cells:
			_root._pathfinder.set_cell_solid(cell, false)
	if (
		building.building_name == "town_center"
		and not building.under_construction
		and building.last_attacker_id >= 0
		and building.last_attacker_id != building.owner_id
	):
		var regressed: Array = _root._tech_manager.trigger_knowledge_burning(building.owner_id)
		if not regressed.is_empty():
			EventBus.emit_knowledge_burned(building.last_attacker_id, building.owner_id, regressed)
			_play_knowledge_burning_vfx(
				building.position,
				building.owner_id,
				building.last_attacker_id,
				regressed,
			)
	if "owner_id" in building and int(building.owner_id) == 1:
		if _root._ai_military != null:
			_root._ai_military.on_building_destroyed(building)
		if _root._ai_economy != null:
			_root._ai_economy.on_building_destroyed(building)
	_root._update_fog_of_war()


func _apply_building_effects(building: Node2D) -> void:
	## Applies data-driven building effects (e.g. research_speed_bonus, cost reduction).
	if not ("building_name" in building and "owner_id" in building):
		return
	var stats: Dictionary = DataLoader.get_building_stats(building.building_name)
	var effects: Dictionary = stats.get("effects", {})
	if effects.is_empty():
		return
	var bonus: float = float(effects.get("research_speed_bonus", 0.0))
	if bonus > 0.0 and _root._tech_manager != null:
		_root._tech_manager.add_building_research_bonus(building.owner_id, bonus)
	# Building cost reduction (e.g. Nuclear Plant)
	if _root._building_placer != null and _root._building_placer.has_method("apply_building_effect"):
		_root._building_placer.apply_building_effect(building)


func _remove_building_effects(building: Node2D) -> void:
	## Removes data-driven building effects when a building is destroyed.
	if not ("building_name" in building and "owner_id" in building):
		return
	var stats: Dictionary = DataLoader.get_building_stats(building.building_name)
	var effects: Dictionary = stats.get("effects", {})
	if effects.is_empty():
		return
	var bonus: float = float(effects.get("research_speed_bonus", 0.0))
	if bonus > 0.0 and _root._tech_manager != null:
		_root._tech_manager.remove_building_research_bonus(building.owner_id, bonus)
	# Revert building cost reduction (e.g. Nuclear Plant)
	if _root._building_placer != null and _root._building_placer.has_method("revert_building_effect"):
		_root._building_placer.revert_building_effect(building)


func on_unit_produced(unit_type: String, building: Node2D) -> void:
	var unit := Node2D.new()
	var unit_count := _root.get_child_count()
	unit.name = "Unit_%d" % unit_count
	unit.set_script(UnitScript)
	var owner_id: int = building.owner_id if "owner_id" in building else 0
	var resolved_type := CivBonusManager.get_resolved_unit_id(owner_id, unit_type)
	unit.unit_type = resolved_type
	unit.owner_id = owner_id
	var pq: Node = building.get_node_or_null("ProductionQueue")
	var offset := Vector2i(1, 1)
	if pq != null and pq.has_method("get_rally_point_offset"):
		offset = pq.get_rally_point_offset()
	var spawn_grid: Vector2i = Vector2i.ZERO
	if "grid_pos" in building:
		spawn_grid = building.grid_pos + offset
	var unit_stats: Dictionary = DataLoader.get_unit_stats(resolved_type)
	if unit_stats.get("movement_type", "") == "water" and _root._map_node != null:
		var naval_spawn: Vector2i = _bootstrapper.find_naval_spawn_point(building)
		if naval_spawn != Vector2i(-1, -1):
			spawn_grid = naval_spawn
	unit.position = IsoUtils.grid_to_screen(Vector2(spawn_grid))
	_root.add_child(unit)
	unit._scene_root = _root
	unit._pathfinder = _root._pathfinder
	if _root._visibility_manager != null:
		unit._visibility_manager = _root._visibility_manager
	if _root._war_survival != null:
		unit._war_survival = _root._war_survival
	if _root._input_handler != null and _root._input_handler.has_method("register_unit"):
		_root._input_handler.register_unit(unit)
	if _root._target_detector != null:
		_root._target_detector.register_entity(unit)
	if _root._population_manager != null:
		_root._population_manager.register_unit(unit, owner_id)
	if _root._unit_upgrade_manager != null:
		_root._unit_upgrade_manager.apply_upgrades_to_unit(unit, owner_id)
	CivBonusManager.apply_bonus_to_unit(unit.stats, unit.unit_type, owner_id)
	_root._entity_registry.register(unit)
	unit.unit_died.connect(on_unit_died)
	EventBus.emit_unit_spawned(unit, owner_id, resolved_type)
	if _root._game_stats_tracker != null:
		_root._game_stats_tracker.record_unit_produced(owner_id, resolved_type)
	if unit_type == "trade_cart" or unit_type == "merchant_ship":
		var trade_ai := Node.new()
		trade_ai.name = "TradeCartAI"
		trade_ai.set_script(TradeCartAIScript)
		unit.add_child(trade_ai)


func on_unit_died(unit: Node2D, killer: Node2D) -> void:
	var owner_id: int = unit.owner_id if "owner_id" in unit else -1
	EventBus.emit_unit_died(unit, killer, owner_id)
	_root._entity_registry.unregister(unit)
	if _root._target_detector != null:
		_root._target_detector.unregister_entity(unit)
	if _root._population_manager != null and owner_id >= 0:
		_root._population_manager.unregister_unit(unit, owner_id)
	if _root._game_stats_tracker != null and owner_id >= 0:
		_root._game_stats_tracker.record_unit_lost(owner_id)
		if killer != null and "owner_id" in killer:
			_root._game_stats_tracker.record_unit_kill(killer.owner_id)
	_root._update_fog_of_war()


func on_fauna_died(unit: Node2D, _killer: Node2D) -> void:
	_root._entity_registry.unregister(unit)
	if _root._target_detector != null:
		_root._target_detector.unregister_entity(unit)
	if "unit_type" in unit and unit.unit_type == "wolf":
		_spawn_wolf_carcass(unit.global_position)
	_root._update_fog_of_war()


func on_resource_depleted(node: Node2D) -> void:
	if _root._target_detector != null and _root._target_detector.has_method("unregister_entity"):
		_root._target_detector.unregister_entity(node)


func on_wolf_domesticated(wolf_unit: Node2D, feeder_owner_id: int) -> void:
	_root._entity_registry.unregister(wolf_unit)
	wolf_unit.owner_id = feeder_owner_id
	wolf_unit.entity_category = "dog"
	wolf_unit.unit_color = Color(0.6, 0.4, 0.2)  # Brown
	var wolf_ai := wolf_unit.get_node_or_null("WolfAI")
	if wolf_ai != null:
		wolf_unit.remove_child(wolf_ai)
		wolf_ai.queue_free()
	wolf_unit.unit_type = "dog"
	wolf_unit._init_stats()
	var dog_ai := Node.new()
	dog_ai.name = "DogAI"
	dog_ai.set_script(DogAIScript)
	wolf_unit.add_child(dog_ai)
	dog_ai.danger_alert.connect(on_dog_danger_alert)
	wolf_unit.queue_redraw()
	_root._entity_registry.register(wolf_unit)
	if _root._input_handler != null and _root._input_handler.has_method("register_unit"):
		_root._input_handler.register_unit(wolf_unit)


func on_dog_danger_alert(_alert_position: Vector2, _player_id: int) -> void:
	pass


# -- VFX / notification helpers ----------------------------------------------


func on_pandemic_started(player_id: int, _severity: float) -> void:
	if _root._pandemic_vfx != null:
		var tc_pos := find_town_center_pos(player_id)
		_root._pandemic_vfx.play_outbreak_effect(tc_pos, player_id)


func on_pandemic_ended(player_id: int) -> void:
	if _root._pandemic_vfx != null:
		_root._pandemic_vfx.play_outbreak_end(player_id)


func on_hist_event_started(event_id: String, player_id: int) -> void:
	if _root._historical_event_vfx == null:
		return
	var pos := find_town_center_pos(player_id)
	match event_id:
		"black_plague":
			_root._historical_event_vfx.play_plague_effect(pos, player_id)
		"renaissance":
			if _root._historical_event_manager.is_phoenix_active(player_id):
				_root._historical_event_vfx.play_phoenix_effect(pos, player_id)
			else:
				_root._historical_event_vfx.play_renaissance_effect(pos, player_id)


func on_hist_event_ended(event_id: String, player_id: int) -> void:
	if _root._historical_event_vfx == null:
		return
	match event_id:
		"black_plague":
			_root._historical_event_vfx.play_plague_end(player_id)
		"renaissance":
			_root._historical_event_vfx.play_renaissance_end(player_id)


func on_barge_destroyed_with_resources(barge: Node2D, resources: Dictionary) -> void:
	if _root._notification_panel == null:
		return
	if barge.owner_id != 0:
		return
	var total: int = 0
	for res_type: int in resources:
		total += resources[res_type]
	if total > 0:
		_root._notification_panel.notify("Barge destroyed! Lost %d resources." % total, "alert")


# -- HUD callbacks -----------------------------------------------------------


func on_tech_researched_spillover(player_id: int, tech_id: String, _effects: Dictionary) -> void:
	if _root._war_bonus != null:
		var tech_data: Dictionary = DataLoader.get_tech_data(tech_id)
		_root._war_bonus.apply_spillover(player_id, tech_id, tech_data)


func on_corruption_changed(player_id: int, rate: float) -> void:
	if player_id == 0 and _root._resource_bar != null:
		_root._resource_bar.update_corruption(rate)


func on_population_changed(player_id: int, current: int, cap: int) -> void:
	if player_id == 0 and _root._resource_bar != null:
		_root._resource_bar.update_population(current, cap)


func on_pause_menu_quit_to_menu() -> void:
	GameManager.reset_game_state()
	ResourceManager.reset()
	CivBonusManager.reset()
	_root.get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func on_pause_menu_quit_to_desktop() -> void:
	_root.get_tree().quit()


func on_minimap_move_command(world_pos: Vector2) -> void:
	if _root._input_handler != null and _root._input_handler.has_method("_move_selected"):
		_root._input_handler._move_selected(world_pos)


# -- Private helpers ---------------------------------------------------------


func find_nearest_idle_unit(target_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for unit in _root._entity_registry.get_by_owner(0):
		if not unit.has_method("is_idle") or not unit.is_idle():
			continue
		var dist: float = unit.global_position.distance_to(target_pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best


func find_town_center_pos(player_id: int) -> Vector2:
	for bld in _root._entity_registry.get_by_owner_and_category(player_id, "building"):
		if "building_name" in bld and bld.building_name == "town_center":
			return bld.position
	return Vector2.ZERO


func _spawn_wolf_carcass(world_pos: Vector2) -> void:
	var res_node := Node2D.new()
	var carcass_index := _root.get_child_count()
	res_node.name = "Resource_wolf_carcass_%d" % carcass_index
	res_node.set_script(preload("res://scripts/prototype/prototype_resource_node.gd"))
	res_node.position = world_pos
	_root.add_child(res_node)
	res_node.setup("wolf_carcass")
	res_node.depleted.connect(on_resource_depleted)
	if _root._target_detector != null:
		_root._target_detector.register_entity(res_node)


func _play_knowledge_burning_vfx(
	world_pos: Vector2,
	defender_id: int,
	attacker_id: int,
	regressed_techs: Array,
) -> void:
	if _root._knowledge_burning_vfx == null:
		return
	for tech_data: Dictionary in regressed_techs:
		var tech_name: String = tech_data.get("name", "Unknown Technology")
		var effects: Dictionary = tech_data.get("effects", {})
		var desc: String = _format_tech_effect_description(effects)
		_root._knowledge_burning_vfx.play_burning_effect(world_pos, tech_name, desc, defender_id, attacker_id)


func _format_tech_effect_description(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in effects:
		var value: Variant = effects[key]
		if value is float or value is int:
			var sign: String = "+" if float(value) >= 0.0 else ""
			parts.append("%s%s %s" % [sign, str(value), key.replace("_", " ")])
		else:
			parts.append("%s: %s" % [key.replace("_", " "), str(value)])
	if parts.is_empty():
		return "unknown effect"
	return ", ".join(parts)
