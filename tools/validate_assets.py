#!/usr/bin/env python3
"""Validate game assets against ADR-008 sprite scale contract.

Checks naming conventions, dimensions, and optional player-color masks
for all PNG files under the assets/ directory.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
from pathlib import Path
from typing import List, Tuple

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG = SCRIPT_DIR / "asset_config.json"


def load_config(config_path: Path) -> dict:
    """Load and return the asset validation config."""
    with open(config_path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# PNG dimension reading (no Pillow required)
# ---------------------------------------------------------------------------

def read_png_dimensions(filepath: Path) -> Tuple[int, int] | None:
    """Read width and height from a PNG file header.

    Returns (width, height) or None if the file is not a valid PNG.
    """
    try:
        with open(filepath, "rb") as f:
            header = f.read(24)
            if len(header) < 24:
                return None
            # PNG signature: 8 bytes
            if header[:8] != b"\x89PNG\r\n\x1a\n":
                return None
            # IHDR chunk starts at byte 8: 4-byte length, 4-byte type, then data
            # Width at offset 16, height at offset 20 (big-endian uint32)
            width, height = struct.unpack(">II", header[16:24])
            return (width, height)
    except OSError:
        return None


# ---------------------------------------------------------------------------
# Naming validation
# ---------------------------------------------------------------------------

def check_naming(filename: str, pattern: re.Pattern) -> str | None:
    """Return an error message if filename does not match the naming pattern."""
    if not pattern.match(filename):
        return f"Naming violation: '{filename}' does not match pattern (expected snake_case, lowercase, .png)"
    return None


# ---------------------------------------------------------------------------
# Dimension validation
# ---------------------------------------------------------------------------

def _strip_numeric_suffix(name: str) -> str:
    """Strip trailing _01, _02, etc. from a building name for data lookup."""
    return re.sub(r"_\d+$", "", name)


def _building_footprint_category(building_name: str) -> str:
    """Look up a building's footprint from data/buildings/ and return a category."""
    # Try exact name first, then stripped (e.g., town_center_02 -> town_center)
    for name in [building_name, _strip_numeric_suffix(building_name)]:
        data_path = SCRIPT_DIR.parent / "data" / "buildings" / f"{name}.json"
        if data_path.is_file():
            try:
                with open(data_path) as f:
                    data = json.load(f)
                fp = data.get("footprint", [1, 1])
                size = max(int(fp[0]), int(fp[1]))
                if size >= 5:
                    return "buildings_5x5"
                if size >= 4:
                    return "buildings_4x4"
                if size >= 3:
                    return "buildings_3x3"
                if size >= 2:
                    return "buildings_2x2"
                return "buildings_1x1"
            except (json.JSONDecodeError, IndexError, TypeError):
                pass
    return "buildings_1x1"


def classify_asset(rel_path: str) -> str | None:
    """Determine the dimension category for an asset based on its path.

    Returns a key into config['dimensions'] or None if unclassified.
    """
    parts = Path(rel_path).parts

    # sprites/units/ -> units or units_source
    if len(parts) >= 2 and parts[0] == "sprites" and parts[1] == "units":
        # placeholder/ contains spritesheets and mixed-size source files
        if len(parts) >= 3 and parts[2] == "placeholder":
            return "units_source"
        return "units"

    # sprites/buildings/ -> try to infer footprint from subdirectory or data JSON
    if len(parts) >= 2 and parts[0] == "sprites" and parts[1] == "buildings":
        # Check for explicit size subdirs like "2x2", "3x3"
        for part in parts[2:]:
            if part == "2x2":
                return "buildings_2x2"
            if part == "3x3":
                return "buildings_3x3"
        # Files directly under sprites/buildings/ (not in a subdirectory) are
        # hi-res source images — use relaxed limits
        if len(parts) == 3:
            return "buildings_source"
        # Infer from building data JSON using the filename (without extension)
        filename = Path(parts[-1]).stem
        return _building_footprint_category(filename)

    # tiles/ -> tiles, tiles_sheet, or tiles_source
    if len(parts) >= 1 and parts[0] == "tiles":
        filename = Path(parts[-1]).stem
        if "quad" in filename or "sixteen" in filename or "twelve" in filename:
            return "tiles_sheet"
        if filename.startswith("raw_") or "source" in filename:
            return "tiles_source"
        return "tiles"

    # resources/ -> resources
    if len(parts) >= 1 and parts[0] == "resources":
        return "resources"

    return None


