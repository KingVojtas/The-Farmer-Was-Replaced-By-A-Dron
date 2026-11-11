"""
crops.py - all 7 crops x 3 stages (ART_BIBLE.md §3). Blender Python.

    blender -b -P tools/blender/crops.py -- --out tools/blender/out/Crops

Writes out/Crops/<cropId>/<stage>.fbx (+ .glb preview). Pivot = tile-top centre (game 0,0,0),
+Y up. ONE mesh per stage (the pumpkin's ready stem is joined too). Opaque, no alpha cards:
leaves are thin wedges. Ready footprint <= 5.2 x 5.2. Authored sizes follow §3.1: sprouts are
2.2 tall (shown at 0.25-0.55), growing ~0.9 x ready height (shown at 0.55-0.85), ready 1.0.
Ready changes SILHOUETTE + COLOUR, never only scale. CastShadow is set in Studio
(off on sprout + grass; AssetLibrary also forces it off).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

STAGES = ("sprout", "growing", "ready")
CROPS = ("grass", "wheat", "carrot", "tree", "sunflower", "pumpkin", "cactus")


def M(name, hexc, r=0.65):
    return material(name, hexc, roughness=r)


def ring(n, radius, phase=0.0):
    for i in range(n):
        a = phase + i / n * 2 * math.pi
        yield math.cos(a) * radius, math.sin(a) * radius


# ---------------------------------------------------------------- per crop builders (game coords)
def build_grass(stage, col):
    parts = []
    tip = M("M_GrassTip", "#C9C27A")
    green = M("M_Grass", "#8CC94F" if stage == "sprout" else "#7FA04A")
    n, h, lean = {"sprout": (3, 2.2, 0.25), "growing": (4, 1.1, 0.35), "ready": (4, 1.2, 0.45)}[stage]
    for i, (x, z) in enumerate(ring(n, 0.35, 0.3)):
        tall = h * (1.12 if i % 2 == 0 else 0.9) if stage == "ready" else h
        parts.append(wedge(f"Blade{i}", (x, 0, z), (x * (1 + lean * 2), tall, z * (1 + lean * 2)), 0.22, 0.05, green, col))
        if stage == "ready" and i % 2 == 0:  # straw-gold tips on the two tallest (ART_BIBLE §3.3)
            parts.append(wedge(f"Tip{i}", (x * 1.6, tall * 0.7, z * 1.6), (x * 1.9, tall, z * 1.9), 0.12, 0.04, tip, col))
    return parts


def build_wheat(stage, col):
    parts = []
    if stage == "sprout":
        g_ = M("M_WheatSprout", "#8CC94F")
        for i, (x, z) in enumerate(ring(5, 0.25)):
            parts.append(wedge(f"Blade{i}", (x * 0.4, 0, z * 0.4), (x * 2.2, 2.2, z * 2.2), 0.18, 0.05, g_, col))
        return parts
    ready = stage == "ready"
    stalk = M("M_WheatStalkR" if ready else "M_WheatStalkG", "#C7A84A" if ready else "#7FA04A", 0.75)
    head = M("M_WheatHeadR" if ready else "M_WheatHeadG", "#E8C45C" if ready else "#B9C46A")
    h = 3.3 if ready else 3.0
    # A dense sheaf: an outer ring and an inner ring of stalks, so from 80 degrees up it reads as
    # one bundle (gold when ripe), not as separate sticks. Budget (ART_BIBLE §7, full 10 x 10
    # fields): 3-sided stalks (8 tris) + a 6-tri cone head while growing, a fat 12-tri wedge ear
    # when ripe: 10 x 14 = 140 growing, 12 x 20 = 240 ready.
    rings = ((8, 0.55, 0.0), (4, 0.22, 0.4)) if ready else ((7, 0.5, 0.0), (3, 0.2, 0.5))
    i = 0
    for count, radius, phase in rings:
        for x, z in ring(count, radius, phase):
            hh = h * (0.86 + 0.14 * ((i * 7) % 3) / 2)  # slightly uneven heights
            parts.append(cylinder(f"Stalk{i}", (x, hh / 2, z), 0.05, hh, stalk, col, sides=3))
            if ready:
                # ripe: a fat golden ear drooping ~25 degrees outward from the stalk top
                d = math.hypot(x, z) or 1.0
                ox, oz = x / d, z / d
                tip = (x + ox * 0.45, hh + 0.5, z + oz * 0.45)
                parts.append(wedge(f"Head{i}", (x, hh - 0.25, z), tip, 0.36, 0.26, head, col))
            else:
                # growing: a closed green-gold head pointing straight up
                parts.append(cone(f"Head{i}", (x, hh + 0.3, z), 0.14, 0.75, head, col, sides=4))
            i += 1
    return parts


def build_carrot(stage, col):
    parts = []
    leaf = M({"sprout": "M_CarrotS", "growing": "M_CarrotG", "ready": "M_CarrotR"}[stage], {"sprout": "#6FBF4E", "growing": "#5FAE45", "ready": "#4E9E3A"}[stage])
    if stage == "sprout":
        parts.append(cylinder("Nub", (0, 0.1, 0), 0.12, 0.2, leaf, col, sides=4))
        for i, (x, z) in enumerate(ring(3, 0.1)):
            parts.append(wedge(f"Leaf{i}", (0, 0.1, 0), (x * 6, 2.2, z * 6), 0.2, 0.05, leaf, col))
        return parts
    n, lh = (7, 1.6) if stage == "growing" else (9, 1.8)
    for i, (x, z) in enumerate(ring(n, 0.25)):
        parts.append(wedge(f"Leaf{i}", (x, 0.15, z), (x * 4.5, lh, z * 4.5), 0.3, 0.06, leaf, col))
    root = M("M_CarrotRoot", "#E07A35" if stage == "growing" else "#F08030", 0.5)
    r = 0.28 if stage == "growing" else 0.45
    parts.append(sphere("Shoulder", (0, 0.08 if stage == "growing" else 0.25, 0), r, root, col, segments=8, rings=5, scale=(1, 0.7, 1)))
    return parts


def build_sunflower(stage, col):
    parts = []
    if stage == "sprout":
        g_ = M("M_SunSprout", "#76C452")
        parts.append(cylinder("Stem", (0, 0.6, 0), 0.06, 1.2, g_, col, sides=5))
        parts.append(wedge("CotA", (0.05, 1.2, 0), (0.7, 1.35, 0), 0.45, 0.08, g_, col))
        parts.append(wedge("CotB", (-0.05, 1.2, 0), (-0.7, 1.35, 0), 0.45, 0.08, g_, col))
        return parts
    stem = M("M_SunStem", "#5A9A3C", 0.7)
    h = 3.6 if stage == "growing" else 4.0
    parts.append(cylinder("Stem", (0, h / 2 - 0.3, 0), 0.08, h - 0.6, stem, col, sides=5))
    parts.append(wedge("LeafA", (0, h * 0.35, 0), (1.3, h * 0.5, 0.4), 0.7, 0.06, stem, col))
    parts.append(wedge("LeafB", (0, h * 0.55, 0), (-1.2, h * 0.7, -0.3), 0.7, 0.06, stem, col))
    if stage == "growing":
        parts.append(sphere("Bud", (0, h - 0.3, 0), 0.35, M("M_SunBud", "#9AB84A"), col, scale=(1, 1.3, 1)))
        return parts
    # open head: disc + 12 petals, tilted 15 deg toward +Z (the camera side)
    disc = M("M_SunDisc", "#5A3C1E", 0.8)
    petal_a, petal_b = M("M_PetalA", "#FFD23C"), M("M_PetalB", "#FFB01F")
    cy, tilt = h - 0.3, math.radians(15)
    d = cylinder("Disc", (0, cy, 0), 0.5, 0.14, disc, col, sides=12, axis="Z")  # faces game +Z
    d.rotation_euler = (-tilt, 0, 0)  # and tips its face 15 degrees up (game +Z = Blender -Y)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    parts.append(d)
    for i, (x, y_) in enumerate(ring(12, 0.5)):
        # petals in the tilted head plane: in-plane "up" is (0, cos t, -sin t), just in front
        base = (x, cy + y_ * math.cos(tilt), -y_ * math.sin(tilt) + 0.09)
        tip = (x * 1.65, cy + y_ * 1.65 * math.cos(tilt), -y_ * 1.65 * math.sin(tilt) + 0.11)
        parts.append(wedge(f"Petal{i}", base, tip, 0.22, 0.05, petal_a if i % 2 == 0 else petal_b, col))
    return parts


def build_pumpkin(stage, col):
    parts = []
    if stage == "sprout":
        g_ = M("M_PumpSprout", "#7DC45A")
        parts.append(cylinder("Stub", (0, 0.3, 0), 0.06, 0.6, g_, col, sides=5))
        parts.append(wedge("LeafA", (0, 0.5, 0), (1.1, 2.0, 0.3), 0.9, 0.06, g_, col))
        parts.append(wedge("LeafB", (0, 0.5, 0), (-1.0, 2.2, -0.4), 0.9, 0.06, g_, col))
        return parts
    leaf = M("M_PumpLeaf", "#5FA040")
    if stage == "growing":
        for i, (x, z) in enumerate(ring(4, 0.3, 0.4)):
            parts.append(wedge(f"Leaf{i}", (x, 0.2, z), (x * 5, 1.6, z * 5), 0.9, 0.06, leaf, col))
        parts.append(sphere("Fruit", (0.5, 0.45, 0.3), 0.6, M("M_PumpUnripe", "#C9B04A", 0.6), col, segments=8, rings=6, scale=(1, 0.75, 1)))
        return parts
    # ready: squashed ribbed sphere o 2.6 x 1.8, 8 ribs (alternate loops pulled in), curly stem, 2 leaves behind (-Z)
    skin = M("M_PumpSkin", "#FF9614", 0.45)
    fruit = sphere("Fruit", (0, 0.9, 0), 1.3, skin, col, segments=16, rings=8, scale=(1, 0.7, 1))
    bm = bmesh.new()
    bm.from_mesh(fruit.data)
    for v in bm.verts:
        ang = math.atan2(v.co.y, v.co.x)  # Blender x/y plane = game x/z
        rib = 0.5 + 0.5 * math.cos(ang * 8)  # 8 ribs
        k = 1 - 0.08 * (1 - rib)
        v.co.x *= k
        v.co.y *= k
    bm.to_mesh(fruit.data)
    bm.free()
    parts.append(fruit)
    parts.append(cylinder("Stem", (0.1, 1.85, -0.1), 0.1, 0.5, M("M_PumpStem", "#6B7A2E", 0.7), col, sides=5))
    # broad leaves lying low behind the fruit (-Z), not standing up like ears
    parts.append(wedge("LeafA", (-0.7, 0.15, -0.9), (-1.9, 0.45, -2.1), 1.4, 0.08, leaf, col))
    parts.append(wedge("LeafB", (0.8, 0.15, -1.0), (2.0, 0.4, -2.2), 1.4, 0.08, leaf, col))
    return parts


def build_cactus(stage, col):
    parts = []
    if stage == "sprout":
        parts.append(sphere("Nub", (0, 0.7, 0), 0.5, M("M_CactusS", "#78B866", 0.55), col, segments=6, rings=4, scale=(1, 1.4, 1)))
        return parts
    body = M("M_CactusG" if stage == "growing" else "M_CactusR", "#66AE5E" if stage == "growing" else "#60B05C", 0.55)
    h = 3.0 if stage == "growing" else 3.3
    parts.append(cylinder("Column", (0, h / 2, 0), 0.55, h, body, col, sides=6))
    parts.append(cylinder("ArmA", (0.95, h * 0.45, 0), 0.3, 0.9, body, col, sides=6, axis="X"))
    parts.append(cylinder("ArmAUp", (1.3, h * 0.45 + 0.6, 0), 0.3, 1.2, body, col, sides=6))
    if stage == "ready":
        parts.append(cylinder("ArmB", (-0.95, h * 0.7, 0.1), 0.3, 0.9, body, col, sides=6, axis="X"))
        parts.append(cylinder("ArmBUp", (-1.3, h * 0.7 + 0.45, 0.1), 0.3, 0.9, body, col, sides=6))
        parts.append(sphere("Bloom", (0, h + 0.15, 0), 0.28, M("M_CactusBloom", "#FF6FA0", 0.6), col, segments=8, rings=5, scale=(1, 0.6, 1)))
    return parts


def build_tree(stage, col):
    parts = []
    trunk = M("M_Trunk", "#6E5238", 0.8)
    if stage == "sprout":
        parts.append(cylinder("Stem", (0, 0.7, 0), 0.08, 1.4, trunk, col, sides=5))
        parts.append(sphere("Leaves", (0, 1.7, 0), 0.5, M("M_TreeSprout", "#7DC45A"), col, segments=6, rings=4))
        return parts
    canopy = M("M_CanopyG" if stage == "growing" else "M_CanopyR", "#5FA040" if stage == "growing" else "#4E9E3A", 0.65)
    h = 4.5 if stage == "growing" else 5.0
    parts.append(cylinder("Trunk", (0, h * 0.3, 0), 0.3, h * 0.6, trunk, col, sides=6))
    parts.append(sphere("CanopyA", (0, h * 0.68, 0), h * 0.26, canopy, col, segments=8, rings=6))
    parts.append(sphere("CanopyB", (0.5, h * 0.84, -0.3), h * 0.19, canopy, col, segments=8, rings=6))
    if stage == "ready":
        fruit = M("M_TreeFruit", "#E0453A", 0.5)
        for i, (x, z) in enumerate(ring(5, h * 0.22, 0.7)):
            parts.append(sphere(f"Fruit{i}", (x, h * 0.66 + (i % 2) * 0.4, z), 0.16, fruit, col, segments=4, rings=3))
    return parts


BUILDERS = {
    "grass": build_grass, "wheat": build_wheat, "carrot": build_carrot, "tree": build_tree,
    "sunflower": build_sunflower, "pumpkin": build_pumpkin, "cactus": build_cactus,
}
BUDGET = {"grass": (40, 60, 80), "wheat": (60, 180, 300), "carrot": (50, 160, 220), "tree": (60, 200, 300),
          "sunflower": (50, 180, 350), "pumpkin": (50, 220, 350), "cactus": (40, 140, 220)}


def footprint_world(obj):
    """(min, max) of the object's world vertices in game x and game z (Blender x and y)."""
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return (min(p.x for p in pts), max(p.x for p in pts)), (min(p.y for p in pts), max(p.y for p in pts))


