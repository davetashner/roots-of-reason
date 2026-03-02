"""Shared material creation for equipment."""

import bpy

# Blender 5.x always has use_nodes enabled
_NEEDS_USE_NODES = bpy.app.version < (5, 0, 0)


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


def create_player_color_material(name="PlayerColor"):
    """Create a magenta Principled BSDF material for player color tinting.

    Unlike create_magenta_material() which uses Emission (flat, no shading),
    this uses Principled BSDF so lighting creates brightness variation. The
    Godot player_color shader preserves luminance when tinting, so shading
    survives the magenta-to-player-color swap.

    The result: clothing that shows folds, shadows, and highlights instead
    of a flat-colored blob.
    """
    mat = bpy.data.materials.new(name)
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (1.0, 0.0, 1.0, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.8  # Matte look
    return mat


def create_colored_material(name, rgba):
    """Create a Principled BSDF material with a solid base color.

    Args:
        name: Material name.
        rgba: Tuple of (r, g, b, a) in 0-1 range.

    Returns:
        bpy.types.Material
    """
    mat = bpy.data.materials.new(name)
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
    return mat