def check_dimensions(
    filepath: Path,
    rel_path: str,
    config: dict,
) -> str | None:
    """Return an error message if dimensions exceed the limit for its category."""
    category = classify_asset(rel_path)
    if category is None:
        return None  # unknown category — skip

    limits = config.get("dimensions", {}).get(category)
    if limits is None:
        return None

    dims = read_png_dimensions(filepath)
    if dims is None:
        return f"Could not read PNG dimensions: {rel_path}"

    width, height = dims
    max_w = limits["max_width"]
    max_h = limits["max_height"]

    if width > max_w or height > max_h:
        return (
            f"Dimension violation: {rel_path} is {width}x{height}px "
            f"(max {max_w}x{max_h}px for {category})"
        )
    return None


# ---------------------------------------------------------------------------
# Player color mask check (optional — requires Pillow)
# ---------------------------------------------------------------------------

def check_player_color_mask(
    filepath: Path,
    rel_path: str,
    mask_color_hex: str,
) -> str | None:
    """Warn if a unit/building sprite has no magenta mask region.

    Only runs when Pillow is available. Returns None on skip or pass.
    """
    parts = Path(rel_path).parts
    if len(parts) < 2 or parts[0] != "sprites":
        return None
    if parts[1] not in ("units", "buildings"):
        return None

    try:
        from PIL import Image  # type: ignore[import-untyped]
    except ImportError:
        return None  # gracefully skip

    # Parse mask color
    mask_color_hex = mask_color_hex.lstrip("#")
    mask_r = int(mask_color_hex[0:2], 16)
    mask_g = int(mask_color_hex[2:4], 16)
    mask_b = int(mask_color_hex[4:6], 16)

    try:
        img = Image.open(filepath).convert("RGB")
    except Exception:
        return None

    pixels = img.getdata()
    for pixel in pixels:
        if pixel[0] == mask_r and pixel[1] == mask_g and pixel[2] == mask_b:
            return None  # found mask pixel

    return f"Player color mask: {rel_path} has no magenta (#FF00FF) mask pixels"


# ---------------------------------------------------------------------------
# Main validation
# ---------------------------------------------------------------------------

def validate_assets(
    assets_dir: Path,
    config: dict,
    verbose: bool = False,
) -> List[str]:
    """Walk assets_dir and return a list of validation error/warning messages."""
    errors: List[str] = []
    excluded = set(config.get("excluded_dirs", []))
    naming_pattern = re.compile(config["naming"]["pattern"])
    mask_color = config.get("player_color_mask", "#FF00FF")

    file_count = 0

    for dirpath, dirnames, filenames in os.walk(assets_dir):
        # Prune excluded top-level dirs
        rel_dir = os.path.relpath(dirpath, assets_dir)
        top_level = rel_dir.split(os.sep)[0] if rel_dir != "." else ""
        if top_level in excluded:
            dirnames.clear()
            continue

        for fname in filenames:
            # Only validate PNGs (skip .import files and others)
            if not fname.lower().endswith(".png"):
                continue

            filepath = Path(dirpath) / fname
            rel_path = os.path.relpath(filepath, assets_dir)
            file_count += 1

            if verbose:
                print(f"  Checking: {rel_path}")

            # 1. Naming
            err = check_naming(fname, naming_pattern)
            if err:
                errors.append(f"{rel_path}: {err}")

            # 2. Dimensions
            err = check_dimensions(filepath, rel_path, config)
            if err:
                errors.append(err)

            # 3. Player color mask (optional)
            err = check_player_color_mask(filepath, rel_path, mask_color)
            if err:
                errors.append(err)

    if verbose:
        print(f"\n  Scanned {file_count} PNG file(s)")

    return errors


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate game assets against ADR-008 rules."
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help="Path to asset_config.json",
    )
    parser.add_argument(
        "--assets-dir",
        type=Path,
        default=None,
        help="Path to assets/ directory (default: auto-detect from project root)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print each file as it is checked",
    )
    args = parser.parse_args(argv)

    # Resolve assets dir
    if args.assets_dir:
        assets_dir = args.assets_dir.resolve()
    else:
        project_root = SCRIPT_DIR.parent
        assets_dir = project_root / "assets"

    if not assets_dir.is_dir():
        print(f"Error: assets directory not found: {assets_dir}", file=sys.stderr)
        return 1

    # Load config
    config = load_config(args.config)

    errors = validate_assets(assets_dir, config, verbose=args.verbose)

    if errors:
        print(f"\n{len(errors)} validation error(s) found:\n")
        for err in errors:
            print(f"  \u2716 {err}")
        print()
        return 1
    else:
        print("All assets passed validation.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
