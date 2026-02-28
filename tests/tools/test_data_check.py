"""Tests for tools/data_check.py — JSON data validation."""
from __future__ import annotations

import json
import os
import textwrap
from pathlib import Path

import pytest

# Import the module under test
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "tools"))
import data_check


# ---------------------------------------------------------------------------
# Fixtures — create a temporary data directory with schemas and data files
# ---------------------------------------------------------------------------

UNIT_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["name", "hp", "attack", "defense", "speed"],
    "properties": {
        "name": {"type": "string"},
        "hp": {"type": "number", "minimum": 1},
        "attack": {"type": "number", "minimum": 0},
        "defense": {"type": "number", "minimum": 0},
        "speed": {"type": "number", "minimum": 0},
    },
    "additionalProperties": False,
}

TECH_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["id", "name", "age", "cost", "research_time", "prerequisites", "effects"],
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string"},
        "age": {"type": "integer", "minimum": 0},
        "cost": {"type": "object"},
        "research_time": {"type": "number", "minimum": 0},
        "prerequisites": {"type": "array", "items": {"type": "string"}},
        "effects": {"type": "object"},
    },
    "additionalProperties": False,
}

AGE_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["id", "name", "index"],
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string"},
        "index": {"type": "integer", "minimum": 0},
    },
    "additionalProperties": False,
}

VALID_UNIT = {
    "name": "Warrior",
    "hp": 50,
    "attack": 8,
    "defense": 2,
    "speed": 1.0,
}

VALID_TECH_TREE = [
    {
        "id": "stone_tools",
        "name": "Stone Tools",
        "age": 0,
        "cost": {"food": 50},
        "research_time": 25,
        "prerequisites": [],
        "effects": {},
    },
    {
        "id": "fire_mastery",
        "name": "Fire Mastery",
        "age": 0,
        "cost": {"food": 75},
        "research_time": 30,
        "prerequisites": ["stone_tools"],
        "effects": {},
    },
]

VALID_AGES = [
    {"id": "stone_age", "name": "Stone Age", "index": 0},
    {"id": "bronze_age", "name": "Bronze Age", "index": 1},
]


@pytest.fixture
def data_dir(tmp_path: Path) -> Path:
    """Create a minimal valid data directory structure."""
    schemas = tmp_path / "schemas"
    schemas.mkdir()
    (schemas / "unit.json").write_text(json.dumps(UNIT_SCHEMA))
    (schemas / "tech.json").write_text(json.dumps(TECH_SCHEMA))
    (schemas / "age.json").write_text(json.dumps(AGE_SCHEMA))

    units = tmp_path / "units"
    units.mkdir()
    (units / "warrior.json").write_text(json.dumps(VALID_UNIT))

    tech = tmp_path / "tech"
    tech.mkdir()
    (tech / "tech_tree.json").write_text(json.dumps(VALID_TECH_TREE))
    (tech / "ages.json").write_text(json.dumps(VALID_AGES))

    return tmp_path


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestValidData:
    """Valid data files should pass with zero errors."""

    def test_all_valid(self, data_dir: Path) -> None:
        files_checked, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count == 0
        assert files_checked > 0
        assert errors == []


class TestMissingRequiredField:
    """A data file missing a required field should produce an error."""

    def test_missing_hp(self, data_dir: Path) -> None:
        bad_unit = {"name": "Broken", "attack": 5, "defense": 1, "speed": 1.0}
        (data_dir / "units" / "broken.json").write_text(json.dumps(bad_unit))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "missing required field 'hp'" in e]
        assert len(matching) == 1

    def test_missing_multiple_required(self, data_dir: Path) -> None:
        bad_unit = {"name": "NoStats"}
        (data_dir / "units" / "nostats.json").write_text(json.dumps(bad_unit))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        # Should report hp, attack, defense, speed all missing
        assert error_count >= 4


class TestWrongType:
    """A field with the wrong type should produce an error."""

    def test_string_where_number_expected(self, data_dir: Path) -> None:
        bad_unit = {
            "name": "BadType",
            "hp": "not_a_number",
            "attack": 5,
            "defense": 1,
            "speed": 1.0,
        }
        (data_dir / "units" / "badtype.json").write_text(json.dumps(bad_unit))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "expected type" in e and "hp" in e]
        assert len(matching) >= 1

    def test_boolean_where_number_expected(self, data_dir: Path) -> None:
        bad_unit = {
            "name": "BoolHP",
            "hp": True,
            "attack": 5,
            "defense": 1,
            "speed": 1.0,
        }
        (data_dir / "units" / "boolhp.json").write_text(json.dumps(bad_unit))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "boolean" in e]
        assert len(matching) >= 1


