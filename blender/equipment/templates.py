"""Equipment template functions for geometric unit accessories.

Each template function creates a Blender mesh, applies materials, and parents
it to the specified bone on the armature.
"""

import math

import bpy

from blender.equipment.materials import create_colored_material

# Blender 5.x always has use_nodes enabled
_NEEDS_USE_NODES = bpy.app.version < (5, 0, 0)


def create_bow(armature, parent_bone="hand_l", **_kwargs):
    """Create a simple bow mesh parented to a hand bone."""
    # Bow arc from a torus
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.035,
        minor_radius=0.003,
        major_segments=16,
        minor_segments=6,
        location=(0, 0, 0),
    )
    bow = bpy.context.active_object
    bow.name = "Bow"

    bow.scale = (0.3, 0.3, 3.0)
    bpy.ops.object.transform_apply(scale=True)

    # Delete the back half to make a D-shape
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh = bow.data
    for v in mesh.vertices:
        if v.co.x < -0.005:
            v.select = True

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")

    # Add bowstring
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

    mat = create_colored_material("BowMaterial", (0.35, 0.2, 0.08, 1.0))
    bow.data.materials.append(mat)

    bow.parent = armature
    bow.parent_type = "BONE"
    bow.parent_bone = parent_bone

    return bow


def create_quiver(
    armature,
    parent_bone="spine_02",
    location=None,
    rotation=None,
    **_kwargs,
):
    """Create a quiver with arrows on the back."""
    location = tuple(location) if location else (0.03, -0.03, 0)
    rotation = tuple(rotation) if rotation else (math.radians(10), 0, 0)

    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.015,
        depth=0.12,
        location=(0, 0, 0),
    )
    quiver = bpy.context.active_object
    quiver.name = "Quiver"

    mat = create_colored_material("QuiverMaterial", (0.4, 0.25, 0.1, 1.0))
    quiver.data.materials.append(mat)

    # Arrow shafts poking out the top
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

        bpy.ops.mesh.primitive_cone_add(
            radius1=0.004,
            depth=0.01,
            location=(offset_x, 0, 0.105),
        )
        fletch = bpy.context.active_object
        fletch.name = f"ArrowFletch_{i}"
        fletch.parent = quiver

    quiver.parent = armature
    quiver.parent_type = "BONE"
    quiver.parent_bone = parent_bone
    quiver.location = location
    quiver.rotation_euler = rotation

    return quiver


def create_sword(armature, parent_bone="hand_r", **_kwargs):
    """Create a simple sword mesh parented to a hand bone."""
    # Blade
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    sword = bpy.context.active_object
    sword.name = "Sword"
    sword.scale = (0.008, 0.003, 0.12)
    bpy.ops.object.transform_apply(scale=True)

    blade_mat = create_colored_material("BladeMaterial", (0.7, 0.7, 0.75, 1.0))
    sword.data.materials.append(blade_mat)

    # Crossguard
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.06))
    guard = bpy.context.active_object
    guard.name = "SwordGuard"
    guard.scale = (0.02, 0.005, 0.005)
    bpy.ops.object.transform_apply(scale=True)
    guard_mat = create_colored_material("GuardMaterial", (0.3, 0.25, 0.1, 1.0))
    guard.data.materials.append(guard_mat)
    guard.parent = sword

    # Handle
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.005,
        depth=0.04,
        location=(0, 0, -0.08),
    )
    handle = bpy.context.active_object
    handle.name = "SwordHandle"
    handle_mat = create_colored_material("HandleMaterial", (0.25, 0.15, 0.05, 1.0))
    handle.data.materials.append(handle_mat)
    handle.parent = sword

    sword.parent = armature
    sword.parent_type = "BONE"
    sword.parent_bone = parent_bone

    return sword


def create_shield(
    armature,
    parent_bone="hand_l",
    location=None,
    **_kwargs,
):
    """Create a simple round shield parented to a hand bone."""
    location = tuple(location) if location else (0, 0, 0)

    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.06,
        depth=0.008,
        location=(0, 0, 0),
    )
    shield = bpy.context.active_object
    shield.name = "Shield"

    shield_mat = create_colored_material("ShieldMaterial", (0.3, 0.2, 0.08, 1.0))
    shield.data.materials.append(shield_mat)

    # Shield boss (center bump)
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.015,
        location=(0, 0, 0.008),
    )
    boss = bpy.context.active_object
    boss.name = "ShieldBoss"
    boss_mat = create_colored_material("BossMaterial", (0.6, 0.6, 0.65, 1.0))
    boss.data.materials.append(boss_mat)
    boss.parent = shield

    shield.parent = armature
    shield.parent_type = "BONE"
    shield.parent_bone = parent_bone
    shield.location = location

    return shield


def create_spear(armature, parent_bone="hand_r", **_kwargs):
    """Create a simple spear mesh parented to a hand bone."""
    # Shaft
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.004,
        depth=0.3,
        location=(0, 0, 0),
    )
    spear = bpy.context.active_object
    spear.name = "Spear"

    shaft_mat = create_colored_material("ShaftMaterial", (0.35, 0.2, 0.08, 1.0))
    spear.data.materials.append(shaft_mat)

    # Spearhead
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.01,
        depth=0.03,
        location=(0, 0, 0.165),
    )
    head = bpy.context.active_object
    head.name = "SpearHead"
    head_mat = create_colored_material("SpearHeadMaterial", (0.7, 0.7, 0.75, 1.0))
    head.data.materials.append(head_mat)
    head.parent = spear

    spear.parent = armature
    spear.parent_type = "BONE"
    spear.parent_bone = parent_bone

    return spear


# Registry of all equipment template functions
EQUIPMENT_TEMPLATES = {
    "bow": create_bow,
    "quiver": create_quiver,
    "sword": create_sword,
    "shield": create_shield,
    "spear": create_spear,
}
