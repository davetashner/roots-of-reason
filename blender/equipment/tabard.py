"""Tabard (player color mask) creation for units."""

import bpy

from blender.equipment.materials import create_magenta_material


def create_tabard(
    basemesh,
    armature,
    parent_bone="spine_02",
    scale=None,
    location=None,
    **_kwargs,
):
    """Create a magenta tabard/sash over the torso for player color mask.

    Args:
        basemesh: Blender mesh object (body). Unused but kept for API consistency.
        armature: Blender armature object.
        parent_bone: Bone to parent the tabard to.
        scale: Tabard scale as [x, y, z]. Defaults to [0.22, 0.12, 0.25].
        location: Tabard location offset as [x, y, z]. Defaults to [0, 0.01, 0].

    Returns:
        Blender object for the tabard.
    """
    magenta = create_magenta_material()

    scale = tuple(scale) if scale else (0.22, 0.12, 0.25)
    location = tuple(location) if location else (0, 0.01, 0.0)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    tabard = bpy.context.active_object
    tabard.name = "Tabard"

    tabard.scale = scale
    tabard.location = location
    bpy.ops.object.transform_apply(scale=True)

    tabard.data.materials.append(magenta)

    tabard.parent = armature
    tabard.parent_type = "BONE"
    tabard.parent_bone = parent_bone

    return tabard
