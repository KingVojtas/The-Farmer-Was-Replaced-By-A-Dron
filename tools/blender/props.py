"""
props.py - the world around the plots, as low-poly meshes. Blender Python.

    blender -b -P tools/blender/props.py -- --out tools/blender/out [--only oak,pine]

Writes Map/<name>.fbx (+ .parts.json) for tools/build_map.luau, which places them into
map/Map.rbxm (Workspace.Map). All through _common.finalize (Decimate guard, Smart UV, Apply
Rot/Scale, pivot check). Pivot = ground centre (y = 0) for everything; "front" = game -Z.
Style: ART_BIBLE chunky low-poly, flat SmoothPlastic colours (no textures), faceted spheres /
cones with a few sides; the palette leans on the Bible's organics (warm greens, browns).
Collide: only parts a player should bump into (trunks, rocks, buildings); foliage, flowers,
paths and water never collide.
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _common  # noqa: E402
from _common import *  # noqa: E402,F403


# ------------------------------------------------------------------ helpers
def M(name, hexc, rough=0.75, emissive=None, roblox=None):
    return material("M_" + name, hexc, rough, emissive=emissive, roblox=roblox)


def collide(obj):
    set_prop(obj, "Collide", True)
    return obj


def rock_mesh(name, center, radius, mat, col, seed, scale=(1.0, 0.7, 1.0), subdivisions=1):
    """A faceted boulder: an ico sphere with every vertex pushed in or out a little."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=g(*center))
    obj = bpy.context.active_object
    rng = random.Random(seed)
    for v in obj.data.vertices:
        v.co *= rng.uniform(0.8, 1.15)
    obj.scale = gsize(*scale)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _common._finish(obj, name, mat, col)


def blob(name, center, radius, mat, col, seed, scale=(1.0, 1.0, 1.0)):
    """Foliage: a low faceted sphere, slightly irregular (6 x 4)."""
    obj = sphere(name, center, radius, mat, col, segments=6, rings=4, scale=scale)
    rng = random.Random(seed)
    for v in obj.data.vertices:
        v.co *= rng.uniform(0.88, 1.1)
    return obj


