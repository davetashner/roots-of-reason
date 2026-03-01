#!/usr/bin/env python3
"""Capture live animation filmstrips from the running debug server.

Spawns a villager, issues movement commands, captures timed screenshots,
crops around the unit, and stitches frames into a horizontal filmstrip.

Requires: Pillow (PIL), running game with --debug-server on port 9222.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

Image = None  # lazy import


def _require_pil():
    """Import PIL lazily so the module can be imported without Pillow."""
    global Image
    if Image is not None:
        return
    try:
        from PIL import Image as _Image

        Image = _Image
    except ImportError:
        print(
            "Error: Pillow is required. Install with: pip install Pillow",
            file=sys.stderr,
        )
        sys.exit(1)


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
SPRITE_DATA_DIR = PROJECT_ROOT / "data" / "units" / "sprites"
OUTPUT_DIR = PROJECT_ROOT / "tests" / "screenshots" / "filmstrips"

DEBUG_SERVER = "http://127.0.0.1:9222"
ALL_DIRECTIONS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

# Isometric direction vectors — map direction name to (dx, dy) world offset.
# These are relative tile offsets for issuing move commands.
DIRECTION_VECTORS: dict[str, tuple[int, int]] = {
    "n": (0, -10),
    "ne": (10, -10),
    "e": (10, 0),
    "se": (10, 10),
    "s": (0, 10),
    "sw": (-10, 10),
    "w": (-10, 0),
    "nw": (-10, -10),
}

# Movement animations that make sense for live capture
MOVEMENT_ANIMATIONS = ["walk"]


def debug_get(endpoint: str) -> dict | bytes:
    """GET request to debug server, returning parsed JSON or raw bytes."""
    url = f"{DEBUG_SERVER}{endpoint}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as resp:
        content_type = resp.headers.get("Content-Type", "")
        data = resp.read()
        if "json" in content_type:
            return json.loads(data)
        return data


def debug_post(endpoint: str, payload: dict) -> dict:
    """POST JSON to debug server."""
    url = f"{DEBUG_SERVER}{endpoint}"
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())


def ping_server() -> bool:
    """Check if the debug server is alive."""
    try:
        debug_get("/status")
        return True
    except (urllib.error.URLError, OSError):
        return False


def spawn_villager(x: int = 50, y: int = 50) -> dict:
    """Spawn a villager at the given position."""
    return debug_post(
        "/command",
        {"action": "spawn", "type": "villager", "x": x, "y": y},
    )


def move_in_direction(origin_x: int, origin_y: int, direction: str) -> dict:
    """Issue a right-click move command in the given direction."""
    dx, dy = DIRECTION_VECTORS[direction]
    return debug_post(
        "/command",
        {
            "action": "right_click",
            "x": origin_x + dx,
            "y": origin_y + dy,
        },
    )


def capture_screenshot() -> bytes:
    """Capture a screenshot from the debug server as PNG bytes."""
    return debug_get("/screenshot")


def get_entities() -> list[dict]:
    """Get all entities from the debug server."""
    result = debug_get("/entities")
    if isinstance(result, dict):
        return result.get("entities", [])
    return []


def reset_game() -> None:
    """Reset game state via debug server."""
    debug_post("/command", {"action": "reset"})


def load_frame_count(direction: str) -> int:
    """Load expected walk frame count from villager sprite data."""
    data_path = SPRITE_DATA_DIR / "villager.json"
    if not data_path.is_file():
        return 4  # sensible default
    with open(data_path) as f:
        data = json.load(f)
    # Use animation_map to find walk sub-animations, then count manifest frames
    # For now, use a reasonable default that captures a full walk cycle
    return 6


def load_frame_duration() -> float:
    """Load frame_duration from villager sprite data."""
    data_path = SPRITE_DATA_DIR / "villager.json"
    if not data_path.is_file():
        return 0.3
    with open(data_path) as f:
        data = json.load(f)
    return float(data.get("frame_duration", 0.3))


def crop_around_entity(
    screenshot_bytes: bytes, entities: list[dict], padding: int = 80
) -> "Image.Image":
    """Crop a screenshot around the first villager entity."""
    _require_pil()
    import io

    img = Image.open(io.BytesIO(screenshot_bytes)).convert("RGBA")

    # Find a villager entity
    for ent in entities:
        if "villager" in ent.get("type", "").lower():
            screen_x = ent.get("screen_x", ent.get("x", img.width // 2))
            screen_y = ent.get("screen_y", ent.get("y", img.height // 2))
            left = max(0, int(screen_x) - padding)
            top = max(0, int(screen_y) - padding)
            right = min(img.width, int(screen_x) + padding)
            bottom = min(img.height, int(screen_y) + padding)
            return img.crop((left, top, right, bottom))

    # Fallback: center crop
    cx, cy = img.width // 2, img.height // 2
    return img.crop(
        (
            max(0, cx - padding),
            max(0, cy - padding),
            min(img.width, cx + padding),
            min(img.height, cy + padding),
        )
    )


def stitch_filmstrip(frames: list["Image.Image"]) -> "Image.Image":
    """Stitch a list of cropped frame images into a horizontal filmstrip."""
    _require_pil()
    if not frames:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))

    max_h = max(f.height for f in frames)
    total_w = sum(f.width for f in frames)
    filmstrip = Image.new("RGBA", (total_w, max_h), (30, 30, 30, 255))

    x_offset = 0
    for frame in frames:
        y_offset = (max_h - frame.height) // 2
        filmstrip.paste(frame, (x_offset, y_offset), frame)
        x_offset += frame.width

    return filmstrip


def capture_filmstrip(
    direction: str,
    spawn_x: int = 50,
    spawn_y: int = 50,
) -> Path:
    """Capture a full filmstrip for a walk animation in one direction."""
    _require_pil()
    frame_duration = load_frame_duration()
    num_frames = load_frame_count(direction)

    # Spawn and select
    spawn_villager(spawn_x, spawn_y)
    time.sleep(0.5)

    # Select all units
    debug_post("/command", {"action": "select_all"})
    time.sleep(0.2)

    # Issue move command
    move_in_direction(spawn_x, spawn_y, direction)
    time.sleep(0.3)

    # Capture frames
    frames = []
    for _ in range(num_frames):
        screenshot_data = capture_screenshot()
        entities = get_entities()
        cropped = crop_around_entity(screenshot_data, entities)
        frames.append(cropped)
        time.sleep(frame_duration)

    # Stitch
    filmstrip = stitch_filmstrip(frames)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUTPUT_DIR / f"walk_{direction}.png"
    filmstrip.save(out_path, "PNG")

    # Reset for next capture
    reset_game()
    time.sleep(0.5)

    return out_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Capture live animation filmstrips from the debug server.",
    )
    parser.add_argument(
        "animation",
        nargs="?",
        default="walk",
        help="Animation to capture (default: walk)",
    )
    parser.add_argument(
        "direction",
        nargs="?",
        help="Direction (e.g., s, ne). Omit for all 8 directions.",
    )
    args = parser.parse_args(argv)

    if not ping_server():
        print(
            "Error: debug server not running. Start the game with --debug-server first.",
            file=sys.stderr,
        )
        return 1

    if args.animation not in MOVEMENT_ANIMATIONS:
        print(
            f"Error: only movement animations supported: {MOVEMENT_ANIMATIONS}",
            file=sys.stderr,
        )
        return 1

    directions = [args.direction] if args.direction else ALL_DIRECTIONS
    for d in directions:
        if d not in DIRECTION_VECTORS:
            print(f"Error: unknown direction '{d}'", file=sys.stderr)
            return 1

    outputs = []
    for d in directions:
        print(f"Capturing {args.animation} {d}...", file=sys.stderr)
        out_path = capture_filmstrip(d)
        outputs.append(out_path)
        print(out_path)

    return 0


if __name__ == "__main__":
    sys.exit(main())
