#!/usr/bin/env python3
"""Blender isometric render template for Roots of Reason.

Renders isometric sprites headlessly via Blender's Python API.
Produces 2x resolution PNGs (downscaling handled by process_sprite.py).

Usage (called via Blender):
    blender --background --python blender/render_isometric.py -- [options]

Or via the CLI wrapper:
    ./tools/ror blender-render --poc
    ./tools/ror blender-archer
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

# 2x canvas for unit rendering (256x256 → downscaled to 128x128)
UNIT_CANVAS_2X = (256, 256)

# Ortho scale for units — tuned so ~1.8m figure is ~52-56px on 128x128 canvas
UNIT_ORTHO_SCALE = 2.8

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


def setup_camera(azimuth_deg, footprint=None, asset_type="building"):
    """Create an orthographic camera at isometric angle."""
    cam_data = bpy.data.cameras.new("IsoCam")
    cam_data.type = "ORTHO"
    if asset_type == "unit":
        cam_data.ortho_scale = UNIT_ORTHO_SCALE
    else:
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

def setup_render(footprint=None, asset_type="building"):
    """Configure render settings for transparent isometric output."""
    scene = bpy.context.scene
    render = scene.render

    # Engine — try EEVEE_NEXT (Blender 4.x) then EEVEE (Blender 5.x)
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"

    # Resolution at 2x canvas
    if asset_type == "unit":
        w, h = UNIT_CANVAS_2X
    else:
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


def _create_diffuse_material(name, color):
    """Create a simple Principled BSDF material with a given base color."""
    mat = bpy.data.materials.new(name)
    if _NEEDS_USE_NODES:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
    return mat


def _create_wall_material():
    """Simple diffuse material for house walls."""
    return _create_diffuse_material("HouseWall", (0.6, 0.5, 0.35, 1.0))


def _create_roof_material():
    """Simple diffuse material for house roof."""
    return _create_diffuse_material("HouseRoof", (0.7, 0.2, 0.15, 1.0))


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
# Geometric archer model
# ---------------------------------------------------------------------------

def build_geometric_archer():
    """Build a geometric archer: cylinder body, sphere head, cone hat, stick bow.

    All parts are parented to an empty at the origin for easy posing.
    Returns the root empty object.
    """
    magenta_mat = _create_magenta_material()
    body_mat = _create_diffuse_material("ArcherBody", (0.35, 0.25, 0.18, 1.0))
    skin_mat = _create_diffuse_material("ArcherSkin", (0.85, 0.65, 0.50, 1.0))
    hat_mat = _create_diffuse_material("ArcherHat", (0.15, 0.35, 0.15, 1.0))
    bow_mat = _create_diffuse_material("ArcherBow", (0.45, 0.30, 0.15, 1.0))

    # Root empty — all parts parented here
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "ArcherRoot"

    # Torso — cylinder
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.2, depth=0.6, location=(0, 0, 0.55)
    )
    torso = bpy.context.active_object
    torso.name = "ArcherTorso"
    torso.data.materials.append(body_mat)
    torso.parent = root

    # Magenta sash/belt — thin cylinder around waist
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.22, depth=0.08, location=(0, 0, 0.30)
    )
    sash = bpy.context.active_object
    sash.name = "ArcherSash"
    sash.data.materials.append(magenta_mat)
    sash.parent = root

    # Legs — two thin cylinders
    for side, x_off in [("L", -0.08), ("R", 0.08)]:
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.07, depth=0.5, location=(x_off, 0, 0.12)
        )
        leg = bpy.context.active_object
        leg.name = f"ArcherLeg{side}"
        leg.data.materials.append(body_mat)
        leg.parent = root

    # Head — sphere
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.18, location=(0, 0, 1.0)
    )
    head = bpy.context.active_object
    head.name = "ArcherHead"
    head.data.materials.append(skin_mat)
    head.parent = root

    # Hat/helmet — cone on top of head
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.2, depth=0.25, location=(0, 0, 1.22)
    )
    hat = bpy.context.active_object
    hat.name = "ArcherHat"
    hat.data.materials.append(hat_mat)
    hat.parent = root

    # Bow arm — small cylinder extending left
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.04, depth=0.35, location=(-0.35, 0, 0.65)
    )
    arm = bpy.context.active_object
    arm.name = "ArcherBowArm"
    arm.rotation_euler = (0, math.radians(90), 0)
    bpy.ops.object.transform_apply(rotation=True)
    arm.data.materials.append(skin_mat)
    arm.parent = root

    # Bow — torus arc (half-ring)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.3, minor_radius=0.02,
        location=(-0.5, 0, 0.65)
    )
    bow = bpy.context.active_object
    bow.name = "ArcherBow"
    bow.rotation_euler = (math.radians(90), 0, 0)
    bow.scale = (1.0, 1.0, 0.6)
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    bow.data.materials.append(bow_mat)
    bow.parent = root

    print("  Built geometric archer model")
    return root


# ---------------------------------------------------------------------------
# Archer animation poses
# ---------------------------------------------------------------------------

def animate_archer(root, animation, frame, total_frames):
    """Set the archer pose for a given animation frame.

    Applies transforms directly to the root empty and child objects.
    Each call sets a discrete pose — no Blender keyframe interpolation.
    """
    # Normalize frame progress [0, 1)
    t = frame / total_frames

    # Reset root transform
    root.location = (0, 0, 0)
    root.rotation_euler = (0, 0, 0)

    # Find child objects by name
    children = {obj.name: obj for obj in root.children}
    bow = children.get("ArcherBow")
    bow_arm = children.get("ArcherBowArm")

    if animation == "idle":
        # Subtle body sway: rotate torso ±3° around Y
        sway = math.sin(t * 2 * math.pi) * math.radians(3)
        root.rotation_euler = (0, sway, 0)

    elif animation == "walk":
        # Bob up/down + lean forward cyclically
        bob = abs(math.sin(t * 2 * math.pi)) * 0.05
        lean = math.sin(t * 2 * math.pi) * math.radians(5)
        root.location = (0, 0, bob)
        root.rotation_euler = (lean, 0, 0)

    elif animation == "attack":
        # Bow arm pulls back then releases
        if t < 0.5:
            # Draw phase — lean back, arm pulls
            pull = t * 2  # 0→1
            root.rotation_euler = (math.radians(-5 * pull), 0, 0)
            if bow_arm:
                bow_arm.location.y = 0.1 * pull
        else:
            # Release phase — snap forward
            release = (t - 0.5) * 2  # 0→1
            root.rotation_euler = (math.radians(5 * (1 - release)), 0, 0)
            if bow_arm:
                bow_arm.location.y = 0.1 * (1 - release)

    elif animation == "death":
        # Tilt entire model backward toward ground
        tilt = t * math.radians(80)
        drop = t * 0.3
        root.rotation_euler = (-tilt, 0, 0)
        root.location = (0, 0, -drop)

    # Force scene update so transforms take effect before render
    bpy.context.view_layer.update()


# ---------------------------------------------------------------------------
# Animated unit render loop
# ---------------------------------------------------------------------------

def render_animated_unit(cam_obj, directions, animations, frames_per_anim,
                         output_dir, subject, root):
    """Render animated unit: all frames x directions x animations.

    Output naming: {subject}_{animation}_{direction}_{frame:02d}.png
    """
    os.makedirs(output_dir, exist_ok=True)
    total_rendered = 0

    for anim, n_frames in zip(animations, frames_per_anim):
        for frame_idx in range(n_frames):
            # Set pose for this animation frame
            animate_archer(root, anim, frame_idx, n_frames)

            for dir_name in directions:
                azimuth = DIRECTIONS[dir_name]
                _position_camera(cam_obj, azimuth)

                # 1-indexed frame number in filename
                fname = f"{subject}_{anim}_{dir_name}_{frame_idx + 1:02d}.png"
                filepath = os.path.join(output_dir, fname)
                bpy.context.scene.render.filepath = filepath
                bpy.ops.render.render(write_still=True)
                total_rendered += 1

        print(f"  {anim}: {n_frames} frames x {len(directions)} dirs = "
              f"{n_frames * len(directions)} renders")

    print(f"  Total: {total_rendered} frames rendered")
    return total_rendered


# ---------------------------------------------------------------------------
# Render loop (buildings / static)
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
    parser.add_argument(
        "--animations", type=str, default=None,
        help="Comma-separated animation names (e.g., idle,walk,attack,death)"
    )
    parser.add_argument(
        "--frames-per-anim", type=str, default=None,
        help="Comma-separated frame counts per animation (e.g., 4,8,6,6)"
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

    # For units, default to all 8 directions
    asset_type = getattr(args, "type", "building")
    if asset_type == "unit" and args.directions == ["s"]:
        args.directions = list(DIRECTIONS.keys())

    output_dir = args.output_dir or os.path.join(
        project_root, "blender", "renders", args.subject
    )

    # Parse animation parameters
    animations = None
    frames_per_anim = None
    if args.animations:
        animations = [a.strip() for a in args.animations.split(",")]
        if args.frames_per_anim:
            frames_per_anim = [int(n) for n in args.frames_per_anim.split(",")]
        else:
            # Default: 4 frames per animation
            frames_per_anim = [4] * len(animations)
        if len(animations) != len(frames_per_anim):
            print("ERROR: --animations and --frames-per-anim must have same count",
                  file=sys.stderr)
            sys.exit(1)

    total_frames = sum(f * len(args.directions) for f in frames_per_anim) if frames_per_anim else len(args.directions)

    print("=== Blender Isometric Render ===")
    print(f"  Subject:    {args.subject}")
    print(f"  Type:       {asset_type}")
    if asset_type == "unit":
        print(f"  Canvas 2x:  {UNIT_CANVAS_2X}")
    else:
        print(f"  Footprint:  {args.footprint}")
        print(f"  Canvas 2x:  {CANVAS_2X[args.footprint]}")
    print(f"  Directions: {', '.join(args.directions)}")
    if animations:
        print(f"  Animations: {', '.join(animations)}")
        print(f"  Frames:     {', '.join(str(f) for f in frames_per_anim)}")
    print(f"  Total:      {total_frames} renders")
    print(f"  Output:     {output_dir}")

    # Scene setup
    clear_scene()
    setup_lighting()
    cam = setup_camera(DIRECTIONS[args.directions[0]],
                       footprint=args.footprint, asset_type=asset_type)
    setup_render(footprint=args.footprint, asset_type=asset_type)

    # Build or load model
    archer_root = None
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
    elif args.subject == "archer" and asset_type == "unit":
        archer_root = build_geometric_archer()
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
    if animations and archer_root:
        render_animated_unit(cam, args.directions, animations,
                             frames_per_anim, output_dir, args.subject,
                             archer_root)
    else:
        render_directions(cam, args.directions, output_dir, args.subject)

    print(f"=== Done: {total_frames} render(s) complete ===")


if __name__ == "__main__":
    main()
