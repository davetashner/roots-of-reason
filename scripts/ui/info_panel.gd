extends PanelContainer
## Bottom-center info panel showing selected unit/building details.
## Polls InputHandler selection each frame; updates HP in real-time.
## When nothing is selected, shows resource node info on hover.

const PANEL_WIDTH: float = 400.0
const VILLAGER_PANEL_WIDTH: float = 640.0
const PANEL_HEIGHT: float = 120.0
const PANEL_HEIGHT_WITH_QUEUE: float = 180.0
const PORTRAIT_SIZE: float = 64.0
const QUEUE_ICON_SIZE: float = 32.0
const BUILD_CATEGORIES := ["civilian", "military", "economy"]
const BUILD_GRID_COLUMNS: int = 3
const BUILD_BUTTON_SIZE: int = 48
const BUILD_BUTTON_MARGIN: int = 4
const MAX_BUILD_SLOTS: int = 12
const CMD_BUTTONS: Array = [
	["[Q] Stop", "stop"],
	["[W] Hold", "hold_position"],
	["[E] Explore", "start_explore"],
]

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

var _input_handler: Node = null
var _target_detector: Node = null
var _river_transport: Node = null
var _building_placer: Node = null
var _tracked_entity: Node = null
var _tracked_entities: Array = []
var _is_multi: bool = false
var _hovered_entity: Node = null
var _is_hovering_resource: bool = false
var _is_hovering_wolf: bool = false
var _trade_manager: Node = null

# Config loaded from data/settings/ui/info_panel.json
var _hp_green_threshold: float = 0.6
var _hp_yellow_threshold: float = 0.3

# Child nodes
var _root_hbox: HBoxContainer = null
var _portrait: ColorRect = null
var _portrait_texture: TextureRect = null
var _name_label: Label = null
var _hp_bar_fill: Panel = null
var _hp_bar_bg: Panel = null
var _hp_label: Label = null
var _stats_label: Label = null
var _hp_bar_container: HBoxContainer = null

# Production queue display nodes
var _queue_section: VBoxContainer = null
var _queue_current_label: Label = null
var _queue_progress_bar: ProgressBar = null
var _queue_icons_container: HBoxContainer = null
var _queue_eta_label: Label = null
var _tracked_queue: Node = null
var _main_vbox: VBoxContainer = null

# Unit command buttons (Stop/Hold)
var _cmd_row: HBoxContainer = null

# Build section (villager mode)
var _build_separator: VSeparator = null
var _build_section: VBoxContainer = null
var _build_tab_bar: HBoxContainer = null
var _build_grid: GridContainer = null
var _build_tab: String = "civilian"
var _is_villager_mode: bool = false
var _player_id: int = 0

# Train buttons section (buildings with units_produced)
var _train_section: HBoxContainer = null

# Age advancement section (Town Center)
var _age_section: VBoxContainer = null
var _age_advancement: Node = null


func _ready() -> void:
	_load_config()
	_build_ui()
	visible = false


func _load_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("info_panel")
	if cfg.is_empty():
		return
	_hp_green_threshold = float(cfg.get("hp_green_threshold", _hp_green_threshold))
	_hp_yellow_threshold = float(cfg.get("hp_yellow_threshold", _hp_yellow_threshold))


func _build_ui() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	# Anchor bottom-center
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -PANEL_WIDTH / 2.0
	offset_right = PANEL_WIDTH / 2.0
	offset_top = -PANEL_HEIGHT
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_root_hbox = HBoxContainer.new()
	_root_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_hbox.add_theme_constant_override("separation", 12)
	add_child(_root_hbox)
	var hbox := _root_hbox

	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_portrait)
	_portrait_texture = TextureRect.new()
	_portrait_texture.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_texture.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_texture.visible = false
	_portrait.add_child(_portrait_texture)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_name_label)

	_hp_bar_container = HBoxContainer.new()
	_hp_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_container.custom_minimum_size = Vector2(0, 16)
	_hp_bar_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_hp_bar_container)

	_hp_bar_bg = Panel.new()
	_hp_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_bg.custom_minimum_size = Vector2(180, 14)
	_hp_bar_bg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	_hp_bar_bg.add_theme_stylebox_override("panel", bg_style)
	_hp_bar_container.add_child(_hp_bar_bg)

	_hp_bar_fill = Panel.new()
	_hp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_fill.position = Vector2.ZERO
	_hp_bar_fill.size = Vector2(180, 14)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.8, 0.2, 0.9)
	_hp_bar_fill.add_theme_stylebox_override("panel", fill_style)
	_hp_bar_bg.add_child(_hp_bar_fill)

	# HP label
	_hp_label = Label.new()
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.add_theme_font_size_override("font_size", 12)
	_hp_bar_container.add_child(_hp_label)

	# Stats line
	_stats_label = Label.new()
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_stats_label)

	# Unit command buttons (Stop/Hold)
	_cmd_row = HBoxContainer.new()
	_cmd_row.name = "CmdRow"
	_cmd_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmd_row.add_theme_constant_override("separation", 4)
	_cmd_row.visible = false
	vbox.add_child(_cmd_row)
	_build_cmd_buttons()

	_main_vbox = vbox
	_train_section = HBoxContainer.new()
	_train_section.set_script(load("res://scripts/ui/train_buttons_section.gd"))
	vbox.add_child(_train_section)
	_build_queue_section(vbox)
	_build_age_section(vbox)
	_build_build_section()


