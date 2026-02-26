class_name SingularityRegression
extends Node
## Manages interaction between tech regression and the Singularity victory path.
## Listens to TechManager signals for singularity-chain tech events and
## coordinates public alerts, AGI Core construction pausing, and
## "Knowledge at Risk" queries for UI.

var _tech_manager: Node = null
var _notification_panel: Control = null
var _config: Dictionary = {}

## Template for public alerts when singularity-chain techs are researched
var _alert_template: String = "{civ} has researched {tech_name}!"

## Label text for the Knowledge at Risk UI section
var _knowledge_at_risk_label: String = "Knowledge at Risk"

## Whether AGI Core construction should pause when its prerequisite is lost
var _construction_pause_enabled: bool = true

## {player_id: bool} — tracks whether AGI Core construction is paused per player
var _agi_paused: Dictionary = {}


func setup(
	tech_manager: Node,
	notification_panel: Control = null,
) -> void:
	_tech_manager = tech_manager
	_notification_panel = notification_panel
	_load_config()
	if _tech_manager != null:
		_tech_manager.singularity_tech_researched.connect(_on_singularity_tech_researched)
		_tech_manager.singularity_tech_lost.connect(_on_singularity_tech_lost)


func _load_config() -> void:
	_config = DataLoader.get_settings("singularity_regression")
	if _config.is_empty():
		return
	_alert_template = str(_config.get("public_alert_template", _alert_template))
	_knowledge_at_risk_label = str(_config.get("knowledge_at_risk_label", _knowledge_at_risk_label))
	_construction_pause_enabled = bool(_config.get("construction_pause_on_regression", true))


func _on_singularity_tech_researched(player_id: int, tech_id: String, tech_name: String) -> void:
	## Fires public alert and resumes AGI Core construction if applicable.
	var tech_data: Dictionary = _tech_manager.get_tech_data(tech_id)
	if tech_data.get("public_alert", false):
		_fire_public_alert(player_id, tech_name)
	# Check if this re-research should resume AGI Core construction
	if _agi_paused.get(player_id, false):
		_agi_paused[player_id] = false


func _on_singularity_tech_lost(player_id: int, tech_id: String) -> void:
	## When a singularity-chain tech is lost, check if AGI Core research
	## is in progress and should be paused.
	if not _construction_pause_enabled:
		return
	if _tech_manager == null:
		return
	# Check if the lost tech is a prerequisite of agi_core
	if _is_prereq_of_agi(tech_id):
		_agi_paused[player_id] = true


func _is_prereq_of_agi(tech_id: String) -> bool:
	## Check if tech_id is a direct or transitive prerequisite of agi_core.
	var agi_data: Dictionary = _tech_manager.get_tech_data("agi_core")
	if agi_data.is_empty():
		return false
	var agi_prereqs: Array = agi_data.get("prerequisites", [])
	if tech_id in agi_prereqs:
		return true
	# Check transitive: each direct prereq's prereqs, etc.
	var to_check: Array = agi_prereqs.duplicate()
	var visited: Dictionary = {}
	while not to_check.is_empty():
		var current: String = to_check.pop_back()
		if current in visited:
			continue
		visited[current] = true
		if current == tech_id:
			return true
		var td: Dictionary = _tech_manager.get_tech_data(current)
		var prereqs: Array = td.get("prerequisites", [])
		for p: String in prereqs:
			if p not in visited:
				to_check.append(p)
	return false


func is_agi_paused(player_id: int) -> bool:
	return _agi_paused.get(player_id, false)


func get_knowledge_at_risk(player_id: int) -> Array:
	## Returns an array of dictionaries describing singularity techs at risk.
	## Each entry: { "tech_id": String, "tech_name": String }
	if _tech_manager == null:
		return []
	var status: Dictionary = _tech_manager.get_singularity_chain_status(player_id)
	var at_risk_id: String = status.get("at_risk", "")
	if at_risk_id == "":
		return []
	return [{"tech_id": at_risk_id, "tech_name": status.get("at_risk_name", at_risk_id)}]


func get_knowledge_at_risk_label() -> String:
	return _knowledge_at_risk_label


func _fire_public_alert(player_id: int, tech_name: String) -> void:
	if _notification_panel == null:
		return
	var civ_id: String = GameManager.get_player_civilization(player_id)
	var civ_name: String = civ_id.capitalize() if civ_id != "" else "Unknown"
	var message: String = _alert_template.replace("{civ}", civ_name).replace("{tech_name}", tech_name)
	if _notification_panel.has_method("notify"):
		_notification_panel.notify(message, "warning")


func save_state() -> Dictionary:
	return {
		"agi_paused": _agi_paused.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_agi_paused.clear()
	var raw: Dictionary = data.get("agi_paused", {})
	for key: Variant in raw:
		_agi_paused[int(key)] = bool(raw[key])