class TestInvalidTechPrerequisite:
    """A tech with a nonexistent prerequisite ID should be caught."""

    def test_bad_prerequisite(self, data_dir: Path) -> None:
        bad_tree = [
            {
                "id": "tech_a",
                "name": "Tech A",
                "age": 0,
                "cost": {"food": 50},
                "research_time": 25,
                "prerequisites": ["nonexistent_tech"],
                "effects": {},
            }
        ]
        (data_dir / "tech" / "tech_tree.json").write_text(json.dumps(bad_tree))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "nonexistent_tech" in e and "prerequisite" in e]
        assert len(matching) == 1


class TestInvalidAgeIndex:
    """A tech with an age index outside valid range should be caught."""

    def test_age_out_of_range(self, data_dir: Path) -> None:
        bad_tree = [
            {
                "id": "future_tech",
                "name": "Future Tech",
                "age": 99,
                "cost": {"gold": 500},
                "research_time": 50,
                "prerequisites": [],
                "effects": {},
            }
        ]
        (data_dir / "tech" / "tech_tree.json").write_text(json.dumps(bad_tree))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "age index" in e]
        assert len(matching) == 1


class TestArrayElementValidation:
    """Array files (tech_tree, ages) should validate each element."""

    def test_bad_element_in_tech_tree(self, data_dir: Path) -> None:
        tree_with_bad_element = [
            {
                "id": "good_tech",
                "name": "Good",
                "age": 0,
                "cost": {},
                "research_time": 10,
                "prerequisites": [],
                "effects": {},
            },
            {
                # Missing required fields: id, name, age, cost, etc.
                "effects": {},
            },
        ]
        (data_dir / "tech" / "tech_tree.json").write_text(
            json.dumps(tree_with_bad_element)
        )

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        # Should report missing fields for element [1]
        matching = [e for e in errors if "[1]" in e and "missing required" in e]
        assert len(matching) >= 1

    def test_bad_element_in_ages(self, data_dir: Path) -> None:
        bad_ages = [
            {"id": "ok_age", "name": "OK Age", "index": 0},
            {"id": "bad_age"},  # missing name, index
        ]
        (data_dir / "tech" / "ages.json").write_text(json.dumps(bad_ages))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "[1]" in e and "missing required" in e]
        assert len(matching) >= 1

    def test_ages_not_array(self, data_dir: Path) -> None:
        (data_dir / "tech" / "ages.json").write_text(json.dumps({"not": "array"}))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "expected array" in e]
        assert len(matching) == 1


class TestInvalidJSON:
    """Files with invalid JSON should be caught."""

    def test_malformed_json(self, data_dir: Path) -> None:
        (data_dir / "units" / "broken.json").write_text("{not valid json")

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "invalid JSON" in e]
        assert len(matching) == 1


class TestUnexpectedField:
    """Fields not in the schema with additionalProperties: false should error."""

    def test_extra_field(self, data_dir: Path) -> None:
        unit_with_extra = {**VALID_UNIT, "magic_power": 100}
        (data_dir / "units" / "extra.json").write_text(json.dumps(unit_with_extra))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "unexpected field 'magic_power'" in e]
        assert len(matching) == 1


class TestMinimumConstraint:
    """Numeric minimum constraints should be enforced."""

    def test_hp_below_minimum(self, data_dir: Path) -> None:
        bad_unit = {
            "name": "Weak",
            "hp": 0,
            "attack": 1,
            "defense": 0,
            "speed": 1.0,
        }
        (data_dir / "units" / "weak.json").write_text(json.dumps(bad_unit))

        _, error_count, errors, _warnings = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "minimum" in e and "hp" in e]
        assert len(matching) == 1


BUILDING_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["id", "name"],
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string"},
    },
    "additionalProperties": False,
}


@pytest.fixture
def data_dir_with_buildings(data_dir: Path) -> Path:
    """Extend data_dir fixture with a buildings directory and schema."""
    schemas = data_dir / "schemas"
    (schemas / "building.json").write_text(json.dumps(BUILDING_SCHEMA))

    buildings = data_dir / "buildings"
    buildings.mkdir()
    (buildings / "barracks.json").write_text(
        json.dumps({"id": "barracks", "name": "Barracks"})
    )
    return data_dir


COST_RESOURCE_SCHEMA = {
    "type": "object",
    "properties": {
        "food": {"type": "number", "minimum": 0},
        "wood": {"type": "number", "minimum": 0},
        "stone": {"type": "number", "minimum": 0},
        "gold": {"type": "number", "minimum": 0},
        "knowledge": {"type": "number", "minimum": 0},
    },
    "additionalProperties": False,
}

