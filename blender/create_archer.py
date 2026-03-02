#!/usr/bin/env python3
"""Create an archer unit model from MakeHuman base via MPFB2.

Loads the archer .mhm file, adds a game_engine rig, adds archer equipment
(bow, quiver, magenta tabard), creates animation Actions (idle, walk, attack,
death), and saves as a self-contained .blend file.

This script now delegates to the reusable blender/animations/ and
blender/equipment/ libraries. It serves as a reference implementation
and will be superseded by the generic create_unit.py in Story 4.

Usage:
    blender --background --python blender/create_archer.py
"""

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

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MHM_PATH = os.path.join(PROJECT_ROOT, "assets", "archer_arms_down.mhm")
OUTPUT_PATH = os.path.join(PROJECT_ROOT, "blender", "models", "archer.blend")

ANIM_FRAMES = {
    "idle": 4,
    "walk": 8,
    "attack": 6,
    "death": 6,
}


# ---------------------------------------------------------------------------
# Model creation
# ---------------------------------------------------------------------------

def load_makehuman_base():
    """Load the MakeHuman model with game_engine rig via MPFB2."""
    settings = HumanService.get_default_deserialization_settings()
    settings["override_rig"] = "game_engine"
    settings["subdiv_levels"] = 0
    settings["load_clothes"] = False
    settings["mask_helpers"] = False
    settings["detailed_helpers"] = False
    settings["clothes_deep_search"] = False
    settings["bodypart_deep_search"] = False

    basemesh = HumanService.deserialize_from_mhm(MHM_PATH, settings)
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


def cleanup_mesh(basemesh):
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
    mod.ratio = 0.25
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


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=== Create Archer Model ===")
    print(f"  MHM: {MHM_PATH}")
    print(f"  Output: {OUTPUT_PATH}")

    # Clear scene
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    # 1. Load MakeHuman base model with rig
    basemesh, armature = load_makehuman_base()
    if not armature:
        print("ERROR: No armature found. Cannot create animations.",
              file=sys.stderr)
        sys.exit(1)

    # 2. Clean up mesh
    print("  Cleaning up mesh...")
    cleanup_mesh(basemesh)

    # 3. Add archer equipment (using reusable equipment library)
    print("  Adding archer equipment...")
    import math
    equipment_list = [
        {"template": "bow", "parent_bone": "hand_l"},
        {"template": "quiver", "parent_bone": "spine_02",
         "location": (0.03, -0.03, 0),
         "rotation": (math.radians(10), 0, 0)},
    ]
    tabard_config = {
        "parent_bone": "spine_02",
        "scale": (0.22, 0.12, 0.25),
        "location": (0, 0.01, 0.0),
    }
    created = create_equipment(armature, basemesh, equipment_list, tabard_config)
    print(f"    Added: {', '.join(obj.name for obj in created)}")

    # 4. Create animations (using reusable animation library)
    print("  Creating animations...")
    actions = create_animations(armature, template="ranged", frame_counts=ANIM_FRAMES)
    for name, action in actions.items():
        print(f"    {name}: {ANIM_FRAMES[name]} frames")

    # 5. Save .blend file
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_PATH)
    print(f"  Saved: {OUTPUT_PATH}")

    file_size = os.path.getsize(OUTPUT_PATH)
    print(f"  Size: {file_size / 1024 / 1024:.1f} MB")
    print(f"  Actions: {', '.join(actions.keys())}")
    print("=== Done ===")


if __name__ == "__main__":
    main()
