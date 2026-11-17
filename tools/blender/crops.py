"""
crops.py - all 7 crops x 3 stages (ART_BIBLE.md §3). Blender Python.

    blender -b -P tools/blender/crops.py -- --out tools/blender/out/Crops

Writes out/Crops/<cropId>/<stage>.fbx (+ .glb preview). Pivot = tile-top centre (game 0,0,0),
+Y up. Opaque, no alpha cards. Ready footprint <= 5.2 x 5.2. Authored sizes follow §3.1:
sprouts are ~2.2 tall (shown at 0.25-0.55), growing ~0.9 x ready height (shown at 0.55-0.85),
ready 1.0. Ready changes SILHOUETTE + COLOUR, never only scale.

v2 (2026-11-17): sculpted organics. Leaves are curved, tapered blades with a raised midrib
(`leaf` / `tube` in _common), fruit are lofted and ribbed, the cactus is fluted, the tree
canopy is a cluster of hand-cut blobs. Every stage stays inside its §3.3 triangle budget (the
finalize Decimate never has to bite) and keeps at most 4 colours (one MeshPart each).
"""

import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

STAGES = ("sprout", "growing", "ready")
CROPS = ("grass", "wheat", "carrot", "tree", "sunflower", "pumpkin", "cactus")


def M(name, hexc, r=0.65):
    return material(name, hexc, roughness=r)


def around(n, phase=0.0):
    for i in range(n):
        a = phase + i / n * 2 * math.pi
        yield i, math.cos(a), math.sin(a)


def blade(name, base, tip, width, mat, col, bend=0.25, segments=2, profile=None, up=(0, 1, 0), section=SEC_LEAF):
    """A curved leaf blade (see _common.leaf), base slightly in the soil so it never floats."""
    return leaf(name, base, tip, width, mat, col, bend=bend, segments=segments, up=up, section=section, profile=profile)


def split_blade(name, base, tip, width, mat_low, mat_tip, col, bend=0.25, split=0.6):
    """A blade whose top `1 - split` is a second colour (grass's straw-gold tips)."""
    b, t = Vector(base), Vector(tip)
    mid = (b + t) / 2 + Vector((0, 1, 0)) * (t - b).length * bend
    pts = bezier(tuple(b), tuple(mid), tuple(t), 2)
    w0, w1 = width, width * 0.72
    low = tube(name + "L", pts[:2], [w0, w1], mat_low, col, section=SEC_LEAF)
    top = tube(name + "T", pts[1:], [w1, 0.0], mat_tip, col, section=SEC_LEAF)
    return [low, top]


def fluted(center_y_r, sides, depth, cx=0.0, cz=0.0, apex=None, phase=0.0):
    """Rings for a ribbed / fluted body: every other vertex pulled in by `depth`."""
    rings = []
    for y, r in center_y_r:
        rings.append(ring_pts((cx, y, cz), r, r, sides, phase, wobble=lambda i: 1.0 - depth * (i % 2)))
    if apex is not None:
        rings.append([(cx, apex, cz)])
    return rings


# ---------------------------------------------------------------- per crop builders (game coords)


def build_grass(stage, col):
    rng = random.Random(11 + STAGES.index(stage))
    parts = []
    green = M("M_Grass" + stage[0].upper(), {"sprout": "#7CC85A", "growing": "#8CC255", "ready": "#96C454"}[stage])
    tip = M("M_GrassTip", "#C9C27A")
    n, h, w = {"sprout": (3, 2.2, 0.16), "growing": (5, 1.1, 0.13), "ready": (6, 1.2, 0.13)}[stage]
    for i, ca, sa in around(n, rng.uniform(0, 1)):
        r0 = 0.12 + 0.08 * (i % 2)
        tall = h * rng.uniform(0.82, 1.12)
        lean = rng.uniform(0.35, 0.6) * (0.6 if stage == "sprout" else 1.0)
        base = (ca * r0, -0.05, sa * r0)
        top = (ca * (r0 + lean * tall), tall, sa * (r0 + lean * tall))
        if stage == "ready" and i % 2 == 0:  # straw-gold tips on every other blade (ART_BIBLE §3.3)
            parts += split_blade(f"Blade{i}", base, top, w, green, tip, col, bend=0.18)
        else:
            parts.append(blade(f"Blade{i}", base, top, w, green, col, bend=0.18))
    return parts


