#!/usr/bin/env python3
"""Create an archer unit model from MakeHuman base via MPFB2.

Loads the archer .mhm file, adds a game_engine rig, adds archer equipment
(bow, quiver, magenta tabard), creates animation Actions (idle, walk, attack,
death), and saves as a self-contained .blend file.

Usage:
    blender --background --python blender/create_archer.py
"""

import math
import os
import sys

try:
    import bpy
    import mathutils
except ImportError:
    print("ERROR: Must run inside Blender.", file=sys.stderr)
    sys.exit(1)

# Enable MPFB2 extension
bpy.ops.preferences.addon_enable(module="bl_ext.blender_org.mpfb")
from bl_ext.blender_org.mpfb.services.humanservice import HumanService  # noqa: E402

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MHM_PATH = os.path.join(PROJECT_ROOT, "assets", "archer_arms_down.mhm")
OUTPUT_PATH = os.path.join(PROJECT_ROOT, "blender", "models", "archer.blend")

# Blender 5.x always has use_nodes enabled
_NEEDS_USE_NODES = bpy.app.version < (5, 0, 0)

# Animation frame counts (must match asset_config.json)
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
    # Remove non-essential meshes (invisible at 128px isometric)
    to_remove = []
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            continue
        if obj == basemesh:
            continue
        name_lower = obj.name.lower()
        # Keep hair, remove eyes/teeth/eyebrows/tongue/eyelashes
        if any(x in name_lower for x in ["eye", "teeth", "tooth", "tongue",
                                          "eyebrow", "eyelash", "cube"]):
            to_remove.append(obj)

    for obj in to_remove:
        print(f"    Removing: {obj.name}")
        bpy.data.objects.remove(obj, do_unlink=True)

    # Decimate body mesh for faster rendering
    bpy.context.view_layer.objects.active = basemesh

    # Remove shape keys first (blocks modifier apply)
    if basemesh.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True)

    # Apply non-armature modifiers, preserve armature modifier
    armature_mod_obj = None
    for mod in list(basemesh.modifiers):
        if mod.type == "ARMATURE":
            armature_mod_obj = mod.object
            basemesh.modifiers.remove(mod)
        else:
            bpy.ops.object.modifier_apply(modifier=mod.name)

    # Decimate
    mod = basemesh.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = 0.25  # ~19K → ~4.7K faces
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f"    Decimated body: {len(basemesh.data.polygons)} faces")

    # Re-add armature modifier so mesh deforms with the rig
    arm_mod = basemesh.modifiers.new("Armature", "ARMATURE")
    if armature_mod_obj:
        arm_mod.object = armature_mod_obj
    else:
        # Find the armature object
        for obj in bpy.data.objects:
            if obj.type == "ARMATURE":
                arm_mod.object = obj
                break
    print(f"    Armature modifier: {arm_mod.object.name if arm_mod.object else 'None'}")


def create_magenta_material():
    """Create an Emission material that outputs pure #FF00FF magenta."""
    mat = bpy.data.materials.new("MagentaMask")
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    for node in nodes:
        nodes.remove(node)

    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1.0, 0.0, 1.0, 1.0)
    emission.inputs["Strength"].default_value = 1.0

    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(emission.outputs["Emission"], output.inputs["Surface"])

    return mat


