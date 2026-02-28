#!/usr/bin/env python3
"""Split a spritesheet into individual tiles.

Supports two modes:
1. Alpha detection (default): Finds sprites via alpha-channel flood-fill for
   images with transparent backgrounds between sprites.
2. Grid mode (--grid CxR or auto-fallback): Cuts the image into a uniform
   grid of columns x rows. Used automatically when alpha detection finds only
   one sprite (opaque background quads).

Usage:
    python3 tools/split_spritesheet.py <input.png> [options]

Examples:
    # Split transparent-background quad (auto-detects 4 sprites)
    python3 tools/split_spritesheet.py assets/raw/terrain/grass_quad.png \\
        --tile-size 128x64 --output-dir assets/tiles/terrain/prototype \\
        --prefix grass_flat

    # Split opaque-background quad (auto-falls back to 2x2 grid)
    python3 tools/split_spritesheet.py assets/raw/terrain/water_quad.png \\
        --tile-size 128x64 --output-dir assets/tiles/terrain/prototype \\
        --prefix water_flat

    # Force grid mode with explicit layout
    python3 tools/split_spritesheet.py input.png --grid 4x4 --tile-size 128x64
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


def grid_bboxes(
    img: Image.Image, cols: int, rows: int
) -> list[tuple[int, int, int, int]]:
    """Split an image into a uniform grid and return bounding boxes.

    Returns (left, top, right, bottom) tuples in row-major order.
    """
    cell_w = img.width // cols
    cell_h = img.height // rows
    bboxes: list[tuple[int, int, int, int]] = []
    for r in range(rows):
        for c in range(cols):
            left = c * cell_w
            top = r * cell_h
            bboxes.append((left, top, left + cell_w, top + cell_h))
    return bboxes


def remove_background(img: Image.Image, tolerance: int = 30) -> Image.Image:
    """Remove near-uniform background color by sampling corners and making matching pixels transparent.

    Detects the background color from the image corners, then sets all pixels
    within `tolerance` distance (per channel) of that color to fully transparent.
    """
    pixels = img.load()
    w, h = img.size
    # Sample corner pixels to determine background color
    corners = [pixels[0, 0], pixels[w - 1, 0], pixels[0, h - 1], pixels[w - 1, h - 1]]
    # Use the most common corner color as background
    bg = max(set(corners), key=corners.count)

    result = img.copy()
    rpx = result.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = rpx[x, y]
            if (
                abs(r - bg[0]) <= tolerance
                and abs(g - bg[1]) <= tolerance
                and abs(b - bg[2]) <= tolerance
            ):
                rpx[x, y] = (0, 0, 0, 0)
    return result


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


def parse_grid(s: str) -> tuple[int, int]:
    """Parse 'CxR' string into (columns, rows) tuple."""
    parts = s.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(f"Invalid grid '{s}', expected CxR (e.g. 2x2)")
    try:
        c, r = int(parts[0]), int(parts[1])
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid grid '{s}', expected CxR with integers")
    if c <= 0 or r <= 0:
        raise argparse.ArgumentTypeError(f"Grid dimensions must be positive, got {c}x{r}")
    return c, r


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
    parser.add_argument(
        "--grid",
        type=parse_grid,
        default=None,
        metavar="CxR",
        help="Force grid-based splitting with CxR columns x rows (e.g. 2x2). "
        "Skips alpha detection entirely.",
    )
    parser.add_argument(
        "--remove-bg",
        action="store_true",
        default=False,
        help="Remove background color (sampled from corners) and make transparent. "
        "Applied automatically when falling back to grid mode for opaque quads.",
    )
    parser.add_argument(
        "--bg-tolerance",
        type=int,
        default=30,
        metavar="N",
        help="Per-channel tolerance for background removal (default: 30)",
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
    do_remove_bg = args.remove_bg
    if args.grid:
        cols, rows = args.grid
        bboxes = grid_bboxes(img, cols, rows)
        print(f"Grid mode: {cols}x{rows} = {len(bboxes)} tile(s)")
    else:
        bboxes = find_sprite_bboxes(img, alpha_threshold=args.alpha_threshold, min_sprite_size=args.min_size)
        if not bboxes:
            print("No sprites detected — image may be fully transparent.", file=sys.stderr)
            return 1
        if len(bboxes) == 1:
            # Opaque background — alpha detection found the whole image as one sprite.
            # Fall back to 2x2 grid split and auto-enable background removal.
            print("Alpha detection found 1 sprite (opaque background) — falling back to 2x2 grid")
            bboxes = grid_bboxes(img, 2, 2)
            do_remove_bg = True
        else:
            print(f"Detected {len(bboxes)} sprite(s)")

    if do_remove_bg:
        print(f"Background removal enabled (tolerance={args.bg_tolerance})")

    # Crop and save
    for i, bbox in enumerate(bboxes, start=1):
        sprite = img.crop(bbox)

        if do_remove_bg:
            sprite = remove_background(sprite, tolerance=args.bg_tolerance)

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
