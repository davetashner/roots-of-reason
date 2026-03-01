#!/usr/bin/env python3
"""Generate contact-sheet images from unit sprite manifests.

Reads manifest.json and individual PNG frames, compositing them into
a side-by-side contact sheet for visual animation verification.
No running game needed — purely offline.

Requires: Pillow (PIL)
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

Image = None  # lazy import — Pillow not available in all CI environments
ImageDraw = None
ImageFont = None


def _require_pil():
    """Import PIL lazily so the module can be imported without Pillow."""
    global Image, ImageDraw, ImageFont
    if Image is not None:
        return
    try:
        from PIL import Image as _Image
        from PIL import ImageDraw as _ImageDraw
        from PIL import ImageFont as _ImageFont

        Image = _Image
        ImageDraw = _ImageDraw
        ImageFont = _ImageFont
    except ImportError:
        print(
            "Error: Pillow is required. Install with: pip install Pillow",
            file=sys.stderr,
        )
        sys.exit(1)


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
SPRITES_DIR = PROJECT_ROOT / "assets" / "sprites" / "units"
SPRITE_DATA_DIR = PROJECT_ROOT / "data" / "units" / "sprites"
OUTPUT_DIR = PROJECT_ROOT / "tests" / "screenshots" / "sprite-sheets"

LABEL_HEIGHT = 16
DIRECTION_LABEL_WIDTH = 32
ALL_DIRECTIONS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]


def load_manifest(variant: str) -> dict:
    """Load the manifest.json for a sprite variant."""
    manifest_path = SPRITES_DIR / variant / "manifest.json"
    if not manifest_path.is_file():
        print(f"Error: manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(1)
    with open(manifest_path) as f:
        return json.load(f)


def load_sprite_data(unit_type: str = "villager") -> dict:
    """Load animation_map data from data/units/sprites/{unit_type}.json."""
    data_path = SPRITE_DATA_DIR / f"{unit_type}.json"
    if not data_path.is_file():
        return {}
    with open(data_path) as f:
        return json.load(f)


def get_frames(manifest: dict, animation: str, direction: str) -> list[dict]:
    """Get sorted frame entries for an animation+direction from the manifest."""
    frames = [
        s
        for s in manifest["sprites"]
        if s["animation"] == animation and s["direction"] == direction
    ]
    frames.sort(key=lambda s: s["frame"])
    return frames


def get_animations(manifest: dict) -> list[str]:
    """Get unique animation names from the manifest, in order."""
    seen = set()
    result = []
    for s in manifest["sprites"]:
        anim = s["animation"]
        if anim not in seen:
            seen.add(anim)
            result.append(anim)
    return result


def get_directions(manifest: dict) -> list[str]:
    """Get directions from the manifest, preserving canonical order."""
    present = {s["direction"] for s in manifest["sprites"]}
    return [d for d in ALL_DIRECTIONS if d in present]


def build_strip(
    variant_dir: Path,
    frames: list[dict],
    canvas_w: int,
    canvas_h: int,
) -> "Image.Image":
    """Build a horizontal strip image from a list of frame entries."""
    _require_pil()
    n = len(frames)
    if n == 0:
        return Image.new("RGBA", (canvas_w, canvas_h + LABEL_HEIGHT), (0, 0, 0, 0))

    strip_w = n * canvas_w
    strip_h = canvas_h + LABEL_HEIGHT
    strip = Image.new("RGBA", (strip_w, strip_h), (40, 40, 40, 255))
    draw = ImageDraw.Draw(strip)

    for i, entry in enumerate(frames):
        png_path = variant_dir / entry["filename"]
        if png_path.is_file():
            frame_img = Image.open(png_path).convert("RGBA")
            # Center the frame in the canvas cell
            x_off = i * canvas_w + (canvas_w - frame_img.width) // 2
            y_off = (canvas_h - frame_img.height) // 2
            strip.paste(frame_img, (x_off, max(0, y_off)), frame_img)
        # Label
        label = str(entry["frame"])
        x_label = i * canvas_w + canvas_w // 2
        draw.text((x_label, canvas_h + 2), label, fill=(200, 200, 200, 255))

    return strip


def generate_sheet(
    variant: str,
    animation: str | None = None,
    direction: str | None = None,
) -> list[Path]:
    """Generate contact sheet(s) and return output path(s)."""
    _require_pil()
    manifest = load_manifest(variant)
    canvas_w, canvas_h = manifest["canvas_size"]
    variant_dir = SPRITES_DIR / variant

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    outputs = []

    animations = [animation] if animation else get_animations(manifest)
    directions_list = [direction] if direction else get_directions(manifest)

    for anim in animations:
        if direction:
            # Single direction — one horizontal strip
            frames = get_frames(manifest, anim, direction)
            if not frames:
                print(f"Warning: no frames for {anim}/{direction}", file=sys.stderr)
                continue
            strip = build_strip(variant_dir, frames, canvas_w, canvas_h)
            out_path = OUTPUT_DIR / f"{variant}_{anim}_{direction}.png"
            strip.save(out_path, "PNG")
            outputs.append(out_path)
        else:
            # All directions — grid with direction labels
            dir_strips = []
            for d in directions_list:
                frames = get_frames(manifest, anim, d)
                if frames:
                    dir_strips.append((d, frames))

            if not dir_strips:
                continue

            max_frames = max(len(f) for _, f in dir_strips)
            grid_w = DIRECTION_LABEL_WIDTH + max_frames * canvas_w
            row_h = canvas_h + LABEL_HEIGHT
            grid_h = len(dir_strips) * row_h
            grid = Image.new("RGBA", (grid_w, grid_h), (30, 30, 30, 255))
            draw = ImageDraw.Draw(grid)

            for row, (d, frames) in enumerate(dir_strips):
                # Direction label
                y_base = row * row_h
                draw.text(
                    (4, y_base + canvas_h // 2),
                    d.upper(),
                    fill=(200, 200, 200, 255),
                )
                # Frame strip
                strip = build_strip(variant_dir, frames, canvas_w, canvas_h)
                grid.paste(strip, (DIRECTION_LABEL_WIDTH, y_base))

            out_path = OUTPUT_DIR / f"{variant}_{anim}.png"
            grid.save(out_path, "PNG")
            outputs.append(out_path)

    return outputs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate sprite contact sheets for animation verification.",
    )
    parser.add_argument("variant", help="Sprite variant (e.g., villager_woman)")
    parser.add_argument("animation", nargs="?", help="Animation name (e.g., walk_a)")
    parser.add_argument("direction", nargs="?", help="Direction (e.g., s, ne)")
    args = parser.parse_args(argv)

    # Validate variant exists
    variant_dir = SPRITES_DIR / args.variant
    if not variant_dir.is_dir():
        print(f"Error: variant directory not found: {variant_dir}", file=sys.stderr)
        return 1

    outputs = generate_sheet(args.variant, args.animation, args.direction)
    if not outputs:
        print("Error: no frames found for the given arguments", file=sys.stderr)
        return 1

    for p in outputs:
        print(p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