def build_wheat(stage, col):
    rng = random.Random(21 + STAGES.index(stage))
    parts = []
    if stage == "sprout":
        g_ = M("M_WheatSproutLeaf", "#8CC94F")
        for i, ca, sa in around(5, 0.4):
            tall = 2.2 * rng.uniform(0.85, 1.05)
            parts.append(blade(f"Blade{i}", (ca * 0.1, -0.05, sa * 0.1), (ca * 0.7, tall, sa * 0.7), 0.13, g_, col, bend=0.12))
        return parts
    ready = stage == "ready"
    stalk = M("M_WheatStalkR" if ready else "M_WheatStalkG", "#C7A84A" if ready else "#7FA04A", 0.75)
    head = M("M_WheatHeadR" if ready else "M_WheatHeadG", "#E8C45C" if ready else "#B9C46A")
    head_hi = M("M_WheatHeadHi", "#F4D987") if ready else head
    leaf_m = M("M_WheatLeafG", "#7FA04A") if not ready else stalk
    h = 3.3 if ready else 3.0
    # A sheaf in three height tiers: outer ring, middle ring, centre.
    layout = ((6, 0.62, 0.0, 0.86), (4, 0.3, 0.5, 0.95), (2, 0.08, 1.1, 1.0)) if ready else ((6, 0.5, 0.0, 0.88), (3, 0.22, 0.5, 0.96), (1, 0.0, 0.0, 1.0))
    k = 0
    for count, radius, phase, tier in layout:
        for i, ca, sa in around(count, phase):
            hh = h * tier * rng.uniform(0.95, 1.03)
            out_x, out_z = (ca, sa) if radius > 0 else (0.3, 0.2)
            top = (ca * radius + out_x * 0.18, hh, sa * radius + out_z * 0.18)
            parts.append(tube(f"Stalk{k}", [(ca * radius * 0.6, -0.05, sa * radius * 0.6), top], [0.05, 0.035], stalk, col, sides=3, cap=False))
            if ready:
                # ripe: a fat ear drooping 20-30 degrees outward from the stalk top
                droop = Vector((out_x * 0.55, 0.62, out_z * 0.55)).normalized()
                p0 = Vector(top) - droop * 0.05
                pts = [tuple(p0 + droop * d) for d in (0.0, 0.25, 0.6, 0.8)]
                parts.append(tube(f"Head{k}", pts, [0.0, 0.14, 0.11, 0.0], head_hi if k % 3 == 0 else head, col, sides=4, phase=math.pi / 4))
            else:
                # growing: a slim closed head pointing straight up
                p0 = Vector(top)
                pts = [tuple(p0 + Vector((0, d, 0))) for d in (-0.05, 0.3, 0.7)]
                parts.append(tube(f"Head{k}", pts, [0.0, 0.1, 0.0], head, col, sides=4))
            k += 1
    for i, ca, sa in around(3 if not ready else 2, 0.9):  # a few long leaves at the foot
        parts.append(blade(f"Leaf{i}", (ca * 0.15, 0.1, sa * 0.15), (ca * 1.25, 1.5, sa * 1.25), 0.12, leaf_m, col, bend=0.3))
    return parts


