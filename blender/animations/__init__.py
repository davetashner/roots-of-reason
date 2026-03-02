"""Animation template library for MakeHuman unit models.

Provides reusable animation creation functions organized by weapon class.
Each template creates Blender Actions with procedural bone keyframes.

Usage:
    from blender.animations import create_animations

    actions = create_animations(armature, template="ranged", frame_counts={
        "idle": 4, "walk": 8, "attack": 6, "death": 6,
    })
"""

from blender.animations.common import (
    create_death_action,
    create_idle_action,
    create_walk_action,
)
from blender.animations.ranged import create_ranged_attack_action

# Map template names to attack action creators
_ATTACK_TEMPLATES = {
    "ranged": create_ranged_attack_action,
}

# Lazy import to avoid errors when melee module doesn't exist yet
_LAZY_TEMPLATES = {
    "melee": "blender.animations.melee",
}


def create_animations(armature, template, frame_counts, overrides=None):
    """Create all animation Actions for a unit.

    Args:
        armature: Blender armature object.
        template: Animation template name ("ranged", "melee").
        frame_counts: Dict mapping animation name to frame count,
            e.g. {"idle": 4, "walk": 8, "attack": 6, "death": 6}.
        overrides: Optional dict of animation name -> callable(armature, n_frames)
            to override specific animations.

    Returns:
        Dict of action name -> bpy.types.Action.
    """
    import bpy

    # Ensure pose mode
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")

    overrides = overrides or {}
    actions = {}

    # Shared animations
    if "idle" not in overrides:
        actions["idle"] = create_idle_action(armature, frame_counts.get("idle", 4))
    else:
        actions["idle"] = overrides["idle"](armature, frame_counts.get("idle", 4))

    if "walk" not in overrides:
        actions["walk"] = create_walk_action(armature, frame_counts.get("walk", 8))
    else:
        actions["walk"] = overrides["walk"](armature, frame_counts.get("walk", 8))

    if "death" not in overrides:
        actions["death"] = create_death_action(armature, frame_counts.get("death", 6))
    else:
        actions["death"] = overrides["death"](armature, frame_counts.get("death", 6))

    # Template-specific attack animation
    if "attack" not in overrides:
        attack_fn = _ATTACK_TEMPLATES.get(template)
        if attack_fn is None and template in _LAZY_TEMPLATES:
            import importlib
            mod = importlib.import_module(_LAZY_TEMPLATES[template])
            attack_fn = mod.create_melee_attack_action
        if attack_fn is None:
            raise ValueError(f"Unknown animation template: {template}")
        actions["attack"] = attack_fn(armature, frame_counts.get("attack", 6))
    else:
        actions["attack"] = overrides["attack"](armature, frame_counts.get("attack", 6))

    bpy.ops.object.mode_set(mode="OBJECT")

    # Mark all actions as fake user so they persist in .blend
    for action in actions.values():
        action.use_fake_user = True

    return actions