func _build_queue_section(parent: VBoxContainer) -> void:
	_queue_section = VBoxContainer.new()
	_queue_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_section.add_theme_constant_override("separation", 2)
	_queue_section.visible = false
	parent.add_child(_queue_section)

	# Separator
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_section.add_child(sep)

	# Current training label + progress bar row
	var current_row := HBoxContainer.new()
	current_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	current_row.add_theme_constant_override("separation", 6)
	_queue_section.add_child(current_row)

	_queue_current_label = Label.new()
	_queue_current_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_current_label.add_theme_font_size_override("font_size", 12)
	_queue_current_label.custom_minimum_size = Vector2(80, 0)
	current_row.add_child(_queue_current_label)

	_queue_progress_bar = ProgressBar.new()
	_queue_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_progress_bar.custom_minimum_size = Vector2(120, 14)
	_queue_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_progress_bar.min_value = 0.0
	_queue_progress_bar.max_value = 100.0
	_queue_progress_bar.show_percentage = true
	current_row.add_child(_queue_progress_bar)

	# Queued icons row
	_queue_icons_container = HBoxContainer.new()
	_queue_icons_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_queue_icons_container.add_theme_constant_override("separation", 4)
	_queue_section.add_child(_queue_icons_container)

	# ETA label
	_queue_eta_label = Label.new()
	_queue_eta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_eta_label.add_theme_font_size_override("font_size", 11)
	_queue_section.add_child(_queue_eta_label)


func _build_age_section(parent: VBoxContainer) -> void:
	_age_section = VBoxContainer.new()
	_age_section.set_script(load("res://scripts/ui/age_advancement_section.gd"))
	parent.add_child(_age_section)


func setup(
	input_handler: Node,
	target_detector: Node = null,
	river_transport: Node = null,
	trade_manager: Node = null,
	building_placer: Node = null,
	age_advancement: Node = null,
) -> void:
	_input_handler = input_handler
	_target_detector = target_detector
	_river_transport = river_transport
	_trade_manager = trade_manager
	_building_placer = building_placer
	_age_advancement = age_advancement
	if _age_section != null and _age_advancement != null:
		_age_section.setup(_age_advancement)


func _all_villagers(units: Array) -> bool:
	if units.is_empty():
		return false
	for unit in units:
		if not is_instance_valid(unit):
			continue
		if not ("unit_type" in unit and unit.unit_type == "villager"):
			return false
	return true


func show_unit(unit: Node2D) -> void:
	_tracked_entity = unit
	_tracked_entities.clear()
	_is_multi = false
	_clear_hover()
	_load_unit_thumbnail(unit)
	_hide_queue_section()
	_hide_train_section()
	_show_cmd_row()
	visible = true
	# Villager build panel
	var is_villager: bool = "unit_type" in unit and unit.unit_type == "villager"
	if is_villager and _building_placer != null:
		_toggle_build_section(true)
	else:
		_toggle_build_section(false)
	# Portrait color
	if "unit_color" in unit:
		_portrait.color = unit.unit_color
	else:
		_portrait.color = Color(0.2, 0.4, 0.9)
	# Name
	var display_name: String = _get_unit_display_name(unit)
	_name_label.text = display_name
	# Stats from DataLoader
	var stats := _get_unit_stats(unit)
	var atk: int = int(stats.get("attack", 0))
	var def: int = int(stats.get("defense", 0))
	var spd: float = float(stats.get("speed", 0.0))
	var stats_text: String = "ATK: %d  DEF: %d  SPD: %.1f" % [atk, def, spd]
	if unit.has_meta("bounty_gold"):
		stats_text += "  Bounty: %d Gold" % int(unit.get_meta("bounty_gold"))
	if unit.has_method("get_embarked_count") and unit.has_method("get_transport_capacity"):
		var cargo_count: int = unit.get_embarked_count()
		var cargo_cap: int = unit.get_transport_capacity()
		if cargo_cap > 0:
			stats_text += "  Cargo: %d/%d" % [cargo_count, cargo_cap]
	var carry_text := _get_carry_text(unit)
	if carry_text != "":
		stats_text += "\n" + carry_text
	_stats_label.text = stats_text
	_update_unit_hp(unit, stats)


func show_building(building: Node2D) -> void:
	_tracked_entity = building
	_tracked_entities.clear()
	_is_multi = false
	_clear_hover()
	_toggle_build_section(false)
	_hide_cmd_row()
	visible = true
	# Check ruins state
	var is_ruins: bool = "_is_ruins" in building and building._is_ruins
	# Portrait color
	if is_ruins:
		_portrait.color = Color(0.4, 0.4, 0.4)
	elif building.owner_id == 0:
		_portrait.color = Color(0.2, 0.5, 1.0)
	else:
		_portrait.color = Color(0.8, 0.2, 0.2)
	# Building sprite thumbnail
	_load_building_thumbnail(building)
	# Name
	if is_ruins:
		_name_label.text = "Ruins"
	else:
		var display_name: String = _get_building_display_name(building)
		_name_label.text = display_name
	# Stats
	if is_ruins:
		_stats_label.text = ""
	elif building.under_construction:
		var pct := int(building.build_progress * 100.0)
		_stats_label.text = "Progress: %d%%" % pct
	else:
		var stats_text := ""
		# Building defense stat
		var bstats := _get_building_stats(building)
		var defense: int = int(bstats.get("defense", 0))
		stats_text = "DEF: %d" % defense
		# Garrison attack bonus
		if building.has_method("get_garrison_attack"):
			var garrison_atk: int = building.get_garrison_attack()
			if garrison_atk > 0:
				stats_text += "  ATK: %d" % garrison_atk
		# Garrison capacity indicator
		if "garrison_capacity" in building and building.garrison_capacity > 0:
			var garrisoned: int = building.get_garrisoned_count() if building.has_method("get_garrisoned_count") else 0
			stats_text += "  Garrisoned: %d/%d" % [garrisoned, building.garrison_capacity]
		# Damage state
		var state_text := ""
		if building.has_method("get_damage_state"):
			var state: String = building.get_damage_state()
			state_text = state.capitalize()
		# Dock transport info
		if _river_transport != null and building.building_name == "river_dock":
			var dock_info: Dictionary = _river_transport.get_dock_info(building)
			if not dock_info.is_empty():
				var queued: int = dock_info.get("queued_total", 0)
				var barges: int = dock_info.get("active_barge_count", 0)
				var countdown: float = dock_info.get("time_until_next_dispatch", 0.0)
				state_text = "Queued: %d  Barges: %d  Next: %.0fs" % [queued, barges, countdown]
		# Market trade info
		if _trade_manager != null and building.building_name == "market":
			var market_info: Dictionary = _trade_manager.get_market_info(building)
			if not market_info.is_empty():
				var rates: Dictionary = market_info.get("rates", {})
				var carts: int = market_info.get("active_cart_count", 0)
				var rate_parts: Array[String] = []
				for res_name: String in rates:
					rate_parts.append("%s: %d" % [res_name.capitalize(), int(rates[res_name])])
				state_text = ", ".join(rate_parts) + "  Carts: %d" % carts
		if state_text != "":
			stats_text += "\n" + state_text
		_stats_label.text = stats_text
	_update_building_hp(building)
	_update_train_section(building)
	_update_queue_display(building)
	_update_age_section(building)


