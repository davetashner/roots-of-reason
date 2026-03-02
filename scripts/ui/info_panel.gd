extends PanelContainer
## Bottom-center info panel showing selected unit/building details.
## Polls InputHandler selection each frame; updates HP in real-time.
## When nothing is selected, shows resource node info on hover.

const PANEL_WIDTH: float = 400.0
const PANEL_HEIGHT: float = 120.0
const PANEL_HEIGHT_WITH_QUEUE: float = 180.0
const PORTRAIT_SIZE: float = 64.0
const QUEUE_ICON_SIZE: float = 32.0

var _input_handler: Node = null
var _target_detector: Node = null
var _river_transport: Node = null
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

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# Portrait
	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_portrait)
	# Building thumbnail overlay (rendered on top of portrait color)
	_portrait_texture = TextureRect.new()
	_portrait_texture.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_texture.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_texture.visible = false
	_portrait.add_child(_portrait_texture)

	# Right side
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	# Name
	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_name_label)

	# HP bar row
	_hp_bar_container = HBoxContainer.new()
	_hp_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_container.custom_minimum_size = Vector2(0, 16)
	_hp_bar_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_hp_bar_container)

	# HP bar background
	_hp_bar_bg = Panel.new()
	_hp_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_bg.custom_minimum_size = Vector2(180, 14)
	_hp_bar_bg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	_hp_bar_bg.add_theme_stylebox_override("panel", bg_style)
	_hp_bar_container.add_child(_hp_bar_bg)

	# HP bar fill (drawn on top of background)
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

	_main_vbox = vbox
	_build_queue_section(vbox)


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


func setup(
	input_handler: Node,
	target_detector: Node = null,
	river_transport: Node = null,
	trade_manager: Node = null,
) -> void:
	_input_handler = input_handler
	_target_detector = target_detector
	_river_transport = river_transport
	_trade_manager = trade_manager


func show_unit(unit: Node2D) -> void:
	_tracked_entity = unit
	_tracked_entities.clear()
	_is_multi = false
	_clear_hover()
	_clear_thumbnail()
	_hide_queue_section()
	visible = true
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
	_update_queue_display(building)


func show_barge(barge: Node2D) -> void:
	_tracked_entity = barge
	_tracked_entities.clear()
	_is_multi = false
	_clear_hover()
	_clear_thumbnail()
	_hide_queue_section()
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
	var regen_text := ""
	if "regenerates" in node and node.regenerates:
		if "_is_regrowing" in node and node._is_regrowing:
			regen_text = " — Regrowing..."
		else:
			regen_text = " — Regenerates"
	var type_label: String = str(node.resource_type).capitalize()
	_stats_label.text = type_label + regen_text
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
	visible = false


func _clear_hover() -> void:
	_hovered_entity = null
	_is_hovering_resource = false
	_is_hovering_wolf = false


func _load_building_thumbnail(building: Node2D) -> void:
	if _portrait_texture == null:
		return
	var bname: String = building.building_name if "building_name" in building else ""
	if bname == "":
		_clear_thumbnail()
		return
	var path := "res://assets/sprites/buildings/placeholder/" + bname + ".png"
	if ResourceLoader.exists(path):
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
	var regen_text := ""
	if "regenerates" in node and node.regenerates:
		if "_is_regrowing" in node and node._is_regrowing:
			regen_text = " — Regrowing..."
		else:
			regen_text = " — Regenerates"
	var type_label: String = str(node.resource_type).capitalize()
	_stats_label.text = type_label + regen_text


func _update() -> void:
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
		_update_queue_display(_tracked_entity as Node2D)
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
	var stats: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		stats = DataLoader.get_unit_stats(unit_type)
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			stats = dl.get_unit_stats(unit_type)
	return stats


func _get_unit_display_name(unit: Node2D) -> String:
	var unit_type: String = unit.unit_type if "unit_type" in unit else "unit"
	var stats := _get_unit_stats(unit)
	if stats.has("name"):
		return str(stats["name"])
	return unit_type.capitalize()


func _get_building_display_name(building: Node2D) -> String:
	var bname: String = building.building_name if "building_name" in building else ""
	var stats: Dictionary = {}
	if bname != "":
		if Engine.has_singleton("DataLoader"):
			stats = DataLoader.get_building_stats(bname)
		elif is_instance_valid(Engine.get_main_loop()):
			var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
			if dl and dl.has_method("get_building_stats"):
				stats = dl.get_building_stats(bname)
	if stats.has("name"):
		return str(stats["name"])
	if bname != "":
		return bname.replace("_", " ").capitalize()
	return "Building"


func _get_building_stats(building: Node2D) -> Dictionary:
	var bname: String = building.building_name if "building_name" in building else ""
	if bname == "":
		return {}
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_building_stats(bname)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_building_stats"):
			return dl.get_building_stats(bname)
	return {}


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
	custom_minimum_size.y = PANEL_HEIGHT
	size.y = PANEL_HEIGHT
	offset_top = -PANEL_HEIGHT


func _is_building(entity: Node) -> bool:
	return "building_name" in entity


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


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	pass