def build_carrot(stage, col):
    rng = random.Random(31 + STAGES.index(stage))
    parts = []
    leaf_m = M({"sprout": "M_CarrotLeafS", "growing": "M_CarrotLeafG", "ready": "M_CarrotLeafR"}[stage], {"sprout": "#6FBF4E", "growing": "#5FAE45", "ready": "#4E9E3A"}[stage])
    lobed = [0.3, 1.0, 0.55, 0.85, 0.0]  # feathery: the frond pinches between its lobes
    if stage == "sprout":
        parts.append(tube("Nub", [(0, -0.05, 0), (0, 0.18, 0)], [0.12, 0.08], leaf_m, col, sides=5, cap=False))
        for i, ca, sa in around(3, 0.2):
            parts.append(blade(f"Leaf{i}", (ca * 0.04, 0.12, sa * 0.04), (ca * 0.65, 2.2 * rng.uniform(0.9, 1.0), sa * 0.65), 0.2, leaf_m, col, bend=0.15, segments=2, profile=[0.3, 1.0, 0.0]))
        return parts
    growing = stage == "growing"
    n, lh, reach = (6, 1.55, 1.2) if growing else (7, 1.8, 1.45)
    for i, ca, sa in around(n, 0.3):
        tall = lh * rng.uniform(0.86, 1.05)
        parts.append(blade(f"Frond{i}", (ca * 0.1, 0.2, sa * 0.1), (ca * reach, tall, sa * reach), 0.26, leaf_m, col, bend=0.32,
                           segments=3 if growing else 4, profile=[0.3, 1.0, 0.7, 0.0] if growing else lobed))
    root = M("M_CarrotRoot", "#E07A35" if growing else "#F08030", 0.5)
    if growing:  # a small orange shoulder just breaking the soil
        rings = [ring_pts((0, -0.15, 0), 0.22, 0.22, 6), ring_pts((0, 0.08, 0), 0.28, 0.28, 6), ring_pts((0, 0.2, 0), 0.2, 0.2, 6), [(0, 0.26, 0)]]
    else:  # a chunky shoulder (diameter 0.9) clearly above the soil
        rings = [ring_pts((0, -0.3, 0), 0.32, 0.32, 8), ring_pts((0, 0.1, 0), 0.45, 0.45, 8), ring_pts((0, 0.32, 0), 0.42, 0.42, 8),
                 ring_pts((0, 0.44, 0), 0.28, 0.28, 8), [(0, 0.48, 0)]]
    parts.append(loft("Shoulder", rings, root, col))
    return parts


def build_sunflower(stage, col):
    rng = random.Random(41 + STAGES.index(stage))
    parts = []
    if stage == "sprout":
        g_ = M("M_SunSproutLeaf", "#76C452")
        parts.append(tube("Stem", [(0, -0.05, 0), (0, 1.35, 0)], [0.07, 0.05], g_, col, sides=5, cap=False))
        for d in (1, -1):  # two round cotyledons
            parts.append(blade(f"Cot{d}", (0, 1.3, 0), (d * 0.85, 1.55, 0.05), 0.32, g_, col, bend=0.2, segments=3, profile=[0.3, 1.0, 0.85, 0.0]))
        return parts
    stem_m = M("M_SunStem", "#5A9A3C", 0.7)
    h = 3.6 if stage == "growing" else 4.0
    top = (0, h - 0.35, 0.12 if stage == "ready" else 0.0)
    parts.append(tube("Stem", [(0, -0.05, 0), (0.06, h * 0.35, 0), (-0.03, h * 0.7, 0.05), top], [0.11, 0.09, 0.08, 0.07], stem_m, col, sides=5, cap=False))
    for i, (y, ang) in enumerate(((0.3, 0.4), (0.5, 2.6), (0.68, 4.6))):  # broad heart-shaped leaves round the stem
        ca, sa = math.cos(ang), math.sin(ang)
        parts.append(blade(f"Leaf{i}", (0, h * y, 0), (ca * 1.35, h * y + 0.25, sa * 1.35), 0.42, stem_m, col, bend=0.18, segments=3, profile=[0.4, 1.0, 0.7, 0.0]))
    if stage == "growing":  # a closed green bud with sepals
        bud = M("M_SunBud", "#9AB84A")
        cx, cy, cz = top
        parts.append(loft("Bud", [[(cx, cy - 0.05, cz)], ring_pts((cx, cy + 0.15, cz), 0.3, 0.3, 6), ring_pts((cx, cy + 0.45, cz), 0.34, 0.34, 6, 0.5), [(cx, cy + 0.75, cz)]], bud, col))
        for i, ca, sa in around(5, 0.3):
            parts.append(blade(f"Sepal{i}", (cx + ca * 0.15, cy + 0.12, cz + sa * 0.15), (cx + ca * 0.55, cy + 0.5, cz + sa * 0.55), 0.12, stem_m, col, bend=0.1, segments=1, profile=[1.0, 0.0]))
        return parts
    # Open head (diameter ~2): a thick seed disc tilted 15 degrees up toward +Z, two petal rings.
    disc_m = M("M_SunDisc", "#5A3C1E", 0.8)
    petal_a, petal_b = M("M_PetalA", "#FFD23C"), M("M_PetalB", "#FFB01F")
    tilt = math.radians(15)
    c = Vector(top) + Vector((0, 0.1, 0.05))
    f = Vector((0, math.sin(tilt), math.cos(tilt)))  # the face direction
    u = Vector((1, 0, 0))
    v = f.cross(u).normalized() * -1  # in-plane "up"
    if v.y < 0:
        v = -v

    def disc_ring(r, depth):
        return [tuple(c + (u * math.cos(a) + v * math.sin(a)) * r + f * depth) for a in (i / 12 * 2 * math.pi for i in range(12))]

    parts.append(loft("Disc", [disc_ring(0.48, -0.1), disc_ring(0.58, 0.05), [tuple(c + f * 0.15)]], disc_m, col))
    for i in range(12):
        a = i / 12 * 2 * math.pi
        d = u * math.cos(a) + v * math.sin(a)
        parts.append(blade(f"Petal{i}", tuple(c + d * 0.48 + f * 0.02), tuple(c + d * 1.05 + f * 0.12), 0.22, petal_a, col, bend=0.08, segments=2, up=tuple(f), profile=[0.6, 1.0, 0.0]))
    for i in range(10):
        a = (i + 0.5) / 10 * 2 * math.pi
        d = u * math.cos(a) + v * math.sin(a)
        parts.append(blade(f"Inner{i}", tuple(c + d * 0.45 + f * 0.05), tuple(c + d * 0.86 + f * 0.2), 0.19, petal_b, col, bend=0.08, segments=2, up=tuple(f), profile=[0.6, 1.0, 0.0]))
    return parts


