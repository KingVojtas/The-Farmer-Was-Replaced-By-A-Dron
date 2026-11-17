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
    # A domed mount, a pole with two collars, a big glossy tip (v2).
    m_pole = material("M_Pole", POLE, 0.4, 1.0, variant="DroneHull")
    x, z = 0.6, 0.6
    pole = loft("HatPole", [ring_pts((x, 0.0, z), 0.2, 0.2, 8), ring_pts((x, 0.1, z), 0.16, 0.16, 8), ring_pts((x, 0.16, z), 0.06, 0.06, 8),
                            ring_pts((x, 1.12, z), 0.04, 0.04, 8)], m_pole, col)
    collars = [torus(f"Collar{k}", (x, y, z), 0.06, 0.025, m_pole, col, major_segments=8, minor_segments=3) for k, y in enumerate((0.5, 0.85))]
    pole = join([pole] + collars, "HatPole", col)
    set_origin(pole, (x, 0.0, z))
    tip = sphere("HatTip", (x, 1.25, z), 0.17, material("M_AntennaTip", ANTENNA_RED, 0.3), col, segments=10, rings=7)
    return [pole, tip]


def build_straw(col):
    # A wide brim that droops at the edge, a crown with a pinched top dent, a red band.
    m_straw = material("M_Straw", STRAW, 0.8)
    brim = loft("HatBrim", [ring_pts((0, 0.14, 0), 0.6, 0.6, 16), ring_pts((0, 0.12, 0), 1.0, 1.0, 16), ring_pts((0, 0.02, 0), 1.32, 1.32, 16),
                            ring_pts((0, -0.04, 0), 1.3, 1.3, 16), ring_pts((0, 0.06, 0), 0.95, 0.95, 16), ring_pts((0, 0.08, 0), 0.6, 0.6, 16)], m_straw, col)
    crown = loft("HatCrownTop", [ring_pts((0, 0.1, 0), 0.64, 0.64, 12), ring_pts((0, 0.55, 0), 0.6, 0.6, 12), ring_pts((0, 0.7, 0), 0.5, 0.42, 12),
                                 [(0, 0.62, 0)]], m_straw, col, cap_start=False)
    band = loft("HatBand", [ring_pts((0, 0.16, 0), 0.665, 0.665, 12), ring_pts((0, 0.32, 0), 0.655, 0.655, 12)], material("M_StrawBand", STRAW_BAND, 0.6), col, cap_start=False, cap_end=False)
    bow = loft("Bow", [ring_pts((0.5, 0.24, 0.45), 0.12, 0.05, 6), [(0.72, 0.18, 0.62)]], band.data.materials[0], col)
    crown = join([crown, band, bow], "HatCrown", col)
    set_origin(brim, (0, 0, 0))
    set_origin(crown, (0, 0, 0))
    return [brim, crown]


def build_propeller(col):
    m_cap = material("M_Cap", CAP_BLUE, 0.5)
    # A beanie in 8 panels (alternating seams pushed in) with a rolled rim and a button stem.
    rings = [ring_pts((0, 0.0, 0), 0.7, 0.7, 16), ring_pts((0, 0.1, 0), 0.72, 0.72, 16)]
    for y, r in ((0.28, 0.64), (0.44, 0.5), (0.54, 0.3)):
        rings.append(ring_pts((0, y, 0), r, r, 16, wobble=lambda i: 1.0 - 0.05 * (i % 2)))
    rings.append([(0, 0.58, 0)])
    cap = loft("HatCap", rings, m_cap, col)
    stem = loft("HatStem", [ring_pts((0, 0.55, 0), 0.06, 0.06, 6), ring_pts((0, 0.8, 0), 0.05, 0.05, 6), ring_pts((0, 0.84, 0), 0.1, 0.1, 6)], material("M_Stem", STEM, 0.3, 1.0), col)
    cap = join([cap, stem], "HatCap", col)
    set_origin(cap, (0, 0, 0))
    # The blade spins in game: a separate part named Rotor..., origin at the hub, modelled flat;
    # two tapered, pitched blades round a hub.
    pieces = [loft("Hub", [ring_pts((0, 0.82, 0), 0.1, 0.1, 6), ring_pts((0, 0.92, 0), 0.08, 0.08, 6)], material("M_Blade", BLADE_GOLD, 0.45), col)]
    for d in (1, -1):
        pts = [(d * x, 0.87, 0) for x in (0.05, 0.35, 0.75, 0.92)]
        pieces.append(tube(f"Blade{d}", pts, [0.1, 0.17, 0.14, 0.0], pieces[0].data.materials[0], col, section=SEC_BLADE, roll=math.radians(14)))
    blade = join(pieces, "RotorBlade", col)
    set_origin(blade, (0, 0.87, 0))
    return [cap, blade]


def build_tophat(col):
    m_top = material("M_TopHat", TOP_GREY, 0.55)
    # A brim curled up at the sides and a crown that flares slightly toward the top.
    def brim_ring(y, r, curl):
        return [(math.cos(a) * r, y + curl * abs(math.cos(a)) ** 2, math.sin(a) * r * 0.9) for a in (i / 16 * 2 * math.pi for i in range(16))]

    brim = loft("HatBrim", [brim_ring(0.1, 0.6, 0.0), brim_ring(0.08, 0.98, 0.14), brim_ring(0.0, 0.98, 0.14), brim_ring(0.02, 0.6, 0.0)], m_top, col)
    crown = loft("HatCrownTop", [ring_pts((0, 0.06, 0), 0.56, 0.5, 14), ring_pts((0, 0.4, 0), 0.565, 0.505, 14), ring_pts((0, 1.15, 0), 0.59, 0.53, 14),
                                 ring_pts((0, 1.22, 0), 0.57, 0.51, 14), [(0, 1.23, 0)]], m_top, col, cap_start=False)
    band = loft("HatBand", [ring_pts((0, 0.12, 0), 0.575, 0.515, 14), ring_pts((0, 0.32, 0), 0.565, 0.505, 14)], material("M_TopBand", TOP_BAND, 0.5), col, cap_start=False, cap_end=False)
    crown = join([crown, band], "HatCrown", col)
    set_origin(brim, (0, 0, 0))
    set_origin(crown, (0, 0, 0))
    return [brim, crown]


def build_halo(col):
    # A floating gold ring 1.1 studs above the body, faceted with a gentle twist.
    ring = torus("HatHalo", (0, 1.1, 0), 0.85, 0.08, material("M_Halo", HALO_GOLD, 0.25, 1.0), col, major_segments=24, minor_segments=5, twist=2 * math.pi / 24)
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
        # Pivot = where the hat sits on the drone's back; the halo hovers above it on purpose.
        modelled = len(parts)  # the ≤ 2 budget counts modelled parts; colour splits come after
        parts, found = finalize(parts, 300, allow_float=(name == "halo"))
        problems += [f"{name}: {p}" for p in found]
        tris = report(f"hat {name}", parts, 300)
        if tris > 300:
            problems.append(f"{name}: {tris} tris > 300")
        if modelled > 2:
            problems.append(f"{name}: {modelled} parts > 2")
        export(parts, os.path.join(out, name))
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Hats.<style> (a Model).")
    print("Set the Model's WorldPivot to the hat's base centre (game 0,0,0 here). 'Rotor*' parts spin.")
    if problems:
        print("\nBUDGET PROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