func show_barge(barge: Node2D) -> void:
	_tracked_entity = barge
	_tracked_entities.clear()
	_is_multi = false
	_clear_hover()
	_clear_thumbnail()
	_hide_queue_section()
	_hide_train_section()
	_toggle_build_section(false)
	_show_cmd_row()
	visible = true
	# Portrait color
	if barge.owner_id == 0:
		_portrait.color = Color(0.6, 0.4, 0.2)
	else:
		_portrait.color = Color(0.8, 0.3, 0.3)
	_name_label.text = "Barge"
	# Cargo display
	var cargo_parts: Array[String] = []
	for res_type: int in barge.carried_resources:
		var amount: int = barge.carried_resources[res_type]
		if amount > 0:
			cargo_parts.append("%s: %d" % [_resource_type_name(res_type), amount])
	if cargo_parts.is_empty():
		_stats_label.text = "Empty"
	else:
		_stats_label.text = ", ".join(cargo_parts)
	# HP
	var current_hp: int = barge.hp
	var max_hp_val: int = barge.max_hp
	var ratio: float = float(current_hp) / float(max_hp_val) if max_hp_val > 0 else 0.0
	_set_hp_bar(ratio, current_hp, max_hp_val)


func show_multi_select(units: Array) -> void:
	_tracked_entity = null
	_tracked_entities = units.duplicate()
	_is_multi = true
	_clear_hover()
	_clear_thumbnail()
	_hide_queue_section()
	_hide_train_section()
	_show_cmd_row()
	# Show build menu when all selected units are villagers
	if _all_villagers(units) and _building_placer != null:
		_toggle_build_section(true)
	else:
		_toggle_build_section(false)
	visible = true
	# Portrait: use first unit's color
	if not units.is_empty() and "unit_color" in units[0]:
		_portrait.color = units[0].unit_color
	else:
		_portrait.color = Color(0.2, 0.4, 0.9)
	# Name: count + type
	var type_name := _get_unit_display_name(units[0]) if not units.is_empty() else "Units"
	_name_label.text = "%d %ss selected" % [units.size(), type_name]
	# Aggregate HP
	_stats_label.text = ""
	_update_multi_hp(units)


func show_resource_node(node: Node2D) -> void:
	_hovered_entity = node
	_is_hovering_resource = true
	_clear_thumbnail()
	_hide_train_section()
	_hide_cmd_row()
	visible = true
	# Portrait color from node
	if "_node_color" in node:
		_portrait.color = node._node_color
	else:
		_portrait.color = Color(0.5, 0.5, 0.5)
	# Name — capitalize and clean underscores
	var display_name: String = str(node.resource_name).replace("_", " ").capitalize()
	_name_label.text = display_name
	# Regen status text
	var type_label: String = str(node.resource_type).capitalize()
	_stats_label.text = type_label + _get_regen_text(node)
	# Yield bar
	var cur: int = int(node.current_yield)
	var tot: int = int(node.total_yield)
	_set_yield_bar(float(cur) / float(tot) if tot > 0 else 0.0, cur, tot)


func clear() -> void:
	_tracked_entity = null
	_tracked_entities.clear()
	_is_multi = false
	_clear_hover()
	_hide_queue_section()
	_hide_train_section()
	_toggle_build_section(false)
	_hide_cmd_row()
	visible = false


func _clear_hover() -> void:
	_hovered_entity = null
	_is_hovering_resource = false
	_is_hovering_wolf = false


func _load_unit_thumbnail(unit: Node2D) -> void:
	var utype: String = unit.unit_type if "unit_type" in unit else ""
	_load_thumbnail("res://assets/sprites/units/placeholder/" + utype + ".png" if utype != "" else "")


func _load_building_thumbnail(building: Node2D) -> void:
	var bname: String = building.building_name if "building_name" in building else ""
	_load_thumbnail("res://assets/sprites/buildings/placeholder/" + bname + ".png" if bname != "" else "")


func _load_thumbnail(path: String) -> void:
	if _portrait_texture == null:
		return
	if path != "" and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null:
			_portrait_texture.texture = tex
			_portrait_texture.visible = true
			return
	_clear_thumbnail()


func _clear_thumbnail() -> void:
	if _portrait_texture != null:
		_portrait_texture.texture = null
		_portrait_texture.visible = false


func _get_hp_color(ratio: float) -> Color:
	if ratio > _hp_green_threshold:
		return Color(0.2, 0.8, 0.2, 0.9)
	if ratio > _hp_yellow_threshold:
		return Color(0.9, 0.8, 0.1, 0.9)
	return Color(0.9, 0.2, 0.2, 0.9)


func _get_yield_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.2, 0.7, 0.3, 0.9)
	if ratio > 0.3:
		return Color(0.6, 0.5, 0.2, 0.9)
	return Color(0.5, 0.3, 0.1, 0.9)


