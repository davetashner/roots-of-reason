#!/usr/bin/env python3
"""Asset pipeline orchestrator for the 3D-to-2D render pipeline.

Chains: Blender render → manifest generation → spritesheet packing → validation.
Supports both procedural (geometric) and imported (.blend/.fbx) models.

Usage:
    python3 tools/asset_pipeline.py archer --type unit
    python3 tools/asset_pipeline.py archer --type unit --skip-render
    python3 tools/asset_pipeline.py archer --type unit --animations idle,walk --frames 4,8
    python3 tools/asset_pipeline.py house --type building --footprint 2
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

# Default animation config per unit type from asset_config.json
DEFAULT_UNIT_ANIMS = ["idle", "walk", "attack", "death"]
DEFAULT_UNIT_FRAMES = [4, 8, 6, 6]


def find_blender():
    """Find the Blender executable."""
    # Check BLENDER_BIN env var
    env_bin = os.environ.get("BLENDER_BIN")
    if env_bin and shutil.which(env_bin):
        return env_bin

    # Check PATH
    path_bin = shutil.which("blender")
    if path_bin:
        return path_bin

    # macOS default location
    mac_path = "/Applications/Blender.app/Contents/MacOS/Blender"
    if os.path.isfile(mac_path):
        return mac_path

    return None


def load_asset_config():
    """Load asset_config.json."""
    config_path = PROJECT_ROOT / "tools" / "asset_config.json"
    if config_path.exists():
        with open(config_path) as f:
            return json.load(f)
    return {}


def step_render(args, blender_bin):
    """Step 1: Render sprites via Blender."""
    render_script = PROJECT_ROOT / "blender" / "render_isometric.py"
    if not render_script.exists():
        print("Error: blender/render_isometric.py not found", file=sys.stderr)
        return False

    cmd = [
        blender_bin, "--background",
        "--python", str(render_script),
        "--",
        args.subject,
        "--type", args.type,
    ]

    if args.type == "building" and args.footprint:
        cmd.extend(["--footprint", str(args.footprint)])

    if args.animations:
        cmd.extend(["--animations", ",".join(args.animations)])
    if args.frames:
        cmd.extend(["--frames-per-anim", ",".join(str(f) for f in args.frames)])
    if args.directions:
        for d in args.directions:
            cmd.extend(["--directions", d])

    print(f"  CMD: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(PROJECT_ROOT))
    return result.returncode == 0


def step_manifest(args):
    """Step 2: Generate manifest and downscale renders."""
    manifest_script = PROJECT_ROOT / "blender" / "generate_manifest.py"
    if not manifest_script.exists():
        print("Error: blender/generate_manifest.py not found", file=sys.stderr)
        return False

    cmd = [sys.executable, str(manifest_script), args.subject]
    print(f"  CMD: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(PROJECT_ROOT))
    return result.returncode == 0


def step_pack(args):
    """Step 3: Pack sprites into atlas spritesheets."""
    packer_script = PROJECT_ROOT / "tools" / "spritesheet_packer.py"
    if not packer_script.exists():
        print("Error: tools/spritesheet_packer.py not found", file=sys.stderr)
        return False

    cmd = [sys.executable, str(packer_script), args.subject]
    print(f"  CMD: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(PROJECT_ROOT))
    return result.returncode == 0


def step_validate(args):
    """Step 4: Validate output sprites."""
    validate_script = PROJECT_ROOT / "tools" / "validate_assets.py"
    if not validate_script.exists():
        print("  SKIP: tools/validate_assets.py not found")
        return True

    cmd = [sys.executable, str(validate_script)]
    print(f"  CMD: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(PROJECT_ROOT))
    return result.returncode == 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Run the full 3D-to-2D asset pipeline."
    )
    parser.add_argument(
        "subject",
        help="Asset name (e.g., archer, villager, house)"
    )
    parser.add_argument(
        "--type", choices=["unit", "building"], default="unit",
        help="Asset type (default: unit)"
    )
    parser.add_argument(
        "--footprint", type=int, default=2, choices=[1, 2, 3, 4, 5],
        help="Building footprint (default: 2, buildings only)"
    )
    parser.add_argument(
        "--animations", type=str, default=None,
        help="Comma-separated animation names (default: idle,walk,attack,death)"
    )
    parser.add_argument(
        "--frames", type=str, default=None,
        help="Comma-separated frame counts per animation (default: 4,8,6,6)"
    )
    parser.add_argument(
        "--directions", nargs="+", default=None,
        help="Directions to render (default: all 8)"
    )
    parser.add_argument(
        "--skip-render", action="store_true",
        help="Skip Blender render step (use existing renders)"
    )
    parser.add_argument(
        "--skip-pack", action="store_true",
        help="Skip spritesheet packing step"
    )
    parser.add_argument(
        "--skip-validate", action="store_true",
        help="Skip validation step"
    )
    args = parser.parse_args(argv)

    # Parse comma-separated args
    if args.animations:
        args.animations = [a.strip() for a in args.animations.split(",")]
    elif args.type == "unit":
        args.animations = DEFAULT_UNIT_ANIMS

    if args.frames:
        args.frames = [int(f) for f in args.frames.split(",")]
    elif args.type == "unit":
        args.frames = DEFAULT_UNIT_FRAMES

    if args.animations and args.frames and len(args.animations) != len(args.frames):
        print("Error: --animations and --frames must have same count",
              file=sys.stderr)
        return 1

    print(f"=== Asset Pipeline: {args.subject} ({args.type}) ===")

    steps = []
    if not args.skip_render:
        steps.append(("Render", step_render))
    steps.append(("Manifest", step_manifest))
    if not args.skip_pack:
        steps.append(("Pack", step_pack))
    if not args.skip_validate:
        steps.append(("Validate", step_validate))

    blender_bin = None
    if not args.skip_render:
        blender_bin = find_blender()
        if blender_bin is None:
            print("Error: Blender not found. Set BLENDER_BIN or install Blender.",
                  file=sys.stderr)
            return 1
        print(f"  Blender: {blender_bin}")

    for i, (name, func) in enumerate(steps, 1):
        print(f"\n--- Step {i}/{len(steps)}: {name} ---")
        if name == "Render":
            ok = func(args, blender_bin)
        else:
            ok = func(args)
        if not ok:
            print(f"\nERROR: Step '{name}' failed. Pipeline aborted.",
                  file=sys.stderr)
            return 1
        print(f"  OK: {name} complete")

    print(f"\n=== Pipeline Complete: {args.subject} ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