def create_bow(armature):
    """Create a simple bow mesh parented to the left hand bone."""
    # Create bow arc from a bezier curve converted to mesh
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.035,
        minor_radius=0.003,
        major_segments=16,
        minor_segments=6,
        location=(0, 0, 0),
    )
    bow = bpy.context.active_object
    bow.name = "ArcherBow"

    # Scale to a bow shape — elongate vertically, flatten
    bow.scale = (0.3, 0.3, 3.0)
    bpy.ops.object.transform_apply(scale=True)

    # Delete the back half to make a D-shape
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")

    # Select vertices on the back side (negative X in local space)
    mesh = bow.data
    for v in mesh.vertices:
        if v.co.x < -0.005:
            v.select = True

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")

    # Add bowstring (thin cylinder connecting endpoints)
    # Get top and bottom of remaining bow
    verts = [v.co.copy() for v in bow.data.vertices]
    if verts:
        top_z = max(v.z for v in verts)
        bot_z = min(v.z for v in verts)
        mid_z = (top_z + bot_z) / 2
        string_len = top_z - bot_z

        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.001,
            depth=string_len,
            location=(bow.location.x, bow.location.y, bow.location.z + mid_z),
        )
        string = bpy.context.active_object
        string.name = "BowString"
        string.parent = bow

    # Brown material for bow
    mat = bpy.data.materials.new("BowMaterial")
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.35, 0.2, 0.08, 1.0)
    bow.data.materials.append(mat)

    # Parent to armature with bone constraint
    bow.parent = armature
    bow.parent_type = "BONE"
    bow.parent_bone = "hand_l"

    return bow


def create_quiver(armature):
    """Create a quiver with arrows on the back."""
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.015,
        depth=0.12,
        location=(0, 0, 0),
    )
    quiver = bpy.context.active_object
    quiver.name = "ArcherQuiver"

    # Brown leather material
    mat = bpy.data.materials.new("QuiverMaterial")
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.4, 0.25, 0.1, 1.0)
    quiver.data.materials.append(mat)

    # Add arrow shafts poking out the top
    for i in range(3):
        offset_x = (i - 1) * 0.005
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.002,
            depth=0.05,
            location=(offset_x, 0, 0.08),
        )
        arrow = bpy.context.active_object
        arrow.name = f"Arrow_{i}"
        arrow.parent = quiver

        # Arrow fletching (small cone at top)
        bpy.ops.mesh.primitive_cone_add(
            radius1=0.004,
            depth=0.01,
            location=(offset_x, 0, 0.105),
        )
        fletch = bpy.context.active_object
        fletch.name = f"ArrowFletch_{i}"
        fletch.parent = quiver

    # Parent to spine bone on back
    quiver.parent = armature
    quiver.parent_type = "BONE"
    quiver.parent_bone = "spine_02"
    # Offset behind the back
    quiver.location = (0.03, -0.03, 0)
    quiver.rotation_euler = (math.radians(10), 0, 0)

    return quiver


def create_tabard(basemesh, armature):
    """Create a magenta tabard/sash over the torso for player color mask."""
    magenta = create_magenta_material()

    # Create a simple box covering the torso area
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    tabard = bpy.context.active_object
    tabard.name = "ArcherTabard"

    # Scale to a visible vest/tabard on the torso
    # Model is ~1.7 units tall, torso spans roughly Z 0.7–1.2
    tabard.scale = (0.22, 0.12, 0.25)
    tabard.location = (0, 0.01, 0.0)
    bpy.ops.object.transform_apply(scale=True)

    # Apply magenta material
    tabard.data.materials.append(magenta)

    # Parent to armature with bone
    tabard.parent = armature
    tabard.parent_type = "BONE"
    tabard.parent_bone = "spine_02"

    return tabard


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

def get_bone_pose(armature, bone_name):
    """Get a pose bone by name, or None if not found."""
    return armature.pose.bones.get(bone_name)


def reset_pose(armature):
    """Reset all pose bones to rest position."""
    for pb in armature.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def keyframe_all_bones(armature, frame):
    """Insert a keyframe for all pose bones at the given frame."""
    for pb in armature.pose.bones:
        pb.keyframe_insert(data_path="location", frame=frame)
        pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def create_idle_action(armature):
    """Create idle animation: subtle breathing/sway."""
    action = bpy.data.actions.new("idle")
    armature.animation_data_create()
    armature.animation_data.action = action

    n_frames = ANIM_FRAMES["idle"]
    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1  # 1-indexed Blender frames

        reset_pose(armature)

        # Subtle spine sway
        spine = get_bone_pose(armature, "spine_02")
        if spine:
            sway = math.sin(t * 2 * math.pi) * math.radians(2)
            spine.rotation_euler = (0, sway, 0)

        # Slight head tilt
        head = get_bone_pose(armature, "head")
        if head:
            tilt = math.sin(t * 2 * math.pi + 0.5) * math.radians(1.5)
            head.rotation_euler = (tilt, 0, 0)

        # Breathing — chest expansion
        spine3 = get_bone_pose(armature, "spine_03")
        if spine3:
            breathe = math.sin(t * 2 * math.pi) * 0.003
            spine3.location = (0, breathe, 0)

        keyframe_all_bones(armature, frame)

    return action


