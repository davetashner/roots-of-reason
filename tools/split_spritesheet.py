#!/usr/bin/env python3
"""Split a spritesheet into individual tiles by detecting non-transparent sprites.

Scans a PNG with transparent background, finds individual sprite bounding boxes
via alpha-channel connected-component detection, crops each sprite, resizes to
the target tile size, and saves as numbered PNGs.

Usage:
    python3 tools/split_spritesheet.py <input.png> [options]

Examples:
    # Split grass quad into 128x64 tiles
    python3 tools/split_spritesheet.py assets/raw/terrain/grass_quad.png \\
        --tile-size 128x64 --output-dir assets/tiles/terrain/prototype \\
        --prefix grass_flat

    # Auto-detect sprites at original scale
    python3 tools/split_spritesheet.py input.png --output-dir out/
"""

import argparse
import sys
from pathlib import Path

from PIL import Image


def find_sprite_bboxes(
    img: Image.Image,
    alpha_threshold: int = 10,
    min_sprite_size: int = 16,
) -> list[tuple[int, int, int, int]]:
    """Find bounding boxes of non-transparent regions using flood-fill connected components.

    Args:
        img: RGBA image to scan.
        alpha_threshold: Minimum alpha value to consider a pixel non-transparent.
        min_sprite_size: Minimum width or height (in pixels) for a detected region
            to be kept. Filters out stray pixels and artifacts.

    Returns a list of (left, top, right, bottom) tuples sorted top-to-bottom,
    left-to-right.
    """
    alpha = img.split()[-1]
    width, height = alpha.size
    pixels = alpha.load()
    visited = [[False] * width for _ in range(height)]
    bboxes: list[tuple[int, int, int, int]] = []

    for y in range(height):
        for x in range(width):
            if visited[y][x] or pixels[x, y] < alpha_threshold:
                visited[y][x] = True
                continue
            # BFS flood fill to find connected component
            min_x, min_y = x, y
            max_x, max_y = x, y
            queue = [(x, y)]
            visited[y][x] = True
            while queue:
                cx, cy = queue.pop()
                min_x = min(min_x, cx)
                min_y = min(min_y, cy)
                max_x = max(max_x, cx)
                max_y = max(max_y, cy)
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < width and 0 <= ny < height and not visited[ny][nx]:
                        visited[ny][nx] = True
                        if pixels[nx, ny] >= alpha_threshold:
                            queue.append((nx, ny))
            bbox = (min_x, min_y, max_x + 1, max_y + 1)
            bw = bbox[2] - bbox[0]
            bh = bbox[3] - bbox[1]
            if bw >= min_sprite_size and bh >= min_sprite_size:
                bboxes.append(bbox)

    # Sort by row then column (top-to-bottom, left-to-right)
    bboxes.sort(key=lambda b: (b[1], b[0]))
    return bboxes


def parse_tile_size(s: str) -> tuple[int, int]:
    """Parse 'WxH' string into (width, height) tuple."""
    parts = s.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(f"Invalid tile size '{s}', expected WxH (e.g. 128x64)")
    try:
        w, h = int(parts[0]), int(parts[1])
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid tile size '{s}', expected WxH with integers")
    if w <= 0 or h <= 0:
        raise argparse.ArgumentTypeError(f"Tile dimensions must be positive, got {w}x{h}")
    return w, h


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Split a spritesheet into individual tiles by detecting non-transparent sprites.",
        epilog="Example: %(prog)s assets/raw/terrain/grass_quad.png --tile-size 128x64 --output-dir out/ --prefix grass_flat",
    )
    parser.add_argument("input", type=Path, help="Input PNG spritesheet with transparent background")
    parser.add_argument(
        "--tile-size",
        type=parse_tile_size,
        default=None,
        metavar="WxH",
        help="Target tile size (e.g. 128x64). If omitted, sprites are saved at detected size.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Output directory (default: same directory as input)",
    )
    parser.add_argument(
        "--prefix",
        default=None,
        help="Output filename prefix (default: input filename stem)",
    )
    parser.add_argument(
        "--alpha-threshold",
        type=int,
        default=10,
        metavar="N",
        help="Minimum alpha value to consider a pixel non-transparent (default: 10)",
    )
    parser.add_argument(
        "--min-size",
        type=int,
        default=16,
        metavar="PX",
        help="Minimum sprite width/height in pixels to keep (filters artifacts, default: 16)",
    )
    args = parser.parse_args()

    # Resolve paths relative to project root
    project_root = Path(__file__).resolve().parent.parent
    input_path = args.input if args.input.is_absolute() else project_root / args.input

    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}", file=sys.stderr)
        return 1

    output_dir = args.output_dir
    if output_dir is None:
        output_dir = input_path.parent
    elif not output_dir.is_absolute():
        output_dir = project_root / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    prefix = args.prefix or input_path.stem

    # Load image
    img = Image.open(input_path).convert("RGBA")
    print(f"Input: {input_path} ({img.width}x{img.height})")

    # Detect sprites
    bboxes = find_sprite_bboxes(img, alpha_threshold=args.alpha_threshold, min_sprite_size=args.min_size)
    if not bboxes:
        print("No sprites detected — image may be fully transparent.", file=sys.stderr)
        return 1

    print(f"Detected {len(bboxes)} sprite(s)")

    # Crop and save
    for i, bbox in enumerate(bboxes, start=1):
        sprite = img.crop(bbox)
        w, h = sprite.size
        label = f"{prefix}_{i:02d}.png"

        if args.tile_size:
            tw, th = args.tile_size
            sprite = sprite.resize((tw, th), Image.LANCZOS)
            w, h = tw, th

        out_path = output_dir / label
        sprite.save(out_path)
        print(f"  [{i}] {label}  ({w}x{h})  bbox={bbox}")

    print(f"Saved {len(bboxes)} tile(s) to {output_dir}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
