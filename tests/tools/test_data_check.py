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
        files_checked, error_count, errors = data_check.run(data_dir=data_dir)
        assert error_count == 0
        assert files_checked > 0
        assert errors == []


class TestMissingRequiredField:
    """A data file missing a required field should produce an error."""

    def test_missing_hp(self, data_dir: Path) -> None:
        bad_unit = {"name": "Broken", "attack": 5, "defense": 1, "speed": 1.0}
        (data_dir / "units" / "broken.json").write_text(json.dumps(bad_unit))

        _, error_count, errors = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "missing required field 'hp'" in e]
        assert len(matching) == 1

    def test_missing_multiple_required(self, data_dir: Path) -> None:
        bad_unit = {"name": "NoStats"}
        (data_dir / "units" / "nostats.json").write_text(json.dumps(bad_unit))

        _, error_count, errors = data_check.run(data_dir=data_dir)
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

        _, error_count, errors = data_check.run(data_dir=data_dir)
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

        _, error_count, errors = data_check.run(data_dir=data_dir)
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

        _, error_count, errors = data_check.run(data_dir=data_dir)
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

        _, error_count, errors = data_check.run(data_dir=data_dir)
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

        _, error_count, errors = data_check.run(data_dir=data_dir)
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

        _, error_count, errors = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "[1]" in e and "missing required" in e]
        assert len(matching) >= 1

    def test_ages_not_array(self, data_dir: Path) -> None:
        (data_dir / "tech" / "ages.json").write_text(json.dumps({"not": "array"}))

        _, error_count, errors = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "expected array" in e]
        assert len(matching) == 1


class TestInvalidJSON:
    """Files with invalid JSON should be caught."""

    def test_malformed_json(self, data_dir: Path) -> None:
        (data_dir / "units" / "broken.json").write_text("{not valid json")

        _, error_count, errors = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "invalid JSON" in e]
        assert len(matching) == 1


class TestUnexpectedField:
    """Fields not in the schema with additionalProperties: false should error."""

    def test_extra_field(self, data_dir: Path) -> None:
        unit_with_extra = {**VALID_UNIT, "magic_power": 100}
        (data_dir / "units" / "extra.json").write_text(json.dumps(unit_with_extra))

        _, error_count, errors = data_check.run(data_dir=data_dir)
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

        _, error_count, errors = data_check.run(data_dir=data_dir)
        assert error_count > 0
        matching = [e for e in errors if "minimum" in e and "hp" in e]
        assert len(matching) == 1
