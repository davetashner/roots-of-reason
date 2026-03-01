#!/usr/bin/env python3
"""Pack individual unit sprite PNGs into atlas spritesheets.

Reads a manifest.json listing individual frame PNGs and packs them into
grid-layout atlas spritesheets. Generates atlas.json with frame-to-rect
mappings that UnitSpriteHandler can use via AtlasTexture.

Usage:
    python3 tools/spritesheet_packer.py villager
    python3 tools/spritesheet_packer.py archer --max-width 1536
    python3 tools/spritesheet_packer.py villager --dry-run
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

Image = None  # lazy import — Pillow not available in all CI environments


def _require_pil():
    """Import PIL lazily so the module can be imported without Pillow."""
    global Image
    if Image is not None:
        return
    try:
        from PIL import Image as _Image
        Image = _Image
    except ImportError:
        print("Error: Pillow is required. Install with: pip install Pillow",
              file=sys.stderr)
        sys.exit(1)


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

# Default max atlas dimensions from asset_config.json
DEFAULT_MAX_WIDTH = 1536
DEFAULT_MAX_HEIGHT = 1536


def load_asset_config():
    """Load asset_config.json for dimension constraints."""
    config_path = PROJECT_ROOT / "tools" / "asset_config.json"
    if config_path.exists():
        with open(config_path) as f:
            return json.load(f)
    return {}


def load_manifest(sprite_dir):
    """Load manifest.json from a sprite directory."""
    manifest_path = sprite_dir / "manifest.json"
    if not manifest_path.exists():
        print(f"Error: manifest.json not found in {sprite_dir}", file=sys.stderr)
        return None
    with open(manifest_path) as f:
        return json.load(f)


def compute_grid(frame_count, frame_w, frame_h, max_width, max_height):
    """Compute grid dimensions (cols, rows) that fit within max atlas size.

    Uses a square-ish layout, preferring wider sheets.
    """
    max_cols = max(1, max_width // frame_w)
    max_rows = max(1, max_height // frame_h)
    max_per_sheet = max_cols * max_rows

    if frame_count <= max_per_sheet:
        # Fit on one sheet — find squarish layout
        cols = min(max_cols, math.ceil(math.sqrt(frame_count)))
        rows = math.ceil(frame_count / cols)
        return cols, rows, 1

    # Need multiple sheets
    cols = max_cols
    rows = max_rows
    sheets = math.ceil(frame_count / max_per_sheet)
    return cols, rows, sheets


def pack_spritesheet(sprite_dir, manifest, max_width, max_height, dry_run=False):
    """Pack individual PNGs into atlas spritesheets.

    Returns atlas metadata dict and list of generated sheet paths.
    """
    _require_pil()

    sprites = manifest.get("sprites", [])
    canvas_size = manifest.get("canvas_size", [128, 128])
    frame_w, frame_h = canvas_size

    if not sprites:
        print("Error: no sprites in manifest", file=sys.stderr)
        return None, []

    cols, rows, num_sheets = compute_grid(
        len(sprites), frame_w, frame_h, max_width, max_height
    )
    frames_per_sheet = cols * rows

    print(f"  Frame size:  {frame_w}x{frame_h}")
    print(f"  Grid layout: {cols}x{rows} ({frames_per_sheet} frames/sheet)")
    print(f"  Sheets:      {num_sheets}")
    print(f"  Total:       {len(sprites)} frames")

    atlas = {
        "canvas_size": canvas_size,
        "sheets": [],
    }
    sheet_paths = []

    for sheet_idx in range(num_sheets):
        start = sheet_idx * frames_per_sheet
        end = min(start + frames_per_sheet, len(sprites))
        sheet_sprites = sprites[start:end]

        sheet_cols = cols
        sheet_rows = math.ceil(len(sheet_sprites) / cols)
        sheet_w = sheet_cols * frame_w
        sheet_h = sheet_rows * frame_h

        sheet_name = f"spritesheet_{sheet_idx:02d}.png"
        sheet_path = sprite_dir / sheet_name

        sheet_meta = {
            "filename": sheet_name,
            "width": sheet_w,
            "height": sheet_h,
            "cols": sheet_cols,
            "rows": sheet_rows,
            "frames": [],
        }

        if not dry_run:
            sheet_img = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

        for i, entry in enumerate(sheet_sprites):
            filename = entry.get("filename", "")
            col = i % cols
            row = i // cols
            x = col * frame_w
            y = row * frame_h

            frame_meta = {
                "filename": filename,
                "animation": entry.get("animation", ""),
                "direction": entry.get("direction", ""),
                "frame": entry.get("frame", 1),
                "sheet": sheet_idx,
                "x": x,
                "y": y,
                "w": frame_w,
                "h": frame_h,
            }
            sheet_meta["frames"].append(frame_meta)

            if not dry_run:
                frame_path = sprite_dir / filename
                if frame_path.exists():
                    frame_img = Image.open(frame_path).convert("RGBA")
                    if frame_img.size != (frame_w, frame_h):
                        frame_img = frame_img.resize(
                            (frame_w, frame_h), Image.LANCZOS
                        )
                    sheet_img.paste(frame_img, (x, y))
                else:
                    print(f"  WARNING: missing frame {filename}")

        if not dry_run:
            sheet_img.save(sheet_path, "PNG")
            print(f"  Wrote: {sheet_path} ({sheet_w}x{sheet_h})")

        atlas["sheets"].append(sheet_meta)
        sheet_paths.append(sheet_path)

    return atlas, sheet_paths


def write_atlas_json(sprite_dir, atlas, dry_run=False):
    """Write atlas.json with frame-to-rect mappings."""
    atlas_path = sprite_dir / "atlas.json"
    if dry_run:
        print(f"  [DRY RUN] Would write: {atlas_path}")
        return atlas_path

    with open(atlas_path, "w") as f:
        json.dump(atlas, f, indent=2)
        f.write("\n")
    print(f"  Wrote: {atlas_path}")
    return atlas_path


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Pack unit sprite PNGs into atlas spritesheets."
    )
    parser.add_argument(
        "subject",
        help="Unit name (e.g., villager, archer)"
    )
    parser.add_argument(
        "--sprite-dir", type=Path, default=None,
        help="Sprite directory (default: assets/sprites/units/<subject>)"
    )
    parser.add_argument(
        "--max-width", type=int, default=DEFAULT_MAX_WIDTH,
        help=f"Max atlas width in pixels (default: {DEFAULT_MAX_WIDTH})"
    )
    parser.add_argument(
        "--max-height", type=int, default=DEFAULT_MAX_HEIGHT,
        help=f"Max atlas height in pixels (default: {DEFAULT_MAX_HEIGHT})"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be done without writing files"
    )
    args = parser.parse_args(argv)

    sprite_dir = args.sprite_dir or (
        PROJECT_ROOT / "assets" / "sprites" / "units" / args.subject
    )

    if not sprite_dir.is_dir():
        print(f"Error: sprite directory not found: {sprite_dir}", file=sys.stderr)
        return 1

    manifest = load_manifest(sprite_dir)
    if manifest is None:
        return 1

    prefix = "[DRY RUN] " if args.dry_run else ""
    print(f"=== {prefix}Spritesheet Packer: {args.subject} ===")
    print(f"  Sprite dir:  {sprite_dir}")
    print(f"  Max atlas:   {args.max_width}x{args.max_height}")

    atlas, sheet_paths = pack_spritesheet(
        sprite_dir, manifest, args.max_width, args.max_height,
        dry_run=args.dry_run,
    )

    if atlas is None:
        return 1

    write_atlas_json(sprite_dir, atlas, dry_run=args.dry_run)

    total_frames = sum(len(s["frames"]) for s in atlas["sheets"])
    print(f"=== {prefix}Done: {total_frames} frames in "
          f"{len(atlas['sheets'])} sheet(s) ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