def create_walk_action(armature):
    """Create walk cycle animation."""
    action = bpy.data.actions.new("walk")
    armature.animation_data.action = action

    n_frames = ANIM_FRAMES["walk"]
    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        # Leg swing (thighs rotate forward/backward alternately)
        swing_angle = math.radians(25)
        thigh_l = get_bone_pose(armature, "thigh_l")
        thigh_r = get_bone_pose(armature, "thigh_r")
        if thigh_l:
            thigh_l.rotation_euler.x = math.sin(t * 2 * math.pi) * swing_angle
        if thigh_r:
            thigh_r.rotation_euler.x = math.sin(t * 2 * math.pi + math.pi) * swing_angle

        # Knee bend (calves bend when leg is behind)
        calf_l = get_bone_pose(armature, "calf_l")
        calf_r = get_bone_pose(armature, "calf_r")
        if calf_l:
            bend = max(0, math.sin(t * 2 * math.pi + math.pi * 0.5)) * math.radians(30)
            calf_l.rotation_euler.x = bend
        if calf_r:
            bend = max(0, math.sin(t * 2 * math.pi + math.pi * 1.5)) * math.radians(30)
            calf_r.rotation_euler.x = bend

        # Counter-swing arms (opposite to legs)
        upperarm_l = get_bone_pose(armature, "upperarm_l")
        upperarm_r = get_bone_pose(armature, "upperarm_r")
        arm_swing = math.radians(15)
        if upperarm_l:
            upperarm_l.rotation_euler.x = math.sin(t * 2 * math.pi + math.pi) * arm_swing
        if upperarm_r:
            upperarm_r.rotation_euler.x = math.sin(t * 2 * math.pi) * arm_swing

        # Body bob
        root = get_bone_pose(armature, "Root")
        if root:
            bob = abs(math.sin(t * 2 * math.pi)) * 0.005
            root.location.z = bob

        # Slight torso lean forward
        spine01 = get_bone_pose(armature, "spine_01")
        if spine01:
            spine01.rotation_euler.x = math.radians(3)

        keyframe_all_bones(armature, frame)

    return action


def create_attack_action(armature):
    """Create bow draw + release animation."""
    action = bpy.data.actions.new("attack")
    armature.animation_data.action = action

    n_frames = ANIM_FRAMES["attack"]
    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        if t < 0.5:
            # Draw phase: raise bow arm, pull string arm back
            pull = t * 2  # 0→1 over first half

            # Left arm (bow arm) raises and extends
            upperarm_l = get_bone_pose(armature, "upperarm_l")
            if upperarm_l:
                upperarm_l.rotation_euler.x = math.radians(-70 * pull)
                upperarm_l.rotation_euler.z = math.radians(20 * pull)

            lowerarm_l = get_bone_pose(armature, "lowerarm_l")
            if lowerarm_l:
                lowerarm_l.rotation_euler.x = math.radians(-10 * pull)

            # Right arm (string arm) pulls back
            upperarm_r = get_bone_pose(armature, "upperarm_r")
            if upperarm_r:
                upperarm_r.rotation_euler.x = math.radians(-60 * pull)
                upperarm_r.rotation_euler.z = math.radians(-30 * pull)

            lowerarm_r = get_bone_pose(armature, "lowerarm_r")
            if lowerarm_r:
                lowerarm_r.rotation_euler.x = math.radians(-80 * pull)

            # Lean back slightly during draw
            spine02 = get_bone_pose(armature, "spine_02")
            if spine02:
                spine02.rotation_euler.x = math.radians(-5 * pull)

        else:
            # Release phase: snap forward
            release = (t - 0.5) * 2  # 0→1 over second half

            # Bow arm stays up but relaxes
            upperarm_l = get_bone_pose(armature, "upperarm_l")
            if upperarm_l:
                upperarm_l.rotation_euler.x = math.radians(-70 * (1 - release * 0.5))
                upperarm_l.rotation_euler.z = math.radians(20 * (1 - release * 0.3))

            # String arm snaps forward then relaxes
            upperarm_r = get_bone_pose(armature, "upperarm_r")
            if upperarm_r:
                upperarm_r.rotation_euler.x = math.radians(-60 * (1 - release))
                upperarm_r.rotation_euler.z = math.radians(-30 * (1 - release))

            lowerarm_r = get_bone_pose(armature, "lowerarm_r")
            if lowerarm_r:
                lowerarm_r.rotation_euler.x = math.radians(-80 * (1 - release))

            # Lean forward on release
            spine02 = get_bone_pose(armature, "spine_02")
            if spine02:
                spine02.rotation_euler.x = math.radians(3 * release * (1 - release) * 4)

        keyframe_all_bones(armature, frame)

    return action


