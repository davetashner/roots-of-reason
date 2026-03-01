#!/usr/bin/env python3
"""Generate manifest and sprite config from rendered unit PNGs.

Downscales 2x renders to game-ready 1x, restores magenta mask pixels,
and generates manifest.json + sprite config for the game engine.

Usage:
    python3 blender/generate_manifest.py archer
    python3 blender/generate_manifest.py archer --render-dir blender/renders/archer
"""
from __future__ import annotations

import argparse
import json
import re
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

# Target canvas for units (1x game resolution)
UNIT_CANVAS = (128, 128)

# Magenta detection thresholds — same as tools/process_sprite.py
MAGENTA_MIN_R = 140
MAGENTA_MIN_B = 140
MAGENTA_MAX_G = 120

# Standard directions in render order
DIRECTION_ORDER = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

# Filename pattern: {subject}_{animation}_{direction}_{frame:02d}.png
FRAME_RE = re.compile(
    r"^(?P<subject>[a-z_]+)_(?P<anim>[a-z_]+)_(?P<dir>[a-z]+)_(?P<frame>\d+)\.png$"
)


def restore_magenta(img):
    """Restore blended magenta pixels to pure #FF00FF after downscaling.

    Returns (processed_image, restored_count).
    """
    _require_pil()
    img = img.copy()
    pixels = list(img.getdata())
    new_pixels = []
    restored = 0
    for r, g, b, a in pixels:
        if (
            a > 64
            and r > MAGENTA_MIN_R
            and b > MAGENTA_MIN_B
            and g < MAGENTA_MAX_G
            and (r + b) > (g * 3)
        ):
            new_pixels.append((255, 0, 255, a))
            restored += 1
        else:
            new_pixels.append((r, g, b, a))
    img.putdata(new_pixels)
    return img, restored


def downscale_frame(src_path, dst_path):
    """Downscale a 2x render to 1x game canvas with magenta restoration."""
    _require_pil()
    img = Image.open(src_path).convert("RGBA")
    target_w, target_h = UNIT_CANVAS

    # Resize to target canvas
    resized = img.resize((target_w, target_h), Image.LANCZOS)

    # Restore magenta mask pixels blended by LANCZOS
    result, magenta_count = restore_magenta(resized)

    dst_path.parent.mkdir(parents=True, exist_ok=True)
    result.save(dst_path, "PNG")
    return magenta_count


def scan_renders(render_dir, subject):
    """Scan render directory for frame PNGs and parse metadata.

    Returns list of dicts: {filename, animation, direction, frame}
    sorted by (animation, direction_index, frame).
    """
    frames = []
    for path in sorted(render_dir.iterdir()):
        if not path.is_file() or path.suffix.lower() != ".png":
            continue
        match = FRAME_RE.match(path.name)
        if not match:
            continue
        if match.group("subject") != subject:
            continue
        anim = match.group("anim")
        direction = match.group("dir")
        frame = int(match.group("frame"))
        frames.append({
            "filename": path.name,
            "animation": anim,
            "direction": direction,
            "frame": frame,
            "src_path": path,
        })

    # Sort: animation name, direction order, frame number
    dir_order = {d: i for i, d in enumerate(DIRECTION_ORDER)}
    frames.sort(key=lambda f: (
        f["animation"],
        dir_order.get(f["direction"], 99),
        f["frame"],
    ))
    return frames


def generate_manifest(frames, subject):
    """Generate manifest.json content from scanned frames."""
    animations = sorted(set(f["animation"] for f in frames))
    directions = [d for d in DIRECTION_ORDER
                  if any(f["direction"] == d for f in frames)]

    sprites = [
        {
            "filename": f["filename"],
            "animation": f["animation"],
            "direction": f["direction"],
            "frame": f["frame"],
        }
        for f in frames
    ]

    return {
        "canvas_size": list(UNIT_CANVAS),
        "directions": directions,
        "animations": animations,
        "sprites": sprites,
    }


