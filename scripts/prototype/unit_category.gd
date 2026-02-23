class_name UnitCategory
extends RefCounted
## Determines available commands and capabilities based on unit category.
## Uses data-driven approach — reads unit_category, attack_type, movement_type
## from the unit data dictionary.


static func get_available_commands(unit_data: Dictionary) -> Array[String]:
	var category: String = unit_data.get("unit_category", "civilian")
	var commands: Array[String] = ["move", "stop"]
	match category:
		"civilian":
			commands.append_array(["gather", "build", "repair"])
		"military":
			commands.append_array(["attack", "patrol", "garrison"])
			if unit_data.get("attack_type", "melee") == "ranged":
				commands.append("stand_ground")
	if unit_data.get("movement_type", "land") == "water":
		commands.append("transport")
	return commands


static func can_gather(unit_data: Dictionary) -> bool:
	return unit_data.get("unit_category", "") == "civilian"


static func can_build(unit_data: Dictionary) -> bool:
	return unit_data.get("unit_category", "") == "civilian"


static func can_attack(unit_data: Dictionary) -> bool:
	return float(unit_data.get("attack", 0)) > 0


static func is_military(unit_data: Dictionary) -> bool:
	return unit_data.get("unit_category", "") == "military"


static func get_movement_type(unit_data: Dictionary) -> String:
	return unit_data.get("movement_type", "land")


static func calculate_bonus_damage(attacker_data: Dictionary, defender_type: String) -> float:
	var bonus_vs: Dictionary = attacker_data.get("bonus_vs", {})
	return float(bonus_vs.get(defender_type, 1.0))
