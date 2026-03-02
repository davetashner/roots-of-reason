#!/usr/bin/env python3
"""Create a unit model from a blueprint JSON via MakeHuman/MPFB2.

Reads a blueprint file that describes body parameters, equipment, animations,
and generates a self-contained .blend file with all Actions baked in.

Usage:
    blender --background --python blender/create_unit.py -- \\
        --blueprint blender/blueprints/archer.json

    # Override output path:
    blender --background --python blender/create_unit.py -- \\
        --blueprint blender/blueprints/archer.json \\
        --output blender/models/custom_archer.blend
"""

import argparse
import json
import os
import sys

try:
    import bpy
except ImportError:
    print("ERROR: Must run inside Blender.", file=sys.stderr)
    sys.exit(1)

# Add project root to sys.path so blender.animations/equipment are importable
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from blender.animations import create_animations  # noqa: E402
from blender.equipment import create_equipment  # noqa: E402

# Enable MPFB2 extension
bpy.ops.preferences.addon_enable(module="bl_ext.blender_org.mpfb")
from bl_ext.blender_org.mpfb.services.humanservice import HumanService  # noqa: E402


def parse_args():
    """Parse CLI arguments (after Blender's -- separator)."""
    # Blender passes its own args before --, ours come after
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    parser = argparse.ArgumentParser(description="Create a unit model from blueprint")
    parser.add_argument(
        "--blueprint", required=True,
        help="Path to blueprint JSON file",
    )
    parser.add_argument(
        "--output", default=None,
        help="Output .blend path (default: blender/models/{name}.blend)",
    )
    return parser.parse_args(argv)


def load_blueprint(path):
    """Load and validate a blueprint JSON file."""
    with open(path) as f:
        blueprint = json.load(f)

    required = ["name", "body", "equipment", "tabard", "animations"]
    missing = [k for k in required if k not in blueprint]
    if missing:
        print(f"ERROR: Blueprint missing fields: {missing}", file=sys.stderr)
        sys.exit(1)

    return blueprint


def load_makehuman_base(mhm_path, decimate_ratio=0.25):
    """Load the MakeHuman model with game_engine rig via MPFB2."""
    settings = HumanService.get_default_deserialization_settings()
    settings["override_rig"] = "game_engine"
    settings["subdiv_levels"] = 0
    settings["load_clothes"] = False
    settings["mask_helpers"] = False
    settings["detailed_helpers"] = False
    settings["clothes_deep_search"] = False
    settings["bodypart_deep_search"] = False

    basemesh = HumanService.deserialize_from_mhm(mhm_path, settings)
    print(f"  Loaded MakeHuman base: {basemesh.name}")
    print(f"    Verts: {len(basemesh.data.vertices)}, "
          f"Faces: {len(basemesh.data.polygons)}")

    # Find armature
    armature = None
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            armature = obj
            break

    if armature:
        print(f"    Armature: {armature.name} ({len(armature.data.bones)} bones)")

    return basemesh, armature


def cleanup_mesh(basemesh, decimate_ratio=0.25):
    """Remove invisible detail meshes and decimate the body."""
    to_remove = []
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            continue
        if obj == basemesh:
            continue
        name_lower = obj.name.lower()
        if any(x in name_lower for x in ["eye", "teeth", "tooth", "tongue",
                                          "eyebrow", "eyelash", "cube"]):
            to_remove.append(obj)

    for obj in to_remove:
        print(f"    Removing: {obj.name}")
        bpy.data.objects.remove(obj, do_unlink=True)

    bpy.context.view_layer.objects.active = basemesh

    if basemesh.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True)

    armature_mod_obj = None
    for mod in list(basemesh.modifiers):
        if mod.type == "ARMATURE":
            armature_mod_obj = mod.object
            basemesh.modifiers.remove(mod)
        else:
            bpy.ops.object.modifier_apply(modifier=mod.name)

    mod = basemesh.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = decimate_ratio
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f"    Decimated body: {len(basemesh.data.polygons)} faces")

    arm_mod = basemesh.modifiers.new("Armature", "ARMATURE")
    if armature_mod_obj:
        arm_mod.object = armature_mod_obj
    else:
        for obj in bpy.data.objects:
            if obj.type == "ARMATURE":
                arm_mod.object = obj
                break
    print(f"    Armature modifier: {arm_mod.object.name if arm_mod.object else 'None'}")


def main():
    args = parse_args()
    blueprint = load_blueprint(args.blueprint)
    name = blueprint["name"]
    body = blueprint["body"]

    # Resolve paths
    mhm_path = os.path.join(PROJECT_ROOT, body["mhm_file"])
    output_path = args.output or os.path.join(
        PROJECT_ROOT, "blender", "models", f"{name}.blend"
    )

    print(f"=== Create Unit: {name} ===")
    print(f"  Blueprint: {args.blueprint}")
    print(f"  MHM: {mhm_path}")
    print(f"  Output: {output_path}")

    # Clear scene
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    # 1. Load MakeHuman base model with rig
    decimate_ratio = body.get("decimate_ratio", 0.25)
    basemesh, armature = load_makehuman_base(mhm_path, decimate_ratio)
    if not armature:
        print("ERROR: No armature found. Cannot create animations.",
              file=sys.stderr)
        sys.exit(1)

    # 2. Clean up mesh
    print("  Cleaning up mesh...")
    cleanup_mesh(basemesh, decimate_ratio)

    # 3. Add equipment from blueprint
    print("  Adding equipment...")
    equipment_list = blueprint["equipment"]
    tabard_config = blueprint.get("tabard")
    created = create_equipment(armature, basemesh, equipment_list, tabard_config)
    print(f"    Added: {', '.join(obj.name for obj in created)}")

    # 4. Create animations from blueprint
    anim_config = blueprint["animations"]
    template = anim_config["template"]
    frame_counts = anim_config["frame_counts"]
    print("  Creating animations...")
    actions = create_animations(armature, template=template, frame_counts=frame_counts)
    for anim_name, action in actions.items():
        print(f"    {anim_name}: {frame_counts.get(anim_name, '?')} frames")

    # 5. Save .blend file
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=output_path)
    print(f"  Saved: {output_path}")

    file_size = os.path.getsize(output_path)
    print(f"  Size: {file_size / 1024 / 1024:.1f} MB")
    print(f"  Actions: {', '.join(actions.keys())}")
    print(f"=== Done: {name} ===")


if __name__ == "__main__":
    main()