func _process(_delta: float) -> void:
	if _input_handler == null:
		return
	# Poll selection from InputHandler
	var selected: Array[Node] = _input_handler._get_selected_units()
	if selected.is_empty():
		_check_resource_hover()
		return
	# Clear hover when selection exists
	_clear_hover()
	# Determine what to show
	if selected.size() == 1:
		var entity: Node = selected[0]
		if _is_resource_node(entity):
			show_resource_node(entity as Node2D)
			return
		if _is_multi or _tracked_entity != entity:
			if _is_barge(entity):
				show_barge(entity as Node2D)
			elif _is_building(entity):
				show_building(entity as Node2D)
			else:
				show_unit(entity as Node2D)
		else:
			_update()
	else:
		# Multi-select — only units (not buildings) in multi
		if not _is_multi or _tracked_entities.size() != selected.size():
			show_multi_select(selected)
		else:
			_update()


func _check_resource_hover() -> void:
	if _target_detector == null:
		if visible and not _is_hovering_resource and not _is_hovering_wolf:
			clear()
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var mouse_pos := viewport.get_mouse_position()
	# Convert screen position to world position using camera transform
	var canvas_transform := viewport.get_canvas_transform()
	var world_pos := canvas_transform.affine_inverse() * mouse_pos
	var found: Node = _target_detector.detect(world_pos)
	if found != null and "entity_category" in found and found.entity_category == "resource_node":
		if found != _hovered_entity:
			show_resource_node(found as Node2D)
		else:
			_update_resource_hover()
	elif found != null and "entity_category" in found and found.entity_category == "wild_fauna":
		if found != _hovered_entity:
			_show_wolf_info(found as Node2D)
		else:
			_update_wolf_info()
	else:
		if _is_hovering_resource or _is_hovering_wolf or visible:
			clear()


func _show_wolf_info(wolf: Node2D) -> void:
	_hovered_entity = wolf
	_is_hovering_wolf = true
	visible = true
	_portrait.color = Color(0.5, 0.5, 0.5)
	_name_label.text = "Wolf"
	# HP bar
	var current_hp: int = wolf.hp if "hp" in wolf else 0
	var max_hp_val: int = wolf.max_hp if "max_hp" in wolf else current_hp
	var ratio: float = float(current_hp) / float(max_hp_val) if max_hp_val > 0 else 0.0
	_set_hp_bar(ratio, current_hp, max_hp_val)
	# Domestication progress
	var wolf_ai: Node = wolf.get_node_or_null("WolfAI")
	if wolf_ai != null and wolf_ai.has_method("get_domestication_progress"):
		var progress: float = wolf_ai.get_domestication_progress()
		var pct := int(progress * 100.0)
		_stats_label.text = "Domestication: %d%%" % pct
	else:
		_stats_label.text = ""


func _update_wolf_info() -> void:
	if _hovered_entity == null or not is_instance_valid(_hovered_entity):
		clear()
		return
	var wolf: Node2D = _hovered_entity as Node2D
	var current_hp: int = wolf.hp if "hp" in wolf else 0
	var max_hp_val: int = wolf.max_hp if "max_hp" in wolf else current_hp
	var ratio: float = float(current_hp) / float(max_hp_val) if max_hp_val > 0 else 0.0
	_set_hp_bar(ratio, current_hp, max_hp_val)
	var wolf_ai: Node = wolf.get_node_or_null("WolfAI")
	if wolf_ai != null and wolf_ai.has_method("get_domestication_progress"):
		var progress: float = wolf_ai.get_domestication_progress()
		var pct := int(progress * 100.0)
		_stats_label.text = "Domestication: %d%%" % pct


func _update_resource_hover() -> void:
	if _hovered_entity == null or not is_instance_valid(_hovered_entity):
		clear()
		return
	var node: Node2D = _hovered_entity as Node2D
	var cur: int = int(node.current_yield)
	var tot: int = int(node.total_yield)
	_set_yield_bar(float(cur) / float(tot) if tot > 0 else 0.0, cur, tot)
	# Update regen status
	var type_label: String = str(node.resource_type).capitalize()
	_stats_label.text = type_label + _get_regen_text(node)


func _get_regen_text(node: Node2D) -> String:
	if "regenerates" not in node or not node.regenerates:
		return ""
	if "_is_regrowing" in node and node._is_regrowing:
		var pct := 0
		if "total_yield" in node and int(node.total_yield) > 0:
			pct = int(float(node.current_yield) / float(node.total_yield) * 100.0)
		return " — Regrowing %d%%" % pct
	return " — Regenerates"


func _update() -> void:
	_update_build_button_states()
	if _is_multi:
		_update_multi_hp(_tracked_entities)
		return
	if _tracked_entity == null or not is_instance_valid(_tracked_entity):
		clear()
		return
	if _is_building(_tracked_entity):
		_update_building_hp(_tracked_entity as Node2D)
		if _tracked_entity.under_construction:
			var pct := int(_tracked_entity.build_progress * 100.0)
			_stats_label.text = "Progress: %d%%" % pct
		else:
			var bstats := _get_building_stats(_tracked_entity as Node2D)
			var defense: int = int(bstats.get("defense", 0))
			var new_stats := "DEF: %d" % defense
			if _tracked_entity.has_method("get_garrison_attack"):
				var garrison_atk: int = _tracked_entity.get_garrison_attack()
				if garrison_atk > 0:
					new_stats += "  ATK: %d" % garrison_atk
			if "garrison_capacity" in _tracked_entity and _tracked_entity.garrison_capacity > 0:
				var garrisoned: int = (
					_tracked_entity.get_garrisoned_count() if _tracked_entity.has_method("get_garrisoned_count") else 0
				)
				new_stats += "  Garrisoned: %d/%d" % [garrisoned, _tracked_entity.garrison_capacity]
			var state_text := ""
			if _tracked_entity.has_method("get_damage_state"):
				var state: String = _tracked_entity.get_damage_state()
				state_text = state.capitalize()
			if _river_transport != null and _tracked_entity.building_name == "river_dock":
				var dock_info: Dictionary = _river_transport.get_dock_info(_tracked_entity)
				if not dock_info.is_empty():
					var queued: int = dock_info.get("queued_total", 0)
					var barges: int = dock_info.get("active_barge_count", 0)
					var countdown: float = dock_info.get("time_until_next_dispatch", 0.0)
					state_text = ("Queued: %d  Barges: %d  Next: %.0fs" % [queued, barges, countdown])
			if _trade_manager != null and _tracked_entity.building_name == "market":
				var market_info: Dictionary = _trade_manager.get_market_info(_tracked_entity)
				if not market_info.is_empty():
					var rates: Dictionary = market_info.get("rates", {})
					var carts: int = market_info.get("active_cart_count", 0)
					var rate_parts: Array[String] = []
					for res_name: String in rates:
						rate_parts.append("%s: %d" % [res_name.capitalize(), int(rates[res_name])])
					state_text = (", ".join(rate_parts) + "  Carts: %d" % carts)
			if state_text != "":
				new_stats += "\n" + state_text
			_stats_label.text = new_stats
		_update_train_section(_tracked_entity as Node2D)
		_update_queue_display(_tracked_entity as Node2D)
		_update_age_section(_tracked_entity as Node2D)
	else:
		var unit: Node2D = _tracked_entity as Node2D
		var stats := _get_unit_stats(unit)
		_update_unit_hp(unit, stats)
		_update_unit_carry(unit, stats)


