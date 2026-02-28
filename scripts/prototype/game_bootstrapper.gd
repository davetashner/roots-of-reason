extends RefCounted
## One-time scene setup: creates managers, units, buildings, AI, and HUD nodes.
## Extracted from prototype_main.gd to separate bootstrapping from coordination.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")
const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const AITechScript := preload("res://scripts/ai/ai_tech.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const WolfAIScript := preload("res://scripts/fauna/wolf_ai.gd")
const DogAIScript := preload("res://scripts/fauna/dog_ai.gd")
const RiverTransportScript := preload("res://scripts/prototype/river_transport.gd")
const TradeManagerScript := preload("res://scripts/prototype/trade_manager.gd")
const TradeCartAIScript := preload("res://scripts/prototype/trade_cart_ai.gd")
const NotificationPanelScript := preload("res://scripts/ui/notification_panel.gd")
const RiverOverlayScript := preload("res://scripts/ui/river_overlay.gd")
const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")
const KnowledgeBurningVFXScript := preload("res://scripts/prototype/knowledge_burning_vfx.gd")
const WarSurvivalScript := preload("res://scripts/prototype/war_survival.gd")
const VictoryScreenScript := preload("res://scripts/ui/victory_screen.gd")
const TechTreeViewerScript := preload("res://scripts/ui/tech_tree_viewer.gd")
const SingularityRegressionScript := preload("res://scripts/prototype/singularity_regression.gd")
const AISingularityScript := preload("res://scripts/ai/ai_singularity.gd")
const SingularityCinematicVFXScript := preload("res://scripts/prototype/singularity_cinematic_vfx.gd")
const CivSelectionScreenScript := preload("res://scripts/ui/civ_selection_screen.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const PirateManagerScript := preload("res://scripts/prototype/pirate_manager.gd")
const PandemicManagerScript := preload("res://scripts/prototype/pandemic_manager.gd")
const PandemicVFXScript := preload("res://scripts/prototype/pandemic_vfx.gd")
const HistoricalEventManagerScript := preload("res://scripts/prototype/historical_event_manager.gd")
const HistoricalEventVFXScript := preload("res://scripts/prototype/historical_event_vfx.gd")
const GameStatsTrackerScript := preload("res://scripts/prototype/game_stats_tracker.gd")
const PostGameStatsScreenScript := preload("res://scripts/ui/postgame_stats_screen.gd")
const EntityRegistryScript := preload("res://scripts/prototype/entity_registry.gd")

## Screen-space offsets for clustered resource nodes within a single tile.
const CLUSTER_OFFSETS: Array[Vector2] = [
	Vector2(0, -16),  # north
	Vector2(32, 0),  # east
	Vector2(-32, 0),  # west
	Vector2(0, 16),  # south
]

## Reference to the root scene node (prototype_main).
var _root: Node2D = null


func setup(root: Node2D) -> void:
	_root = root


func setup_civilizations() -> void:
	var player_civ: String = GameManager.get_player_civilization(0)
	var ai_civ: String = GameManager.get_player_civilization(1)
	if player_civ == "":
		player_civ = "mesopotamia"
	if ai_civ == "":
		ai_civ = "rome"
	CivBonusManager.apply_civ_bonuses(0, player_civ)
	CivBonusManager.apply_civ_bonuses(1, ai_civ)
	CivBonusManager.apply_starting_bonuses(0)
	CivBonusManager.apply_starting_bonuses(1)


func setup_units() -> void:
	var offsets := get_villager_offsets()
	var tc_pos := get_start_position(0)
	for i in offsets.size():
		var unit := Node2D.new()
		unit.name = "Unit_%d" % i
		unit.set_script(UnitScript)
		var offset: Vector2i = offsets[i]
		var spawn_pos: Vector2i = tc_pos + offset
		unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
		unit.unit_type = "villager"
		_root.add_child(unit)
		unit._scene_root = _root
		unit._pathfinder = _root._pathfinder
		if _root._visibility_manager != null:
			unit._visibility_manager = _root._visibility_manager
		if _root._war_survival != null:
			unit._war_survival = _root._war_survival
		if _root._input_handler.has_method("register_unit"):
			_root._input_handler.register_unit(unit)
		if _root._target_detector != null:
			_root._target_detector.register_entity(unit)
		if _root._population_manager != null:
			_root._population_manager.register_unit(unit, 0)
		_root._entity_registry.register(unit)
		unit.unit_died.connect(_root._on_unit_died)


func setup_demo_entities() -> void:
	var all_resource_positions: Dictionary = _root._map_node.get_resource_positions()

	var res_index := 0
	for res_name: String in all_resource_positions:
		var positions: Array = all_resource_positions[res_name]
		# Track cluster index per grid position for sub-tile offsets
		var cluster_counts: Dictionary = {}  # Vector2i -> int
		for pos in positions:
			var grid_pos: Vector2i = pos as Vector2i
			var cluster_idx: int = cluster_counts.get(grid_pos, 0)
			cluster_counts[grid_pos] = cluster_idx + 1
			var base_screen: Vector2 = IsoUtils.grid_to_screen(Vector2(grid_pos))
			var offset := Vector2.ZERO
			if cluster_idx > 0 and cluster_idx < CLUSTER_OFFSETS.size():
				offset = CLUSTER_OFFSETS[cluster_idx]
			var res_node := Node2D.new()
			res_node.name = "Resource_%s_%d" % [res_name, res_index]
			res_node.set_script(ResourceNodeScript)
			res_node.position = base_screen + offset
			res_node.grid_position = grid_pos
			res_node.z_index = 2
			res_node.variant_index = res_index
			_root.add_child(res_node)
			res_node.setup(res_name)
			res_node.depleted.connect(_root._on_resource_depleted)
			_root._target_detector.register_entity(res_node)
			res_index += 1
	var start_cfg: Dictionary = _load_start_config(GameManager.player_difficulty)
	var bld_pos := get_start_position(0)
	if start_cfg.get("pre_built_tc", true):
		_create_town_center(0, bld_pos, "")
	var house_count: int = int(start_cfg.get("starting_houses", 0))
	for i in house_count:
		var house_offset := Vector2i(4 + i * 3, -1)
		_create_house(0, bld_pos + house_offset, "")


func setup_fauna() -> void:
	var all_fauna: Dictionary = _root._map_node.get_fauna_positions()
	var fauna_index := 0
	var pack_index := 0
	for fauna_name: String in all_fauna:
		var packs: Array = all_fauna[fauna_name]
		for pack in packs:
			var pack_dict: Dictionary = pack as Dictionary
			var grid_pos: Vector2i = pack_dict.get("position", Vector2i.ZERO)
			var pack_size: int = int(pack_dict.get("pack_size", 2))
			for i in pack_size:
				var unit := Node2D.new()
				unit.name = "Fauna_%s_%d" % [fauna_name, fauna_index]
				unit.set_script(UnitScript)
				var offset := Vector2i(i % 2, i / 2)
				var spawn_pos: Vector2i = grid_pos + offset
				unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
				unit.unit_type = fauna_name
				unit.owner_id = -1  # Gaia faction
				unit.unit_color = Color(0.5, 0.5, 0.5)
				_root.add_child(unit)
				unit._scene_root = _root
				unit._pathfinder = _root._pathfinder
				if _root._war_survival != null:
					unit._war_survival = _root._war_survival
				if _root._target_detector != null:
					_root._target_detector.register_entity(unit)
				if fauna_name == "wolf":
					unit.entity_category = "wild_fauna"
				if fauna_name == "wolf":
					var wolf_ai := Node.new()
					wolf_ai.name = "WolfAI"
					wolf_ai.set_script(WolfAIScript)
					wolf_ai.pack_id = pack_index
					unit.add_child(wolf_ai)
					wolf_ai.domesticated.connect(func(foid: int) -> void: _root._on_wolf_domesticated(unit, foid))
				_root._entity_registry.register(unit)
				if unit.has_signal("unit_died"):
					unit.unit_died.connect(_root._on_fauna_died)
				fauna_index += 1
			pack_index += 1


func setup_tech() -> void:
	_root._tech_manager = Node.new()
	_root._tech_manager.name = "TechManager"
	_root._tech_manager.set_script(load("res://scripts/prototype/tech_manager.gd"))
	_root.add_child(_root._tech_manager)
	_root._war_bonus = Node.new()
	_root._war_bonus.name = "WarResearchBonus"
	_root._war_bonus.set_script(load("res://scripts/prototype/war_research_bonus.gd"))
	_root.add_child(_root._war_bonus)
	_root._tech_manager.setup_war_bonus(_root._war_bonus)
	_root._unit_upgrade_manager = Node.new()
	_root._unit_upgrade_manager.name = "UnitUpgradeManager"
	_root._unit_upgrade_manager.set_script(load("res://scripts/prototype/unit_upgrade_manager.gd"))
	_root.add_child(_root._unit_upgrade_manager)
	_root._unit_upgrade_manager.setup(_root)
	_root._tech_manager.tech_researched.connect(_root._unit_upgrade_manager.on_tech_researched)
	_root._tech_manager.tech_regressed.connect(_root._unit_upgrade_manager.on_tech_regressed)
	_root._war_survival = Node.new()
	_root._war_survival.name = "WarSurvival"
	_root._war_survival.set_script(WarSurvivalScript)
	_root.add_child(_root._war_survival)
	_root._war_survival.setup(_root._tech_manager)
	_root._tech_manager.tech_researched.connect(_root._on_tech_researched_spillover)
	_root._singularity_regression = Node.new()
	_root._singularity_regression.name = "SingularityRegression"
	_root._singularity_regression.set_script(SingularityRegressionScript)
	_root.add_child(_root._singularity_regression)
	_root._singularity_regression.setup(_root._tech_manager, _root._notification_panel)
	_root._tech_manager.victory_tech_completed.connect(_root._on_victory_tech_completed)
	if _root._building_placer != null:
		_root._building_placer._tech_manager = _root._tech_manager


func setup_corruption() -> void:
	_root._corruption_manager = Node.new()
	_root._corruption_manager.name = "CorruptionManager"
	_root._corruption_manager.set_script(load("res://scripts/prototype/corruption_manager.gd"))
	_root.add_child(_root._corruption_manager)
	_root._corruption_manager.setup(_root._population_manager, _root._tech_manager)


func setup_pandemic() -> void:
	_root._pandemic_manager = Node.new()
	_root._pandemic_manager.name = "PandemicManager"
	_root._pandemic_manager.set_script(PandemicManagerScript)
	_root.add_child(_root._pandemic_manager)
	_root._pandemic_manager.setup(_root._population_manager, _root._tech_manager, _root)
	_root._pandemic_manager.pandemic_started.connect(_root._on_pandemic_started)
	_root._pandemic_manager.pandemic_ended.connect(_root._on_pandemic_ended)


func setup_historical_events() -> void:
	_root._historical_event_manager = Node.new()
	_root._historical_event_manager.name = "HistoricalEventManager"
	_root._historical_event_manager.set_script(HistoricalEventManagerScript)
	_root.add_child(_root._historical_event_manager)
	(
		_root
		. _historical_event_manager
		. setup(
			_root._population_manager,
			_root._tech_manager,
			_root._trade_manager,
			_root._building_placer,
			_root,
		)
	)
	_root._historical_event_manager.event_started.connect(_root._on_hist_event_started)
	_root._historical_event_manager.event_ended.connect(_root._on_hist_event_ended)


func setup_victory() -> void:
	_root._victory_manager = Node.new()
	_root._victory_manager.name = "VictoryManager"
	_root._victory_manager.set_script(VictoryManagerScript)
	_root.add_child(_root._victory_manager)
	_root._victory_manager.setup(_root._building_placer)
	for bld in _root._entity_registry.get_by_category("building"):
		if "building_name" in bld and bld.building_name == "town_center" and not bld.under_construction:
			_root._victory_manager.register_town_center(bld.owner_id, bld)
	_root._victory_manager.player_defeated.connect(_root._on_player_defeated)
	_root._victory_manager.player_victorious.connect(_root._on_player_victorious)
	_root._victory_manager.agi_core_built.connect(_root._on_agi_core_built)
	_root._victory_manager.wonder_countdown_started.connect(_root._on_wonder_countdown_started)
	_root._victory_manager.wonder_countdown_cancelled.connect(_root._on_wonder_countdown_cancelled)
	GameManager.age_advanced.connect(_root._victory_manager.on_age_advanced)
	var player_start_cfg: Dictionary = _load_start_config(GameManager.player_difficulty)
	if not player_start_cfg.get("pre_built_tc", true):
		_root._victory_manager.register_nomadic_player(0)
	var ai_start_cfg: Dictionary = _load_start_config(GameManager.ai_difficulty)
	if not ai_start_cfg.get("pre_built_tc", true):
		_root._victory_manager.register_nomadic_player(1)


func setup_river_transport() -> void:
	_root._river_transport = Node.new()
	_root._river_transport.name = "RiverTransport"
	_root._river_transport.set_script(RiverTransportScript)
	_root.add_child(_root._river_transport)
	_root._river_transport.setup(_root._map_node, _root._building_placer, _root._target_detector)
	_root._river_transport.barge_destroyed_with_resources.connect(_root._on_barge_destroyed_with_resources)


func setup_trade() -> void:
	_root._trade_manager = Node.new()
	_root._trade_manager.name = "TradeManager"
	_root._trade_manager.set_script(TradeManagerScript)
	_root.add_child(_root._trade_manager)
	_root._trade_manager.setup(_root._building_placer)


func setup_ai() -> void:
	var difficulty: String = GameManager.ai_difficulty
	var tier_config: Dictionary = _load_ai_tier_config(difficulty)
	var multiplier: float = tier_config.get("gather_rate_multiplier", 1.0)
	if not is_equal_approx(multiplier, 1.0):
		ResourceManager.set_gather_multiplier(1, multiplier)
	var ai_start_cfg: Dictionary = _load_start_config(difficulty)
	var villager_count: int = tier_config.get("starting_villagers", 3)
	if ai_start_cfg.get("pre_built_tc", true):
		var ai_tc := _create_ai_town_center()
		_create_ai_starting_villagers(ai_tc, villager_count)
	else:
		var ai_spawn := get_start_position(1)
		_create_ai_starting_villagers(null, villager_count, ai_spawn)
	var personality_id: String = str(tier_config.get("gameplay_personality", "random"))
	if personality_id == "random":
		personality_id = AIPersonality.get_random_id()
	var ai_pers: AIPersonality = AIPersonality.get_personality(personality_id)
	_root._ai_economy = Node.new()
	_root._ai_economy.name = "AIEconomy"
	_root._ai_economy.set_script(AIEconomyScript)
	_root._ai_economy.difficulty = difficulty
	_root._ai_economy.personality = ai_pers
	_root.add_child(_root._ai_economy)
	(
		_root
		. _ai_economy
		. setup(
			_root,
			_root._population_manager,
			_root._pathfinder,
			_root._map_node,
			_root._target_detector,
			_root._tech_manager,
			_root._entity_registry,
		)
	)
	_root._ai_economy._build_planner.spawn_position = get_start_position(1)
	_root._ai_military = Node.new()
	_root._ai_military.name = "AIMilitary"
	_root._ai_military.set_script(AIMilitaryScript)
	_root._ai_military.difficulty = difficulty
	_root._ai_military.personality = ai_pers
	_root.add_child(_root._ai_military)
	(
		_root
		. _ai_military
		. setup(
			_root,
			_root._population_manager,
			_root._target_detector,
			_root._ai_economy,
			_root._tech_manager,
			_root._entity_registry,
		)
	)
	_root._ai_tech = Node.new()
	_root._ai_tech.name = "AITech"
	_root._ai_tech.set_script(AITechScript)
	_root._ai_tech.difficulty = difficulty
	_root._ai_tech.gameplay_personality = ai_pers
	_root.add_child(_root._ai_tech)
	_root._ai_tech.setup(_root._tech_manager)
	_root._tech_manager.tech_regressed.connect(_root._ai_military.on_tech_regressed)
	_root._tech_manager.tech_regressed.connect(_root._ai_tech.on_tech_regressed)
	_root._ai_singularity = Node.new()
	_root._ai_singularity.name = "AISingularity"
	_root._ai_singularity.set_script(AISingularityScript)
	_root._ai_singularity.difficulty = difficulty
	_root._ai_singularity.personality = ai_pers
	_root.add_child(_root._ai_singularity)
	_root._ai_singularity.setup(_root._tech_manager, _root._ai_military, _root._ai_tech)


func setup_pirates() -> void:
	_root._pirate_manager = Node.new()
	_root._pirate_manager.name = "PirateManager"
	_root._pirate_manager.set_script(PirateManagerScript)
	_root.add_child(_root._pirate_manager)
	_root._pirate_manager.setup(_root, _root._map_node, _root._target_detector, _root._tech_manager)


func setup_game_stats_tracker() -> void:
	_root._game_stats_tracker = Node.new()
	_root._game_stats_tracker.name = "GameStatsTracker"
	_root._game_stats_tracker.set_script(GameStatsTrackerScript)
	_root.add_child(_root._game_stats_tracker)
	var config: Dictionary = DataLoader.load_json("res://data/settings/ui/postgame_stats.json")
	_root._game_stats_tracker.setup(config, _root._tech_manager)
	_root._game_stats_tracker.init_player(0)
	_root._game_stats_tracker.init_player(1)


func setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/prototype/prototype_hud.gd"))
	_root.add_child(hud)
	if hud.has_method("setup"):
		hud.setup(_root._camera, _root._input_handler)
	var info_panel_layer := CanvasLayer.new()
	info_panel_layer.name = "InfoPanel"
	info_panel_layer.layer = 10
	_root.add_child(info_panel_layer)
	_root._info_panel = PanelContainer.new()
	_root._info_panel.name = "InfoPanelWidget"
	_root._info_panel.set_script(load("res://scripts/ui/info_panel.gd"))
	info_panel_layer.add_child(_root._info_panel)
	_root._info_panel.setup(_root._input_handler, _root._target_detector, _root._river_transport, _root._trade_manager)
	var cmd_panel_layer := CanvasLayer.new()
	cmd_panel_layer.name = "CommandPanel"
	cmd_panel_layer.layer = 10
	_root.add_child(cmd_panel_layer)
	var cmd_panel := PanelContainer.new()
	cmd_panel.name = "CommandPanelWidget"
	cmd_panel.set_script(load("res://scripts/ui/command_panel.gd"))
	cmd_panel_layer.add_child(cmd_panel)
	cmd_panel.setup(_root._input_handler, _root._building_placer, _root._trade_manager)
	_root._cursor_overlay = CanvasLayer.new()
	_root._cursor_overlay.name = "CursorOverlay"
	_root._cursor_overlay.set_script(load("res://scripts/prototype/cursor_overlay.gd"))
	_root.add_child(_root._cursor_overlay)
	_root._input_handler._cursor_overlay = _root._cursor_overlay
	_setup_resource_bar()
	var notif_layer := CanvasLayer.new()
	notif_layer.name = "NotificationLayer"
	notif_layer.layer = 11
	_root.add_child(notif_layer)
	_root._notification_panel = Control.new()
	_root._notification_panel.name = "NotificationPanel"
	_root._notification_panel.set_script(NotificationPanelScript)
	notif_layer.add_child(_root._notification_panel)
	_root._knowledge_burning_vfx = Node.new()
	_root._knowledge_burning_vfx.name = "KnowledgeBurningVFX"
	_root._knowledge_burning_vfx.set_script(KnowledgeBurningVFXScript)
	_root.add_child(_root._knowledge_burning_vfx)
	_root._knowledge_burning_vfx.setup(_root, _root._camera, _root._notification_panel)
	_root._pandemic_vfx = Node.new()
	_root._pandemic_vfx.name = "PandemicVFX"
	_root._pandemic_vfx.set_script(PandemicVFXScript)
	_root.add_child(_root._pandemic_vfx)
	_root._pandemic_vfx.setup(_root, _root._camera, _root._notification_panel)
	_root._historical_event_vfx = Node.new()
	_root._historical_event_vfx.name = "HistoricalEventVFX"
	_root._historical_event_vfx.set_script(HistoricalEventVFXScript)
	_root.add_child(_root._historical_event_vfx)
	_root._historical_event_vfx.setup(_root, _root._camera, _root._notification_panel)
	_root._singularity_cinematic = Node.new()
	_root._singularity_cinematic.name = "SingularityCinematicVFX"
	_root._singularity_cinematic.set_script(SingularityCinematicVFXScript)
	_root.add_child(_root._singularity_cinematic)
	_root._singularity_cinematic.setup(_root, _root._camera)
	_root._river_overlay = Node2D.new()
	_root._river_overlay.name = "RiverOverlay"
	_root._river_overlay.set_script(RiverOverlayScript)
	_root._river_overlay.z_index = 5
	_root.add_child(_root._river_overlay)
	_root._river_overlay.setup(_root._map_node, get_start_position(0))
	_root._input_handler._river_overlay = _root._river_overlay
	var victory_layer := CanvasLayer.new()
	victory_layer.name = "VictoryLayer"
	victory_layer.layer = 20
	_root.add_child(victory_layer)
	_root._victory_screen = PanelContainer.new()
	_root._victory_screen.name = "VictoryScreen"
	_root._victory_screen.set_script(VictoryScreenScript)
	_root._victory_screen.stats_pressed.connect(_root._on_victory_stats_pressed)
	victory_layer.add_child(_root._victory_screen)
	_root._postgame_stats_screen = PanelContainer.new()
	_root._postgame_stats_screen.name = "PostGameStatsScreen"
	_root._postgame_stats_screen.set_script(PostGameStatsScreenScript)
	victory_layer.add_child(_root._postgame_stats_screen)
	var tech_viewer_layer := CanvasLayer.new()
	tech_viewer_layer.name = "TechTreeViewerLayer"
	tech_viewer_layer.layer = 15
	_root.add_child(tech_viewer_layer)
	_root._tech_tree_viewer = PanelContainer.new()
	_root._tech_tree_viewer.name = "TechTreeViewer"
	_root._tech_tree_viewer.set_script(TechTreeViewerScript)
	tech_viewer_layer.add_child(_root._tech_tree_viewer)
	_root._tech_tree_viewer.setup(_root._tech_manager, 0)
	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseMenuLayer"
	pause_layer.layer = 22
	_root.add_child(pause_layer)
	_root._pause_menu = PanelContainer.new()
	_root._pause_menu.name = "PauseMenu"
	_root._pause_menu.set_script(PauseMenuScript)
	pause_layer.add_child(_root._pause_menu)
	_root._pause_menu.quit_to_menu.connect(_root._on_pause_menu_quit_to_menu)
	_root._pause_menu.quit_to_desktop.connect(_root._on_pause_menu_quit_to_desktop)
	var minimap_layer := CanvasLayer.new()
	minimap_layer.name = "MinimapLayer"
	minimap_layer.layer = 10
	_root.add_child(minimap_layer)
	_root._minimap = Control.new()
	_root._minimap.name = "Minimap"
	_root._minimap.set_script(MinimapScript)
	_root._minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_root._minimap.position = Vector2(8, -208)
	minimap_layer.add_child(_root._minimap)
	_root._minimap.setup(_root._map_node, _root._camera, _root._visibility_manager, _root)
	_root._minimap.minimap_move_command.connect(_root._on_minimap_move_command)


func _setup_resource_bar() -> void:
	var resource_bar_layer := CanvasLayer.new()
	resource_bar_layer.name = "ResourceBar"
	resource_bar_layer.layer = 10
	_root.add_child(resource_bar_layer)
	_root._resource_bar = PanelContainer.new()
	_root._resource_bar.name = "ResourceBarPanel"
	_root._resource_bar.set_script(load("res://scripts/ui/resource_bar.gd"))
	resource_bar_layer.add_child(_root._resource_bar)
	if _root._population_manager != null:
		_root._population_manager.population_changed.connect(_root._on_population_changed)
		(
			_root
			. _resource_bar
			. update_population(
				_root._population_manager.get_population(0),
				_root._population_manager.get_population_cap(0),
			)
		)
	if _root._corruption_manager != null:
		_root._corruption_manager.corruption_changed.connect(_root._on_corruption_changed)
	if _root._river_transport != null:
		_root._resource_bar.setup_transit(_root._river_transport)


func try_attach_production_queue(building: Node2D) -> void:
	if not "building_name" in building:
		return
	var building_name: String = building.building_name
	if building_name == "":
		return
	var stats: Dictionary = DataLoader.get_building_stats(building_name)
	var units_produced: Array = stats.get("units_produced", [])
	if units_produced.is_empty():
		return
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	var owner_id: int = building.owner_id if "owner_id" in building else 0
	pq.setup(building, owner_id, _root._population_manager)
	pq.unit_produced.connect(_root._on_unit_produced)


func get_start_position(player_index: int) -> Vector2i:
	var positions: Array = _root._map_node.get_starting_positions()
	if positions.size() > player_index:
		return positions[player_index] as Vector2i
	if player_index == 0:
		return Vector2i(4, 4)
	return Vector2i(_root._map_node.get_map_size() - 7, _root._map_node.get_map_size() - 7)


func get_villager_offsets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cfg: Dictionary = DataLoader.load_json("res://data/settings/map/map_generation.json")
	var start_cfg: Dictionary = cfg.get("starting_locations", {})
	var raw_offsets: Array = start_cfg.get("villager_offsets", [[-1, 0], [0, -1], [-1, -1], [1, -1], [-1, 1]])
	for offset in raw_offsets:
		if offset is Array and offset.size() == 2:
			result.append(Vector2i(int(offset[0]), int(offset[1])))
	return result


func find_naval_spawn_point(building: Node2D) -> Vector2i:
	if _root._map_node == null or not _root._map_node.has_method("get_terrain_at"):
		return Vector2i(-1, -1)
	var footprint: Vector2i = building.footprint if "footprint" in building else Vector2i(1, 1)
	var origin: Vector2i = building.grid_pos if "grid_pos" in building else Vector2i.ZERO
	var cells := BuildingValidator.get_footprint_cells(origin, footprint)
	var directions: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
	]
	for cell in cells:
		for dir in directions:
			var neighbor := cell + dir
			if neighbor in cells:
				continue
			if _root._map_node.get_terrain_at(neighbor) in ["water", "shallows", "deep_water"]:
				return neighbor
	return Vector2i(-1, -1)


func _load_ai_tier_config(difficulty: String) -> Dictionary:
	var data: Dictionary = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	if data == null:
		return {}
	var tiers: Dictionary = data.get("tiers", {})
	if difficulty in tiers:
		return tiers[difficulty]
	var default_tier: String = data.get("default", "normal")
	return tiers.get(default_tier, {})


func _create_town_center(player_id: int, grid_pos: Vector2i, category: String) -> Node2D:
	var stats: Dictionary = DataLoader.get_building_stats("town_center")
	var max_hp: int = int(stats.get("hp", 2400))
	var footprint := Vector2i(int(stats.get("footprint", [3, 3])[0]), int(stats.get("footprint", [3, 3])[1]))
	var building := Node2D.new()
	building.name = "Building_TC_%d" % player_id
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = player_id
	building.building_name = "town_center"
	building.footprint = footprint
	building.grid_pos = grid_pos
	building.hp = max_hp
	building.max_hp = max_hp
	building.under_construction = false
	building.build_progress = 1.0
	if category != "":
		building.entity_category = category
	_root.add_child(building)
	_root._target_detector.register_entity(building)
	if _root._population_manager != null:
		_root._population_manager.register_building(building, building.owner_id)
	_root._entity_registry.register(building)
	building.building_destroyed.connect(_root._on_building_destroyed)
	try_attach_production_queue(building)
	var cells := BuildingValidator.get_footprint_cells(grid_pos, footprint)
	for cell in cells:
		_root._pathfinder.set_cell_solid(cell, true)
	return building


func _create_house(player_id: int, grid_pos: Vector2i, category: String) -> Node2D:
	var stats: Dictionary = DataLoader.get_building_stats("house")
	var max_hp: int = int(stats.get("hp", 550))
	var footprint := Vector2i(int(stats.get("footprint", [2, 2])[0]), int(stats.get("footprint", [2, 2])[1]))
	var building := Node2D.new()
	building.name = "Building_House_%d_%d" % [player_id, grid_pos.x]
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = player_id
	building.building_name = "house"
	building.footprint = footprint
	building.grid_pos = grid_pos
	building.hp = max_hp
	building.max_hp = max_hp
	building.under_construction = false
	building.build_progress = 1.0
	if category != "":
		building.entity_category = category
	_root.add_child(building)
	_root._target_detector.register_entity(building)
	if _root._population_manager != null:
		_root._population_manager.register_building(building, building.owner_id)
	_root._entity_registry.register(building)
	building.building_destroyed.connect(_root._on_building_destroyed)
	var cells := BuildingValidator.get_footprint_cells(grid_pos, footprint)
	for cell in cells:
		_root._pathfinder.set_cell_solid(cell, true)
	return building


func _load_start_config(difficulty: String) -> Dictionary:
	var data: Dictionary = DataLoader.load_json("res://data/settings/game/start_config.json")
	if data == null or data.is_empty():
		return {"pre_built_tc": true, "starting_houses": 0}
	if difficulty in data:
		return data[difficulty]
	return data.get("normal", {"pre_built_tc": true, "starting_houses": 0})


func _create_ai_town_center() -> Node2D:
	var tc_pos := get_start_position(1)
	return _create_town_center(1, tc_pos, "enemy_building")


func _create_ai_starting_villagers(tc: Node2D, count: int, spawn_origin: Vector2i = Vector2i(-1, -1)) -> void:
	var offsets := get_villager_offsets()
	var base_pos: Vector2i = spawn_origin if tc == null else tc.grid_pos
	for i in count:
		var unit := Node2D.new()
		unit.name = "AIVillager_%d" % i
		unit.set_script(UnitScript)
		unit.unit_type = "villager"
		unit.owner_id = 1
		unit.unit_color = Color(0.9, 0.2, 0.2)
		var offset := offsets[i % offsets.size()]
		var spawn_pos: Vector2i = base_pos + offset
		unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
		_root.add_child(unit)
		unit._scene_root = _root
		unit._pathfinder = _root._pathfinder
		if _root._war_survival != null:
			unit._war_survival = _root._war_survival
		if _root._target_detector != null:
			_root._target_detector.register_entity(unit)
		if _root._population_manager != null:
			_root._population_manager.register_unit(unit, 1)
		_root._entity_registry.register(unit)
		unit.unit_died.connect(_root._on_unit_died)
