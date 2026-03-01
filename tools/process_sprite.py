#!/usr/bin/env python3
"""Process high-res source building sprites into game-ready assets.

Downscales source PNGs to the correct canvas size based on building
footprint data, preserving magenta (#FF00FF) player-color mask pixels
that would otherwise be destroyed by interpolation.

Requires: Pillow (PIL)
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
        print("Error: Pillow is required. Install with: pip install Pillow", file=sys.stderr)
        sys.exit(1)

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEFAULT_CONFIG = SCRIPT_DIR / "asset_config.json"

# Magenta detection thresholds for post-downscale restoration.
# LANCZOS interpolation blends pure #FF00FF with neighboring pixels,
# producing pinkish/purplish colors. These thresholds catch blended
# magenta while avoiding false positives on warm browns/reds.
MAGENTA_MIN_R = 140
MAGENTA_MIN_B = 140
MAGENTA_MAX_G = 120


def load_config(config_path: Path) -> dict:
    with open(config_path) as f:
        return json.load(f)


def strip_numeric_suffix(name: str) -> str:
    """Strip trailing _01, _02, etc. from a building name."""
    return re.sub(r"_\d+$", "", name)


def extract_building_name(source_path: Path) -> str:
    """Derive building name from source filename, stripping numeric suffix."""
    return strip_numeric_suffix(source_path.stem)


def lookup_footprint(building_name: str, data_dir: Path) -> tuple[int, int]:
    """Load building footprint from data/buildings/{name}.json.

    Returns (width, height) tuple.
    Raises FileNotFoundError if no data file exists.
    """
    data_path = data_dir / "buildings" / f"{building_name}.json"
    if not data_path.is_file():
        raise FileNotFoundError(
            f"No building data file found: {data_path}\n"
            f"Create it with the correct 'footprint' field before processing."
        )
    with open(data_path) as f:
        data = json.load(f)
    fp = data.get("footprint", [1, 1])
    return (int(fp[0]), int(fp[1]))


def footprint_to_canvas(footprint: tuple[int, int], config: dict) -> tuple[int, int]:
    """Map a building footprint to its target canvas dimensions."""
    size = max(footprint[0], footprint[1])
    if size >= 5:
        cat = "buildings_5x5"
    elif size >= 4:
        cat = "buildings_4x4"
    elif size >= 3:
        cat = "buildings_3x3"
    elif size >= 2:
        cat = "buildings_2x2"
    else:
        cat = "buildings_1x1"

    dims = config["dimensions"][cat]
    return (dims["max_width"], dims["max_height"])


def restore_magenta(img: Image.Image) -> tuple[Image.Image, int]:
    """Restore blended magenta pixels to pure #FF00FF after downscaling.

    LANCZOS interpolation blends magenta with neighbors, producing
    pinkish/purplish artifacts. This detects those blended pixels and
    snaps them back to pure magenta, preserving the alpha channel.

    Returns (processed_image, restored_count).
    """
    _require_pil()
    img = img.copy()
    get_data = getattr(img, "get_flattened_data", img.getdata)
    pixels = list(get_data())
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


def _remove_background(img: Image.Image, tolerance: int = 30) -> Image.Image:
    """Remove near-white/gray backgrounds via flood-fill from corners.

    AI-generated source sprites often have opaque light backgrounds.
    This flood-fills from each corner, marking reachable near-white
    pixels as transparent.
    """
    img = img.copy()
    w, h = img.size
    pixels = img.load()

    # Seed from all four corners
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    visited = set()
    queue = []

    for sx, sy in seeds:
        r, g, b, a = pixels[sx, sy]
        if a == 0:
            continue  # already transparent
        # Only seed if the corner is light (near-white/gray)
        if min(r, g, b) < 180:
            continue
        queue.append((sx, sy))

    while queue:
        x, y = queue.pop()
        if (x, y) in visited:
            continue
        if x < 0 or x >= w or y < 0 or y >= h:
            continue
        visited.add((x, y))
        r, g, b, a = pixels[x, y]
        if a == 0:
            continue
        # Check if this pixel is close to white/light gray
        if min(r, g, b) < 180 or max(r, g, b) - min(r, g, b) > tolerance:
            continue
        # Make transparent
        pixels[x, y] = (r, g, b, 0)
        # Expand to neighbors
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                queue.append((nx, ny))

    return img


def process_sprite(
    source_path: Path,
    output_path: Path,
    canvas_size: tuple[int, int],
    dry_run: bool = False,
) -> dict:
    """Process a source sprite to game-ready dimensions.

    Returns a summary dict with processing metadata.
    """
    _require_pil()
    img = Image.open(source_path).convert("RGBA")
    src_w, src_h = img.size

    # Remove opaque backgrounds (AI-generated sources often have light gray bg)
    img = _remove_background(img)

    target_w, target_h = canvas_size

    # Crop to content bounding box
    bbox = img.getbbox()
    if bbox is None:
        raise ValueError(f"Source image is fully transparent: {source_path}")
    cropped = img.crop(bbox)
    content_w, content_h = cropped.size

    # Scale to fit within target canvas maintaining aspect ratio
    scale = min(target_w / content_w, target_h / content_h)
    new_w = int(content_w * scale)
    new_h = int(content_h * scale)

    # Downscale with high-quality resampling
    resized = cropped.resize((new_w, new_h), Image.LANCZOS)

    # Place on target canvas: centered horizontally, bottom-aligned
    canvas = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    x_offset = (target_w - new_w) // 2
    y_offset = target_h - new_h
    canvas.paste(resized, (x_offset, y_offset))

    # Restore magenta mask pixels blended by LANCZOS
    canvas, magenta_count = restore_magenta(canvas)

    summary = {
        "source": str(source_path),
        "source_size": f"{src_w}x{src_h}",
        "content_bbox": bbox,
        "content_size": f"{content_w}x{content_h}",
        "scale_factor": round(scale, 4),
        "canvas_size": f"{target_w}x{target_h}",
        "output": str(output_path),
        "magenta_pixels_restored": magenta_count,
        "dry_run": dry_run,
    }

    if not dry_run:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(output_path, "PNG")

    return summary


def default_output_path(building_name: str) -> Path:
    """Return the default output path for a processed building sprite."""
    return PROJECT_ROOT / "assets" / "sprites" / "buildings" / "placeholder" / f"{building_name}.png"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Process source building sprites to game-ready assets.",
        epilog="Example: process_sprite.py assets/sprites/buildings/lumber_camp_01.png",
    )
    parser.add_argument(
        "source",
        type=Path,
        help="Path to source PNG file (e.g., assets/sprites/buildings/lumber_camp_01.png)",
    )
    parser.add_argument(
        "--building",
        type=str,
        default=None,
        help="Building name override (default: auto-detect from filename)",
    )
    parser.add_argument(
        "--canvas",
        type=str,
        default=None,
        help="Canvas size override as WxH (e.g., 256x192)",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Output path (default: assets/sprites/buildings/placeholder/{name}.png)",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help="Path to asset_config.json",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=PROJECT_ROOT / "data",
        help="Path to data/ directory (default: auto-detect)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be done without writing any files",
    )
    args = parser.parse_args(argv)

    source = args.source.resolve() if args.source.is_absolute() else (Path.cwd() / args.source).resolve()
    if not source.is_file():
        print(f"Error: source file not found: {source}", file=sys.stderr)
        return 1

    # Determine building name
    building_name = args.building or extract_building_name(source)

    # Determine canvas size
    config = load_config(args.config)
    if args.canvas:
        try:
            w, h = args.canvas.lower().split("x")
            canvas_size = (int(w), int(h))
        except (ValueError, IndexError):
            print(f"Error: invalid canvas size '{args.canvas}' (expected WxH, e.g., 256x192)", file=sys.stderr)
            return 1
    else:
        try:
            footprint = lookup_footprint(building_name, args.data_dir)
        except FileNotFoundError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        canvas_size = footprint_to_canvas(footprint, config)

    # Determine output path
    output = args.output or default_output_path(building_name)
    if not output.is_absolute():
        output = (Path.cwd() / output).resolve()

    # Process
    prefix = "[DRY RUN] " if args.dry_run else ""
    print(f"{prefix}Processing: {source.name}")
    print(f"  Building:  {building_name}")
    print(f"  Canvas:    {canvas_size[0]}x{canvas_size[1]}")
    print(f"  Output:    {output}")

    try:
        summary = process_sprite(source, output, canvas_size, dry_run=args.dry_run)
    except (ValueError, OSError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    print(f"  Scale:     {summary['scale_factor']}x")
    print(f"  Magenta:   {summary['magenta_pixels_restored']} pixels restored")
    if not args.dry_run:
        print(f"  Saved:     {output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