def create_death_action(armature):
    """Create death animation: hit reaction and fall."""
    action = bpy.data.actions.new("death")
    armature.animation_data.action = action

    n_frames = ANIM_FRAMES["death"]
    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        # Hit reaction then fall backward
        root = get_bone_pose(armature, "Root")
        if root:
            # Stagger back and fall
            fall_angle = t * math.radians(75)
            root.rotation_euler.x = -fall_angle
            root.location.z = -t * 0.05

        # Head snaps back
        head = get_bone_pose(armature, "head")
        if head:
            head.rotation_euler.x = -t * math.radians(30)

        # Arms go limp
        for side in ["_l", "_r"]:
            upperarm = get_bone_pose(armature, f"upperarm{side}")
            if upperarm:
                # Arms spread and drop
                spread = math.radians(20 * t)
                upperarm.rotation_euler.x = math.radians(-10 * t)
                upperarm.rotation_euler.z = spread if side == "_l" else -spread

            lowerarm = get_bone_pose(armature, f"lowerarm{side}")
            if lowerarm:
                lowerarm.rotation_euler.x = math.radians(20 * t)

        # Knees buckle
        calf_l = get_bone_pose(armature, "calf_l")
        calf_r = get_bone_pose(armature, "calf_r")
        if calf_l:
            calf_l.rotation_euler.x = math.radians(30 * t)
        if calf_r:
            calf_r.rotation_euler.x = math.radians(25 * t)

        keyframe_all_bones(armature, frame)

    return action


def create_all_animations(armature):
    """Create all animation Actions on the armature."""
    print("  Creating animations...")

    # Ensure pose mode is accessible
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")

    actions = {}
    actions["idle"] = create_idle_action(armature)
    print(f"    idle: {ANIM_FRAMES['idle']} frames")

    actions["walk"] = create_walk_action(armature)
    print(f"    walk: {ANIM_FRAMES['walk']} frames")

    actions["attack"] = create_attack_action(armature)
    print(f"    attack: {ANIM_FRAMES['attack']} frames")

    actions["death"] = create_death_action(armature)
    print(f"    death: {ANIM_FRAMES['death']} frames")

    bpy.ops.object.mode_set(mode="OBJECT")

    # Mark all actions as "fake user" so they persist in the .blend file
    for name, action in actions.items():
        action.use_fake_user = True

    return actions


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

    # 3. Add archer equipment
    print("  Adding archer equipment...")
    bow = create_bow(armature)
    quiver = create_quiver(armature)
    tabard = create_tabard(basemesh, armature)
    print(f"    Added: {bow.name}, {quiver.name}, {tabard.name}")

    # 4. Create animations
    actions = create_all_animations(armature)

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
