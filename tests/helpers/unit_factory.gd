## Shared unit factory for tests. Returns unparented nodes — caller must
## add_child() and auto_free().
##
## Usage:
##   const UnitFactory = preload("res://tests/helpers/unit_factory.gd")
##   var v := UnitFactory.create_villager({scene_root = _root})
##   _root.add_child(v)
##   auto_free(v)

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

const _VILLAGER_DEFAULTS := {
	"unit_type": "villager",
	"unit_category": "civilian",
	"owner_id": 0,
	"hp": 25,
	"max_hp": 25,
	"build_speed": 1.0,
	"build_reach": 80.0,
	"carry_capacity": 10,
	"gather_rates": {"food": 0.4, "wood": 0.4, "stone": 0.35, "gold": 0.35},
	"gather_reach": 80.0,
	"drop_off_reach": 80.0,
}

const _COMBAT_DEFAULTS := {
	"unit_type": "infantry",
	"unit_category": "military",
	"owner_id": 0,
	"hp": 40,
	"max_hp": 40,
	"attack": 6,
	"defense": 1,
	"range": 0,
	"attack_speed": 1.5,
	"attack_type": "melee",
}

const _COMBAT_CONFIG := {
	"attack_cooldown": 1.0,
	"aggro_scan_radius": 6,
	"scan_interval": 0.5,
	"leash_range": 8,
	"building_damage_reduction": 0.80,
	"show_damage_numbers": false,
	"death_fade_duration": 0.0,
	"attack_flash_duration": 0.0,
	"stances":
	{
		"aggressive": {"auto_scan": true, "pursue": true, "retaliate": true},
		"defensive": {"auto_scan": false, "pursue": false, "retaliate": true},
		"stand_ground": {"auto_scan": false, "pursue": false, "retaliate": false},
	},
}


## Create a villager unit with standard defaults. Override any field via `overrides`.
## Common overrides: position, name, owner_id, scene_root, hp, gather_rates.
static func create_villager(overrides: Dictionary = {}) -> Node2D:
	var cfg := _VILLAGER_DEFAULTS.duplicate()
	cfg.merge(overrides, true)

	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = cfg.get("unit_type")
	u.unit_category = cfg.get("unit_category", "civilian")
	u.owner_id = int(cfg.get("owner_id"))
	u.position = cfg.get("position", Vector2.ZERO)
	u.hp = int(cfg.get("hp"))
	u.max_hp = int(cfg.get("max_hp"))
	u._build_speed = float(cfg.get("build_speed"))
	u._build_reach = float(cfg.get("build_reach"))
	u._carry_capacity = int(cfg.get("carry_capacity"))
	u._gather_rates = cfg.get("gather_rates")
	u._gather_reach = float(cfg.get("gather_reach"))
	u._drop_off_reach = float(cfg.get("drop_off_reach"))
	if cfg.has("name"):
		u.name = str(cfg.get("name"))
	if cfg.has("scene_root"):
		u._scene_root = cfg.get("scene_root")
	if cfg.has("unit_color"):
		u.unit_color = cfg.get("unit_color")
	return u


## Create a combat unit with UnitStats and _combat_config. Override base stats
## or combat config via `overrides` and `combat_config_overrides`.
static func create_combat_unit(overrides: Dictionary = {}, combat_config_overrides: Dictionary = {}) -> Node2D:
	var cfg := _COMBAT_DEFAULTS.duplicate()
	cfg.merge(overrides, true)

	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = str(cfg.get("unit_type"))
	u.unit_category = str(cfg.get("unit_category"))
	u.owner_id = int(cfg.get("owner_id"))
	u.position = cfg.get("position", Vector2.ZERO)
	if cfg.has("name"):
		u.name = str(cfg.get("name"))
	if cfg.has("scene_root"):
		u._scene_root = cfg.get("scene_root")

	var base_stats := {}
	for key in ["hp", "max_hp", "attack", "defense", "range", "attack_speed", "attack_type"]:
		if cfg.has(key):
			base_stats[key] = cfg.get(key)
	u.stats = UnitStats.new(str(cfg.get("unit_type")), base_stats)
	u.hp = int(cfg.get("hp"))
	u.max_hp = int(cfg.get("max_hp"))

	var cc := _COMBAT_CONFIG.duplicate(true)
	cc.merge(combat_config_overrides, true)
	u._combat_config = cc
	return u