BUILDING_COST_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["name", "hp", "footprint", "build_time", "build_cost",
                 "population_bonus", "garrison_capacity", "is_drop_off",
                 "drop_off_types", "units_produced", "age_required",
                 "placement_constraint"],
    "properties": {
        "name": {"type": "string"},
        "hp": {"type": "number", "minimum": 1},
        "footprint": {"type": "array", "items": {"type": "integer", "minimum": 1},
                      "minItems": 2, "maxItems": 2},
        "build_time": {"type": "number", "minimum": 0},
        "build_cost": COST_RESOURCE_SCHEMA,
        "population_bonus": {"type": "integer", "minimum": 0},
        "garrison_capacity": {"type": "integer", "minimum": 0},
        "is_drop_off": {"type": "boolean"},
        "drop_off_types": {"type": "array", "items": {"type": "string"}},
        "units_produced": {"type": "array", "items": {"type": "string"}},
        "age_required": {"type": "integer", "minimum": 0},
        "placement_constraint": {
            "type": "string",
            "enum": ["", "adjacent_to_river", "adjacent_to_water"],
        },
    },
    "additionalProperties": True,
}

UNIT_TRAIN_COST_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["name", "hp", "attack", "defense", "speed"],
    "properties": {
        "name": {"type": "string"},
        "hp": {"type": "number", "minimum": 1},
        "attack": {"type": "number", "minimum": 0},
        "defense": {"type": "number", "minimum": 0},
        "speed": {"type": "number", "minimum": 0},
        "train_cost": COST_RESOURCE_SCHEMA,
    },
    "additionalProperties": True,
}

VALID_BUILDING = {
    "name": "Barracks",
    "hp": 1200,
    "footprint": [3, 3],
    "build_time": 50,
    "build_cost": {"wood": 175},
    "population_bonus": 0,
    "garrison_capacity": 10,
    "is_drop_off": False,
    "drop_off_types": [],
    "units_produced": ["infantry"],
    "age_required": 1,
    "placement_constraint": "",
}

VALID_UNIT_WITH_TRAIN_COST = {
    "name": "Archer",
    "hp": 30,
    "attack": 5,
    "defense": 0,
    "speed": 1.3,
    "train_cost": {"food": 30, "wood": 45, "gold": 10},
}


@pytest.fixture
def data_dir_with_cost_schemas(tmp_path: Path) -> Path:
    """Create a data directory using real cost-aware building and unit schemas."""
    schemas = tmp_path / "schemas"
    schemas.mkdir()
    (schemas / "building.json").write_text(json.dumps(BUILDING_COST_SCHEMA))
    (schemas / "unit.json").write_text(json.dumps(UNIT_TRAIN_COST_SCHEMA))

    buildings = tmp_path / "buildings"
    buildings.mkdir()
    (buildings / "barracks.json").write_text(json.dumps(VALID_BUILDING))

    units = tmp_path / "units"
    units.mkdir()
    (units / "archer.json").write_text(json.dumps(VALID_UNIT_WITH_TRAIN_COST))

    return tmp_path


class TestCostResourceKeyValidation:
    """Cost objects must only use recognised resource keys."""

    def test_valid_build_cost_passes(
        self, data_dir_with_cost_schemas: Path
    ) -> None:
        """A building with a valid build_cost should produce no errors."""
        _, error_count, errors, _warnings = data_check.run(
            data_dir=data_dir_with_cost_schemas
        )
        assert error_count == 0
        assert errors == []

    def test_valid_train_cost_passes(
        self, data_dir_with_cost_schemas: Path
    ) -> None:
        """A unit with a valid train_cost should produce no errors."""
        _, error_count, errors, _warnings = data_check.run(
            data_dir=data_dir_with_cost_schemas
        )
        assert error_count == 0
        assert errors == []

    def test_invalid_key_in_build_cost_is_rejected(
        self, data_dir_with_cost_schemas: Path
    ) -> None:
        """An invalid resource key in build_cost (e.g. 'iron') should cause an error."""
        bad_building = {**VALID_BUILDING, "build_cost": {"iron": 50}}
        (data_dir_with_cost_schemas / "buildings" / "bad_building.json").write_text(
            json.dumps(bad_building)
        )

        _, error_count, errors, _warnings = data_check.run(
            data_dir=data_dir_with_cost_schemas
        )
        assert error_count > 0
        matching = [e for e in errors if "iron" in e and "unexpected field" in e]
        assert len(matching) == 1

    def test_invalid_key_in_train_cost_is_rejected(
        self, data_dir_with_cost_schemas: Path
    ) -> None:
        """An invalid resource key in train_cost (e.g. 'mana') should cause an error."""
        bad_unit = {**VALID_UNIT_WITH_TRAIN_COST, "train_cost": {"mana": 100}}
        (data_dir_with_cost_schemas / "units" / "bad_unit.json").write_text(
            json.dumps(bad_unit)
        )

        _, error_count, errors, _warnings = data_check.run(
            data_dir=data_dir_with_cost_schemas
        )
        assert error_count > 0
        matching = [e for e in errors if "mana" in e and "unexpected field" in e]
        assert len(matching) == 1

    def test_all_valid_resource_keys_accepted_in_build_cost(
        self, data_dir_with_cost_schemas: Path
    ) -> None:
        """All five canonical resource keys must be accepted in build_cost."""
        all_resources_building = {
            **VALID_BUILDING,
            "build_cost": {"food": 10, "wood": 20, "stone": 30, "gold": 40, "knowledge": 50},
        }
        (data_dir_with_cost_schemas / "buildings" / "all_resources.json").write_text(
            json.dumps(all_resources_building)
        )

        _, error_count, errors, _warnings = data_check.run(
            data_dir=data_dir_with_cost_schemas
        )
        assert error_count == 0
        assert errors == []

    def test_all_valid_resource_keys_accepted_in_train_cost(
        self, data_dir_with_cost_schemas: Path
    ) -> None:
        """All five canonical resource keys must be accepted in train_cost."""
        all_resources_unit = {
            **VALID_UNIT_WITH_TRAIN_COST,
            "train_cost": {"food": 10, "wood": 20, "stone": 30, "gold": 40, "knowledge": 50},
        }
        (data_dir_with_cost_schemas / "units" / "all_resources_unit.json").write_text(
            json.dumps(all_resources_unit)
        )

        _, error_count, errors, _warnings = data_check.run(
            data_dir=data_dir_with_cost_schemas
        )
        assert error_count == 0
        assert errors == []