def build_pumpkin(stage, col):
    rng = random.Random(51 + STAGES.index(stage))
    parts = []
    if stage == "sprout":
        g_ = M("M_PumpSproutLeaf", "#7DC45A")
        parts.append(tube("Stub", [(0, -0.05, 0), (0.03, 0.55, 0)], [0.08, 0.06], g_, col, sides=5, cap=False))
        parts.append(blade("LeafA", (0, 0.5, 0), (1.15, 2.0, 0.3), 0.55, g_, col, bend=0.15, segments=3, profile=[0.3, 1.0, 0.75, 0.0]))
        parts.append(blade("LeafB", (0, 0.5, 0), (-1.0, 2.2, -0.4), 0.55, g_, col, bend=0.15, segments=3, profile=[0.3, 1.0, 0.75, 0.0]))
        return parts
    leaf_m = M("M_PumpLeaf", "#5FA040" if stage == "ready" else "#7BAA4A")
    vine_m = M("M_PumpVine", "#6B7A2E", 0.7)
    lobed = [0.35, 1.0, 0.7, 0.9, 0.0]
    if stage == "growing":
        for i, ca, sa in around(4, 0.4):
            parts.append(blade(f"Leaf{i}", (ca * 0.2, 0.2, sa * 0.2), (ca * 1.9, 1.3 * rng.uniform(0.9, 1.1), sa * 1.9), 0.62, leaf_m, col, bend=0.25, segments=4, profile=lobed))
        parts.append(tube("Vine", [(0, 0.05, 0), (0.5, 0.15, 0.45), (0.9, 0.1, 0.9), (0.75, 0.25, 1.25), (0.5, 0.2, 1.1)], [0.06, 0.05, 0.045, 0.035, 0.02], vine_m, col, sides=4))
        fruit = M("M_PumpUnripe", "#C9B04A", 0.6)
        cx, cz = 0.55, 0.35
        rings = [[(cx, 0.03, cz)]] + fluted(((0.12, 0.42), (0.38, 0.62), (0.68, 0.58), (0.88, 0.36)), 12, 0.08, cx, cz) + [[(cx, 0.85, cz)]]
        parts.append(loft("Fruit", rings, fruit, col))
        return parts
    # ready: a squashed, deeply ribbed pumpkin (2.6 x 1.8) with a dimpled top, a curly stem and
    # two broad leaves lying low behind it (-Z).
    skin = M("M_PumpSkin", "#FF9614", 0.45)
    rings = [[(0, 0.04, 0)]] + fluted(((0.18, 0.78), (0.5, 1.18), (0.92, 1.3), (1.34, 1.16), (1.66, 0.72)), 20, 0.09) + [[(0, 1.56, 0)]]
    parts.append(loft("Fruit", rings, skin, col))
    parts.append(tube("Stem", [(0, 1.5, 0), (0.05, 1.82, 0.02), (0.2, 2.0, 0.08), (0.36, 1.98, 0.12)], [0.13, 0.1, 0.08, 0.06], vine_m, col, sides=5))
    parts.append(tube("Tendril", [(0.1, 1.62, 0.1), (0.5, 1.8, 0.3), (0.75, 1.65, 0.1), (0.62, 1.5, -0.12), (0.45, 1.62, -0.02)], [0.035, 0.03, 0.025, 0.02, 0.0], vine_m, col, sides=3))
    parts.append(blade("LeafA", (-0.6, 0.12, -0.75), (-2.05, 0.5, -2.15), 0.8, leaf_m, col, bend=0.18, segments=4, profile=lobed))
    parts.append(blade("LeafB", (0.7, 0.12, -0.85), (2.1, 0.45, -2.2), 0.8, leaf_m, col, bend=0.18, segments=4, profile=lobed))
    parts.append(blade("LeafC", (-1.0, 0.1, 0.2), (-2.35, 0.35, 0.9), 0.6, leaf_m, col, bend=0.15, segments=4, profile=lobed))
    return parts