func _update_unit_carry(unit: Node2D, stats: Dictionary) -> void:
	var atk: int = int(stats.get("attack", 0))
	var def: int = int(stats.get("defense", 0))
	var spd: float = float(stats.get("speed", 0.0))
	var stats_text: String = "ATK: %d  DEF: %d  SPD: %.1f" % [atk, def, spd]
	if unit.has_meta("bounty_gold"):
		stats_text += "  Bounty: %d Gold" % int(unit.get_meta("bounty_gold"))
	if unit.has_method("get_embarked_count") and unit.has_method("get_transport_capacity"):
		var cargo_count: int = unit.get_embarked_count()
		var cargo_cap: int = unit.get_transport_capacity()
		if cargo_cap > 0:
			stats_text += "  Cargo: %d/%d" % [cargo_count, cargo_cap]
	var carry_text := _get_carry_text(unit)
	if carry_text != "":
		stats_text += "\n" + carry_text
	_stats_label.text = stats_text


func _update_unit_hp(unit: Node2D, stats: Dictionary) -> void:
	var max_hp_val: int = int(stats.get("hp", 25))
	var current_hp: int = max_hp_val
	if "hp" in unit:
		current_hp = int(unit.hp)
		max_hp_val = int(unit.max_hp) if "max_hp" in unit else max_hp_val
	var ratio: float = float(current_hp) / float(max_hp_val) if max_hp_val > 0 else 0.0
	_set_hp_bar(ratio, current_hp, max_hp_val)


func _update_building_hp(building: Node2D) -> void:
	if building.under_construction:
		_set_build_progress_bar(building.build_progress)
		return
	var current_hp: int = building.hp
	var max_hp_val: int = building.max_hp
	var ratio: float = float(current_hp) / float(max_hp_val) if max_hp_val > 0 else 0.0
	_set_hp_bar(ratio, current_hp, max_hp_val)


func _update_multi_hp(units: Array) -> void:
	var total_hp: int = 0
	var total_max: int = 0
	for u in units:
		if not is_instance_valid(u):
			continue
		if "hp" in u and "max_hp" in u:
			total_hp += int(u.hp)
			total_max += int(u.max_hp)
		else:
			var stats := _get_unit_stats(u as Node2D)
			var hp_val: int = int(stats.get("hp", 25))
			total_hp += hp_val
			total_max += hp_val
	var ratio: float = float(total_hp) / float(total_max) if total_max > 0 else 0.0
	_set_hp_bar(ratio, total_hp, total_max)


func _set_hp_bar(ratio: float, current: int, maximum: int) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	var bar_width: float = _hp_bar_bg.custom_minimum_size.x
	_hp_bar_fill.size = Vector2(bar_width * ratio, _hp_bar_fill.size.y)
	var fill_style: StyleBoxFlat = _hp_bar_fill.get_theme_stylebox("panel") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = _get_hp_color(ratio)
	_hp_label.text = "HP: %d/%d" % [current, maximum]


func _set_yield_bar(ratio: float, current: int, maximum: int) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	var bar_width: float = _hp_bar_bg.custom_minimum_size.x
	_hp_bar_fill.size = Vector2(bar_width * ratio, _hp_bar_fill.size.y)
	var fill_style: StyleBoxFlat = _hp_bar_fill.get_theme_stylebox("panel") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = _get_yield_color(ratio)
	_hp_label.text = "Yield: %d/%d" % [current, maximum]


