#!/usr/bin/env python3
"""Generate placeholder isometric diamond tiles for the prototype.

Produces 128x64 PNG tiles with filled diamond shapes for each terrain type.
Output: assets/tiles/terrain/prototype/
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw

TILE_W = 128
TILE_H = 64
BUILDING_SIZE = 128  # Buildings use 128x128 isometric diamond

# Terrain definitions: name -> (fill_color, border_color)
TERRAINS = {
    "grass":    ("#4A7C4A", "#3A6C3A"),
    "dirt":     ("#8B7355", "#7B6345"),
    "sand":     ("#D2B48C", "#C2A47C"),
    "desert":   ("#D4B87A", "#C4A86A"),
    "water":    ("#5B9BD5", "#4B8BC5"),
    "forest":   ("#2D5A2D", "#1D4A1D"),
    "stone":    ("#808080", "#707070"),
    "mountain": ("#404050", "#303040"),
    "river":    ("#4A90C4", "#3A80B4"),
}

# Diamond vertices for a 128x64 tile
DIAMOND = [
    (TILE_W // 2, 0),          # top
    (TILE_W - 1, TILE_H // 2), # right
    (TILE_W // 2, TILE_H - 1), # bottom
    (0, TILE_H // 2),          # left
]


def generate_tile(name: str, fill: str, border: str, out_dir: Path) -> None:
    img = Image.new("RGBA", (TILE_W, TILE_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.polygon(DIAMOND, fill=fill, outline=border, width=1)
    path = out_dir / f"{name}.png"
    img.save(path)
    print(f"  Created {path}")


# Building definitions: name -> (fill_color, border_color)
BUILDINGS = {
    "river_dock": ("#6B8E9B", "#5A7E8B"),
}

# Diamond vertices for a 128x128 building tile
BUILDING_DIAMOND = [
    (BUILDING_SIZE // 2, 0),
    (BUILDING_SIZE - 1, BUILDING_SIZE // 2),
    (BUILDING_SIZE // 2, BUILDING_SIZE - 1),
    (0, BUILDING_SIZE // 2),
]


def generate_building_tile(name: str, fill: str, border: str, out_dir: Path) -> None:
    img = Image.new("RGBA", (BUILDING_SIZE, BUILDING_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.polygon(BUILDING_DIAMOND, fill=fill, outline=border, width=2)
    # Dock plank detail lines (horizontal)
    cx, cy = BUILDING_SIZE // 2, BUILDING_SIZE // 2
    for offset in (-12, 0, 12):
        y = cy + offset
        draw.line([(cx - 20, y), (cx + 20, y)], fill=border, width=1)
    path = out_dir / f"{name}.png"
    img.save(path)
    print(f"  Created {path}")


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    out_dir = project_root / "assets" / "tiles" / "terrain" / "prototype"
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Generating prototype isometric tiles...")
    for name, (fill, border) in TERRAINS.items():
        generate_tile(name, fill, border, out_dir)

    # Generate building placeholder sprites
    building_dir = project_root / "assets" / "sprites" / "buildings" / "placeholder"
    building_dir.mkdir(parents=True, exist_ok=True)
    print("Generating prototype building sprites...")
    for name, (fill, border) in BUILDINGS.items():
        generate_building_tile(name, fill, border, building_dir)
    print("Done.")


if __name__ == "__main__":
    main()
