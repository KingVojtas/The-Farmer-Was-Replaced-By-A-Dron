"""
buildings.py - the farm village's buildings and yard props, as low-poly meshes. Blender Python.

    blender -b -P tools/blender/buildings.py -- --out tools/blender/out [--only barn,silo]

Writes Map/<name>.fbx (+ .parts.json) next to props.py's, for tools/build_map.luau. Same rules
as props.py: _common.finalize (Decimate guard, Smart UV, Apply Rot/Scale, pivot check), pivot =
ground centre, front = game -Z, walls collide (Box). Material names choose the detail
MaterialVariant (_common.VARIANT_RULES): *Wall / *Door -> Planks, *Roof -> Shingles,
*Foundation / Chimney -> Stone, Silo / Tank / Tractor -> DroneHull (metal), plants -> CropLeaf /
CropSkin. Colours stay the part's own (the variants are neutral and tinted by Color).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403
from props import M, blob, collide, turn_about  # noqa: E402


def xy_prism(name, pts_xy, z0, z1, mat, col):
    """A gable / end wall: a game-space (x, y) outline extruded from z0 to z1."""
    bm = bmesh.new()
    front = [bm.verts.new(g(x, y, z0)) for x, y in pts_xy]
    back = [bm.verts.new(g(x, y, z1)) for x, y in pts_xy]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts_xy)
    for i in range(n):
        bm.faces.new([front[i], front[(i + 1) % n], back[(i + 1) % n], back[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("SM_" + name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def xy_prism_axis(name, pts_zy, x0, x1, mat, col):
    """The same with a (z, y) outline extruded along x (gables of a roof whose ridge runs along x)."""
    bm = bmesh.new()
    a = [bm.verts.new(g(x0, y, z)) for z, y in pts_zy]
    b = [bm.verts.new(g(x1, y, z)) for z, y in pts_zy]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts_zy)
    for i in range(n):
        bm.faces.new([a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("SM_" + name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def slab(name, center, size, axis, degrees, mat, col):
    """A box turned about its own centre around a game axis (roof planes)."""
    obj = box(name, center, size, mat, col)
    return turn_about(obj, center, axis, degrees)


def gable_roof_x(prefix, half_w, half_d, eave_y, rise, overhang, thick, mat, col):
    """Two roof planes, ridge along game X; returns the two slabs."""
    run = half_d + overhang
    length = math.hypot(run, rise * run / half_d)  # eave overhang continues the slope
    angle = math.degrees(math.atan2(rise, half_d))
    out = []
    for s in (-1, 1):
        cz = s * run / 2
        cy = eave_y + rise / 2 - (overhang * rise / half_d) / 2
        out.append(slab(f"{prefix}{s}", (0, cy + thick / 2, cz), (2 * half_w + 2 * overhang, thick, length), "X", s * angle, mat, col))
    return out


# ------------------------------------------------------------------ buildings
def farmhouse(col):
    stone = M("HouseFoundation", "#8E8880")
    wall = M("HouseWall", "#F2E6CF")
    roof = M("HouseRoof", "#8E3A2A")
    foundation = collide(box("Foundation", (0, 0.4, 0), (14.4, 0.8, 10.4), stone, col))
    walls = collide(box("Walls", (0, 4.8, 0), (14.0, 8.0, 10.0), wall, col))
    gables = [xy_prism_axis(f"Gable{s}", ((-5.0, 8.8), (5.0, 8.8), (0.0, 12.6)), s * 7.0, s * 6.6, wall, col) for s in (-1, 1)]
    slabs = gable_roof_x("Roof", 7.0, 5.0, 8.8, 3.8, 0.7, 0.35, roof, col)
    chimney = box("Chimney", (4.0, 11.4, 2.2), (1.4, 4.2, 1.4), M("HouseChimney", "#9AA1A8"), col)
    door = box("Door", (0, 2.5, -5.06), (1.8, 3.4, 0.2), M("HouseDoor", "#7A4E2E"), col)
    windows = [box(f"Win{k}", (x, y, -5.06), (1.8, 1.6, 0.16), M("HouseWindow", "#9CC7E6"), col)
               for k, (x, y) in enumerate(((-4.2, 3.4), (4.2, 3.4), (-4.2, 6.9), (4.2, 6.9), (0, 6.9)))]
    sills = [box(f"Sill{k}", (x, y - 0.95, -5.12), (2.1, 0.18, 0.3), M("HouseTrim", "#FFFFFF"), col)
             for k, (x, y) in enumerate(((-4.2, 3.4), (4.2, 3.4), (-4.2, 6.9), (4.2, 6.9), (0, 6.9)))]
    porch_floor = box("Porch", (0, 0.95, -6.4), (6.4, 0.3, 2.6), M("PorchWood", "#A06A3C"), col)
    posts = [box(f"PorchPost{s}", (s * 2.9, 2.85, -7.4), (0.3, 3.6, 0.3), M("PorchWood", "#A06A3C"), col) for s in (-1, 1)]
    porch_roof = slab("PorchRoof", (0, 4.75, -6.6), (7.0, 0.25, 3.2), "X", -12, roof, col)
    return [foundation, walls, join(gables, "Gables", col), join(slabs + [porch_roof], "Roof", col), chimney,
            join([door], "Door", col), join(windows, "Windows", col), join(sills, "Trim", col),
            join([porch_floor] + posts, "Porch", col)]


def barn(col):
    red, trim, roof = M("BarnWall", "#B5523B"), M("BarnTrim", "#F2EEE6"), M("BarnRoof", "#5A5F66")
    walls = collide(box("Walls", (0, 4.5, 0), (16.0, 9.0, 20.0), red, col))
    outline = ((-8.0, 9.0), (-5.0, 13.0), (0.0, 15.0), (5.0, 13.0), (8.0, 9.0))
    ends = [xy_prism(f"End{s}", outline, s * 10.0, s * 9.6, red, col) for s in (-1, 1)]
    planes = []
    for s in (-1, 1):
        planes.append(slab(f"Lower{s}", (s * 6.6, 11.1, 0), (0.4, 5.3, 21.0), "Z", s * 37, roof, col))
        planes.append(slab(f"Upper{s}", (s * 2.55, 14.15, 0), (0.4, 5.6, 21.0), "Z", s * 68, roof, col))
    door = box("Door", (0, 3.6, -10.08), (6.4, 7.2, 0.3), M("BarnDoor", "#8E3A2A"), col)
    braces = [slab(f"Brace{s}", (0, 3.6, -10.25), (0.35, 9.4, 0.12), "Z", s * 41, trim, col) for s in (-1, 1)]
    frame = [box(f"Frame{k}", c, s, trim, col) for k, (c, s) in enumerate((((0, 7.3, -10.2), (6.8, 0.35, 0.14)),
                                                                          ((-3.3, 3.6, -10.2), (0.35, 7.2, 0.14)),
                                                                          ((3.3, 3.6, -10.2), (0.35, 7.2, 0.14))))]
    loft = box("Loft", (0, 11.2, -10.08), (3.2, 2.6, 0.3), M("BarnDoor", "#8E3A2A"), col)
    corners = [box(f"Corner{x}{z}", (x * 7.9, 4.5, z * 9.9), (0.45, 9.0, 0.45), trim, col) for x in (-1, 1) for z in (-1, 1)]
    return [walls, join(ends, "Gables", col), join(planes, "Roof", col), join([door, loft], "Door", col),
            join(braces + frame + corners, "Trim", col)]


def silo(col):
    body = collide(cylinder("Silo", (0, 7.6, 0), 3.2, 14.0, M("SiloBody", "#C9CDD2"), col, sides=12))
    base = cylinder("SiloBase", (0, 0.3, 0), 3.5, 0.6, M("SiloBaseStone", "#8E8880"), col, sides=12)
    dome = sphere("Dome", (0, 14.6, 0), 3.3, M("SiloDome", "#B5523B"), col, segments=12, rings=6, scale=(1, 0.55, 1))
    bands = [cylinder(f"Band{k}", (0, y, 0), 3.26, 0.25, M("SiloBand", "#8E959E"), col, sides=12) for k, y in enumerate((4.0, 8.0, 12.0))]
    rails = [box(f"Rail{s}", (s * 0.45, 7.4, -3.35), (0.12, 13.6, 0.12), M("Ladder", "#555E69"), col) for s in (-1, 1)]
    rungs = [box(f"Rung{k}", (0, 1.2 + k * 1.1, -3.35), (0.9, 0.08, 0.08), M("Ladder", "#555E69"), col) for k in range(12)]
    return [body, join([base], "Base", col), join([dome], "Dome", col), join(bands, "Bands", col), join(rails + rungs, "Ladder", col)]


def greenhouse(col):
    stone = M("GreenFoundation", "#8E8880")
    steel = M("GreenFrame", "#EEF2F4")
    glass = material("M_GreenGlass", "#BFE6D8", 0.1, alpha=0.45)
    base = collide(box("Base", (0, 0.4, 0), (12.4, 0.8, 8.4), stone, col))
    panes = [box("PaneL", (-6.0, 2.6, 0), (0.12, 3.6, 8.0), glass, col), box("PaneR", (6.0, 2.6, 0), (0.12, 3.6, 8.0), glass, col),
             box("PaneB", (0, 2.6, 4.0), (12.0, 3.6, 0.12), glass, col), box("PaneF", (0, 2.6, -4.0), (12.0, 3.6, 0.12), glass, col)]
    roof = gable_roof_x("Glass", 6.0, 4.0, 4.4, 2.2, 0.1, 0.12, glass, col)
    gables = [xy_prism_axis(f"GlassEnd{s}", ((-4.0, 4.4), (4.0, 4.4), (0.0, 6.6)), s * 6.0, s * 5.9, glass, col) for s in (-1, 1)]
    frame = [box(f"Post{x}{z}", (x * 6.0, 2.6, z * 4.0), (0.22, 3.6, 0.22), steel, col) for x in (-1, 1) for z in (-1, 1)]
    frame.append(box("Ridge", (0, 6.6, 0), (12.2, 0.22, 0.22), steel, col))
    frame += [box(f"Mullion{k}", (-3.0 + k * 3.0, 2.6, -4.05), (0.15, 3.6, 0.15), steel, col) for k in range(3)]
    beds = [box(f"Bed{s}", (0, 1.05, s * 2.2), (10.0, 0.5, 1.8), M("GreenSoil", "#5A3F27"), col) for s in (-1, 1)]
    plants = [blob(f"Plant{k}", (-4.0 + (k % 5) * 2.0, 1.65, (1 if k < 5 else -1) * 2.2), 0.55, M("GreenLeaf", "#5E9C48"), col, 400 + k)
              for k in range(10)]
    return [base, join(panes, "Glass", col), join(roof + gables, "GlassRoof", col), join(frame, "Frame", col),
            join(beds, "Beds", col), join(plants, "Plants", col)]


def chicken_coop(col):
    wall, roof = M("CoopWall", "#D9B27A"), M("CoopRoof", "#8E3A2A")
    legs = [box(f"Leg{x}{z}", (x * 1.8, 0.6, z * 1.3), (0.25, 1.2, 0.25), M("CoopWood", "#8A6A4A"), col) for x in (-1, 1) for z in (-1, 1)]
    house = collide(box("House", (0, 2.5, 0), (4.0, 2.6, 3.0), wall, col))
    gables = [xy_prism_axis(f"Gable{s}", ((-1.5, 3.8), (1.5, 3.8), (0.0, 5.0)), s * 2.0, s * 1.9, wall, col) for s in (-1, 1)]
    slabs = gable_roof_x("Roof", 2.0, 1.5, 3.8, 1.2, 0.3, 0.18, roof, col)
    door = box("Door", (0.9, 2.2, -1.53), (0.8, 1.0, 0.08), M("CoopDoor", "#6E5238"), col)
    ramp = slab("Ramp", (0.9, 0.85, -2.6), (0.7, 0.08, 2.4), "X", -36, M("CoopWood", "#8A6A4A"), col)
    posts, rails = [], []
    for k, (x, z) in enumerate(((-3.0, -2.0), (3.0, -2.0), (3.0, -6.0), (-3.0, -6.0))):
        posts.append(box(f"RunPost{k}", (x, 0.5, z), (0.15, 1.0, 0.15), M("CoopWood", "#8A6A4A"), col))
    for k, (c, s) in enumerate((((0, 0.8, -6.0), (6.0, 0.08, 0.08)), ((-3.0, 0.8, -4.0), (0.08, 0.08, 4.0)), ((3.0, 0.8, -4.0), (0.08, 0.08, 4.0)))):
        rails.append(box(f"RunRail{k}", c, s, M("CoopWood", "#8A6A4A"), col))
    hens, combs = [], []
    for k, (x, z) in enumerate(((-1.6, -3.6), (0.4, -4.6), (1.8, -3.2))):
        hens.append(sphere(f"Hen{k}", (x, 0.38, z), 0.35, M("Hen", "#F4F1EA"), col, segments=6, rings=4, scale=(1, 0.9, 1.25)))
        hens.append(sphere(f"HenHead{k}", (x, 0.72, z - 0.35), 0.18, M("Hen", "#F4F1EA"), col, segments=5, rings=3))
        combs.append(box(f"Comb{k}", (x, 0.92, z - 0.35), (0.06, 0.12, 0.16), M("Comb", "#D9434A"), col))
    return [join(legs + [door, ramp] + posts + rails, "CoopFrame", col), house, join(gables, "Gables", col), join(slabs, "Roof", col),
            join(hens, "Hens", col), join(combs, "Combs", col)]


def water_tower(col):
    legs = []
    for k, (x, z) in enumerate(((-2.2, -2.2), (2.2, -2.2), (2.2, 2.2), (-2.2, 2.2))):
        leg = cylinder(f"Leg{k}", (x * 0.92, 5.0, z * 0.92), 0.22, 10.2, M("TowerWood", "#8A6A4A"), col, sides=6)
        legs.append(collide(leg))
    braces = [box(f"Brace{k}", (0, 3.5 + (k // 2) * 3.4, (-1 if k % 2 == 0 else 1) * 2.05), (4.2, 0.18, 0.18), M("TowerWood", "#8A6A4A"), col) for k in range(4)]
    braces += [box(f"BraceX{k}", ((-1 if k % 2 == 0 else 1) * 2.05, 3.5 + (k // 2) * 3.4, 0), (0.18, 0.18, 4.2), M("TowerWood", "#8A6A4A"), col) for k in range(4)]
    deck = box("Deck", (0, 10.2, 0), (6.0, 0.3, 6.0), M("TowerWood", "#8A6A4A"), col)
    tank = cylinder("Tank", (0, 12.4, 0), 2.9, 4.0, M("TowerTank", "#7F93A8"), col, sides=12)
    hoops = [cylinder(f"Hoop{k}", (0, y, 0), 2.95, 0.18, M("TankHoop", "#4A5560"), col, sides=12) for k, y in enumerate((11.0, 13.8))]
    roof = cone("Roof", (0, 15.4, 0), 3.2, 2.0, M("TowerRoof", "#8E3A2A"), col, sides=12)
    return [join(legs, "Legs", col), join(braces + [deck], "Frame", col), tank, join(hoops, "Hoops", col), join([roof], "Roof", col)]


def tool_shed(col):
    wall = M("ShedWall", "#5E8A5A")
    # lean-to: low front (game -Z), high back; one prism so the sides close under the roof
    walls = collide(xy_prism_axis("Walls", ((-2.0, 0.0), (2.0, 0.0), (2.0, 4.3), (-2.0, 3.5)), -2.2, 2.2, wall, col))
    roof = slab("Roof", (0, 4.02, 0), (5.0, 0.22, 4.9), "X", -11.3, M("ShedRoof", "#5A5F66"), col)
    door = box("Door", (0, 1.4, -2.03), (1.4, 2.6, 0.12), M("ShedDoor", "#8A6A4A"), col)
    window = box("Window", (1.4, 2.4, -2.03), (0.8, 0.7, 0.1), M("ShedWindow", "#9CC7E6"), col)
    return [walls, join([roof], "Roof", col), join([door], "Door", col), window]


def market_stall(col):
    wood = M("StallWood", "#A06A3C")
    counter = collide(box("Counter", (0, 0.55, -0.4), (5.0, 1.1, 1.4), wood, col))
    posts = [box(f"Post{x}{z}", (x * 2.4, 1.6, z * 1.1), (0.2, 3.2, 0.2), wood, col) for x in (-1, 1) for z in (-1, 1)]
    stripes = []
    for k in range(6):
        color = M("AwningRed", "#D9434A") if k % 2 == 0 else M("AwningWhite", "#F4F1EA")
        stripes.append(slab(f"Stripe{k}", (-2.1 + k * 0.84, 3.3, -0.2), (0.84, 0.12, 3.2), "X", -10, color, col))
    crates = [box(f"Crate{k}", (-1.6 + k * 1.6, 1.3, -0.6), (1.2, 0.4, 0.9), M("CrateWood", "#B07B45"), col) for k in range(3)]
    produce = []
    for k, (hexc, name) in enumerate((("#F08030", "VegCarrot"), ("#D9434A", "VegTomato"), ("#7DC45A", "VegCabbageLeaf"))):
        for j in range(4):
            produce.append(sphere(f"{name}{j}", (-1.6 + k * 1.6 + (j % 2 - 0.5) * 0.5, 1.62, -0.6 + (j // 2 - 0.5) * 0.4), 0.22,
                                  M(name, hexc), col, segments=6, rings=4))
    return [join([counter] + posts, "Stall", col)] + [s for s in stripes[:1]] + [join(stripes[1:], "Awning", col)] + [join(crates, "Crates", col)] + [join(produce, "Produce", col)]


def tractor(col):
    body = collide(box("Body", (0, 1.7, 0.2), (2.4, 1.4, 4.2), M("TractorBody", "#C8432F"), col, bevel=(0.12, 1)))
    hood = box("Hood", (0, 2.3, -1.3), (1.9, 0.8, 1.8), M("TractorBody", "#C8432F"), col, bevel=(0.1, 1))
    grille = box("Grille", (0, 1.9, -2.15), (1.6, 1.0, 0.1), M("Grille", "#2E3846"), col)
    cab_posts = [box(f"Cab{x}{z}", (x * 1.0, 3.6, 1.0 + z * 0.9), (0.14, 2.4, 0.14), M("Cab", "#2E3846"), col) for x in (-1, 1) for z in (-1, 1)]
    cab_roof = box("CabRoof", (0, 4.85, 1.0), (2.4, 0.16, 2.2), M("TractorTopSteel", "#F2EEE6"), col)
    seat = box("Seat", (0, 2.75, 1.3), (0.9, 0.3, 0.8), M("Seat", "#2E3846"), col)
    wheels = [cylinder(f"Rear{s}", (s * 1.45, 1.35, 1.2), 1.35, 0.7, M("Tyre", "#2A2A2A"), col, sides=12, axis="X") for s in (-1, 1)]
    wheels += [cylinder(f"Front{s}", (s * 1.25, 0.75, -1.4), 0.75, 0.5, M("Tyre", "#2A2A2A"), col, sides=10, axis="X") for s in (-1, 1)]
    hubs = [cylinder(f"Hub{k}", (x, y, z), r, 0.74 if r > 0.5 else 0.54, M("WheelHub", "#E3C463"), col, sides=8, axis="X")
            for k, (x, y, z, r) in enumerate(((-1.45, 1.35, 1.2, 0.55), (1.45, 1.35, 1.2, 0.55), (-1.25, 0.75, -1.4, 0.3), (1.25, 0.75, -1.4, 0.3)))]
    pipe = cylinder("Exhaust", (0.6, 3.4, -1.6), 0.1, 1.6, M("Pipe", "#4A5560"), col, sides=6)
    return [join([body, hood], "Body", col), grille, join(cab_posts + [seat, pipe], "Cab", col), cab_roof, join(wheels, "Wheels", col), join(hubs, "Hubs", col)]


def fence_segment(col):
    white = M("PicketFence", "#F2EEE6")
    rails = [box(f"Rail{k}", (0, y, 0), (6.0, 0.14, 0.1), white, col) for k, y in enumerate((0.45, 0.95))]
    pickets = [box(f"Picket{k}", (-2.75 + k * 0.5, 0.65, 0), (0.22, 1.3, 0.1), white, col) for k in range(12)]
    tips = [cone(f"Tip{k}", (-2.75 + k * 0.5, 1.38, 0), 0.16, 0.18, white, col, sides=4) for k in range(12)]
    return [join(rails + pickets + tips, "PicketFence", col)]


def garden_bed(col):
    frame = collide(box("Frame", (0, 0.25, 0), (4.2, 0.5, 2.2), M("BedWood", "#8A6A4A"), col))
    soil = box("Soil", (0, 0.42, 0), (3.8, 0.2, 1.8), M("BedSoil", "#5A3F27"), col)
    cabbages = [blob(f"Cabbage{k}", (-1.4 + k * 0.95, 0.75, -0.45), 0.36, M("CabbageLeaf", "#7DC45A"), col, 500 + k) for k in range(4)]
    carrots = [cone(f"CarrotTop{k}", (-1.4 + k * 0.95, 0.8, 0.45), 0.2, 0.5, M("CarrotLeaf", "#4F8A3C"), col, sides=5) for k in range(4)]
    return [frame, soil, join(cabbages + carrots, "Veg", col)]


def haystack(col):
    mound = collide(sphere("Stack", (0, 1.4, 0), 2.2, M("Haystack", "#E3C463"), col, segments=10, rings=6, scale=(1.0, 0.75, 1.0)))
    top = cone("Top", (0, 2.9, 0), 1.3, 1.2, M("HayTop", "#D9B54F"), col, sides=10)
    return [mound, join([top], "Stack_Top", col)]


# name -> (builder, budget)
BUILDINGS = {
    "farmhouse": (farmhouse, 3000),
    "barn": (barn, 3000),
    "silo": (silo, 3000),
    "greenhouse": (greenhouse, 3000),
    "chicken_coop": (chicken_coop, 3000),
    "water_tower": (water_tower, 3000),
    "tool_shed": (tool_shed, 600),
    "market_stall": (market_stall, 600),
    "tractor": (tractor, 600),
    "fence_segment": (fence_segment, 600),
    "garden_bed": (garden_bed, 600),
    "haystack": (haystack, 600),
}

if __name__ == "__main__":
    a = args_after_dashes()
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))
    only = a[a.index("--only") + 1].split(",") if "--only" in a else list(BUILDINGS)
    problems = []
    for name in only:
        builder, budget = BUILDINGS[name]
        scene = reset_scene()
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
        parts = builder(col)
        for p in parts:
            shade_flat(p)
        parts, found = finalize(parts, budget, pivot="bottom")
        problems += [f"{name}: {p}" for p in found]
        if report(name, parts, budget) > budget:
            problems.append(f"{name}: over {budget} tris")
        export(parts, os.path.join(out, "Map", name))
    if problems:
        print("\nPROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
