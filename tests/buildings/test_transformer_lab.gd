extends GdUnitTestSuite
## Tests for Transformer Lab building — Singularity Age singularity chain building.


func test_transformer_lab_data_loads() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	assert_dict(stats).is_not_empty()


func test_transformer_lab_name() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	assert_str(str(stats.get("name", ""))).is_equal("Transformer Lab")


func test_transformer_lab_has_required_fields() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	var required := [
		"name",
		"hp",
		"footprint",
		"build_time",
		"build_cost",
		"age_required",
		"required_techs",
		"required_buildings",
		"effects",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_transformer_lab_footprint_3x3() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	var fp: Array = stats.get("footprint", [])
	assert_int(int(fp[0])).is_equal(3)
	assert_int(int(fp[1])).is_equal(3)


func test_transformer_lab_age_required_singularity() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	assert_int(int(stats.get("age_required", -1))).is_equal(6)


func test_transformer_lab_requires_transformer_architecture_tech() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	var req_techs: Array = stats.get("required_techs", [])
	assert_array(req_techs).contains(["transformer_architecture"])


func test_transformer_lab_requires_gpu_foundry_building() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	var req_buildings: Array = stats.get("required_buildings", [])
	assert_array(req_buildings).contains(["gpu_foundry"])


func test_transformer_lab_research_bonus_applied() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	var effects: Dictionary = stats.get("effects", {})
	assert_float(float(effects.get("research_speed_bonus", 0.0))).is_equal_approx(2.0, 0.001)


func test_transformer_lab_singularity_chain_flag() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	assert_bool(bool(stats.get("singularity_chain", false))).is_true()


func test_transformer_lab_hp() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	assert_int(int(stats.get("hp", 0))).is_equal(2000)


func test_transformer_lab_build_cost() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	var cost: Dictionary = stats.get("build_cost", {})
	assert_int(int(cost.get("stone", 0))).is_equal(500)
	assert_int(int(cost.get("gold", 0))).is_equal(500)
	assert_int(int(cost.get("knowledge", 0))).is_equal(300)


func test_transformer_lab_defense() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	assert_int(int(stats.get("defense", 0))).is_equal(5)


func test_transformer_lab_los() -> void:
	var stats := DataLoader.get_building_stats("transformer_lab")
	assert_int(int(stats.get("los", 0))).is_equal(8)


func test_agi_core_requires_transformer_lab() -> void:
	var stats := DataLoader.get_building_stats("agi_core")
	var req_buildings: Array = stats.get("required_buildings", [])
	assert_array(req_buildings).contains(["transformer_lab"])


func test_singularity_chain_order() -> void:
	## Verify the full chain: GPU Foundry -> Transformer Lab -> AGI Core.
	var gpu_stats := DataLoader.get_building_stats("gpu_foundry")
	var tl_stats := DataLoader.get_building_stats("transformer_lab")
	var agi_stats := DataLoader.get_building_stats("agi_core")
	# GPU Foundry has no required_buildings (it's the first in the chain)
	var gpu_req: Array = gpu_stats.get("required_buildings", [])
	assert_array(gpu_req).is_empty()
	# Transformer Lab requires GPU Foundry
	var tl_req: Array = tl_stats.get("required_buildings", [])
	assert_array(tl_req).contains(["gpu_foundry"])
	# AGI Core requires Transformer Lab
	var agi_req: Array = agi_stats.get("required_buildings", [])
	assert_array(agi_req).contains(["transformer_lab"])


func test_transformer_architecture_tech_unlocks_transformer_lab() -> void:
	## The transformer_architecture tech should unlock transformer_lab building.
	var tech_data := DataLoader.get_tech_data("transformer_architecture")
	assert_dict(tech_data).is_not_empty()
	var effects: Dictionary = tech_data.get("effects", {})
	var unlock_buildings: Array = effects.get("unlock_buildings", [])
	assert_array(unlock_buildings).contains(["transformer_lab"])