def generate_sprite_config(subject, animations):
    """Generate data/units/sprites/{subject}.json sprite config."""
    # Build animation_map: each animation maps to itself,
    # with fallbacks for gather/build → idle
    anim_map = {}
    for anim in animations:
        anim_map[anim] = [anim]
    # Add fallbacks for game animations not directly rendered
    if "gather" not in anim_map:
        anim_map["gather"] = [animations[0] if "idle" not in animations else "idle"]
    if "build" not in anim_map:
        anim_map["build"] = [animations[0] if "idle" not in animations else "idle"]

    return {
        "variants": [subject],
        "base_path": "res://assets/sprites/units",
        "scale": 0.5,
        "offset_y": -16.0,
        "frame_duration": 0.3,
        "directions": DIRECTION_ORDER,
        "animation_map": {
            subject: anim_map,
        },
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate manifest and sprite config from rendered unit PNGs."
    )
    parser.add_argument(
        "subject",
        help="Unit name (e.g., archer)"
    )
    parser.add_argument(
        "--render-dir", type=Path, default=None,
        help="Directory containing 2x rendered PNGs "
             "(default: blender/renders/<subject>)"
    )
    parser.add_argument(
        "--output-dir", type=Path, default=None,
        help="Directory for game-ready 1x PNGs "
             "(default: assets/sprites/units/<subject>)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be done without writing files"
    )
    args = parser.parse_args(argv)

    render_dir = args.render_dir or (
        PROJECT_ROOT / "blender" / "renders" / args.subject
    )
    output_dir = args.output_dir or (
        PROJECT_ROOT / "assets" / "sprites" / "units" / args.subject
    )
    manifest_path = output_dir / "manifest.json"
    config_path = (
        PROJECT_ROOT / "data" / "units" / "sprites" / f"{args.subject}.json"
    )

    if not render_dir.is_dir():
        print(f"Error: render directory not found: {render_dir}", file=sys.stderr)
        return 1

    # Scan rendered frames
    frames = scan_renders(render_dir, args.subject)
    if not frames:
        print(f"Error: no frames found for '{args.subject}' in {render_dir}",
              file=sys.stderr)
        return 1

    animations = sorted(set(f["animation"] for f in frames))
    anim_counts = {}
    for f in frames:
        key = (f["animation"], f["direction"])
        anim_counts[key] = max(anim_counts.get(key, 0), f["frame"])

    print(f"=== Generate Manifest: {args.subject} ===")
    print(f"  Render dir: {render_dir}")
    print(f"  Output dir: {output_dir}")
    print(f"  Frames:     {len(frames)}")
    print(f"  Animations: {', '.join(animations)}")

    prefix = "[DRY RUN] " if args.dry_run else ""

    # Downscale frames
    total_magenta = 0
    for f in frames:
        dst = output_dir / f["filename"]
        if args.dry_run:
            print(f"  {prefix}Would downscale: {f['filename']}")
        else:
            magenta = downscale_frame(f["src_path"], dst)
            total_magenta += magenta

    if not args.dry_run:
        print(f"  Downscaled {len(frames)} frames to {UNIT_CANVAS[0]}x{UNIT_CANVAS[1]}")
        print(f"  Magenta pixels restored: {total_magenta}")

    # Generate manifest
    manifest = generate_manifest(frames, args.subject)
    if args.dry_run:
        print(f"  {prefix}Would write: {manifest_path}")
    else:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        with open(manifest_path, "w") as fp:
            json.dump(manifest, fp, indent=2)
            fp.write("\n")
        print(f"  Wrote: {manifest_path}")

    # Generate sprite config
    sprite_config = generate_sprite_config(args.subject, animations)
    if args.dry_run:
        print(f"  {prefix}Would write: {config_path}")
    else:
        config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(config_path, "w") as fp:
            json.dump(sprite_config, fp, indent=2)
            fp.write("\n")
        print(f"  Wrote: {config_path}")

    print(f"=== {prefix}Done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