def build_cactus(stage, col):
    parts = []
    if stage == "sprout":  # a small round nub with 4 ridges
        body = M("M_CactusS", "#78B866", 0.55)
        parts.append(loft("Nub", fluted(((-0.05, 0.42), (0.6, 0.62), (1.25, 0.5)), 8, 0.16, apex=1.6), body, col, cap_start=False))
        return parts
    body = M("M_CactusG" if stage == "growing" else "M_CactusR", "#66AE5E" if stage == "growing" else "#60B05C", 0.55)
    h = 3.0 if stage == "growing" else 3.3
    # A fluted column (5 ribs) with a rounded crown.
    col_rings = fluted(((-0.05, 0.6), (h * 0.75, 0.6), (h * 0.92, 0.48), (h * 0.99, 0.28)), 10, 0.2, apex=h + 0.06)
    parts.append(loft("Column", col_rings, body, col, cap_start=False))

    def arm(name, side, y0, out, up_len, z=0.0):
        # One tube from inside the column: out, a rounded elbow, up, and a domed tip.
        sx, top = side, y0 + 0.3 + up_len
        pts = [(0.0, y0, z), (sx * (out - 0.28), y0, z), (sx * (out - 0.04), y0 + 0.16, z), (sx * out, top, z), (sx * out, top + 0.15, z), (sx * out, top + 0.23, z)]
        return [tube(name, pts, [0.3, 0.3, 0.29, 0.27, 0.18, 0.0], body, col, sides=6, cap=False)]

    parts += arm("ArmA", 1, h * 0.38, 1.15, 0.85)
    if stage == "ready":
        parts += arm("ArmB", -1, h * 0.58, 1.05, 0.6, 0.12)
        bloom = M("M_CactusBloom", "#FF6FA0", 0.6)
        for i, ca, sa in around(5, 0.2):  # a small pink bloom on the crown
            parts.append(blade(f"Bloom{i}", (ca * 0.05, h + 0.03, sa * 0.05), (ca * 0.4, h + 0.17, sa * 0.4), 0.14, bloom, col, bend=0.1, segments=1, profile=[1.0, 0.0]))
    return parts


def blob(name, center, r, mat, col, seed, squash=0.85):
    """A hand-cut canopy blob: a 7 x 4 sphere with jittered vertices."""
    obj = sphere(name, center, r, mat, col, segments=7, rings=4, scale=(1, squash, 1))
    rng = random.Random(seed)
    for v in obj.data.vertices:
        v.co *= 1 + rng.uniform(-0.1, 0.1)
    obj.data.update()
    return obj