class TestUnlockBuildingsValidation:
    """unlock_buildings cross-reference checks emit warnings, not errors."""

    def test_known_building_produces_no_warning(
        self, data_dir_with_buildings: Path
    ) -> None:
        tree = [
            {
                "id": "bronze_working",
                "name": "Bronze Working",
                "age": 0,
                "cost": {"food": 100},
                "research_time": 30,
                "prerequisites": [],
                "effects": {"unlock_buildings": ["barracks"]},
            }
        ]
        (data_dir_with_buildings / "tech" / "tech_tree.json").write_text(
            json.dumps(tree)
        )

        _, error_count, errors, warnings = data_check.run(
            data_dir=data_dir_with_buildings
        )
        assert error_count == 0
        assert errors == []
        assert warnings == []

    def test_unknown_building_produces_warning_not_error(
        self, data_dir_with_buildings: Path
    ) -> None:
        tree = [
            {
                "id": "mystery_tech",
                "name": "Mystery Tech",
                "age": 0,
                "cost": {"food": 100},
                "research_time": 30,
                "prerequisites": [],
                "effects": {"unlock_buildings": ["nonexistent_building"]},
            }
        ]
        (data_dir_with_buildings / "tech" / "tech_tree.json").write_text(
            json.dumps(tree)
        )

        _, error_count, errors, warnings = data_check.run(
            data_dir=data_dir_with_buildings
        )
        # Must not be an error
        assert error_count == 0
        assert errors == []
        # Must produce exactly one warning mentioning the unknown building
        assert len(warnings) == 1
        assert "nonexistent_building" in warnings[0]
        assert "unlock_buildings" in warnings[0]

    def test_multiple_unknown_buildings_each_produce_a_warning(
        self, data_dir_with_buildings: Path
    ) -> None:
        tree = [
            {
                "id": "advanced_tech",
                "name": "Advanced Tech",
                "age": 1,
                "cost": {"gold": 200},
                "research_time": 60,
                "prerequisites": [],
                "effects": {
                    "unlock_buildings": ["phantom_a", "phantom_b", "barracks"]
                },
            }
        ]
        (data_dir_with_buildings / "tech" / "tech_tree.json").write_text(
            json.dumps(tree)
        )

        _, error_count, errors, warnings = data_check.run(
            data_dir=data_dir_with_buildings
        )
        assert error_count == 0
        assert errors == []
        # Only the two unknown ones should warn; barracks is known
        assert len(warnings) == 2
        warning_text = " ".join(warnings)
        assert "phantom_a" in warning_text
        assert "phantom_b" in warning_text
        assert "barracks" not in warning_text

    def test_no_buildings_dir_skips_unlock_building_check(
        self, data_dir: Path
    ) -> None:
        """If there is no data/buildings/ directory, no warnings are emitted."""
        tree = [
            {
                "id": "any_tech",
                "name": "Any Tech",
                "age": 0,
                "cost": {"food": 50},
                "research_time": 20,
                "prerequisites": [],
                "effects": {"unlock_buildings": ["some_building"]},
            }
        ]
        (data_dir / "tech" / "tech_tree.json").write_text(json.dumps(tree))

        _, error_count, errors, warnings = data_check.run(data_dir=data_dir)
        assert error_count == 0
        assert warnings == []
