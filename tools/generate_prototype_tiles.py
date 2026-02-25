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


def generate_fog_tile(name: str, alpha: int, out_dir: Path) -> None:
    """Generate a fog tile — solid black diamond at given alpha (0-255)."""
    img = Image.new("RGBA", (TILE_W, TILE_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.polygon(DIAMOND, fill=(0, 0, 0, alpha))
    path = out_dir / f"{name}.png"
    img.save(path)
    print(f"  Created {path}")


# Building definitions: name -> (fill_color, border_color)
BUILDINGS = {
    "river_dock": ("#6B8E9B", "#5A7E8B"),
    "farm": ("#8B9B4A", "#7B8B3A"),
    "barracks": ("#8B4A4A", "#7B3A3A"),
    "dock": ("#4A6B8B", "#3A5B7B"),
    "market": ("#B8860B", "#A8760B"),
    "library": ("#6A5ACD", "#5A4ABD"),
    "wonder": ("#DAA520", "#CA9510"),
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


# Unit placeholder definitions: name -> (fill_color, border_color, letter)
UNITS = {
    "archer":   ("#5B8C3A", "#4B7C2A", "A"),
    "cavalry":  ("#8B6914", "#7B5904", "C"),
    "siege":    ("#6B4A3A", "#5B3A2A", "S"),
    "naval":    ("#2A6B8B", "#1A5B7B", "N"),
    "wolf":     ("#808080", "#606060", "W"),
}

UNIT_SIZE = 32


def generate_unit_tile(name: str, fill: str, border: str, letter: str, out_dir: Path) -> None:
    img = Image.new("RGBA", (UNIT_SIZE, UNIT_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = UNIT_SIZE // 2, UNIT_SIZE // 2
    radius = UNIT_SIZE // 2 - 2
    draw.ellipse(
        [(cx - radius, cy - radius), (cx + radius, cy + radius)],
        fill=fill,
        outline=border,
        width=2,
    )
    # Draw letter indicator centered
    bbox = draw.textbbox((0, 0), letter)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((cx - tw // 2, cy - th // 2 - 1), letter, fill="white")
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
    # Fog of war tiles
    generate_fog_tile("fog_black", 255, out_dir)
    generate_fog_tile("fog_dim", 128, out_dir)

    # Generate building placeholder sprites
    building_dir = project_root / "assets" / "sprites" / "buildings" / "placeholder"
    building_dir.mkdir(parents=True, exist_ok=True)
    print("Generating prototype building sprites...")
    for name, (fill, border) in BUILDINGS.items():
        generate_building_tile(name, fill, border, building_dir)
    # Generate unit placeholder sprites
    unit_dir = project_root / "assets" / "sprites" / "units" / "placeholder"
    unit_dir.mkdir(parents=True, exist_ok=True)
    print("Generating prototype unit sprites...")
    for name, (fill, border, letter) in UNITS.items():
        generate_unit_tile(name, fill, border, letter, unit_dir)
    print("Done.")


if __name__ == "__main__":
    main()
