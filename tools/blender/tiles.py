"""
tiles.py - the field tile and the plot dressing kit, as low-poly meshes. Blender Python.

    blender -b -P tools/blender/tiles.py -- --out tools/blender/out

Writes (all through _common.finalize, so: Decimate guard, Smart UV, Apply Rot/Scale, pivot check):
  Tiles/Soil         the field tile: a bevelled soil slab 6 x 0.6 x 6 with a few clods on the
                     bevel ring (never on the flat top: crops stand there). Pivot = its CENTRE:
                     the server clones it in place of the Part it used to build
                     (GridService.newTilePart), and SoilLook still sets Material / MaterialVariant
                     / Color on it. Collide + Query (raycasts and the smoke test hit tiles).
  Dressing/FencePost a fence post with a pyramid cap, 0.32 x 1.3 x 0.32, pivot = centre
  Dressing/FenceRail a rail 0.12 x 0.12 x 2.0 (PlotDressing stretches it along Z), pivot = centre
  Dressing/Walkway   gravel strip + plank edging, 6.4 wide (PlotDressing stretches X to the
                     field width), 6 deep; pivot = ground centre
  Dressing/SignPost  pole 10.6 + bar + cap (the owner billboard hangs above it); pivot = ground
Sizes match what PlotDressing / GridService used to build from Parts, so swapping is 1:1.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

WOOD, WOOD_DARK, GRAVEL, SOIL = "#8A6A4A", "#6E5238", "#7A7468", "#7A5A3A"


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def build_soil(col):
    m = material("M_Soil", SOIL, 0.9, roblox="Ground")
    slab = apply_modifiers(box("Soil", (0, 0, 0), (6.0, 0.6, 6.0), m, col, bevel=(0.22, 1)))
    clods = [
        sphere(f"Clod{k}", (x, -0.1, z), 0.2, m, col, segments=4, rings=3, scale=(1.25, 0.55, 1.0))
        for k, (x, z) in enumerate(((-2.72, -1.3), (2.7, 1.5), (0.9, -2.74)))
    ]
    tile = join([slab] + clods, "Soil", col)
    set_origin(tile, (0, 0, 0))
    set_prop(tile, "Collide", True)
    set_prop(tile, "Query", True)
    return [tile]


def build_post(col):
    m = material("M_FenceWood", WOOD, 0.85, roblox="Wood")
    post = box("FencePost", (0, -0.1, 0), (0.32, 1.1, 0.32), m, col, bevel=(0.03, 1))
    cap = cone("Cap", (0, 0.55, 0), 0.23, 0.2, m, col, sides=4)
    cap.rotation_euler = (0, 0, math.radians(45))
    bpy.ops.object.select_all(action="DESELECT")
    cap.select_set(True)
    bpy.context.view_layer.objects.active = cap
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    part = join([apply_modifiers(post), cap], "FencePost", col)
    set_origin(part, (0, 0, 0))
    return [part]


def build_rail(col):
    m = material("M_FenceWoodDark", WOOD_DARK, 0.85, roblox="Wood")
    rail = box("FenceRail", (0, 0, 0), (0.12, 0.12, 2.0), m, col, bevel=(0.02, 1))
    return [rail]


def build_walkway(col):
    m_gravel = material("M_Gravel", GRAVEL, 0.95, roblox="Pebble")
    m_plank = material("M_Plank", WOOD, 0.85, roblox="WoodPlanks")
    gravel = box("Walkway", (0, 0.03, 0), (6.4, 0.06, 6.0), m_gravel, col)
    planks = [box(f"Plank{s}", (0, 0.06, s * 3.18), (6.4, 0.12, 0.35), m_plank, col, bevel=(0.02, 1)) for s in (-1, 1)]
    edging = join([apply_modifiers(p) for p in planks], "WalkwayPlanks", col)
    set_origin(edging, (0, 0, 0))
    set_origin(gravel, (0, 0, 0))
    return [gravel, edging]


def build_signpost(col):
    m_wood = material("M_SignWood", WOOD, 0.85, roblox="Wood")
    m_dark = material("M_SignWoodDark", WOOD_DARK, 0.85, roblox="Wood")
    pole = box("SignPost", (0, 5.3, 0), (0.45, 10.6, 0.45), m_wood, col, bevel=(0.04, 1))
    bar = box("Bar", (0, 10.35, 0), (3.4, 0.28, 0.28), m_dark, col, bevel=(0.03, 1))
    cap = sphere("Cap", (0, 10.75, 0), 0.3, m_dark, col, segments=8, rings=5)
    top = join([apply_modifiers(bar), cap], "SignTop", col)
    set_origin(top, (0, 0, 0))
    set_origin(pole, (0, 0, 0))
    return [apply_modifiers(pole), top]


# name -> (builder, budget, pivot)
KIT = {
    "Tiles/Soil": (build_soil, 120, "center"),
    "Dressing/FencePost": (build_post, 60, "center"),
    "Dressing/FenceRail": (build_rail, 60, "center"),
    "Dressing/Walkway": (build_walkway, 120, "bottom"),
    "Dressing/SignPost": (build_signpost, 200, "bottom"),
}

if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))
    problems = []
    for name, (builder, budget, pivot) in KIT.items():
        scene = reset_scene()
        col = bpy.data.collections.new(name.replace("/", "_"))
        scene.collection.children.link(col)
        parts = builder(col)
        for p in parts:
            shade_flat(p)
        centre = parts[0] if pivot == "center" else None
        parts, found = finalize(parts, budget, pivot=pivot, center_part=centre)
        problems += [f"{name}: {p}" for p in found]
        if report(name, parts, budget) > budget:
            problems.append(f"{name}: over {budget} tris")
        export(parts, os.path.join(out, *name.split("/")))
    if problems:
        print("\nPROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