def prism(name, pts, y0, y1, mat, col):
    """A flat slab from a game-space (x, z) outline: paths, water, plazas."""
    bm = bmesh.new()
    bottom = [bm.verts.new(g(x, y0, z)) for x, z in pts]
    top = [bm.verts.new(g(x, y1, z)) for x, z in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    n = len(pts)
    for i in range(n):
        bm.faces.new([bottom[i], bottom[(i + 1) % n], top[(i + 1) % n], top[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("SM_" + name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def blob_outline(n, rx, rz, seed, wobble=0.18):
    rng = random.Random(seed)
    return [
        (math.cos(t) * rx * rng.uniform(1 - wobble, 1 + wobble), math.sin(t) * rz * rng.uniform(1 - wobble, 1 + wobble))
        for t in (k / n * 2 * math.pi for k in range(n))
    ]


def turn_about(obj, pivot, axis, degrees):
    """Rotates `obj` around a game-space point (its origin moves there first, then stays)."""
    set_origin(obj, pivot)
    euler = {"X": (math.radians(degrees), 0, 0), "Y": (0, 0, math.radians(degrees)), "Z": (0, math.radians(-degrees), 0)}[axis]
    obj.rotation_euler = euler
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return obj


# ------------------------------------------------------------------ nature
TRUNK, BIRCH_BARK = "#7A5034", "#E8E4DA"
LEAF_A, LEAF_B, LEAF_C, PINE, BIRCH_LEAF = "#5E9C48", "#6FB052", "#4E8A3C", "#3E7A47", "#8DC461"


def oak(col):
    trunk = collide(cylinder("Trunk", (0, 1.8, 0), 0.5, 3.6, M("Trunk", TRUNK), col, sides=7))
    crown = [
        blob("Crown1", (0, 5.4, 0), 2.5, M("LeafA", LEAF_A), col, 1),
        blob("Crown2", (1.6, 4.7, 0.6), 1.8, M("LeafB", LEAF_B), col, 2),
        blob("Crown3", (-1.4, 4.9, -0.7), 1.9, M("LeafB", LEAF_B), col, 3),
    ]
    return [trunk, join(crown[:1], "Crown", col), join(crown[1:], "Crown_Light", col)]


def pine(col):
    trunk = collide(cylinder("Trunk", (0, 1.0, 0), 0.4, 2.0, M("Trunk", TRUNK), col, sides=6))
    tiers = [cone(f"Tier{k}", (0, 2.4 + k * 1.9, 0), r, h, M("Pine", PINE), col, sides=7)
             for k, (r, h) in enumerate(((2.7, 3.2), (2.1, 2.8), (1.4, 2.4)))]
    return [trunk, join(tiers, "Needles", col)]


def birch(col):
    bark = M("BirchBark", BIRCH_BARK)
    trunk = collide(cylinder("Trunk", (0, 2.6, 0), 0.3, 5.2, bark, col, sides=6))
    marks = [box(f"Mark{k}", (0.0, 1.2 + k * 1.1, -0.29), (0.32, 0.12, 0.06), M("BirchMark", "#3A3532"), col) for k in range(4)]
    crown = [blob("Crown1", (0.2, 6.2, 0), 1.9, M("BirchLeaf", BIRCH_LEAF), col, 4, (1, 1.25, 1)),
             blob("Crown2", (-0.8, 5.3, 0.4), 1.4, M("BirchLeaf", BIRCH_LEAF), col, 5)]
    return [trunk, join(marks, "Trunk_Marks", col), join(crown, "Crown", col)]


def bush(col):
    leaves = [blob(f"B{k}", c, r, M("Bush", LEAF_C), col, 10 + k, (1, 0.8, 1))
              for k, (c, r) in enumerate((((0, 0.8, 0), 1.0), ((0.8, 0.6, 0.3), 0.75), ((-0.7, 0.6, -0.2), 0.7)))]
    return [join(leaves, "Bush", col)]


def berry_bush(col):
    parts = bush(col)
    rng = random.Random(21)
    berries = [sphere(f"Berry{k}", (rng.uniform(-0.9, 0.9), rng.uniform(0.6, 1.4), rng.uniform(-1.0, -0.5)), 0.14,
                      M("Berry", "#D9434A"), col, segments=5, rings=3) for k in range(7)]
    return parts + [join(berries, "Bush_Berries", col)]


def rock(size, seed):
    def build(col):
        r = {"small": 0.6, "medium": 1.3, "large": 2.4}[size]
        stone = rock_mesh("Rock", (0, r * 0.45, 0), r, M("Stone", "#8D96A0"), col, seed, (1.15, 0.75, 1.0),
                          subdivisions=1 if size == "small" else 2)
        if size != "small":
            collide(stone)
        return [stone]
    return build


def flowers(color_name, hexc, seed):
    def build(col):
        rng = random.Random(seed)
        stems, heads = [], []
        for k in range(6):
            x, z = rng.uniform(-0.9, 0.9), rng.uniform(-0.9, 0.9)
            h = rng.uniform(0.5, 0.9)
            stems.append(box(f"Stem{k}", (x, h / 2, z), (0.06, h, 0.06), M("Stem", "#4F8A3C"), col))
            heads.append(sphere(f"Head{k}", (x, h + 0.08, z), 0.16, M("Petal" + color_name, hexc), col, segments=5, rings=3))
        return [join(stems, "Stems", col), join(heads, "Flowers", col)]
    return build


def grass_tuft(col):
    rng = random.Random(31)
    blades = [wedge(f"Blade{k}", (rng.uniform(-0.3, 0.3), 0, rng.uniform(-0.3, 0.3)),
                    (rng.uniform(-0.7, 0.7), rng.uniform(0.6, 1.1), rng.uniform(-0.7, 0.7)), 0.18, 0.05, M("Tuft", "#6DA84C"), col)
              for k in range(7)]
    return [join(blades, "Tuft", col)]


def log(col):
    body = collide(cylinder("Log", (0, 0.42, 0), 0.42, 2.8, M("Bark", "#7A5034"), col, sides=8, axis="X"))
    ends = [cylinder(f"End{s}", (s * 1.41, 0.42, 0), 0.36, 0.04, M("Rings", "#D9B27A"), col, sides=8, axis="X") for s in (-1, 1)]
    return [body, join(ends, "Log_Ends", col)]


def mushroom(col):
    stem = cylinder("Stem", (0, 0.25, 0), 0.12, 0.5, M("MushStem", "#EFE6D2"), col, sides=6)
    cap = sphere("Cap", (0, 0.55, 0), 0.38, M("MushCap", "#D9434A"), col, segments=8, rings=4, scale=(1, 0.55, 1))
    spots = [sphere(f"Spot{k}", (math.cos(a) * 0.22, 0.7, math.sin(a) * 0.22), 0.06, M("MushSpot", "#FFFFFF"), col, segments=4, rings=3)
             for k, a in enumerate((0.3, 2.2, 4.1))]
    return [stem, cap, join(spots, "Cap_Spots", col)]


# ------------------------------------------------------------------ farm props
def hay_bale(col):
    bale = collide(box("Bale", (0, 0.6, 0), (2.0, 1.2, 1.4), M("Hay", "#E3C463"), col, bevel=(0.1, 1)))
    bands = [box(f"Band{s}", (s * 0.55, 0.6, 0), (0.08, 1.24, 1.44), M("Twine", "#8A6A4A"), col) for s in (-1, 1)]
    return [bale, join(bands, "Bale_Twine", col)]


def crate(col):
    body = collide(box("Crate", (0, 0.7, 0), (1.4, 1.4, 1.4), M("Crate", "#B07B45"), col, bevel=(0.05, 1)))
    slats = [box(f"Slat{k}", (0, 0.35 + k * 0.7, -0.71), (1.3, 0.12, 0.04), M("CrateDark", "#8A5D33"), col) for k in range(2)]
    return [body, join(slats, "Crate_Slats", col)]


def barrel(col):
    body = collide(cylinder("Barrel", (0, 0.7, 0), 0.6, 1.4, M("Barrel", "#8E5D35"), col, sides=10))
    bands = [cylinder(f"Hoop{k}", (0, y, 0), 0.62, 0.08, M("Hoop", "#555E69"), col, sides=10) for k, y in enumerate((0.25, 1.15))]
    return [body, join(bands, "Barrel_Hoops", col)]


def cart(col):
    wood = M("Cart", "#A06A3C")
    bed = collide(box("Cart", (0, 1.1, 0), (2.6, 0.6, 1.6), wood, col, bevel=(0.04, 1)))
    shafts = [box(f"Shaft{s}", (1.9, 0.9, s * 0.6), (1.6, 0.12, 0.12), wood, col) for s in (-1, 1)]
    wheels = [cylinder(f"Wheel{s}", (-0.3, 0.6, s * 0.9), 0.6, 0.16, M("Wheel", "#5A3F27"), col, sides=10, axis="Z") for s in (-1, 1)]
    load = [box("Load", (-0.2, 1.55, 0), (1.8, 0.5, 1.2), M("Hay", "#E3C463"), col, bevel=(0.08, 1))]
    return [join([bed] + shafts, "Cart", col), join(wheels, "Cart_Wheels", col), join(load, "Cart_Load", col)]


def scarecrow(col):
    pole = collide(cylinder("Pole", (0, 1.5, 0), 0.1, 3.0, M("Pole", "#8A6A4A"), col, sides=6))
    arms = box("Arms", (0, 2.2, 0), (2.4, 0.12, 0.12), M("Pole", "#8A6A4A"), col)
    shirt = box("Shirt", (0, 1.95, 0), (1.1, 1.0, 0.45), M("Shirt", "#4F7FB5"), col, bevel=(0.05, 1))
    head = sphere("Head", (0, 2.75, 0), 0.38, M("Sack", "#D8C18F"), col, segments=7, rings=5)
    hat = cone("Hat", (0, 3.2, 0), 0.6, 0.55, M("StrawHat", "#E3C463"), col, sides=8)
    brim = cylinder("Brim", (0, 3.0, 0), 0.75, 0.06, M("StrawHat", "#E3C463"), col, sides=10)
    return [join([pole, arms], "Pole", col), shirt, head, join([hat, brim], "Hat", col)]


def well(col):
    stone = collide(cylinder("Well", (0, 0.5, 0), 1.4, 1.0, M("WellStone", "#9AA1A8"), col, sides=12))
    water = cylinder("Water", (0, 0.95, 0), 1.1, 0.04, M("WellWater", "#2E5E8C"), col, sides=12)
    posts = [box(f"Post{s}", (s * 1.2, 1.9, 0), (0.18, 1.9, 0.18), M("WellWood", "#8A6A4A"), col) for s in (-1, 1)]
    roof = [box(f"Roof{s}", (s * 0.75, 3.05, 0), (1.7, 0.12, 2.2), M("WellRoof", "#B5523B"), col) for s in (-1, 1)]
    for s, slab in zip((-1, 1), roof):
        slab.rotation_euler = (0, math.radians(32 * s), 0)
        bpy.ops.object.select_all(action="DESELECT")
        slab.select_set(True)
        bpy.context.view_layer.objects.active = slab
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    crank = cylinder("Crank", (0, 2.4, 0), 0.1, 2.3, M("WellWood", "#8A6A4A"), col, sides=6, axis="X")
    return [stone, water, join(posts + [crank], "Well_Frame", col), join(roof, "Well_Roof", col)]


def lamp_post(col):
    metal = M("LampMetal", "#2E3846", 0.5)
    pole = collide(cylinder("Pole", (0, 2.1, 0), 0.13, 4.2, metal, col, sides=6))
    arm = box("Arm", (0.35, 4.05, 0), (0.8, 0.1, 0.1), metal, col)
    lantern = box("Lantern", (0.7, 3.75, 0), (0.42, 0.5, 0.42), metal, col, bevel=(0.04, 1))
    bulb = box("Bulb", (0.7, 3.72, 0), (0.3, 0.32, 0.44), M("LampLight", "#FFD27A", emissive="#FFD27A"), col)
    return [join([pole, arm, lantern], "LampPost", col), bulb]


def bench(col):
    wood = M("BenchWood", "#A06A3C", roblox=None)
    seat = collide(box("Seat", (0, 0.75, 0), (2.4, 0.14, 0.7), wood, col, bevel=(0.03, 1)))
    back = box("Back", (0, 1.25, 0.32), (2.4, 0.5, 0.1), wood, col, bevel=(0.03, 1))
    legs = [box(f"Leg{x}{z}", (x, 0.36, z), (0.12, 0.72, 0.12), M("BenchIron", "#2E3846"), col) for x in (-1.0, 1.0) for z in (-0.25, 0.25)]
    return [join([seat, back], "Bench", col), join(legs, "Bench_Legs", col)]


# ------------------------------------------------------------------ landmarks + ground pieces
def windmill(col):
    """The spawn landmark: a white tower, red cap, four blades on the front (game -Z)."""
    tower = collide(cylinder("Tower", (0, 4.5, 0), 2.4, 9.0, M("Tower", "#E9E2D2"), col, sides=8))
    band = cylinder("Band", (0, 0.3, 0), 2.5, 0.6, M("TowerBase", "#9AA1A8"), col, sides=8)
    cap = cone("Cap", (0, 10.3, 0), 2.9, 2.6, M("Roof", "#B5523B"), col, sides=8)
    door = box("Door", (0, 1.1, -2.32), (1.0, 2.0, 0.2), M("Door", "#6E5238"), col)
    window = box("Window", (0, 5.6, -2.3), (0.8, 0.8, 0.15), M("Window", "#5B7FA6"), col)
    hub = cylinder("Hub", (0, 8.2, -2.7), 0.35, 0.6, M("Hub", "#555E69"), col, sides=8, axis="Z")
    blades = []
    for k in range(4):
        b = box(f"Blade{k}", (0, 8.2 + 2.9, -3.0), (0.9, 5.4, 0.1), M("Sail", "#F2EEE6"), col)
        frame = box(f"Spar{k}", (0, 8.2 + 2.6, -2.95), (0.14, 5.2, 0.12), M("Spar", "#6E5238"), col)
        part = join([b, frame], f"Blade{k}", col)
        blades.append(turn_about(part, (0, 8.2, -3.0), "Z", 45 + 90 * k))
    return [join([tower, band], "Tower", col), join([cap], "Roof", col), join([door], "Door", col), window, hub,
            join(blades, "Blades", col)]


def welcome_sign(col):
    wood = M("SignWood", "#8A6A4A", roblox="Wood")
    posts = [collide(box(f"Post{s}", (s * 2.6, 1.6, 0), (0.3, 3.2, 0.3), wood, col)) for s in (-1, 1)]
    board = box("Board", (0, 2.6, -0.05), (6.0, 2.2, 0.3), M("SignBoard", "#D9B27A", roblox="WoodPlanks"), col, bevel=(0.05, 1))
    roof = box("Roof", (0, 3.85, 0), (6.6, 0.18, 0.9), M("SignRoof", "#B5523B"), col)
    return [join(posts, "Posts", col), board, roof]


def plaza(col):
    def octagon(r):
        return [(math.cos(math.pi / 8 + k * math.pi / 4) * r, math.sin(math.pi / 8 + k * math.pi / 4) * r) for k in range(8)]
    outer = prism("Plaza", octagon(15.0), 0.0, 0.1, M("PlazaStone", "#A9A39A"), col)
    inner = prism("Plaza_Inner", octagon(11.0), 0.1, 0.14, M("PlazaInner", "#8E8880"), col)
    centre = prism("Plaza_Centre", octagon(4.0), 0.14, 0.18, M("PlazaCentre", "#C9C1B2"), col)
    return [outer, inner, centre]


def path_segment(col):
    rng = random.Random(41)
    left = [(-3.0 + rng.uniform(-0.35, 0.35), z) for z in (6.0, 3.0, 0.0, -3.0, -6.0)]
    right = [(3.0 + rng.uniform(-0.35, 0.35), z) for z in (-6.0, -3.0, 0.0, 3.0, 6.0)]
    return [prism("Path", left + right, 0.0, 0.05, M("Dirt", "#9C7B55"), col)]


def pond(col):
    shore = prism("Shore", blob_outline(12, 11.0, 8.0, 51, 0.12), 0.0, 0.05, M("Sand", "#CDB98A"), col)
    water = prism("Water", blob_outline(12, 9.4, 6.6, 52, 0.1), 0.05, 0.09, M("Water", "#4A8FC4"), col)
    pads = [cylinder(f"Pad{k}", (x, 0.11, z), r, 0.03, M("LilyPad", "#5E9C48"), col, sides=7)
            for k, (x, z, r) in enumerate(((-3.5, 1.2, 0.8), (2.0, -2.2, 0.6), (4.6, 2.4, 0.7), (-1.0, -3.1, 0.5)))]
    reeds = []
    for k, (x, z) in enumerate(((-9.6, 3.0), (-9.0, 4.2), (8.8, -3.5), (9.6, -2.4))):
        reeds.append(cylinder(f"Reed{k}", (x, 0.8, z), 0.05, 1.6, M("Reed", "#6DA84C"), col, sides=4))
        reeds.append(cylinder(f"Tail{k}", (x, 1.5, z), 0.1, 0.4, M("Cattail", "#6E4A2E"), col, sides=5))
    return [shore, water, join(pads, "LilyPads", col), join(reeds, "Reeds", col)]


def hedge(col):
    body = collide(box("Hedge", (0, 0.8, 0), (6.0, 1.6, 1.2), M("Hedge", "#4F8A3E"), col, bevel=(0.15, 1)))
    bumps = [blob(f"Bump{k}", (x, 1.55, 0), 0.6, M("Hedge", "#4F8A3E"), col, 60 + k, (1.2, 0.6, 1.1)) for k, x in enumerate((-2.0, 0.0, 2.0))]
    return [join([body] + bumps, "Hedge", col)]


def hill(seed, scale):
    def build(col):
        rng = random.Random(seed)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
        obj = bpy.context.active_object
        for v in obj.data.vertices:
            v.co *= rng.uniform(0.86, 1.1)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.co.z < -0.05 for v in f.verts)], context="FACES")
        for v in bm.verts:  # flatten whatever still dips below the ground line
            v.co.z = max(v.co.z, 0.0)
        bm.to_mesh(obj.data)
        bm.free()
        obj.scale = gsize(*scale)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        return [_common._finish(obj, "Hill", M("Hill", "#6E8A66"), col)]
    return build


# name -> (builder, budget)
PROPS = {
    "oak": (oak, 400),
    "pine": (pine, 200),
    "birch": (birch, 300),
    "bush": (bush, 200),
    "berry_bush": (berry_bush, 400),
    "rock_small": (rock("small", 71), 60),
    "rock_medium": (rock("medium", 72), 120),
    "rock_large": (rock("large", 73), 120),
    "flowers_yellow": (flowers("Yellow", "#FFD23F", 81), 300),
    "flowers_pink": (flowers("Pink", "#FF7FB0", 82), 300),
    "flowers_white": (flowers("White", "#F4F1EA", 83), 300),
    "grass_tuft": (grass_tuft, 120),
    "log": (log, 120),
    "mushroom": (mushroom, 200),
    "hay_bale": (hay_bale, 120),
    "crate": (crate, 80),
    "barrel": (barrel, 160),
    "cart": (cart, 300),
    "scarecrow": (scarecrow, 300),
    "well": (well, 400),
    "lamp_post": (lamp_post, 160),
    "bench": (bench, 200),
    "windmill": (windmill, 1500),
    "welcome_sign": (welcome_sign, 160),
    "plaza": (plaza, 120),
    "path": (path_segment, 60),
    "pond": (pond, 400),
    "hedge": (hedge, 450),
    "hill_a": (hill(91, (220, 90, 160)), 700),
    "hill_b": (hill(92, (300, 70, 200)), 700),
    "hill_c": (hill(93, (180, 120, 150)), 700),
}

if __name__ == "__main__":
    a = args_after_dashes()
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))
    only = a[a.index("--only") + 1].split(",") if "--only" in a else list(PROPS)
    problems = []
    for name in only:
        builder, budget = PROPS[name]
        scene = reset_scene()
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
        parts = builder(col)
        for p in parts:
            shade_flat(p)
        # hills and boulders are meant to sit partly in the ground
        sink = 5.0 if name.startswith("hill") else 1.0 if name.startswith("rock") else 0.6
        parts, found = finalize(parts, budget, pivot="bottom", sink_limit=sink)
        problems += [f"{name}: {p}" for p in found]
        if report(name, parts, budget) > budget:
            problems.append(f"{name}: over {budget} tris")
        export(parts, os.path.join(out, "Map", name))
    if problems:
        print("\nPROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
