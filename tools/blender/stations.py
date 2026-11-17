"""
stations.py - Charging Station + Factory (ART_BIBLE.md §4.2-4.3). Blender Python.

    blender -b -P tools/blender/stations.py -- --out tools/blender/out/Stations

charger.fbx / factory.fbx (+ .glb previews). Pivot = TOP-FACE CENTRE of the server part
(charger pad 6 x 0.4 x 6; factory block 6 x 3 x 6), game (0,0,0) here. Neon only for STATE:
these parts export dark and the client lights them at runtime (PlotRenderer / PlotDressing):
  charger  Ring1..Ring4 (edge light guides), PylonLight, Conduit  -> cyan + pulse while charging
  factory  Slit (the biofluid inside both tanks) -> #4DFFB0 flicker, Lamp -> amber pulse while working
No baked pulse, no smoke, no armature, no animation. One transparent layer (the factory tanks'
glass shells; the fluid inside them is opaque).

v2 (2026-11-17): a hex landing pad with a ceramic H, two wound copper coils, edge light guides
in corner blocks, a capacitor pylon with cables; the bioreactor gets a banded composting drum
on a frame, flanged copper pipes, glass tanks with steel caps round the biofluid, a wooden
intake funnel with straw spill, a work lamp on a bracket, louvred walls and a hazard-banded
chimney. Charger <= 2.5 tall (pylon <= 3.5 in its corner), <= 1,500 tris; factory <= 4,000.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

DARK_STEEL, STEEL, BRUSHED, CERAMIC, COPPER = "#2A3440", "#3C4652", "#8E9AA6", "#D7E2EC", "#C27744"
STATE_IDLE, LAMP_IDLE, SLIT_IDLE, GLASS = "#22343C", "#4A3A22", "#1E4034", "#9FD8E8"
HULL, ROOF, WOOD, STRAW, RUBBER, HAZARD = "#1E2530", "#343A46", "#A87A4A", "#E8C45C", "#1A1D22", "#F2B630"


def hexagon(center, r, phase=math.pi / 6):
    return ring_pts(center, r, r, 6, phase)


def build_charger(col):
    m_dark = material("M_DarkSteel", DARK_STEEL, 0.45, 1.0)
    m_steel = material("M_Steel", STEEL, 0.4, 1.0)
    m_brushed = material("M_BrushedSteel", BRUSHED, 0.35, 1.0)
    m_ceramic = material("M_Ceramic", CERAMIC, 0.3)
    m_copper = material("M_Copper", COPPER, 0.3, 1.0)
    m_rubber = material("M_RubberCable", RUBBER, 0.85, variant="")
    m_state = material("M_StateIdle", STATE_IDLE, 0.5, 1.0)  # the game sets Neon
    parts = []

    # Base plate (6.1 x 0.3 x 6.1, covers the server pad's neon) + four corner blocks the light
    # guides sit between.
    base = [box("Base", (0, -0.15, 0), (6.1, 0.3, 6.1), m_dark, col, bevel=(0.04, 1))]
    for sx in (1, -1):
        for sz in (1, -1):
            base.append(loft(f"Corner{sx}{sz}", [rounded_rect((sx * 2.72, 0.0, sz * 2.72), 0.32, 0.32, 0.08, 1),
                                                rounded_rect((sx * 2.72, 0.26, sz * 2.72), 0.25, 0.25, 0.06, 1)], m_dark, col))
    pad = join(base, "Base", col)
    set_origin(pad, (0, 0, 0))
    parts.append(pad)

    # Hexagonal landing deck (brushed steel), chamfered top edge.
    deck = loft("Pad", [hexagon((0, 0.0, 0), 2.2), hexagon((0, 0.12, 0), 2.2), hexagon((0, 0.18, 0), 2.05)], m_brushed, col)
    set_origin(deck, (0, 0.09, 0))
    parts.append(deck)

    # Ceramic H landing mark (its own part: a small area would merge into the deck colour).
    mark = [box("HL", (-0.55, 0.2, 0), (0.28, 0.04, 1.7), m_ceramic, col), box("HR", (0.55, 0.2, 0), (0.28, 0.04, 1.7), m_ceramic, col),
            box("HM", (0, 0.2, 0), (0.82, 0.04, 0.26), m_ceramic, col)]
    mark = join(mark, "Mark", col)
    set_origin(mark, (0, 0.2, 0))
    parts.append(mark)

    # Two wound copper coils lying flat round the deck (helical facets = windings).
    for i, r in enumerate((2.32, 2.52), start=1):
        coil = torus(f"Coil{i}", (0, 0.1 + 0.04 * i, 0), r, 0.08, m_copper, col, major_segments=24, minor_segments=4, twist=2 * math.pi * 2 / 24)
        set_origin(coil, (0, 0.1 + 0.04 * i, 0))
        parts.append(coil)

    # Light guides along the four edges, between the corner blocks (the game pulses each one).
    for i, (dx, dz, w, d) in enumerate([(2.74, 0, 0.2, 5.0), (-2.74, 0, 0.2, 5.0), (0, 2.74, 5.0, 0.2), (0, -2.74, 5.0, 0.2)], start=1):
        ring_ = box(f"Ring{i}", (dx, 0.08, dz), (w, 0.16, d), m_state, col)
        parts.append(ring_)

    # Conduit: from the pylon foot across the plate to the outer coil (lights with the rings).
    conduit = tube("Conduit", [(-2.3, 0.06, -2.3), (-2.05, 0.08, -2.05), (-1.82, 0.14, -1.82)], [0.08, 0.08, 0.07], m_state, col, sides=6)
    set_origin(conduit, (-2.05, 0.08, -2.05))
    parts.append(conduit)

    # Capacitor pylon in the back-left corner (-X, -Z): an octagonal foot, three banded drums
    # (alternating steel / dark), an insulator cap, two cables down to the plate.
    px, pz = -2.62, -2.62
    pylon = [loft("Foot", [ring_pts((px, 0.26, pz), 0.42, 0.42, 8, math.pi / 8), ring_pts((px, 0.4, pz), 0.36, 0.36, 8, math.pi / 8), ring_pts((px, 0.46, pz), 0.24, 0.24, 8, math.pi / 8)], m_dark, col)]
    for k in range(3):
        y0 = 0.46 + k * 0.72
        m = m_steel if k % 2 == 0 else m_dark
        pylon.append(loft(f"Drum{k}", [ring_pts((px, y0, pz), 0.27, 0.27, 8, math.pi / 8), ring_pts((px, y0 + 0.06, pz), 0.33, 0.33, 8, math.pi / 8),
                                       ring_pts((px, y0 + 0.58, pz), 0.33, 0.33, 8, math.pi / 8), ring_pts((px, y0 + 0.66, pz), 0.24, 0.24, 8, math.pi / 8)], m, col))
    pylon.append(loft("Insulator", [ring_pts((px, 2.6, pz), 0.2, 0.2, 8, math.pi / 8), ring_pts((px, 2.72, pz), 0.14, 0.14, 8, math.pi / 8), ring_pts((px, 2.76, pz), 0.08, 0.08, 8, math.pi / 8)], m_steel, col))
    for k, (ox, oz) in enumerate(((0.38, 0.1), (0.1, 0.38))):
        pylon.append(tube(f"Cable{k}", [(px + ox * 0.6, 1.9, pz + oz * 0.6), (px + ox * 1.2, 1.4, pz + oz * 1.2), (px + ox * 1.5, 0.6, pz + oz * 1.5), (px + ox * 1.6, 0.05, pz + oz * 1.6)],
                          [0.06, 0.06, 0.06, 0.07], m_rubber, col, sides=4))
    pylon = join(pylon, "Pylon", col)
    set_origin(pylon, (px, 0, pz))
    parts.append(pylon)
    light = sphere("PylonLight", (px, 3.0, pz), 0.26, m_state, col, segments=7, rings=4)
    parts.append(light)
    return parts


def build_factory(col):
    m_hull = material("M_FactoryHull", HULL, 0.5, 0.8)
    m_roof = material("M_Roof", ROOF, 0.5, 0.9, variant="DroneHull")
    m_steel = material("M_DarkSteelTank", STEEL, 0.45, 1.0)
    m_copper = material("M_Copper", COPPER, 0.3, 1.0)
    m_wood = material("M_HopperWood", WOOD, 0.8, variant="Planks")
    m_straw = material("M_Straw", STRAW, 0.85, variant="CropSkin")
    m_glass = material("M_Glass", GLASS, 0.05, alpha=0.45)
    m_slit = material("M_SlitIdle", SLIT_IDLE, 0.4)
    m_lamp = material("M_LampIdle", LAMP_IDLE, 0.5)
    m_hazard = material("M_HazardPaint", HAZARD, 0.6, variant="")
    parts = []

    # Housing wraps the 6 x 3 x 6 server block (inner clearance 6.05), 3 down from the pivot:
    # walls, corner pillars, a mid band, louvres on the sides, a window frame, the drum frame,
    # the lamp bracket and the control panel at the back.
    h = [box("Walls", (0, -1.5, 0), (6.4, 3.0, 6.4), m_hull, col, bevel=(0.05, 1))]
    for sx in (1, -1):
        for sz in (1, -1):
            h.append(box(f"Pillar{sx}{sz}", (sx * 3.15, -1.45, sz * 3.15), (0.36, 3.1, 0.36), m_hull, col, bevel=(0.04, 1)))
        for k in range(4):  # louvres on the +-X walls
            h.append(box(f"Louvre{sx}{k}", (sx * 3.24, -0.9 - k * 0.32, -1.2), (0.1, 0.1, 2.0), m_hull, col))
    h.append(box("Band", (0, -2.1, 0), (6.5, 0.18, 6.5), m_hull, col))
    h.append(box("WindowFrame", (0, -1.2, 3.22), (3.9, 0.85, 0.08), m_hull, col))
    for sx in (1, -1):  # drum frame: two A-legs
        for sz in (1, -1):
            h.append(tube(f"Leg{sx}{sz}", [(-0.6 + sx * 1.0, 0.35, 0.1 + sz * 0.75), (-0.6 + sx * 1.0, 1.05, 0.1 + sz * 0.3)], [0.08, 0.07], m_hull, col, sides=4))
        h.append(box(f"Cradle{sx}", (-0.6 + sx * 1.0, 0.75, 0.1), (0.16, 0.16, 1.6), m_hull, col))
    h.append(tube("LampPost", [(2.85, 0.35, 2.85), (2.85, 2.2, 2.85), (2.55, 2.45, 2.55)], [0.07, 0.07, 0.06], m_hull, col, sides=4))
    h.append(box("Panel", (0.9, 0.85, -2.75), (1.4, 1.0, 0.3), m_hull, col, bevel=(0.03, 1)))
    housing = join(h, "Housing", col)
    set_origin(housing, (0, 0, 0))
    parts.append(housing)

    # Roof deck with a raised rim.
    roof = [box("Deck", (0, 0.17, 0), (6.5, 0.34, 6.5), m_roof, col, bevel=(0.05, 1))]
    roof.append(loft("Rim", [rounded_rect((0, 0.34, 0), 3.25, 3.25, 0.1, 1), rounded_rect((0, 0.46, 0), 3.25, 3.25, 0.1, 1)], m_roof, col, cap_start=False, cap_end=False))
    roof = join(roof, "Roof", col)
    set_origin(roof, (0, 0.17, 0))
    parts.append(roof)

    # Composting drum: a banded horizontal cylinder with domed ends, plus tank caps, the
    # chimney's steel sleeve and the panel's dials (steel).
    dx, dy, dz, dr = -0.6, 1.35, 0.1, 0.85
    rings = [[(dx - 1.42, dy, dz)]]
    for x, r in ((-1.3, 0.62), (-1.2, dr), (-1.05, dr + 0.06), (-0.95, dr), (0.95, dr), (1.05, dr + 0.06), (1.2, dr), (1.3, 0.62)):
        rings.append([(dx + x, dy + math.cos(a) * r, dz + math.sin(a) * r) for a in (i / 12 * 2 * math.pi for i in range(12))])
    rings.append([(dx + 1.42, dy, dz)])
    steel = [loft("Drum", rings, m_steel, col)]
    steel.append(torus("DrumBand", (dx, dy, dz), dr + 0.04, 0.06, m_steel, col, major_segments=12, minor_segments=4, axis="X"))
    for k, tz in enumerate((-1.6, -0.35)):
        for y0, y1, r0, r1 in ((0.35, 0.6, 0.6, 0.6), (2.0, 2.25, 0.6, 0.45)):
            steel.append(loft(f"TankCap{k}{y0}", [ring_pts((1.95, y0, tz), r0, r0, 10), ring_pts((1.95, y1, tz), r1, r1, 10)], m_steel, col))
    for k, (bx, bz) in enumerate(((-2.2, 2.1), (-1.45, 2.5), (-2.35, 1.3))):  # biofuel barrels, front-left
        steel.append(loft(f"Barrel{k}", [ring_pts((bx, 0.34, bz), 0.3, 0.3, 8), ring_pts((bx, 0.62, bz), 0.34, 0.34, 8), ring_pts((bx, 1.0, bz), 0.3, 0.3, 8)], m_steel, col))
        steel.append(torus(f"Hoop{k}", (bx, 0.62, bz), 0.345, 0.035, m_steel, col, major_segments=8, minor_segments=3))
    for k in range(3):
        steel.append(cylinder(f"Dial{k}", (0.5 + k * 0.4, 0.95, -2.92), 0.11, 0.06, m_steel, col, sides=8, axis="Z"))
    drum = join(steel, "Drum", col)
    set_origin(drum, (dx, dy, dz))
    parts.append(drum)

    # Flanged copper pipes: drum -> each tank top, hopper -> drum.
    pipes = []
    for k, tz in enumerate((-1.6, -0.35)):
        pts = [(dx + 1.35, dy + 0.2, dz), (1.2, 2.0, dz * 0.5 + tz * 0.5), (1.95, 2.55, tz), (1.95, 2.25, tz)]
        pipes.append(tube(f"Pipe{k}", pts, [0.11] * 4, m_copper, col, sides=8))
        pipes.append(cylinder(f"Flange{k}", (1.95, 2.32, tz), 0.18, 0.08, m_copper, col, sides=8))
    pipes.append(tube("Feed", [(1.35, 0.55, 1.55), (0.6, 0.75, 1.2), (dx + 0.6, dy - 0.55, dz + 0.5)], [0.13, 0.13, 0.12], m_copper, col, sides=8))
    pipes.append(cylinder("FlangeD", (dx + 1.42, dy + 0.2, dz), 0.2, 0.08, m_copper, col, sides=8, axis="X"))
    pipe = join(pipes, "Pipes", col)
    set_origin(pipe, (1.2, 1.8, -0.9))
    parts.append(pipe)

    # Glass tank shells (the one transparent layer) round the opaque biofluid (Slit).
    tanks, fluid = [], []
    for k, tz in enumerate((-1.6, -0.35)):
        tanks.append(loft(f"Tank{k}", [ring_pts((1.95, 0.6, tz), 0.52, 0.52, 10), ring_pts((1.95, 2.0, tz), 0.52, 0.52, 10)], m_glass, col, cap_start=False, cap_end=False))
        fluid.append(loft(f"Fluid{k}", [ring_pts((1.95, 0.6, tz), 0.4, 0.4, 10, 0.3), ring_pts((1.95, 1.75, tz), 0.4, 0.4, 10, 0.3), ring_pts((1.95, 1.82, tz), 0.3, 0.3, 10, 0.3)], m_slit, col))
    tank = join(tanks, "Tanks", col)
    set_origin(tank, (1.95, 1.3, -0.98))
    parts.append(tank)
    slit = join(fluid, "Slit", col)
    set_origin(slit, (1.95, 1.2, -0.98))
    parts.append(slit)

    # Front (+Z, camera side): a wooden-slat intake funnel (the game jitters "Hopper").
    hx, hz = 1.35, 1.65
    funnel = [rounded_rect((hx, 0.4, hz), 0.38, 0.38, 0.06, 1), rounded_rect((hx, 0.75, hz), 0.55, 0.55, 0.08, 1), rounded_rect((hx, 1.4, hz), 0.95, 0.95, 0.1, 1)]
    hop = [loft("Funnel", funnel, m_wood, col)]
    for k in range(4):  # horizontal slats round the funnel's upper rim
        y = 0.85 + k * 0.15
        s = 0.62 + k * 0.1
        hop.append(loft(f"Slat{k}", [rounded_rect((hx, y, hz), s, s, 0.08, 1), rounded_rect((hx, y + 0.07, hz), s + 0.03, s + 0.03, 0.08, 1)], m_wood, col, cap_start=False, cap_end=False))
    hopper = join(hop, "Hopper", col)
    set_origin(hopper, (hx, 0.8, hz))
    parts.append(hopper)

    # Straw spill: a heap in the funnel and a few clumps on the deck.
    straw = [loft("Heap", [ring_pts((hx, 1.25, hz), 0.82, 0.82, 8, 0.2), ring_pts((hx, 1.45, hz), 0.6, 0.6, 8, 0.5), [(hx + 0.1, 1.62, hz - 0.05)]], m_straw, col)]
    for k, (sx_, sz_) in enumerate(((0.3, 2.75), (2.5, 1.0), (0.8, 2.3))):
        straw.append(loft(f"Clump{k}", [ring_pts((sx_, 0.33, sz_), 0.3, 0.22, 6, k), [(sx_ + 0.05, 0.52, sz_)]], m_straw, col))
    straw = join(straw, "Straw", col)
    set_origin(straw, (hx, 0.8, hz))
    parts.append(straw)

    # Work Lamp on its bracket, aimed at the funnel.
    parts.append(loft("Lamp", [ring_pts((2.5, 2.3, 2.5), 0.2, 0.2, 8), ring_pts((2.5, 2.48, 2.5), 0.24, 0.24, 8), [(2.5, 2.6, 2.5)]], m_lamp, col))
    set_origin(parts[-1], (2.5, 2.45, 2.5))

    # Back: chimney (named ChimneyCap: PlotRenderer reads its top for the puffs) + hazard bands.
    cx, cz = -1.9, -1.9
    stack = [loft("Stack", [ring_pts((cx, 0.35, cz), 0.6, 0.6, 8, math.pi / 8), ring_pts((cx, 0.6, cz), 0.48, 0.48, 8, math.pi / 8),
                            ring_pts((cx, 3.0, cz), 0.44, 0.44, 8, math.pi / 8), ring_pts((cx, 3.05, cz), 0.62, 0.62, 8, math.pi / 8),
                            ring_pts((cx, 3.4, cz), 0.62, 0.62, 8, math.pi / 8), ring_pts((cx, 3.4, cz), 0.5, 0.5, 8, math.pi / 8),
                            ring_pts((cx, 3.1, cz), 0.5, 0.5, 8, math.pi / 8)], m_steel, col, cap_start=False)]
    chim = join(stack, "ChimneyCap", col)
    set_origin(chim, (cx, 1.9, cz))
    parts.append(chim)
    bands = [torus(f"Hazard{k}", (cx, 3.12 + k * 0.17, cz), 0.635, 0.05, m_hazard, col, major_segments=8, minor_segments=4, phase=0) for k in range(2)]
    hazard = join(bands, "Hazard", col)
    set_origin(hazard, (cx, 3.2, cz))
    parts.append(hazard)

    # Window: one glass strip on the front wall.
    parts.append(box("Window", (0, -1.2, 3.25), (3.6, 0.6, 0.1), m_glass, col))
    return parts


if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "Stations"))
    problems = []
    # The game pivots a station model on the TOP face of its server block (PlotRenderer
    # `asset:PivotTo(top)`): the charger pad is 0.4 tall, the factory block 3 (its housing wraps it).
    for name, builder, budget, sink, need in (
        ("charger", build_charger, 1500, 0.6, {"Ring1", "Ring2", "Ring3", "Ring4", "PylonLight", "Conduit"}),
        ("factory", build_factory, 4000, 3.0, {"Hopper", "ChimneyCap", "Slit", "Lamp", "Window"}),
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
        missing = need - {p.name for p in parts}
        if missing:
            problems.append(f"{name}: missing the game's parts {sorted(missing)}")
        # World heights (parts keep their own centre as origin, so local z isn't height).
        zs = [max(((p.matrix_world @ v.co).z for v in p.data.vertices), default=0) for p in parts]
        print(f"   max height above pivot: {max(zs):.2f} studs ({'<= 2.5 pad / 3.5 pylon' if name == 'charger' else '<= 6'}), {len(parts)} MeshParts")
        export(parts, os.path.join(out, name))
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Stations.charger / factory. Set WorldPivot = top-face centre.")
    print("Runtime Neon (do NOT bake): Ring1..4 + PylonLight + Conduit cyan while charging; Slit #4DFFB0 + Lamp amber while working.")
    if problems:
        print("\nPROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
