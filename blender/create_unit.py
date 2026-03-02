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
import math
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
from bl_ext.blender_org.mpfb.services.locationservice import LocationService  # noqa: E402


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


def load_makehuman_base(mhm_path, body_config):
    """Load the MakeHuman model with game_engine rig via MPFB2.

    Enables skin material, body parts (eyes), and optionally clothes/hair
    based on the blueprint's body config.
    """
    settings = HumanService.get_default_deserialization_settings()
    settings["override_rig"] = "game_engine"
    settings["subdiv_levels"] = 0
    settings["mask_helpers"] = True
    settings["detailed_helpers"] = False
    settings["clothes_deep_search"] = False
    settings["bodypart_deep_search"] = True
    # Enable clothes loading so hair/clothes defined in .mhm are loaded
    settings["load_clothes"] = True
    # Use GAMEENGINE skin model for better render performance
    settings["override_skin_model"] = "GAMEENGINE"

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


def get_bone_local_offset(basemesh, armature, bone_name):
    """Compute a bone-local offset to align equipment with the visible mesh.

    MPFB2's game_engine rig bones are often misaligned with the mesh.
    This finds the average world position of vertices weighted to a bone's
    vertex group, then transforms the offset into the bone's local space
    so that bone-parented objects appear at the correct mesh location.
    """
    import mathutils

    bone = armature.data.bones.get(bone_name)
    if not bone:
        return mathutils.Vector((0, 0, 0))

    bone_world = armature.matrix_world @ bone.head_local

    vg = basemesh.vertex_groups.get(bone_name)
    if not vg:
        return mathutils.Vector((0, 0, 0))

    vg_idx = vg.index
    positions = []
    for v in basemesh.data.vertices:
        for g in v.groups:
            if g.group == vg_idx and g.weight > 0.3:
                positions.append(basemesh.matrix_world @ v.co)
                break

    if not positions:
        return mathutils.Vector((0, 0, 0))

    avg = mathutils.Vector((0, 0, 0))
    for p in positions:
        avg += p
    avg /= len(positions)

    # World-space offset
    world_offset = avg - bone_world

    # Transform into the bone's local coordinate system
    # Bone-parented objects use the bone's matrix for their local space
    bone_matrix = armature.matrix_world @ bone.matrix_local
    bone_local_offset = bone_matrix.inverted().to_3x3() @ world_offset

    return bone_local_offset


def apply_skin(basemesh, skin_name):
    """Apply a named skin texture from MPFB2's skin library."""
    skins_dir = LocationService.get_mpfb_data("skins")
    mhmat_path = os.path.join(skins_dir, skin_name, f"{skin_name}.mhmat")

    if not os.path.exists(mhmat_path):
        print(f"    WARNING: Skin '{skin_name}' not found at {mhmat_path}")
        return

    HumanService.set_character_skin(
        mhmat_path, basemesh,
        skin_type="GAMEENGINE",
        material_instances=False,
    )
    print(f"    Applied skin: {skin_name}")


def load_hair(basemesh, hair_name):
    """Load a hair asset from MPFB2's hair library."""
    hair_dir = LocationService.get_mpfb_data("hair")
    mhclo_path = os.path.join(hair_dir, hair_name, f"{hair_name}.mhclo")

    if not os.path.exists(mhclo_path):
        print(f"    WARNING: Hair '{hair_name}' not found at {mhclo_path}")
        return

    HumanService.add_mhclo_asset(
        mhclo_path, basemesh,
        asset_type="hair",
        subdiv_levels=0,
        material_type="MAKESKIN",
    )
    print(f"    Applied hair: {hair_name}")


def create_loincloth(armature, basemesh):
    """Create a simple procedural loincloth/wrap for prehistoric units.

    Builds a flat rectangular cloth around the waist, bone-parented to the
    hip area. Uses magenta material for player color masking.
    """
    from blender.equipment.materials import create_colored_material

    # Find pelvis/hip bone position for placement
    pelvis_bone = armature.data.bones.get("pelvis")
    if not pelvis_bone:
        # Fallback: use spine bone
        pelvis_bone = armature.data.bones.get("spine")

    # Front panel — flat box at waist height
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    loincloth = bpy.context.active_object
    loincloth.name = "Loincloth"
    loincloth.scale = (0.14, 0.005, 0.10)
    bpy.ops.object.transform_apply(scale=True)

    # Leather/hide color
    cloth_mat = create_colored_material("LoinclothMaterial", (0.35, 0.22, 0.10, 1.0))
    loincloth.data.materials.append(cloth_mat)

    # Back panel
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    back_panel = bpy.context.active_object
    back_panel.name = "LoinclothBack"
    back_panel.scale = (0.12, 0.005, 0.08)
    bpy.ops.object.transform_apply(scale=True)
    back_panel.data.materials.append(cloth_mat)
    back_panel.location = (0, 0.04, 0)
    back_panel.parent = loincloth

    # Belt/cord
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.10,
        minor_radius=0.005,
        major_segments=16,
        minor_segments=4,
        location=(0, 0, 0.05),
    )
    belt = bpy.context.active_object
    belt.name = "LoinclothBelt"
    belt.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    cord_mat = create_colored_material("CordMaterial", (0.45, 0.30, 0.12, 1.0))
    belt.data.materials.append(cord_mat)
    belt.parent = loincloth

    # Parent to pelvis bone
    parent_bone = "pelvis" if armature.data.bones.get("pelvis") else "spine"
    loincloth.parent = armature
    loincloth.parent_type = "BONE"
    loincloth.parent_bone = parent_bone

    print(f"    Added loincloth (parented to {parent_bone})")
    return loincloth