def footprint(obj):
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    return max(xs) - min(xs), max(ys) - min(ys)


if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "Crops"))
    problems = []
    for crop in CROPS:
        for si, stage in enumerate(STAGES):
            scene = reset_scene()
            col = bpy.data.collections.new(f"{crop}_{stage}")
            scene.collection.children.link(col)
            pieces = BUILDERS[crop](stage, col)
            extents = {p.name: footprint_world(p) for p in pieces}
            name = f"{crop}_{stage}"
            obj = join(pieces, name, col) if len(pieces) > 1 else pieces[0]
            obj.name = name
            set_origin(obj, (0, 0, 0))  # pivot = tile-top centre
            shade_flat(obj)
            tris = report(name, [obj], BUDGET[crop][si])
            fx, fz = footprint(obj)
            print(f"   footprint {fx:.2f} x {fz:.2f} {'OK' if fx <= 5.2 and fz <= 5.2 else 'TOO WIDE'}  (one mesh, pivot tile top)")
            export([obj], os.path.join(out, crop, stage))
            if fx > 5.2 or fz > 5.2:
                for part_name, (px, pz) in extents.items():
                    print(f"     part {part_name:10s} game x {px[0]:+.2f}..{px[1]:+.2f}  z {pz[0]:+.2f}..{pz[1]:+.2f}")
            if tris > BUDGET[crop][si] or fx > 5.2 or fz > 5.2:
                problems.append(f"{name}: {tris} tris (budget {BUDGET[crop][si]}), footprint {fx:.2f} x {fz:.2f}")
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Crops.<cropId>.<stage>; CastShadow off on sprout + grass.")
    if problems:
        print("\nBUDGET PROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