func _set_build_progress_bar(progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	var bar_width: float = _hp_bar_bg.custom_minimum_size.x
	_hp_bar_fill.size = Vector2(bar_width * progress, _hp_bar_fill.size.y)
	var fill_style: StyleBoxFlat = _hp_bar_fill.get_theme_stylebox("panel") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = Color(0.2, 0.8, 0.2, 0.9)
	var pct := int(progress * 100.0)
	_hp_label.text = "Building: %d%%" % pct


func _get_unit_stats(unit: Node2D) -> Dictionary:
	var unit_type: String = unit.unit_type if "unit_type" in unit else "villager"
	var result: Variant = _dl_call("get_unit_stats", [unit_type])
	return result if result is Dictionary else {}


func _get_unit_display_name(unit: Node2D) -> String:
	var unit_type: String = unit.unit_type if "unit_type" in unit else "unit"
	var stats := _get_unit_stats(unit)
	if stats.has("name"):
		return str(stats["name"])
	return unit_type.capitalize()


func _get_building_display_name(building: Node2D) -> String:
	var bname: String = building.building_name if "building_name" in building else ""
	var stats: Dictionary = _load_building_data(bname) if bname != "" else {}
	if stats.has("name"):
		return str(stats["name"])
	if bname != "":
		return bname.replace("_", " ").capitalize()
	return "Building"


func _get_building_stats(building: Node2D) -> Dictionary:
	var bname: String = building.building_name if "building_name" in building else ""
	return _load_building_data(bname) if bname != "" else {}


func _get_carry_text(unit: Node2D) -> String:
	if "_carried_amount" not in unit or "_carry_capacity" not in unit:
		return ""
	var amount: int = int(unit._carried_amount)
	var capacity: int = int(unit._carry_capacity)
	if capacity <= 0:
		return ""
	var res_type: String = ""
	if "_gather_type" in unit:
		res_type = str(unit._gather_type)
	if amount <= 0 and res_type == "":
		return ""
	var type_label: String = res_type.capitalize() if res_type != "" else ""
	if amount > 0 and type_label != "":
		return "Carrying: %d/%d %s" % [amount, capacity, type_label]
	if type_label != "":
		return "Gathering: %s  (0/%d)" % [type_label, capacity]
	return ""


func _update_queue_display(building: Node2D) -> void:
	var pq: Node = building.get_node_or_null("ProductionQueue")
	if pq == null or not pq.has_method("get_queue"):
		_hide_queue_section()
		return
	var queue: Array = pq.get_queue()
	if queue.is_empty():
		_hide_queue_section()
		return
	_tracked_queue = pq
	_show_queue_section()
	# Current training unit
	var current_type: String = queue[0]
	var display_name: String = current_type.replace("_", " ").capitalize()
	_queue_current_label.text = display_name
	# Progress bar
	var progress: float = pq.get_progress() if pq.has_method("get_progress") else 0.0
	_queue_progress_bar.value = progress * 100.0
	# Queued icons (index 1+)
	_rebuild_queue_icons(queue, pq)
	# ETA
	_update_queue_eta(pq, queue)


func _rebuild_queue_icons(queue: Array, pq: Node) -> void:
	# Clear existing icons
	for child in _queue_icons_container.get_children():
		child.queue_free()
	# Add icon for each queued item (including current at index 0)
	for i in queue.size():
		var unit_type: String = queue[i]
		var icon_btn := Button.new()
		icon_btn.custom_minimum_size = Vector2(QUEUE_ICON_SIZE, QUEUE_ICON_SIZE)
		icon_btn.text = unit_type.substr(0, 2).to_upper()
		icon_btn.add_theme_font_size_override("font_size", 10)
		icon_btn.tooltip_text = unit_type.replace("_", " ").capitalize()
		if i == 0:
			icon_btn.tooltip_text += " (training)"
		else:
			icon_btn.tooltip_text += " (queued — click to cancel)"
		# Use container to avoid lambda capture issue
		var idx_arr: Array = [i]
		var pq_ref: Array = [pq]
		icon_btn.pressed.connect(func() -> void: _on_queue_icon_pressed(pq_ref[0], idx_arr[0]))
		_queue_icons_container.add_child(icon_btn)


func _on_queue_icon_pressed(pq: Node, index: int) -> void:
	if pq == null or not is_instance_valid(pq):
		return
	if not pq.has_method("cancel_at"):
		return
	pq.cancel_at(index)


func _update_queue_eta(pq: Node, queue: Array) -> void:
	if queue.is_empty():
		_queue_eta_label.text = ""
		return
	var remaining: float = 0.0
	# Time remaining for current item
	var train_time: float = pq.get_current_train_time() if pq.has_method("get_current_train_time") else 0.0
	var elapsed: float = pq.get_elapsed_time() if pq.has_method("get_elapsed_time") else 0.0
	remaining += maxf(train_time - elapsed, 0.0)
	# Time for rest of queue
	for i in range(1, queue.size()):
		var unit_type: String = queue[i]
		if pq.has_method("get_train_time_for"):
			remaining += pq.get_train_time_for(unit_type)
	if remaining > 0.0:
		_queue_eta_label.text = "ETA: %ds" % int(ceilf(remaining))
	else:
		_queue_eta_label.text = ""


func _show_queue_section() -> void:
	if _queue_section != null:
		_queue_section.visible = true
	custom_minimum_size.y = PANEL_HEIGHT_WITH_QUEUE
	size.y = PANEL_HEIGHT_WITH_QUEUE
	offset_top = -PANEL_HEIGHT_WITH_QUEUE


func _hide_queue_section() -> void:
	if _queue_section != null:
		_queue_section.visible = false
	_tracked_queue = null
	_hide_age_section()
	custom_minimum_size.y = PANEL_HEIGHT
	size.y = PANEL_HEIGHT
	offset_top = -PANEL_HEIGHT


func _update_age_section(building: Node2D) -> void:
	if _age_section == null:
		return
	_age_section.update_display(building)
	if _age_section.visible:
		custom_minimum_size.y = PANEL_HEIGHT_WITH_QUEUE
		size.y = PANEL_HEIGHT_WITH_QUEUE
		offset_top = -PANEL_HEIGHT_WITH_QUEUE


func _update_train_section(building: Node2D) -> void:
	if _train_section != null:
		_train_section.update_for_building(building)


func _hide_train_section() -> void:
	if _train_section != null:
		_train_section.visible = false


func _hide_age_section() -> void:
	if _age_section != null:
		_age_section.visible = false


func _is_building(entity: Node) -> bool:
	return "building_name" in entity


func _is_resource_node(entity: Node) -> bool:
	return "entity_category" in entity and entity.entity_category == "resource_node"


func _is_barge(entity: Node) -> bool:
	if "entity_category" not in entity:
		return false
	var cat: String = entity.entity_category
	return cat == "own_barge" or cat == "enemy_barge"


func _resource_type_name(res_type: int) -> String:
	match res_type:
		0:
			return "Food"
		1:
			return "Wood"
		2:
			return "Stone"
		3:
			return "Gold"
		4:
			return "Knowledge"
	return "Res%d" % res_type


# -- Unit command buttons (Stop/Hold/Explore) --


func _build_cmd_buttons() -> void:
	for cmd_data: Array in CMD_BUTTONS:
		var btn := Button.new()
		btn.text = cmd_data[0]
		btn.custom_minimum_size = Vector2(60, 24)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.add_theme_font_size_override("font_size", 11)
		_apply_btn_style(btn, "normal", Color(0.2, 0.2, 0.3, 0.9))
		_apply_btn_style(btn, "hover", Color(0.3, 0.3, 0.5, 0.9))
		btn.pressed.connect(_issue_unit_command.bind(cmd_data[1]))
		_cmd_row.add_child(btn)


func _show_cmd_row() -> void:
	if _cmd_row != null:
		_cmd_row.visible = true


func _hide_cmd_row() -> void:
	if _cmd_row != null:
		_cmd_row.visible = false


func _issue_unit_command(method: String) -> void:
	if _input_handler == null:
		return
	for unit in _input_handler._get_selected_units():
		if is_instance_valid(unit) and unit.has_method(method):
			unit.call(method)


# -- Build section (villager mode) --


func _build_build_section() -> void:
	_build_separator = VSeparator.new()
	_build_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_separator.visible = false
	_root_hbox.add_child(_build_separator)

	_build_section = VBoxContainer.new()
	_build_section.name = "BuildSection"
	_build_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_section.add_theme_constant_override("separation", 2)
	_build_section.visible = false
	_root_hbox.add_child(_build_section)

	_build_tab_bar = HBoxContainer.new()
	_build_tab_bar.name = "BuildTabBar"
	_build_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_section.add_child(_build_tab_bar)
	_rebuild_build_tabs()

	_build_grid = GridContainer.new()
	_build_grid.name = "BuildGrid"
	_build_grid.columns = BUILD_GRID_COLUMNS
	_build_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_section.add_child(_build_grid)


func _rebuild_build_tabs() -> void:
	for child in _build_tab_bar.get_children():
		child.queue_free()
	for cat: String in BUILD_CATEGORIES:
		var tab_btn := Button.new()
		tab_btn.name = "Tab_%s" % cat
		tab_btn.text = cat.capitalize()
		tab_btn.custom_minimum_size = Vector2(60, 20)
		tab_btn.clip_text = true
		tab_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		tab_btn.add_theme_font_size_override("font_size", 10)
		_style_build_tab(tab_btn, cat == _build_tab)
		tab_btn.pressed.connect(_on_build_tab_pressed.bind(cat))
		_build_tab_bar.add_child(tab_btn)


func _apply_btn_style(btn: Button, state: String, color: Color, radius: int = 3) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	btn.add_theme_stylebox_override(state, s)


func _style_build_tab(btn: Button, active: bool) -> void:
	var c := Color(0.3, 0.3, 0.5, 0.9) if active else Color(0.15, 0.15, 0.2, 0.7)
	_apply_btn_style(btn, "normal", c, 2)
	_apply_btn_style(btn, "hover", Color(0.35, 0.35, 0.55, 0.9), 2)


func _on_build_tab_pressed(category: String) -> void:
	if _build_tab == category:
		return
	_build_tab = category
	for child in _build_tab_bar.get_children():
		if child is Button:
			var cat: String = child.name.replace("Tab_", "")
			_style_build_tab(child, cat == _build_tab)
	if _is_villager_mode:
		_render_build_grid()


func _toggle_build_section(show: bool) -> void:
	_is_villager_mode = show
	if _build_separator != null:
		_build_separator.visible = show
	if _build_section != null:
		_build_section.visible = show
	_set_panel_width(VILLAGER_PANEL_WIDTH if show else PANEL_WIDTH)
	if show:
		_render_build_grid()


func _set_panel_width(w: float) -> void:
	custom_minimum_size.x = w
	size.x = w
	offset_left = -w / 2.0
	offset_right = w / 2.0


func _render_build_grid() -> void:
	_clear_build_grid()
	var commands: Array = _get_build_commands()
	var hotkeys: Array = [["Q", "W", "E"], ["A", "S", "D"], ["Z", "X", "C"], ["R", "F", "V"]]
	for i in commands.size():
		var cmd: Dictionary = commands[i]
		@warning_ignore("integer_division")
		var row: int = i / BUILD_GRID_COLUMNS
		var col: int = i % BUILD_GRID_COLUMNS
		var hotkey: String = ""
		if row < hotkeys.size() and col < hotkeys[row].size():
			hotkey = hotkeys[row][col]
		var btn := _create_build_button(cmd, hotkey)
		_build_grid.add_child(btn)


func _get_build_commands() -> Array:
	var all_ids: Array = _get_all_building_ids()
	var unlocked: Array = []
	for building_id: String in all_ids:
		if _is_civ_unique_for_other(building_id):
			continue
		var resolved: String = CivBonusManager.get_resolved_building_id(_player_id, building_id)
		var stats: Dictionary = _load_building_data(resolved)
		if stats.is_empty():
			continue
		var cat: String = str(stats.get("category", ""))
		if cat != _build_tab:
			continue
		if not _is_build_unlocked(building_id):
			continue
		var cmd := {
			"id": "build_%s" % resolved,
			"label": str(stats.get("name", resolved)),
			"tooltip": _build_cost_tooltip(resolved, stats),
			"action": "build",
			"building": building_id,
		}
		unlocked.append(cmd)
	var start: int = 0
	var end: int = mini(start + MAX_BUILD_SLOTS, unlocked.size())
	if start >= unlocked.size():
		return []
	return unlocked.slice(start, end)


func _dl_call(method: String, args: Array = []) -> Variant:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.callv(method, args)
	var dl: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		dl = Engine.get_main_loop().root.get_node_or_null("DataLoader")
	if dl != null and dl.has_method(method):
		return dl.callv(method, args)
	return null


func _get_all_building_ids() -> Array:
	var result: Variant = _dl_call("get_all_building_ids")
	return result if result is Array else []


func _is_civ_unique_for_other(building_id: String) -> bool:
	var stats: Dictionary = _load_building_data(building_id)
	if stats.is_empty():
		return false
	var all_civs: Variant = _dl_call("get_all_civ_ids")
	if not all_civs is Array:
		return false
	for civ_id: String in all_civs:
		var civ_data: Variant = _dl_call("get_civ_data", [civ_id])
		if not civ_data is Dictionary:
			continue
		var unique: Dictionary = civ_data.get("unique_building", {})
		if unique.is_empty():
			continue
		var unique_name: String = str(unique.get("name", "")).to_lower().replace(" ", "_")
		if unique_name == building_id:
			return CivBonusManager.get_active_civ(_player_id) != civ_id
	return false


func _load_building_data(building_name: String) -> Dictionary:
	var result: Variant = _dl_call("get_building_stats", [building_name])
	return result if result is Dictionary else {}


func _is_build_unlocked(building_id: String) -> bool:
	if _building_placer != null and _building_placer.has_method("is_building_unlocked"):
		return _building_placer.is_building_unlocked(building_id, _player_id)
	return true


func _build_cost_tooltip(building_id: String, stats: Dictionary) -> String:
	var tip: String = "Build %s" % str(stats.get("name", building_id))
	var costs: Dictionary = stats.get("build_cost", {})
	if not costs.is_empty():
		var parts: Array[String] = []
		for res: String in costs:
			parts.append("%d %s" % [int(costs[res]), res.capitalize()])
		tip += " (%s)" % ", ".join(parts)
	return tip


func _create_build_button(command: Dictionary, hotkey: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BUILD_BUTTON_SIZE, BUILD_BUTTON_SIZE)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var label_text: String = command.get("label", "?")
	if hotkey != "":
		label_text = "[%s] %s" % [hotkey, label_text]
	btn.text = label_text
	var tip: String = command.get("tooltip", "")
	if hotkey != "":
		tip += " (%s)" % hotkey
	btn.tooltip_text = tip
	btn.clip_text = true
	_apply_btn_style(btn, "normal", Color(0.2, 0.2, 0.3, 0.9))
	_apply_btn_style(btn, "hover", Color(0.3, 0.3, 0.5, 0.9))
	_apply_btn_style(btn, "pressed", Color(0.15, 0.15, 0.25, 0.9))
	_apply_btn_style(btn, "disabled", Color(0.15, 0.15, 0.15, 0.5))
	btn.add_theme_font_size_override("font_size", 10)
	if not _check_build_affordability(command):
		btn.disabled = true
	btn.pressed.connect(_on_build_pressed.bind(command))
	btn.set_meta("command", command)
	return btn


func _on_build_pressed(command: Dictionary) -> void:
	var building_name: String = command.get("building", "")
	if building_name != "" and _building_placer != null:
		_building_placer.start_placement(building_name, _player_id)


func _check_build_affordability(command: Dictionary) -> bool:
	var building_name: String = command.get("building", "")
	if building_name == "":
		return true
	var stats: Dictionary = _load_building_data(building_name)
	if stats.is_empty():
		return true
	var raw_costs: Dictionary = stats.get("build_cost", {})
	var multiplier: float = 1.0
	if _building_placer != null and _building_placer.has_method("get_building_cost_multiplier"):
		multiplier = _building_placer.get_building_cost_multiplier()
	var costs: Dictionary = {}
	for key: String in raw_costs:
		var lower_key := key.to_lower()
		if RESOURCE_NAME_TO_TYPE.has(lower_key):
			costs[RESOURCE_NAME_TO_TYPE[lower_key]] = int(int(raw_costs[key]) * multiplier)
	return ResourceManager.can_afford(_player_id, costs)


func _update_build_button_states() -> void:
	if _build_grid == null or not _is_villager_mode:
		return
	for child in _build_grid.get_children():
		if child is Button and child.has_meta("command"):
			var cmd: Dictionary = child.get_meta("command")
			child.disabled = not _check_build_affordability(cmd)


func _clear_build_grid() -> void:
	if _build_grid == null:
		return
	for child in _build_grid.get_children():
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var key_char := char(key.keycode).to_upper()
	# Train button hotkeys for buildings with production
	if _train_section != null and _train_section.visible and _train_section.try_hotkey(key_char):
		get_viewport().set_input_as_handled()
		return
	# Stop/Hold/Explore hotkeys for non-villager units
	if _cmd_row != null and _cmd_row.visible and not _is_villager_mode:
		var cmd_keys := ["Q", "W", "E"]
		for i in CMD_BUTTONS.size():
			if i < cmd_keys.size() and key_char == cmd_keys[i]:
				_issue_unit_command(CMD_BUTTONS[i][1])
				get_viewport().set_input_as_handled()
				return
	# Build grid hotkeys for villager mode
	if _is_villager_mode and _build_grid != null and _build_grid.get_child_count() > 0:
		var hotkeys: Array = [["Q", "W", "E"], ["A", "S", "D"], ["Z", "X", "C"], ["R", "F", "V"]]
		for row_idx in hotkeys.size():
			var row: Array = hotkeys[row_idx]
			for col_idx in row.size():
				if row[col_idx] == key_char:
					var btn_index: int = row_idx * BUILD_GRID_COLUMNS + col_idx
					if btn_index < _build_grid.get_child_count():
						var btn: Button = _build_grid.get_child(btn_index) as Button
						if btn != null and not btn.disabled:
							btn.emit_signal("pressed")
							get_viewport().set_input_as_handled()
					return


func save_state() -> Dictionary:
	return {"build_tab": _build_tab}


func load_state(data: Dictionary) -> void:
	_build_tab = str(data.get("build_tab", "civilian"))