def orient_hand_equipment(armature, basemesh, created_objects, blueprint):
    """Orient hand-held equipment and curl fingers into a grip pose.

    Rotates weapons parented to hand bones so they hang naturally,
    and poses finger bones to close around the grip.
    """
    # Find equipment attached to hand bones
    hand_bones = {"hand_r", "hand_l"}
    for obj in created_objects:
        if (obj.parent == armature and obj.parent_type == "BONE"
                and obj.parent_bone in hand_bones):
            # Rotate the weapon so it rests on the shoulder — club head
            # pointing up and behind. The bone's local Y axis points along
            # the finger direction.
            obj.rotation_euler = (
                math.radians(-110),  # tilt back past vertical
                math.radians(10),    # slight outward lean
                0,
            )
            print(f"    Oriented {obj.name} in {obj.parent_bone}")

    # Curl right-hand fingers into a grip
    grip_bones_r = [
        "index_01_r", "index_02_r", "index_03_r",
        "middle_01_r", "middle_02_r", "middle_03_r",
        "ring_01_r", "ring_02_r", "ring_03_r",
        "pinky_01_r", "pinky_02_r", "pinky_03_r",
    ]
    thumb_bones_r = ["thumb_01_r", "thumb_02_r", "thumb_03_r"]

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")

    for bone_name in grip_bones_r:
        pbone = armature.pose.bones.get(bone_name)
        if pbone:
            # Curl fingers inward (~70 degrees per joint)
            pbone.rotation_mode = "XYZ"
            pbone.rotation_euler = (math.radians(70), 0, 0)

    for bone_name in thumb_bones_r:
        pbone = armature.pose.bones.get(bone_name)
        if pbone:
            # Thumb wraps around (~45 degrees, different axis)
            pbone.rotation_mode = "XYZ"
            pbone.rotation_euler = (math.radians(30), 0, math.radians(-30))

    bpy.ops.object.mode_set(mode="OBJECT")
    print("    Posed right hand grip")


def cleanup_mesh(basemesh, decimate_ratio=0.25):
    """Clean up mesh while preserving facial features.

    Only removes truly invisible geometry (tongue, default cube).
    Keeps eyes, eyebrows, eyelashes, and teeth for visual detail.
    """
    to_remove = []
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            continue
        if obj == basemesh:
            continue
        name_lower = obj.name.lower()
        # Only remove truly invisible interior meshes and stray defaults
        if any(x in name_lower for x in ["tongue", "cube"]):
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
        elif mod.type == "MASK":
            # Keep the helper mask modifier — don't try to apply it
            continue
        else:
            try:
                bpy.ops.object.modifier_apply(modifier=mod.name)
            except RuntimeError as e:
                print(f"    WARNING: Could not apply modifier {mod.name}: {e}")

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
    basemesh, armature = load_makehuman_base(mhm_path, body)
    if not armature:
        print("ERROR: No armature found. Cannot create animations.",
              file=sys.stderr)
        sys.exit(1)

    # 2. Apply skin texture
    skin_name = body.get("skin", "young_caucasian_male")
    print("  Applying skin...")
    apply_skin(basemesh, skin_name)

    # 3. Load hair
    hair_name = body.get("hair")
    if hair_name:
        print("  Loading hair...")
        load_hair(basemesh, hair_name)

    # 4. Clean up mesh (preserving facial features)
    print("  Cleaning up mesh...")
    cleanup_mesh(basemesh, decimate_ratio)

    # 5. Add equipment from blueprint
    print("  Adding equipment...")
    equipment_list = blueprint["equipment"]
    tabard_config = blueprint.get("tabard")
    created = create_equipment(armature, basemesh, equipment_list, tabard_config)
    print(f"    Added: {', '.join(obj.name for obj in created)}")

    # 6. Add procedural clothing if specified
    clothing = body.get("clothing")
    if clothing:
        print("  Adding clothing...")
        if "loincloth" in clothing:
            loincloth = create_loincloth(armature, basemesh)
            created.append(loincloth)

    # 6b. Fix bone-mesh misalignment — MPFB2's game_engine rig bones
    # are often at different positions than the visible mesh vertices.
    # Compute the offset per bone and apply it to bone-parented objects.
    print("  Fixing bone-mesh alignment...")
    for obj in created:
        if obj.parent == armature and obj.parent_type == "BONE":
            offset = get_bone_local_offset(basemesh, armature, obj.parent_bone)
            if offset.length > 0.01:
                obj.location = obj.location + offset
                print(f"    {obj.name} -> offset {obj.parent_bone} by "
                      f"({offset.x:.3f}, {offset.y:.3f}, {offset.z:.3f})")

    # 6c. Orient hand-held equipment and pose grip fingers
    orient_hand_equipment(armature, basemesh, created, blueprint)

    # 7. Create animations from blueprint
    anim_config = blueprint["animations"]
    template = anim_config["template"]
    frame_counts = anim_config["frame_counts"]
    print("  Creating animations...")
    actions = create_animations(armature, template=template, frame_counts=frame_counts)
    for anim_name, action in actions.items():
        print(f"    {anim_name}: {frame_counts.get(anim_name, '?')} frames")

    # 8. Save .blend file
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=output_path)
    print(f"  Saved: {output_path}")

    file_size = os.path.getsize(output_path)
    print(f"  Size: {file_size / 1024 / 1024:.1f} MB")
    print(f"  Actions: {', '.join(actions.keys())}")
    print(f"=== Done: {name} ===")


if __name__ == "__main__":
    main()
