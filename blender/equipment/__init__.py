"""Equipment template library for MakeHuman unit models.

Provides reusable equipment creation and tabard attachment.

Usage:
    from blender.equipment import create_equipment

    create_equipment(armature, basemesh, equipment_list=[
        {"template": "bow", "parent_bone": "hand_l"},
        {"template": "quiver", "parent_bone": "spine_02"},
    ], tabard_config={"parent_bone": "spine_02", "scale": [0.22, 0.12, 0.25]})
"""

import os

from blender.equipment.tabard import create_tabard
from blender.equipment.templates import EQUIPMENT_TEMPLATES


def create_equipment(armature, basemesh, equipment_list, tabard_config=None):
    """Create all equipment and tabard for a unit.

    Args:
        armature: Blender armature object.
        basemesh: Blender mesh object (body).
        equipment_list: List of dicts with "template" and optional overrides.
            Each dict has: template (str), parent_bone (str), and optional
            location, rotation, scale overrides.
        tabard_config: Optional dict with tabard params (parent_bone, scale,
            location). If None, no tabard is created.

    Returns:
        List of created Blender objects (equipment + tabard).
    """
    created = []

    for equip in equipment_list:
        template_name = equip["template"]

        # mhclo: prefix routes to MakeHuman community equipment loader
        if template_name.startswith("mhclo:"):
            asset_name = template_name[6:]  # strip "mhclo:" prefix
            obj = create_mhclo_equipment(
                armature, basemesh, asset_name, **_extract_overrides(equip)
            )
            if obj:
                created.append(obj)
            continue

        create_fn = EQUIPMENT_TEMPLATES.get(template_name)
        if create_fn is None:
            print(f"  WARNING: Unknown equipment template: {template_name}")
            continue
        obj = create_fn(armature, **_extract_overrides(equip))
        created.append(obj)

    if tabard_config:
        tabard = create_tabard(basemesh, armature, **tabard_config)
        created.append(tabard)

    return created


def create_mhclo_equipment(armature, basemesh, asset_name, parent_bone="hand_r",
                           color=None, **_kwargs):
    """Load equipment from a MakeHuman .mhclo asset.

    Used for community equipment like wooden_bow, crude_sword, war_hammer.
    These are loaded as MPFB2 clothing items and optionally recolored.

    Args:
        armature: Blender armature object.
        basemesh: Blender mesh object (body).
        asset_name: MPFB2 clothing/equipment asset name.
        parent_bone: Bone to parent equipment to (used for overrides).
        color: Optional RGBA color tuple.
    """
    import bpy
    from blender.equipment.materials import create_colored_material

    try:
        from bl_ext.blender_org.mpfb.services.humanservice import HumanService
        from bl_ext.blender_org.mpfb.services.locationservice import LocationService
    except ImportError:
        print(f"    WARNING: MPFB2 not available, skipping mhclo equipment: {asset_name}")
        return None

    clothes_dir = LocationService.get_mpfb_data("clothes")
    mhclo_path = os.path.join(clothes_dir, asset_name, f"{asset_name}.mhclo")

    if not os.path.exists(mhclo_path):
        print(f"    WARNING: Equipment asset '{asset_name}' not found at {mhclo_path}")
        print(f"    Install it with: ./tools/ror mh-install <pack>")
        return None

    HumanService.add_mhclo_asset(
        mhclo_path, basemesh,
        asset_type="clothes",
        subdiv_levels=0,
        material_type="MAKESKIN",
    )

    # Find the newly added equipment mesh
    equip_obj = None
    for obj in bpy.data.objects:
        if obj.type == "MESH" and asset_name.lower() in obj.name.lower():
            equip_obj = obj
            break

    if equip_obj and color:
        mat = create_colored_material(f"{asset_name}_Color", tuple(color))
        equip_obj.data.materials.clear()
        equip_obj.data.materials.append(mat)

    if equip_obj:
        print(f"    Loaded mhclo equipment: {asset_name}")
    else:
        print(f"    WARNING: Could not find loaded equipment mesh for {asset_name}")

    return equip_obj


def _extract_overrides(equip_dict):
    """Extract override params from an equipment config dict."""
    overrides = {}
    if "parent_bone" in equip_dict:
        overrides["parent_bone"] = equip_dict["parent_bone"]
    if "location" in equip_dict:
        overrides["location"] = tuple(equip_dict["location"])
    if "rotation" in equip_dict:
        overrides["rotation"] = tuple(equip_dict["rotation"])
    if "scale" in equip_dict:
        overrides["scale"] = tuple(equip_dict["scale"])
    return overrides
