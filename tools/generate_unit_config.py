#!/usr/bin/env python3
"""Generate game-side config files from a unit blueprint.

Reads a blueprint JSON and outputs:
  - data/units/{name}.json       (unit stats from template)
  - data/units/sprites/{name}.json (sprite config with animation_map)

Usage:
    python3 tools/generate_unit_config.py --blueprint blender/blueprints/archer.json
    python3 tools/generate_unit_config.py --blueprint blender/blueprints/archer.json --force
"""

import argparse
import json
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEMPLATE_DIR = os.path.join(PROJECT_ROOT, "data", "templates")

DIRECTIONS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

# Animation map: game states that map to manifest animations.
# Military units use attack/death/idle/walk; gather/build fall back to idle.
ANIMATION_MAP_MILITARY = {
    "attack": ["attack"],
    "death": ["death"],
    "idle": ["idle"],
    "walk": ["walk"],
    "gather": ["idle"],
    "build": ["idle"],
}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate Godot unit config from blueprint"
    )
    parser.add_argument(
        "--blueprint", required=True,
        help="Path to blueprint JSON file",
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite existing files",
    )
    return parser.parse_args()


def load_blueprint(path):
    with open(path) as f:
        return json.load(f)


def load_stats_template(template_name):
    """Load a unit stats template."""
    path = os.path.join(TEMPLATE_DIR, f"unit_stats_{template_name}.json")
    if not os.path.exists(path):
        print(f"ERROR: Stats template not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path) as f:
        return json.load(f)


def generate_unit_stats(blueprint):
    """Generate data/units/{name}.json from blueprint + stats template."""
    template_name = blueprint.get("stats_template", "melee")
    stats = load_stats_template(template_name)

    # Set the display name (capitalized)
    name = blueprint["name"]
    stats["name"] = name.replace("_", " ").title()

    return stats


def generate_sprite_config(blueprint):
    """Generate data/units/sprites/{name}.json from blueprint."""
    name = blueprint["name"]

    config = {
        "variants": [name],
        "base_path": "res://assets/sprites/units",
        "scale": 0.5,
        "offset_y": -16.0,
        "frame_duration": 0.3,
        "directions": DIRECTIONS,
        "animation_map": {
            name: ANIMATION_MAP_MILITARY.copy(),
        },
    }

    return config


def write_json(path, data, force=False):
    """Write JSON to file, respecting --force flag."""
    if os.path.exists(path) and not force:
        print(f"  SKIP: {path} (exists, use --force to overwrite)")
        return False

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"  WROTE: {path}")
    return True


def main():
    args = parse_args()
    blueprint = load_blueprint(args.blueprint)
    name = blueprint["name"]

    print(f"=== Generate Unit Config: {name} ===")

    # Generate unit stats
    stats_path = os.path.join(PROJECT_ROOT, "data", "units", f"{name}.json")
    stats = generate_unit_stats(blueprint)
    write_json(stats_path, stats, force=args.force)

    # Generate sprite config
    sprite_path = os.path.join(
        PROJECT_ROOT, "data", "units", "sprites", f"{name}.json"
    )
    sprite_config = generate_sprite_config(blueprint)
    write_json(sprite_path, sprite_config, force=args.force)

    print(f"=== Done: {name} ===")


if __name__ == "__main__":
    main()