def build_tree(stage, col):
    parts = []
    trunk = M("M_Trunk", "#6E4A2E" if stage == "ready" else "#7A5434", 0.85)
    if stage == "sprout":
        sprout = M("M_TreeSproutLeaf", "#6FBA52")
        parts.append(tube("Stem", [(0, -0.05, 0), (0.05, 0.9, 0), (0, 1.75, 0)], [0.09, 0.07, 0.05], trunk, col, sides=5, cap=False))
        for i, ca, sa in around(3, 0.5):
            parts.append(blade(f"Leaf{i}", (0, 1.2 + i * 0.25, 0), (ca * 0.7, 1.55 + i * 0.25, sa * 0.7), 0.24, sprout, col, bend=0.15, segments=2, profile=[0.35, 1.0, 0.0]))
        return parts
    ready = stage == "ready"
    canopy = M("M_CanopyR" if ready else "M_CanopyG", "#4A8C46" if ready else "#5A9A48", 0.65)
    canopy_hi = M("M_CanopyHi", "#6DB25A", 0.65)
    h = 5.0 if ready else 4.5
    # Trunk with a root flare and two branches.
    parts.append(loft("Trunk", [ring_pts((0, -0.05, 0), 0.42, 0.42, 6), ring_pts((0, 0.3, 0), 0.28, 0.28, 6, 0.3), ring_pts((0, h * 0.62, 0.05), 0.2, 0.2, 6, 0.1)], trunk, col, cap_start=False))
    parts.append(tube("BranchA", [(0, h * 0.42, 0), (0.75, h * 0.6, 0.15)], [0.12, 0.07], trunk, col, sides=4))
    parts.append(tube("BranchB", [(0, h * 0.5, 0.02), (-0.6, h * 0.68, -0.35)], [0.11, 0.06], trunk, col, sides=4))
    blobs = [((0, h * 0.7, 0), h * 0.27, canopy), ((0.8, h * 0.66, 0.35), h * 0.19, canopy), ((-0.7, h * 0.74, -0.4), h * 0.2, canopy)]
    if ready:
        blobs.append(((0.15, h * 0.88, -0.1), h * 0.17, canopy_hi))
    for i, (cpos, r, m) in enumerate(blobs):
        parts.append(blob(f"Canopy{i}", cpos, r, m, col, seed=61 + i * 7 + (0 if ready else 3)))
    if ready:
        fruit = M("M_TreeFruit", "#E0453A", 0.5)
        for i, ca, sa in around(5, 0.7):
            y = h * (0.6 + 0.08 * (i % 2))
            parts.append(sphere(f"Fruit{i}", (ca * h * 0.27, y, sa * h * 0.27), 0.18, fruit, col, segments=4, rings=3))
    return parts


BUILDERS = {
    "grass": build_grass, "wheat": build_wheat, "carrot": build_carrot, "tree": build_tree,
    "sunflower": build_sunflower, "pumpkin": build_pumpkin, "cactus": build_cactus,
}
# ART_BIBLE §3.3 per-crop maxima (S / M / R); §7 caps every crop at 80 / 220 / 350.
BUDGET = {"grass": (40, 60, 80), "wheat": (60, 180, 300), "carrot": (50, 160, 220), "tree": (60, 200, 300),
          "sunflower": (50, 180, 350), "pumpkin": (50, 220, 350), "cactus": (40, 140, 220)}
MAX_PARTS = 4


def footprint_world(obj):
    """(min, max) of the object's world vertices in game x and game z (Blender x and y)."""
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return (min(p.x for p in pts), max(p.x for p in pts)), (min(p.y for p in pts), max(p.y for p in pts))


if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "Crops"))
    a = args_after_dashes()
    only = a[a.index("--only") + 1].split(",") if "--only" in a else CROPS
    problems = []
    for crop in only:
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
            raw = tri_count([obj])
            meshes, found = finalize([obj], BUDGET[crop][si])
            problems += [f"{name}: {p}" for p in found]
            tris = report(name, meshes, BUDGET[crop][si])
            lo, hi = game_bounds(meshes)
            fx, fz = hi.x - lo.x, hi.z - lo.z
            print(f"   footprint {fx:.2f} x {fz:.2f} {'OK' if fx <= 5.2 and fz <= 5.2 else 'TOO WIDE'}  ({len(meshes)} MeshParts, pivot tile top, raw {raw} tris)")
            export(meshes, os.path.join(out, crop, stage))
            if fx > 5.2 or fz > 5.2:
                for part_name, (px, pz) in extents.items():
                    print(f"     part {part_name:10s} game x {px[0]:+.2f}..{px[1]:+.2f}  z {pz[0]:+.2f}..{pz[1]:+.2f}")
            if raw > BUDGET[crop][si]:
                problems.append(f"{name}: {raw} raw tris > budget {BUDGET[crop][si]} (the Decimate had to bite)")
            if len(meshes) > MAX_PARTS:
                problems.append(f"{name}: {len(meshes)} MeshParts > {MAX_PARTS}")
            if tris > BUDGET[crop][si] or fx > 5.2 or fz > 5.2:
                problems.append(f"{name}: {tris} tris (budget {BUDGET[crop][si]}), footprint {fx:.2f} x {fz:.2f}")
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Crops.<cropId>.<stage>; CastShadow off on sprout + grass.")
    if problems:
        print("\nBUDGET PROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
