"""Equipment template library for MakeHuman unit models.

Provides reusable equipment creation and tabard attachment.

Usage:
    from blender.equipment import create_equipment

    create_equipment(armature, basemesh, equipment_list=[
        {"template": "bow", "parent_bone": "hand_l"},
        {"template": "quiver", "parent_bone": "spine_02"},
    ], tabard_config={"parent_bone": "spine_02", "scale": [0.22, 0.12, 0.25]})
"""

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
