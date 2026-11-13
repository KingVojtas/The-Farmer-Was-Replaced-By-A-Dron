"""
stations.py - Charging Station + Factory (ART_BIBLE.md §4.2-4.3). Blender Python.

    blender -b -P tools/blender/stations.py -- --out tools/blender/out/Stations

charger.fbx / factory.fbx (+ .glb previews). Pivot = TOP-FACE CENTRE of the server part
(charger pad 6 x 0.4 x 6; factory block 6 x 3 x 6), game (0,0,0) here. Neon only for STATE:
the rings (Ring1..Ring4), PylonLight, Slit and Lamp export as plain dark Metal / glass;
PlotRenderer + PlotDressing colour them Neon cyan / biofluid / amber at runtime. No baked
pulse, no smoke, no armature, no animation. Opaque except the factory Window (one glass).
Charger <= 2.5 tall (pylon <= 3.5 in one corner), <= 1,500 tris, <= 6 parts... the rings
count as 4 separate parts because the game pulses each one; 9 parts total is the trade-off.
Factory <= 4,000 tris, <= 10 parts.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

DARK_STEEL, STEEL, CERAMIC, COPPER = "#2A3440", "#3A424F", "#D7E2EC", "#C27744"
STATE_IDLE, LAMP_IDLE, SLIT_IDLE, GLASS = "#22343C", "#4A3A22", "#1E4034", "#24332E"
HULL, HOPPER, ROOF, WOOD = "#1E2530", "#E6A03C", "#343A46", "#8A6A4A"


def build_charger(col):
    m_dark = material("M_DarkSteel", DARK_STEEL, 0.45, 1.0)
    m_steel = material("M_Steel", STEEL, 0.35, 1.0)
    m_ceramic = material("M_Ceramic", CERAMIC, 0.3)
    m_copper = material("M_Copper", COPPER, 0.3, 1.0)
    m_state = material("M_StateIdle", STATE_IDLE, 0.5, 1.0)  # the game sets Neon
    parts = []
    # Base plate (6.1 x 0.3 x 6.1) covers the server pad's neon; hex landing pad on top.
    base = box("Base", (0, -0.15, 0), (6.1, 0.3, 6.1), m_dark, col, bevel=(0.04, 1))
    pad = cylinder("Pad", (0, 0.08, 0), 2.4, 0.16, m_steel, col, sides=6)
    markA = box("MarkA", (0, 0.17, 0), (0.3, 0.04, 2.0), m_ceramic, col)
    markB = box("MarkB", (0, 0.17, 0), (2.0, 0.04, 0.3), m_ceramic, col)
    pad = join([base, pad, markA, markB], "Pad", col)
    set_origin(pad, (0, 0, 0))
    parts.append(pad)
    # Copper coils: two concentric rings lying FLAT around the landing pad (a torus is created
    # flat in Blender's XY plane = the game's ground plane). Rotating it 90 degrees stood the
    # rings up as an arch across the pad, right where the drone lands.
    for i, r in enumerate((1.9, 2.25), start=1):
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.07, major_segments=24, minor_segments=5, location=g(0, 0.2, 0))
        coil = bpy.context.active_object
        coil.name = f"Coil{i}"
        coil.data.name = f"SM_Coil{i}"
        coil.data.materials.append(m_copper)
        for c in coil.users_collection:
            c.objects.unlink(coil)
        col.objects.link(coil)
        parts.append(coil)
    # Rings (the game pulses these, so each is its own part, exported dark).
    for i, (dx, dz, w, d) in enumerate([(2.6, 0, 0.2, 5.4), (-2.6, 0, 0.2, 5.4), (0, 2.6, 5.4, 0.2), (0, -2.6, 5.4, 0.2)], start=1):
        ring_ = box(f"Ring{i}", (dx, 0.15, dz), (w, 0.2, d), m_state, col)
        parts.append(ring_)
    # Capacitor pylon in the back-left corner (-X, -Z): drums + a status lamp.
    drums = [cylinder(f"Drum{k}", (-2.6, 0.55 + k * 0.75, -2.6), 0.32, 0.65, m_dark if k % 2 else m_steel, col, sides=8) for k in range(3)]
    post = cylinder("Post", (-2.6, 1.3, -2.6), 0.12, 2.6, m_steel, col, sides=6)
    pylon = join(drums + [post], "Pylon", col)
    set_origin(pylon, (-2.6, 0, -2.6))
    parts.append(pylon)
    light = sphere("PylonLight", (-2.6, 2.75, -2.6), 0.3, m_state, col, segments=8, rings=5)
    parts.append(light)
    return parts


def build_factory(col):
    m_hull = material("M_FactoryHull", HULL, 0.5, 0.8)
    m_roof = material("M_Roof", ROOF, 0.5, 0.9, variant="DroneHull")
    m_steel = material("M_Steel", STEEL, 0.35, 1.0)
    m_copper = material("M_Copper", COPPER, 0.3, 1.0)
    m_hopper = material("M_Hopper", HOPPER, 0.6, variant="DroneHull")
    m_wood = material("M_Wood", WOOD, 0.8)
    m_glass = material("M_Glass", GLASS, 0.05, alpha=0.55)
    m_slit = material("M_SlitIdle", SLIT_IDLE, 0.4)
    m_lamp = material("M_LampIdle", LAMP_IDLE, 0.5)
    parts = []
    # Housing wraps the 6 x 3 x 6 server block (inner clearance 6.05), extends 3 down from the pivot.
    outer = box("Housing", (0, -1.5, 0), (6.4, 3.0, 6.4), m_hull, col, bevel=(0.05, 1))
    roof = box("Roof", (0, 0.2, 0), (6.4, 0.4, 6.4), m_roof, col, bevel=(0.05, 1))
    housing = join([outer, roof], "Housing", col)
    set_origin(housing, (0, 0, 0))
    parts.append(housing)
    # Composting drum on the roof (industrial core) + flanged copper pipe to the tanks.
    drum = cylinder("Drum", (-0.6, 1.2, 0.2), 0.9, 2.6, m_steel, col, sides=10, axis="X")
    frame = box("DrumFrame", (-0.6, 0.55, 0.2), (2.8, 0.3, 2.0), m_hull, col)
    parts.append(join([drum, frame], "Drum", col))
    pipeA = cylinder("PipeA", (0.9, 1.3, 0.2), 0.14, 1.6, m_copper, col, sides=6, axis="X")
    pipeB = cylinder("PipeB", (1.7, 1.0, 0.2), 0.14, 1.2, m_copper, col, sides=6)
    parts.append(join([pipeA, pipeB], "Pipes", col))
    # Two glass tanks (outer glass shells) with the biofluid Slit between them: the Slit is the
    # one part the game lights (#4DFFB0 Neon); tanks stay glass.
    tanks = [cylinder(f"Tank{k}", (1.9 + k * 0.0, 1.0, -1.4 + k * 1.2), 0.5, 1.8, m_glass, col, sides=8) for k in range(2)]
    parts.append(join(tanks, "Tanks", col))
    slit = box("Slit", (1.9, 1.0, -0.8), (0.28, 1.6, 0.1), m_slit, col)
    parts.append(slit)
    # Front (+Z, camera side): wooden-slat intake hopper with a warm work Lamp above it.
    hop_box = box("HopperBody", (1.4, 0.8, 1.2), (1.8, 0.8, 1.8), m_hopper, col, bevel=(0.03, 1))
    slats = [box(f"Slat{k}", (1.4 - 0.6 + k * 0.6, 1.25, 2.1), (0.45, 0.08, 0.1), m_wood, col) for k in range(3)]
    hopper = join([hop_box] + slats, "Hopper", col)
    set_origin(hopper, (1.4, 0.8, 1.2))
    parts.append(hopper)
    lamp = sphere("Lamp", (2.4, 1.9, 2.2), 0.18, m_lamp, col, segments=8, rings=5)
    parts.append(lamp)
    # Back: chimney with a hazard-striped cap (two parts joined; smoke is a game particle).
    chimney = cylinder("ChimneyStack", (-1.9, 1.7, -1.9), 0.5, 2.6, m_steel, col, sides=8)
    cap = cylinder("ChimneyCap", (-1.9, 3.1, -1.9), 0.65, 0.3, m_hull, col, sides=8)
    chim = join([chimney, cap], "ChimneyCap", col)  # named ChimneyCap: PlotRenderer reads its top for puffs
    set_origin(chim, (-1.9, 3.25, -1.9))
    parts.append(chim)
    # Window: one glass strip on the front wall (the only transparent part).
    parts.append(box("Window", (0, -1.2, 3.22), (3.6, 0.6, 0.12), m_glass, col))
    return parts


if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "Stations"))
    problems = []
    # The game pivots a station model on the TOP face of its server block (PlotRenderer
    # `asset:PivotTo(top)`): the charger pad is 0.4 tall, the factory block 3 (its housing wraps it).
    for name, builder, budget, sink in (
        ("charger", build_charger, 1500, 0.6),
        ("factory", build_factory, 4000, 3.0),
    ):
        scene = reset_scene()
        col = bpy.data.collections.new(f"{name}_export")
        scene.collection.children.link(col)
        parts = builder(col)
        for p in parts:
            shade_flat(p)
        parts, found = finalize(parts, budget, sink_limit=sink)
        problems += [f"{name}: {p}" for p in found]
        if report(name, parts, budget) > budget:
            problems.append(f"{name}: over {budget} tris")
        # World heights (parts keep their own centre as origin, so local z isn't height).
        zs = [max(((p.matrix_world @ v.co).z for v in p.data.vertices), default=0) for p in parts]
        print(f"   max height above pivot: {max(zs):.2f} studs ({'<= 2.5 pad / 3.5 pylon' if name == 'charger' else '<= 6'})")
        export(parts, os.path.join(out, name))
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Stations.charger / factory. Set WorldPivot = top-face centre.")
    print("Runtime Neon (do NOT bake): Ring1..4 + PylonLight cyan while charging; Slit #4DFFB0 + Lamp amber while working.")
    if problems:
        print("\nPROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
