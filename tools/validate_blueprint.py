#!/usr/bin/env python3
"""Validate a unit blueprint JSON file against the schema.

Usage:
    python3 tools/validate_blueprint.py blender/blueprints/archer.json
    python3 tools/validate_blueprint.py blender/blueprints/*.json
"""

import json
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_PATH = os.path.join(PROJECT_ROOT, "blender", "blueprints", "schema.json")


def validate_blueprint(blueprint_path, schema):
    """Validate a single blueprint file against the schema.

    Returns list of error strings (empty = valid).
    """
    errors = []

    try:
        with open(blueprint_path) as f:
            blueprint = json.load(f)
    except json.JSONDecodeError as e:
        return [f"Invalid JSON: {e}"]
    except FileNotFoundError:
        return [f"File not found: {blueprint_path}"]

    # Validate required top-level fields
    for field in schema.get("required", []):
        if field not in blueprint:
            errors.append(f"Missing required field: {field}")

    if errors:
        return errors

    # Validate name format
    name = blueprint.get("name", "")
    if not name or not all(c.isalnum() or c == "_" for c in name) or not name[0].isalpha():
        errors.append(f"Invalid name '{name}': must be snake_case starting with a letter")

    # Validate body
    body = blueprint.get("body", {})
    if "mhm_file" not in body:
        errors.append("body.mhm_file is required")
    for field in ["gender", "age", "muscle", "weight"]:
        val = body.get(field)
        if val is not None and not (0 <= val <= 1):
            errors.append(f"body.{field} must be 0-1, got {val}")
    if "decimate_ratio" in body:
        dr = body["decimate_ratio"]
        if not (0.05 <= dr <= 1):
            errors.append(f"body.decimate_ratio must be 0.05-1, got {dr}")

    # Validate equipment
    valid_templates = {"bow", "quiver", "sword", "shield", "spear"}
    for i, equip in enumerate(blueprint.get("equipment", [])):
        if "template" not in equip:
            errors.append(f"equipment[{i}]: missing 'template'")
        elif equip["template"] not in valid_templates:
            errors.append(
                f"equipment[{i}]: unknown template '{equip['template']}', "
                f"valid: {sorted(valid_templates)}"
            )
        if "parent_bone" not in equip:
            errors.append(f"equipment[{i}]: missing 'parent_bone'")
        for vec_field in ["location", "rotation", "scale"]:
            if vec_field in equip:
                vec = equip[vec_field]
                if not isinstance(vec, list) or len(vec) != 3:
                    errors.append(
                        f"equipment[{i}].{vec_field}: must be [x, y, z] array"
                    )

    # Validate tabard
    tabard = blueprint.get("tabard", {})
    if "parent_bone" not in tabard:
        errors.append("tabard.parent_bone is required")
    for vec_field in ["scale", "location"]:
        if vec_field in tabard:
            vec = tabard[vec_field]
            if not isinstance(vec, list) or len(vec) != 3:
                errors.append(f"tabard.{vec_field}: must be [x, y, z] array")

    # Validate animations
    anims = blueprint.get("animations", {})
    valid_anim_templates = {"ranged", "melee"}
    if "template" not in anims:
        errors.append("animations.template is required")
    elif anims["template"] not in valid_anim_templates:
        errors.append(
            f"animations.template: unknown '{anims['template']}', "
            f"valid: {sorted(valid_anim_templates)}"
        )
    frame_counts = anims.get("frame_counts", {})
    for anim_name in ["idle", "walk", "attack", "death"]:
        if anim_name not in frame_counts:
            errors.append(f"animations.frame_counts.{anim_name} is required")
        elif not isinstance(frame_counts[anim_name], int) or frame_counts[anim_name] < 1:
            errors.append(
                f"animations.frame_counts.{anim_name}: must be positive integer"
            )

    # Validate stats_template
    valid_stats = {"ranged", "melee"}
    st = blueprint.get("stats_template", "")
    if st not in valid_stats:
        errors.append(
            f"stats_template: unknown '{st}', valid: {sorted(valid_stats)}"
        )

    return errors


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <blueprint.json> [...]", file=sys.stderr)
        sys.exit(1)

    # Load schema
    try:
        with open(SCHEMA_PATH) as f:
            schema = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"ERROR: Cannot load schema at {SCHEMA_PATH}: {e}", file=sys.stderr)
        sys.exit(1)

    all_valid = True
    for path in sys.argv[1:]:
        errors = validate_blueprint(path, schema)
        if errors:
            print(f"FAIL: {path}")
            for err in errors:
                print(f"  - {err}")
            all_valid = False
        else:
            print(f"OK: {path}")

    sys.exit(0 if all_valid else 1)


if __name__ == "__main__":
    main()
