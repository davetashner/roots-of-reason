#!/usr/bin/env python3
"""Blender isometric render template for Roots of Reason.

Renders isometric sprites headlessly via Blender's Python API.
Produces 2x resolution PNGs (downscaling handled by process_sprite.py).

Usage (called via Blender):
    blender --background --python blender/render_isometric.py -- [options]

Or via the CLI wrapper:
    ./tools/ror blender-render --poc
"""

import argparse
import math
import os
import sys

# Blender's bpy is only available when run inside Blender
try:
    import bpy  # type: ignore[import-not-found]
    import mathutils  # type: ignore[import-not-found]
except ImportError:
    print("ERROR: This script must be run inside Blender.", file=sys.stderr)
    print("  blender --background --python blender/render_isometric.py -- [opts]",
          file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# 2x canvas sizes by footprint (rendered at 2x, downscaled by process_sprite)
CANVAS_2X = {
    1: (256, 256),
    2: (512, 384),
    3: (768, 512),
    4: (1024, 640),
    5: (1280, 768),
}

# 8 direction azimuths (degrees, clockwise from camera's perspective)
# S is the default "front" view for isometric sprites
DIRECTIONS = {
    "s":  0,
    "sw": 45,
    "w":  90,
    "nw": 135,
    "n":  180,
    "ne": 225,
    "e":  270,
    "se": 315,
}

# Blender 5.x always has use_nodes enabled; setting it raises DeprecationWarning
_NEEDS_USE_NODES = bpy.app.version < (5, 0, 0)

# Isometric elevation: arctan(1/sqrt(2)) ≈ 35.264° from horizontal = 54.736° from vertical
ELEVATION_DEG = 35.264

# Ortho scale per footprint (tuned to fill ~80-90% of canvas)
ORTHO_SCALE = {
    1: 3.0,
    2: 5.5,
    3: 8.0,
    4: 10.5,
    5: 13.0,
}


# ---------------------------------------------------------------------------
# Scene setup
# ---------------------------------------------------------------------------

def clear_scene():
    """Remove all default objects from the scene."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    # Also remove orphan data
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)
    for block in bpy.data.lights:
        if block.users == 0:
            bpy.data.lights.remove(block)
    for block in bpy.data.cameras:
        if block.users == 0:
            bpy.data.cameras.remove(block)


def setup_camera(azimuth_deg, footprint):
    """Create an orthographic camera at isometric angle."""
    cam_data = bpy.data.cameras.new("IsoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ORTHO_SCALE[footprint]

    cam_obj = bpy.data.objects.new("IsoCam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj

    _position_camera(cam_obj, azimuth_deg)
    return cam_obj


def _position_camera(cam_obj, azimuth_deg):
    """Position camera at given azimuth, isometric elevation."""
    distance = 20.0
    elev_rad = math.radians(ELEVATION_DEG)
    az_rad = math.radians(azimuth_deg)

    x = distance * math.cos(elev_rad) * math.sin(az_rad)
    y = -distance * math.cos(elev_rad) * math.cos(az_rad)
    z = distance * math.sin(elev_rad)

    cam_obj.location = (x, y, z)

    # Point camera at origin
    direction = mathutils.Vector((0, 0, 0)) - cam_obj.location
    rot_quat = direction.to_track_quat("-Z", "Y")
    cam_obj.rotation_euler = rot_quat.to_euler()


def setup_lighting():
    """Create key + fill lighting rig."""
    # Key light — Sun from NW above
    key_data = bpy.data.lights.new("KeyLight", "SUN")
    key_data.energy = 3.0
    key_obj = bpy.data.objects.new("KeyLight", key_data)
    bpy.context.scene.collection.objects.link(key_obj)
    key_obj.rotation_euler = (math.radians(45), 0, math.radians(-135))

    # Fill light — Sun from SE, softer
    fill_data = bpy.data.lights.new("FillLight", "SUN")
    fill_data.energy = 1.2
    fill_obj = bpy.data.objects.new("FillLight", fill_data)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(60), 0, math.radians(45))

    # Dark ambient via world
    world = bpy.data.worlds.get("World")
    if world is None:
        world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    if _NEEDS_USE_NODES:
        world.use_nodes = True
    bg_node = world.node_tree.nodes.get("Background")
    if bg_node:
        bg_node.inputs["Color"].default_value = (0.02, 0.02, 0.02, 1.0)
        bg_node.inputs["Strength"].default_value = 0.3


# ---------------------------------------------------------------------------
# Render config
# ---------------------------------------------------------------------------

def setup_render(footprint):
    """Configure render settings for transparent isometric output."""
    scene = bpy.context.scene
    render = scene.render

    # Engine — try EEVEE_NEXT (Blender 4.x) then EEVEE (Blender 5.x)
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"

    # Resolution at 2x canvas
    w, h = CANVAS_2X[footprint]
    render.resolution_x = w
    render.resolution_y = h
    render.resolution_percentage = 100

    # Transparent background
    render.film_transparent = True

    # Output format
    render.image_settings.file_format = "PNG"
    render.image_settings.color_mode = "RGBA"
    render.image_settings.color_depth = "8"
    render.image_settings.compression = 15

    # Color management — Standard to avoid alpha artifacts
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


# ---------------------------------------------------------------------------
# PoC house model
# ---------------------------------------------------------------------------

def _create_magenta_material():
    """Create an Emission material that outputs pure #FF00FF magenta.

    Uses Emission shader to bypass color management tone-mapping,
    ensuring the magenta player-color mask survives the render pipeline.
    """
    mat = bpy.data.materials.new("MagentaMask")
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    # Clear defaults
    for node in nodes:
        nodes.remove(node)

    # Emission at (1, 0, 1) = magenta
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1.0, 0.0, 1.0, 1.0)
    emission.inputs["Strength"].default_value = 1.0

    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(emission.outputs["Emission"], output.inputs["Surface"])

    return mat


def _create_wall_material():
    """Simple diffuse material for house walls."""
    mat = bpy.data.materials.new("HouseWall")
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.6, 0.5, 0.35, 1.0)
    return mat


def _create_roof_material():
    """Simple diffuse material for house roof."""
    mat = bpy.data.materials.new("HouseRoof")
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.7, 0.2, 0.15, 1.0)
    return mat


def build_poc_house():
    """Build a proof-of-concept house: box body + prism roof + magenta door.

    Returns list of created objects.
    """
    objects = []
    wall_mat = _create_wall_material()
    roof_mat = _create_roof_material()
    magenta_mat = _create_magenta_material()

    # Body — cube scaled to house shape
    bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0.8))
    body = bpy.context.active_object
    body.name = "HouseBody"
    body.scale = (1.2, 0.9, 0.8)
    bpy.ops.object.transform_apply(scale=True)
    body.data.materials.append(wall_mat)
    objects.append(body)

    # Roof — scaled cube rotated 45° around X to form a prism-like shape
    bpy.ops.mesh.primitive_cone_add(
        vertices=4, radius1=1.5, depth=1.0, location=(0, 0, 2.1)
    )
    roof = bpy.context.active_object
    roof.name = "HouseRoof"
    roof.scale = (1.3, 1.0, 0.6)
    roof.rotation_euler = (0, 0, math.radians(45))
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    roof.data.materials.append(roof_mat)
    objects.append(roof)

    # Door — small box on front face with magenta mask
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.91, 0.35))
    door = bpy.context.active_object
    door.name = "HouseDoor"
    door.scale = (0.3, 0.02, 0.45)
    bpy.ops.object.transform_apply(scale=True)
    door.data.materials.append(magenta_mat)
    objects.append(door)

    return objects


# ---------------------------------------------------------------------------
# Render loop
# ---------------------------------------------------------------------------

def render_directions(cam_obj, directions, output_dir, subject):
    """Render the scene from each specified direction."""
    os.makedirs(output_dir, exist_ok=True)

    for dir_name in directions:
        azimuth = DIRECTIONS[dir_name]
        _position_camera(cam_obj, azimuth)

        filepath = os.path.join(output_dir, f"{subject}_{dir_name}.png")
        bpy.context.scene.render.filepath = filepath
        bpy.ops.render.render(write_still=True)
        print(f"  Rendered: {filepath}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args():
    """Parse arguments after Blender's -- separator."""
    # Blender passes everything after '--' to the script
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    parser = argparse.ArgumentParser(
        description="Render isometric sprites from Blender"
    )
    parser.add_argument(
        "subject", nargs="?", default="poc_house",
        help="Name of the subject to render (default: poc_house)"
    )
    parser.add_argument(
        "--footprint", type=int, default=2, choices=[1, 2, 3, 4, 5],
        help="Building footprint size (default: 2)"
    )
    parser.add_argument(
        "--type", choices=["building", "unit"], default="building",
        help="Asset type (default: building)"
    )
    parser.add_argument(
        "--directions", nargs="+", default=["s"],
        choices=list(DIRECTIONS.keys()),
        help="Directions to render (default: s)"
    )
    parser.add_argument(
        "--output-dir", default=None,
        help="Output directory (default: blender/renders/<subject>)"
    )
    parser.add_argument(
        "--poc", action="store_true",
        help="Render the proof-of-concept house"
    )
    parser.add_argument(
        "--blend-file", default=None,
        help="Path to a .blend file to load instead of building procedurally"
    )

    return parser.parse_args(argv)


def main():
    args = parse_args()

    # Determine project root (script is at <project>/blender/render_isometric.py)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    if args.poc:
        args.subject = "poc_house"
        args.footprint = 2
        args.directions = list(DIRECTIONS.keys())

    output_dir = args.output_dir or os.path.join(
        project_root, "blender", "renders", args.subject
    )

    print(f"=== Blender Isometric Render ===")
    print(f"  Subject:    {args.subject}")
    print(f"  Footprint:  {args.footprint}")
    print(f"  Canvas 2x:  {CANVAS_2X[args.footprint]}")
    print(f"  Directions: {', '.join(args.directions)}")
    print(f"  Output:     {output_dir}")

    # Scene setup
    clear_scene()
    setup_lighting()
    cam = setup_camera(DIRECTIONS[args.directions[0]], args.footprint)
    setup_render(args.footprint)

    # Build or load model
    if args.blend_file:
        # Append all objects from the blend file's Scene collection
        with bpy.data.libraries.load(args.blend_file) as (data_from, data_to):
            data_to.objects = data_from.objects
        for obj in data_to.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
        print(f"  Loaded: {args.blend_file}")
    elif args.subject == "poc_house" or args.poc:
        build_poc_house()
        print("  Built PoC house model")
    else:
        # Try loading a .blend file from blender/models/
        blend_path = os.path.join(project_root, "blender", "models",
                                  f"{args.subject}.blend")
        if os.path.exists(blend_path):
            with bpy.data.libraries.load(blend_path) as (data_from, data_to):
                data_to.objects = data_from.objects
            for obj in data_to.objects:
                if obj is not None:
                    bpy.context.scene.collection.objects.link(obj)
            print(f"  Loaded: {blend_path}")
        else:
            print(f"  WARNING: No model found for '{args.subject}'")
            print(f"  Expected: {blend_path}")
            print(f"  Rendering empty scene.")

    # Render
    render_directions(cam, args.directions, output_dir, args.subject)
    print(f"=== Done: {len(args.directions)} direction(s) rendered ===")


if __name__ == "__main__":
    main()
