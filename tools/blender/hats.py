"""
hats.py - the 5 drone hats (CosmeticConfig styles: antenna, straw, propeller, tophat, halo).
Blender Python.

    blender -b -P tools/blender/hats.py -- --out tools/blender/out/Hats

One FBX per style (+ a .glb preview) -> ReplicatedStorage.Assets.Hats.<style>.
CONTRACT (PlotRenderer.applyHat, AssetLibrary.hat):
  * Pivot = where the hat sits on the drone's back = the TOP CENTRE of the drone body, game
    (0, 0, 0) here. The game places it 0.4 studs above the body centre.
  * The body top is a 2.4 x 2.4 square; keep the hat inside a 1.2-stud circle around the
    pivot (the battery strip lies behind it, z 0.63 .. 0.93), except the antenna, which
    stands on the back-right corner like the procedural one.
  * A part named "Rotor..." spins around its own origin (propeller blade: origin at the hub).
  * <= 300 tris, <= 2 parts (ART_BIBLE §7). Opaque, no Neon, no armature, no animation.
    The game tints nothing on an artist hat: author the colours (CosmeticConfig colours).
  * It bobs with the drone (0.35 studs) and leans 14 degrees: keep it compact.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

# CosmeticConfig hat colours + Bible accents.
ANTENNA_RED, POLE = "#C83C3C", "#3C4048"
STRAW, STRAW_BAND = "#E4C478", "#C84638"
CAP_BLUE, BLADE_GOLD, STEM = "#4682E6", "#FFC83C", "#E6E6EB"
TOP_GREY, TOP_BAND = "#A0A0AA", "#C8283C"
HALO_GOLD = "#FFEC8C"


def build_antenna(col):
    pole = cylinder("HatPole", (0.6, 0.6, 0.6), 0.05, 1.2, material("M_Pole", POLE, 0.4, 1.0), col, sides=6)
    set_origin(pole, (0.6, 0.0, 0.6))
    tip = sphere("HatTip", (0.6, 1.25, 0.6), 0.15, material("M_AntennaTip", ANTENNA_RED, 0.35), col, segments=10, rings=6)
    return [pole, tip]


def build_straw(col):
    m_straw = material("M_Straw", STRAW, 0.8)
    brim = cylinder("HatBrim", (0, 0.1, 0), 1.3, 0.12, m_straw, col, sides=16)
    crown = cylinder("HatCrownTop", (0, 0.42, 0), 0.62, 0.6, m_straw, col, sides=12)
    band = cylinder("HatBand", (0, 0.22, 0), 0.66, 0.14, material("M_StrawBand", STRAW_BAND, 0.6), col, sides=12)
    crown = join([crown, band], "HatCrown", col)
    set_origin(brim, (0, 0, 0))
    set_origin(crown, (0, 0, 0))
    return [brim, crown]


def build_propeller(col):
    m_cap = material("M_Cap", CAP_BLUE, 0.5)
    cap = sphere("HatCap", (0, 0.15, 0), 0.65, m_cap, col, segments=12, rings=6, scale=(1, 0.55, 1))
    stem = cylinder("HatStem", (0, 0.6, 0), 0.05, 0.35, material("M_Stem", STEM, 0.3, 1.0), col, sides=6)
    cap = join([cap, stem], "HatCap", col)
    set_origin(cap, (0, 0, 0))
    # The blade spins in game: a separate part named Rotor..., origin at the hub, modelled flat.
    blade = box("RotorBlade", (0, 0.78, 0), (1.8, 0.06, 0.28), material("M_Blade", BLADE_GOLD, 0.45), col)
    set_origin(blade, (0, 0.78, 0))
    return [cap, blade]


def build_tophat(col):
    m_top = material("M_TopHat", TOP_GREY, 0.55)
    brim = cylinder("HatBrim", (0, 0.06, 0), 0.95, 0.1, m_top, col, sides=16)
    crown = cylinder("HatCrownTop", (0, 0.65, 0), 0.6, 1.1, m_top, col, sides=14)
    band = cylinder("HatBand", (0, 0.24, 0), 0.63, 0.16, material("M_TopBand", TOP_BAND, 0.5), col, sides=14)
    crown = join([crown, band], "HatCrown", col)
    set_origin(brim, (0, 0, 0))
    set_origin(crown, (0, 0, 0))
    return [brim, crown]


def build_halo(col):
    # A floating ring 1.1 studs above the body (game Y); torus axis = game Y = Blender Z.
    bpy.ops.mesh.primitive_torus_add(
        major_segments=16,
        minor_segments=4,
        major_radius=0.85,
        minor_radius=0.07,
        location=g(0, 1.1, 0),
    )
    ring = bpy.context.active_object
    ring.name = "HatHalo"
    ring.data.name = "SM_HatHalo"
    ring.data.materials.append(material("M_Halo", HALO_GOLD, 0.25, 1.0))
    for c in ring.users_collection:
        c.objects.unlink(ring)
    col.objects.link(ring)
    set_origin(ring, (0, 0, 0))
    return [ring]


HATS = (
    ("antenna", build_antenna),
    ("straw", build_straw),
    ("propeller", build_propeller),
    ("tophat", build_tophat),
    ("halo", build_halo),
)

if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "Hats"))
    problems = []
    for name, builder in HATS:
        scene = reset_scene()
        col = bpy.data.collections.new(f"hat_{name}_export")
        scene.collection.children.link(col)
        parts = builder(col)
        for p in parts:
            shade_flat(p)
        tris = report(f"hat {name}", parts, 300)
        if tris > 300:
            problems.append(f"{name}: {tris} tris > 300")
        if len(parts) > 2:
            problems.append(f"{name}: {len(parts)} parts > 2")
        export(parts, os.path.join(out, name))
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Hats.<style> (a Model).")
    print("Set the Model's WorldPivot to the hat's base centre (game 0,0,0 here). 'Rotor*' parts spin.")
    if problems:
        print("\nBUDGET PROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
