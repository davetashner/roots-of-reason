#!/usr/bin/env python3
"""Validate JSON data files against their schemas.

Uses only Python stdlib — no external dependencies required.
Implements basic JSON Schema draft-07 validation: required fields,
type checking, array constraints, numeric constraints, and
additionalProperties enforcement.

Cross-reference checks:
  - Tech prerequisites must reference existing tech IDs
  - Tech age values must be valid age indices (0-6)
  - Tech unlock_buildings entries must reference existing building data files
    (warnings only — missing files are flagged but do not fail validation)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Colours (respects NO_COLOR / CI)
# ---------------------------------------------------------------------------
_NO_COLOR = os.environ.get("NO_COLOR") or not sys.stdout.isatty()
_GREEN = "" if _NO_COLOR else "\033[0;32m"
_RED = "" if _NO_COLOR else "\033[0;31m"
_YELLOW = "" if _NO_COLOR else "\033[0;33m"
_CYAN = "" if _NO_COLOR else "\033[0;36m"
_RESET = "" if _NO_COLOR else "\033[0m"


def _ok(msg: str) -> None:
    print(f"{_GREEN}\u2714{_RESET} {msg}")


def _err(msg: str) -> None:
    print(f"{_RED}\u2716{_RESET} {msg}")


def _warn(msg: str) -> None:
    print(f"{_YELLOW}\u26a0{_RESET} {msg}")


def _info(msg: str) -> None:
    print(f"{_CYAN}\u25b8{_RESET} {msg}")


# ---------------------------------------------------------------------------
# Mini JSON-Schema validator (draft-07 subset)
# ---------------------------------------------------------------------------
_JSON_TYPE_MAP: dict[str, tuple[type, ...]] = {
    "string": (str,),
    "number": (int, float),
    "integer": (int,),
    "boolean": (bool,),
    "array": (list,),
    "object": (dict,),
    "null": (type(None),),
}


def _type_name(value: Any) -> str:
    """Return the JSON type name for a Python value."""
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    return type(value).__name__


def validate_value(
    value: Any,
    schema: dict[str, Any],
    path: str,
    errors: list[str],
) -> None:
    """Recursively validate *value* against *schema*, appending to *errors*."""

    # --- type ---
    expected_type = schema.get("type")
    if expected_type:
        # JSON Schema allows type as a list: ["string", "null"]
        type_list = (
            expected_type if isinstance(expected_type, list)
            else [expected_type]
        )
        ok_types: tuple[type, ...] = ()
        for t in type_list:
            ok_types += _JSON_TYPE_MAP.get(t, ())
        # bool is a subclass of int in Python — reject bools for number/integer
        if any(
            t in ("number", "integer") for t in type_list
        ) and isinstance(value, bool):
            errors.append(
                f"{path}: expected type '{expected_type}', got 'boolean'"
            )
            return
        if not isinstance(value, ok_types):
            errors.append(
                f"{path}: expected type '{expected_type}', "
                f"got '{_type_name(value)}'"
            )
            return  # no point checking further constraints

    # --- required ---
    if isinstance(value, dict):
        for req in schema.get("required", []):
            if req not in value:
                errors.append(f"{path}: missing required field '{req}'")

    # --- properties ---
    props = schema.get("properties")
    if isinstance(value, dict) and props:
        for key, val in value.items():
            if key in props:
                validate_value(val, props[key], f"{path}.{key}", errors)

    # --- additionalProperties ---
    if (
        isinstance(value, dict)
        and props is not None
        and schema.get("additionalProperties") is False
    ):
        allowed = set(props.keys())
        for key in value:
            if key not in allowed:
                errors.append(f"{path}: unexpected field '{key}'")

    # --- numeric constraints ---
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(
                f"{path}: value {value} < minimum {schema['minimum']}"
            )

    # --- array constraints ---
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(
                f"{path}: array length {len(value)} < minItems {schema['minItems']}"
            )
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(
                f"{path}: array length {len(value)} > maxItems {schema['maxItems']}"
            )
        items_schema = schema.get("items")
        if items_schema:
            for i, item in enumerate(value):
                validate_value(item, items_schema, f"{path}[{i}]", errors)


# ---------------------------------------------------------------------------
# Schema loading and file discovery
# ---------------------------------------------------------------------------
def _project_root() -> Path:
    """Return the project root (parent of tools/)."""
    return Path(__file__).resolve().parent.parent


def load_schema(schema_path: Path) -> dict[str, Any]:
    with open(schema_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


# Schema mapping: directory name -> schema filename
_DIR_SCHEMA_MAP: dict[str, str] = {
    "units": "unit.json",
    "buildings": "building.json",
    "civilizations": "civilization.json",
    "resources": "resource.json",
}

# Special array files: filename -> schema
_ARRAY_FILE_MAP: dict[str, str] = {
    "tech_tree.json": "tech.json",
    "ages.json": "age.json",
}

# Files to skip (config files that don't match their directory's schema)
_SKIP_FILES: set[str] = {
    "resource_config.json",
}


def discover_files(data_dir: Path) -> list[tuple[Path, Path, bool]]:
    """Return list of (data_file, schema_file, is_array) tuples."""
    schema_dir = data_dir / "schemas"
    results: list[tuple[Path, Path, bool]] = []

    for subdir_name, schema_name in _DIR_SCHEMA_MAP.items():
        subdir = data_dir / subdir_name
        if not subdir.is_dir():
            continue
        schema_path = schema_dir / schema_name
        for json_file in sorted(subdir.glob("*.json")):
            if json_file.name in _SKIP_FILES:
                continue
            results.append((json_file, schema_path, False))

    # Tech directory — special array files
    tech_dir = data_dir / "tech"
    if tech_dir.is_dir():
        for filename, schema_name in _ARRAY_FILE_MAP.items():
            json_file = tech_dir / filename
            schema_path = schema_dir / schema_name
            if json_file.exists():
                results.append((json_file, schema_path, True))

    return results


# ---------------------------------------------------------------------------
# Cross-reference checks
# ---------------------------------------------------------------------------
MAX_AGE_INDEX = 6


def cross_reference_checks(
    data_dir: Path, verbose: bool = False
) -> tuple[list[str], list[str]]:
    """Run cross-reference validation on tech data.

    Returns a tuple of (errors, warnings). Errors cause a non-zero exit;
    warnings are informational and do not fail validation.
    """
    errors: list[str] = []
    warnings: list[str] = []
    tech_file = data_dir / "tech" / "tech_tree.json"
    ages_file = data_dir / "tech" / "ages.json"
    base_dir = data_dir.parent

    if not tech_file.exists():
        return errors, warnings

    try:
        with open(tech_file, "r", encoding="utf-8") as fh:
            techs = json.load(fh)
    except (json.JSONDecodeError, OSError):
        return errors, warnings  # parse errors already reported

    if not isinstance(techs, list):
        return errors, warnings

    tech_ids = {t["id"] for t in techs if isinstance(t, dict) and "id" in t}

    # Collect known building IDs from data/buildings/*.json filenames
    buildings_dir = data_dir / "buildings"
    known_building_ids: set[str] = set()
    if buildings_dir.is_dir():
        for bfile in buildings_dir.glob("*.json"):
            known_building_ids.add(bfile.stem)

    # Load valid age indices from ages.json if available
    valid_age_indices: set[int] = set()
    if ages_file.exists():
        try:
            with open(ages_file, "r", encoding="utf-8") as fh:
                ages = json.load(fh)
            if isinstance(ages, list):
                for age in ages:
                    if isinstance(age, dict) and "index" in age:
                        valid_age_indices.add(age["index"])
        except (json.JSONDecodeError, OSError):
            pass

    # Fallback to 0-6 range if ages.json not available
    if not valid_age_indices:
        valid_age_indices = set(range(MAX_AGE_INDEX + 1))

    rel_path = tech_file.relative_to(base_dir)

    for i, tech in enumerate(techs):
        if not isinstance(tech, dict):
            continue

        # Check prerequisites
        for prereq in tech.get("prerequisites", []):
            if prereq not in tech_ids:
                errors.append(
                    f"{rel_path}[{i}]: prerequisite '{prereq}' not found"
                )

        # Check age index
        age_val = tech.get("age")
        if isinstance(age_val, int) and age_val not in valid_age_indices:
            errors.append(
                f"{rel_path}[{i}]: age index {age_val} is not a valid age "
                f"(valid: {sorted(valid_age_indices)})"
            )

        # Check unlock_buildings references (warnings only)
        if known_building_ids:
            effects = tech.get("effects", {})
            if isinstance(effects, dict):
                for building_id in effects.get("unlock_buildings", []):
                    if building_id not in known_building_ids:
                        tech_id = tech.get("id", f"[{i}]")
                        warnings.append(
                            f"{rel_path}[{i}] (tech '{tech_id}'): "
                            f"unlock_buildings references unknown building "
                            f"'{building_id}' — no matching file in "
                            f"data/buildings/"
                        )

    return errors, warnings


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def run(
    data_dir: Path | None = None, verbose: bool = False
) -> tuple[int, int, list[str], list[str]]:
    """Run all validations.

    Returns (files_checked, error_count, error_msgs, warning_msgs).
    Errors cause a non-zero exit; warnings are informational only.
    """
    if data_dir is None:
        data_dir = _project_root() / "data"

    # Use data_dir's parent as base for relative paths so that paths
    # display as "data/units/foo.json" when run from project root, and
    # still work correctly when data_dir points to a tmp directory.
    base_dir = data_dir.parent

    files = discover_files(data_dir)
    all_errors: list[str] = []
    all_warnings: list[str] = []
    files_checked = 0
    error_files: set[str] = set()

    for data_path, schema_path, is_array in files:
        rel = data_path.relative_to(base_dir)
        schema_label = schema_path.stem
        files_checked += 1

        # Load and parse JSON
        try:
            with open(data_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except json.JSONDecodeError as exc:
            _err(f"{rel}: invalid JSON — {exc}")
            all_errors.append(f"{rel}: invalid JSON — {exc}")
            error_files.add(str(rel))
            continue

        # Load schema
        try:
            schema = load_schema(schema_path)
        except (json.JSONDecodeError, FileNotFoundError) as exc:
            _err(f"{rel}: cannot load schema {schema_path.name} — {exc}")
            all_errors.append(
                f"{rel}: cannot load schema {schema_path.name} — {exc}"
            )
            error_files.add(str(rel))
            continue

        file_errors: list[str] = []

        if is_array:
            if not isinstance(data, list):
                msg = f"{rel}: expected array, got {_type_name(data)}"
                file_errors.append(msg)
            else:
                for i, element in enumerate(data):
                    validate_value(
                        element, schema, f"{rel}[{i}]", file_errors
                    )
        else:
            validate_value(data, schema, str(rel), file_errors)

        if file_errors:
            for e in file_errors:
                _err(e)
            all_errors.extend(file_errors)
            error_files.add(str(rel))
        else:
            if verbose:
                _info(
                    f"Checking {rel} against {schema_label} schema... OK"
                )

    # Cross-reference checks
    xref_errors, xref_warnings = cross_reference_checks(data_dir, verbose=verbose)
    if xref_errors:
        for e in xref_errors:
            _err(e)
        all_errors.extend(xref_errors)
    elif verbose and (data_dir / "tech" / "tech_tree.json").exists():
        _info("Cross-reference check: all prerequisites valid... OK")
    if xref_warnings:
        for w in xref_warnings:
            _warn(w)
        all_warnings.extend(xref_warnings)
    elif verbose and (data_dir / "tech" / "tech_tree.json").exists():
        _info("Cross-reference check: all unlock_buildings references valid... OK")

    return files_checked, len(all_errors), all_errors, all_warnings


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate JSON data files against schemas."
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show extra detail"
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=None,
        help="Path to data/ directory (auto-detected if omitted)",
    )
    args = parser.parse_args()

    files_checked, error_count, _, warnings = run(
        data_dir=args.data_dir, verbose=args.verbose
    )

    print()
    if warnings:
        _warn(f"{len(warnings)} warning(s) found (non-fatal)")
    if error_count == 0:
        _ok(f"All {files_checked} data files passed validation")
        sys.exit(0)
    else:
        # Count unique files with errors from error messages
        _err(f"{error_count} error(s) found")
        sys.exit(1)


if __name__ == "__main__":
    main()
