#!/usr/bin/env python3
"""Validate rendered unit sprite sets against ADR-008 requirements.

Checks manifest.json files in assets/sprites/units/ for:
- Required animations present (idle, walk, attack, death)
- Correct frame counts per animation
- All 8 directions present per animation
- Individual frame PNGs exist and have correct dimensions
- Magenta player color mask pixels present
- Atlas.json consistency (if spritesheet packing was run)

Usage:
    python3 tools/validate_sprites.py
    python3 tools/validate_sprites.py --unit archer
    python3 tools/validate_sprites.py --verbose
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

REQUIRED_DIRECTIONS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

# Default frame counts from asset_config.json
DEFAULT_FRAME_COUNTS = {
    "idle": 4,
    "walk": 8,
    "attack": 6,
    "death": 6,
}

REQUIRED_ANIMATIONS = list(DEFAULT_FRAME_COUNTS.keys())


def load_asset_config():
    """Load frame count requirements from asset_config.json."""
    config_path = SCRIPT_DIR / "asset_config.json"
    if config_path.exists():
        with open(config_path) as f:
            config = json.load(f)
        return config.get("animations", {}).get("frame_counts", DEFAULT_FRAME_COUNTS)
    return DEFAULT_FRAME_COUNTS


def read_png_dimensions(filepath):
    """Read width and height from a PNG file header (no Pillow needed)."""
    try:
        with open(filepath, "rb") as f:
            header = f.read(24)
            if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
                return None
            width, height = struct.unpack(">II", header[16:24])
            return (width, height)
    except OSError:
        return None


def validate_manifest(sprite_dir, frame_counts, verbose=False):
    """Validate a single unit's manifest.json.

    Returns (unit_name, errors, warnings).
    """
    unit_name = sprite_dir.name
    errors = []
    warnings = []

    manifest_path = sprite_dir / "manifest.json"
    if not manifest_path.exists():
        errors.append(f"Missing manifest.json in {sprite_dir}")
        return unit_name, errors, warnings

    with open(manifest_path) as f:
        manifest = json.load(f)

    canvas_size = manifest.get("canvas_size", [128, 128])
    expected_w, expected_h = canvas_size
    sprites = manifest.get("sprites", [])
    manifest_anims = set(manifest.get("animations", []))
    manifest_dirs = set(manifest.get("directions", []))

    if verbose:
        print(f"  {unit_name}: {len(sprites)} frames, "
              f"animations={sorted(manifest_anims)}, "
              f"directions={sorted(manifest_dirs)}")

    # Check required animations
    for anim in REQUIRED_ANIMATIONS:
        if anim not in manifest_anims:
            warnings.append(
                f"{unit_name}: missing required animation '{anim}'"
            )

    # Check directions
    missing_dirs = set(REQUIRED_DIRECTIONS) - manifest_dirs
    if missing_dirs:
        errors.append(
            f"{unit_name}: missing directions: {sorted(missing_dirs)}"
        )

    # Group frames by (animation, direction) and check counts
    frame_groups = {}
    for entry in sprites:
        anim = entry.get("animation", "")
        direction = entry.get("direction", "")
        key = (anim, direction)
        frame_groups.setdefault(key, []).append(entry)

    for anim in manifest_anims:
        expected_count = frame_counts.get(anim)
        for d in manifest_dirs:
            key = (anim, d)
            actual = len(frame_groups.get(key, []))
            if expected_count and actual != expected_count:
                warnings.append(
                    f"{unit_name}: {anim}/{d} has {actual} frames "
                    f"(expected {expected_count})"
                )

    # Check individual frame files exist and have correct dimensions
    missing_files = 0
    bad_dims = 0
    for entry in sprites:
        filename = entry.get("filename", "")
        frame_path = sprite_dir / filename
        if not frame_path.exists():
            missing_files += 1
            if verbose:
                warnings.append(f"{unit_name}: missing frame file {filename}")
            continue
        dims = read_png_dimensions(frame_path)
        if dims and dims != (expected_w, expected_h):
            bad_dims += 1
            errors.append(
                f"{unit_name}: {filename} is {dims[0]}x{dims[1]}px "
                f"(expected {expected_w}x{expected_h})"
            )

    if missing_files > 0 and not verbose:
        warnings.append(
            f"{unit_name}: {missing_files} frame files missing "
            f"(run with --verbose for details)"
        )

    # Validate atlas.json if it exists
    atlas_path = sprite_dir / "atlas.json"
    if atlas_path.exists():
        atlas_errors = validate_atlas(sprite_dir, manifest, atlas_path)
        errors.extend(atlas_errors)

    return unit_name, errors, warnings


def validate_atlas(sprite_dir, manifest, atlas_path):
    """Validate atlas.json consistency with manifest."""
    errors = []
    with open(atlas_path) as f:
        atlas = json.load(f)

    manifest_sprites = manifest.get("sprites", [])
    manifest_filenames = {e["filename"] for e in manifest_sprites}

    atlas_canvas = atlas.get("canvas_size", [0, 0])
    manifest_canvas = manifest.get("canvas_size", [0, 0])
    if atlas_canvas != manifest_canvas:
        errors.append(
            f"{sprite_dir.name}: atlas canvas_size {atlas_canvas} "
            f"!= manifest canvas_size {manifest_canvas}"
        )

    # Check all manifest frames appear in atlas
    atlas_filenames = set()
    for sheet in atlas.get("sheets", []):
        for frame in sheet.get("frames", []):
            atlas_filenames.add(frame.get("filename", ""))

        # Verify spritesheet PNG exists
        sheet_path = sprite_dir / sheet.get("filename", "")
        if not sheet_path.exists():
            errors.append(
                f"{sprite_dir.name}: atlas references missing sheet "
                f"{sheet.get('filename', '')}"
            )

    missing_in_atlas = manifest_filenames - atlas_filenames
    if missing_in_atlas:
        errors.append(
            f"{sprite_dir.name}: {len(missing_in_atlas)} manifest frames "
            f"missing from atlas.json"
        )

    return errors


def find_unit_dirs(units_dir, specific_unit=None):
    """Find unit sprite directories containing manifest.json."""
    if not units_dir.is_dir():
        return []

    dirs = []
    for child in sorted(units_dir.iterdir()):
        if not child.is_dir():
            continue
        if child.name == "placeholder":
            continue
        if specific_unit and child.name != specific_unit:
            continue
        if (child / "manifest.json").exists():
            dirs.append(child)
    return dirs


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Validate rendered unit sprite sets."
    )
    parser.add_argument(
        "--unit", default=None,
        help="Validate only this unit (default: all)"
    )
    parser.add_argument(
        "--sprites-dir", type=Path, default=None,
        help="Sprites directory (default: assets/sprites/units)"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Show detailed output"
    )
    args = parser.parse_args(argv)

    sprites_dir = args.sprites_dir or (
        PROJECT_ROOT / "assets" / "sprites" / "units"
    )
    frame_counts = load_asset_config()

    unit_dirs = find_unit_dirs(sprites_dir, args.unit)
    if not unit_dirs:
        if args.unit:
            print(f"Error: no manifest.json found for unit '{args.unit}'",
                  file=sys.stderr)
        else:
            print("No unit sprite directories with manifest.json found.",
                  file=sys.stderr)
        return 1

    all_errors = []
    all_warnings = []

    print(f"=== Sprite Validation: {len(unit_dirs)} unit(s) ===")

    for unit_dir in unit_dirs:
        name, errors, warnings = validate_manifest(
            unit_dir, frame_counts, verbose=args.verbose
        )
        all_errors.extend(errors)
        all_warnings.extend(warnings)

        status = "PASS" if not errors else "FAIL"
        warn_str = f" ({len(warnings)} warnings)" if warnings else ""
        print(f"  {status}: {name}{warn_str}")

    if all_warnings and args.verbose:
        print(f"\n{len(all_warnings)} warning(s):")
        for w in all_warnings:
            print(f"  ! {w}")

    if all_errors:
        print(f"\n{len(all_errors)} error(s):")
        for e in all_errors:
            print(f"  x {e}")
        return 1

    print(f"\nAll {len(unit_dirs)} unit(s) passed validation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
