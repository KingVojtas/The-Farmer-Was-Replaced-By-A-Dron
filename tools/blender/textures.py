"""
textures.py - the game's tileable PBR sets, made in Blender (v2 art pass, 2026-11-17).

    blender -b -P tools/blender/textures.py                 # soil + detail
    blender -b -P tools/blender/textures.py -- soil         # one family: soil | detail
    blender -b -P tools/blender/textures.py -- --only Stone,Planks

Replaces the 512² Pillow sets of tools/build_textures.py (still there for the trim sheet and the
crop palette atlas) with 1024² maps, same file names, same folders, so
`python tools/roblox_upload.py textures` picks them up unchanged:

  art/textures/soil/<SoilDry|SoilTilled|SoilWet|SoilDug>_{Color,Normal,Roughness,Metalness}.png
  art/textures/detail/<DroneHull|CropLeaf|CropSkin|Bark|Planks|Shingles|Stone>_{...}.png

How: Cycles BAKES Blender's procedural noise (fBm / ridged multifractal, 4D) onto a 1 x 1 plane;
cell patterns (stones, cracks, clods, veins) come from an exact periodic Voronoi in numpy. Every field is SEAMLESS by construction: the plane's UV is
wrapped onto a 4D torus, (Ru cos 2pi u, Ru sin 2pi u, Rv cos 2pi v) + W = Rv sin 2pi v, so u = 0
and u = 1 are the same point. numpy then composes the fields (furrows, planks, panels: exact
periodic maths on the pixel grid), derives the normal map from the height (OpenGL, green = +V,
what Roblox uses), darkens crevices (cavity AO) and writes 8-bit PNGs with its own encoder (no
colour management in the way: the numbers ARE the sRGB values).

Palette: docs/ART_BIBLE.md §1.4 / §2.4. Detail sets stay light and NEUTRAL (grey): Roblox
multiplies a MaterialVariant's ColorMap by Part.Color, so the part keeps its hue (paint slots,
crop colours) and the texture adds light, shadow and relief.
"""

import math
import os
import struct
import sys
import zlib

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import args_after_dashes, reset_scene  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "textures")
N = 1024
TAU = 2 * math.pi


# ---------------------------------------------------------------- Blender: bake seamless fields


class Baker:
    """Bakes up to three scalar fields per Cycles pass (R, G, B of an emission shader)."""

    def __init__(self):
        scene = reset_scene()
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 4
        scene.cycles.use_denoising = False
        scene.render.bake.margin = 0
        bpy.ops.mesh.primitive_plane_add(size=1)
        self.plane = bpy.context.active_object
        self.mat = bpy.data.materials.new("Bake")
        self.mat.use_nodes = True
        self.plane.data.materials.append(self.mat)
        self.image = bpy.data.images.new("BakeTarget", N, N, alpha=False, float_buffer=True)
        self.image.colorspace_settings.name = "Non-Color"
        self.cache = {}

    # -- node helpers
    def _math(self, op, a, b=None):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                self.nt.links.new(x, n.inputs[i])
        return n.outputs[0]

    def _torus(self, cu, cv, seed):
        """(vector, w) sockets: the UV wrapped on a 4D torus, cu x cv features across the tile."""
        uv = self.nt.nodes.new("ShaderNodeTexCoord").outputs["UV"]
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(uv, sep.inputs[0])
        au = self._math("MULTIPLY", sep.outputs["X"], TAU)
        av = self._math("MULTIPLY", sep.outputs["Y"], TAU)
        ru, rv = cu / TAU, cv / TAU
        o = (seed * 17.13 % 97, seed * 31.7 % 89, seed * 7.77 % 83, seed * 13.31 % 79)
        x = self._math("ADD", self._math("MULTIPLY", self._math("COSINE", au), ru), o[0])
        y = self._math("ADD", self._math("MULTIPLY", self._math("SINE", au), ru), o[1])
        z = self._math("ADD", self._math("MULTIPLY", self._math("COSINE", av), rv), o[2])
        w = self._math("ADD", self._math("MULTIPLY", self._math("SINE", av), rv), o[3])
        comb = self.nt.nodes.new("ShaderNodeCombineXYZ")
        for s, i in ((x, 0), (y, 1), (z, 2)):
            self.nt.links.new(s, comb.inputs[i])
        return comb.outputs[0], w

    def _field(self, spec):
        kind = spec[0]
        if kind == "noise":  # ("noise", cu, cv, seed, detail, roughness, distortion, type)
            _, cu, cv, seed, detail, rough, dist, ntype = spec
            vec, w = self._torus(cu, cv, seed)
            n = self.nt.nodes.new("ShaderNodeTexNoise")
            n.noise_dimensions = "4D"
            n.noise_type = ntype
            n.normalize = ntype == "FBM"
            n.inputs["Scale"].default_value = 1.0
            n.inputs["Detail"].default_value = detail
            n.inputs["Roughness"].default_value = rough
            n.inputs["Distortion"].default_value = dist
            self.nt.links.new(vec, n.inputs["Vector"])
            self.nt.links.new(w, n.inputs["W"])
            return n.outputs["Fac"]
        if kind == "voronoi":  # ("voronoi", cu, cv, seed, feature, randomness, output)
            _, cu, cv, seed, feature, randomness, output = spec
            vec, w = self._torus(cu, cv, seed)
            n = self.nt.nodes.new("ShaderNodeTexVoronoi")
            n.voronoi_dimensions = "4D"
            n.feature = feature
            n.inputs["Scale"].default_value = 1.0
            n.inputs["Randomness"].default_value = randomness
            self.nt.links.new(vec, n.inputs["Vector"])
            self.nt.links.new(w, n.inputs["W"])
            if output == "Color":
                sep = self.nt.nodes.new("ShaderNodeSeparateColor")
                self.nt.links.new(n.outputs["Color"], sep.inputs[0])
                return sep.outputs[0]
            return n.outputs["Distance"]
        raise ValueError(spec)

    def bake(self, specs):
        """Returns one float32 N x N array per spec (row 0 = the image's TOP row)."""
        todo = [s for s in specs if s not in self.cache]
        for k in range(0, len(todo), 3):
            group = todo[k : k + 3]
            self.mat.node_tree.nodes.clear()
            self.nt = self.mat.node_tree
            out = self.nt.nodes.new("ShaderNodeOutputMaterial")
            emit = self.nt.nodes.new("ShaderNodeEmission")
            comb = self.nt.nodes.new("ShaderNodeCombineColor")
            for i, spec in enumerate(group):
                self.nt.links.new(self._field(spec), comb.inputs[i])
            self.nt.links.new(comb.outputs[0], emit.inputs["Color"])
            emit.inputs["Strength"].default_value = 1.0
            self.nt.links.new(emit.outputs[0], out.inputs["Surface"])
            tex = self.nt.nodes.new("ShaderNodeTexImage")
            tex.image = self.image
            self.nt.nodes.active = tex
            bpy.ops.object.select_all(action="DESELECT")
            self.plane.select_set(True)
            bpy.context.view_layer.objects.active = self.plane
            bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True)
            buf = np.empty(N * N * 4, dtype=np.float32)
            self.image.pixels.foreach_get(buf)
            px = buf.reshape(N, N, 4)[::-1]  # Blender stores bottom row first
            for i, spec in enumerate(group):
                self.cache[spec] = np.ascontiguousarray(px[:, :, i])
        return [self.cache[s] for s in specs]


# ---------------------------------------------------------------- numpy helpers


def norm(a):
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / ((hi - lo) or 1.0)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def hexc(h):
    return np.array([int(h[i : i + 2], 16) / 255 for i in (1, 3, 5)], dtype=np.float32)


def mix(a, b, t):
    """a, b: colours (3,) or images (N, N, 3); t: (N, N) weight."""
    t = np.asarray(t, dtype=np.float32)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def blur(a, sigma):
    """Wrap-around Gaussian blur (the texture tiles, so its blur must too)."""
    f = np.fft.fftfreq(N)
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def grid():
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    return x / N, y / N  # u right, v DOWN the image (0..1)


def normal_map(h, strength):
    """OpenGL tangent-space normals from a wrapped height field (green = +V = up the image)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def cavity(h, radius=6.0, amount=1.2):
    """Ambient-occlusion-ish darkening of crevices: 1 on peaks, < 1 in grooves."""
    return np.clip(1.0 - amount * np.maximum(blur(h, radius) - h, 0.0), 0.55, 1.0)


def write_png(path, a):
    """8-bit PNG (gray or RGB) from 0..1 floats, no colour management."""
    a = np.clip(np.round(np.asarray(a) * 255), 0, 255).astype(np.uint8)
    h, w = a.shape[:2]
    ct = 0 if a.ndim == 2 else 2
    rows = a.reshape(h, -1)
    raw = np.hstack([np.zeros((h, 1), dtype=np.uint8), rows]).tobytes()

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ct, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def save_set(folder, name, color, rough, height, strength, metal=0.0):
    os.makedirs(folder, exist_ok=True)
    if np.ndim(color) == 2:
        color = np.repeat(color[..., None], 3, axis=-1)
    if np.ndim(metal) == 0:
        metal = np.full((N, N), float(metal), dtype=np.float32)
    write_png(os.path.join(folder, f"{name}_Color.png"), color)
    write_png(os.path.join(folder, f"{name}_Roughness.png"), rough)
    write_png(os.path.join(folder, f"{name}_Metalness.png"), metal)
    write_png(os.path.join(folder, f"{name}_Normal.png"), normal_map(height, strength))
    # seam check: the first and last columns / rows must continue each other
    edge = max(float(np.abs(height[:, 0] - height[:, -1]).mean()), float(np.abs(height[0] - height[-1]).mean()))
    inner = float(np.abs(height[:, 1:] - height[:, :-1]).mean())
    print(f"  {name}: {N}x{N} Color / Normal / Roughness / Metalness  (seam step {edge:.4f} vs inner step {inner:.4f})")


def vor(cu, cv, seed, randomness=0.9):
    """Exact PERIODIC Voronoi on the pixel grid (a jittered cu x cv point grid, wrap-around):
    f1 / f2 = nearest / second distance and edge = (f2 - f1) / 2, all in cell units; cell = a
    random 0..1 value per cell. (Blender's 4D Voronoi on the torus makes nested, broken cells.)"""
    rng = np.random.default_rng(seed)
    jx = 0.5 + (rng.random((cv, cu)) - 0.5) * randomness
    jy = 0.5 + (rng.random((cv, cu)) - 0.5) * randomness
    cr = rng.random((cv, cu))
    u, v = grid()
    X, Y = u * cu, v * cv
    ix, iy = np.floor(X).astype(int), np.floor(Y).astype(int)
    f1 = np.full(X.shape, 9.0, dtype=np.float32)
    f2 = np.full(X.shape, 9.0, dtype=np.float32)
    cell = np.zeros(X.shape, dtype=np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx, ny = ix + ox, iy + oy
            wx, wy = nx % cu, ny % cv
            d = np.hypot(X - (nx + jx[wy, wx]), Y - (ny + jy[wy, wx])).astype(np.float32)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cell = np.where(closer, cr[wy, wx], cell)
            f1 = np.where(closer, d, f1)
    return {"f1": f1, "f2": f2, "edge": (f2 - f1) * 0.5, "cell": cell}


def pebbles(seed, cells, share, size=0.22):
    """(mask 0..1, tone 0..1): small round stones in `share` of the cells."""
    vr = vor(cells, cells, seed)
    cell = vr["cell"]
    pick = cell > (1 - share)
    r = size * (0.7 + 0.6 * ((cell * 7.31) % 1.0))
    mask = np.where(pick, smooth(r, r * 0.55, vr["f1"]), 0.0)
    return mask.astype(np.float32), (cell * 3.7) % 1.0


# ---------------------------------------------------------------- soil (ART_BIBLE §2.4)

DRY, DRY_DARK, DUST, CRACK = map(hexc, ("#8A6544", "#6B4A30", "#A98258", "#4E3524"))
RIDGE, TROUGH, CRUMB = map(hexc, ("#6E4A2F", "#4A3020", "#8C6040"))
WET, WET_DARK, PUDDLE = map(hexc, ("#4A3324", "#35241A", "#2A1D16"))
DUG_TOP, STONE_T = hexc("#7A563A"), hexc("#968A78")
FURROWS = 4  # per tile; StudsPerTile 6.4 -> a furrow every 1.6 studs, lines up across tiles


def soil_dry(bk, folder):
    big, mid, grain = bk.bake([("noise", 5, 5, 11, 6, 0.55, 0.0, "FBM"), ("noise", 16, 16, 12, 4, 0.5, 0.3, "FBM"), ("noise", 90, 90, 13, 2, 0.5, 0.0, "FBM")])
    warp, = bk.bake([("noise", 9, 9, 16, 3, 0.6, 0.0, "FBM")])
    big, mid, grain, warp = norm(big), norm(mid), norm(grain), norm(warp)
    crack_e = vor(7, 7, 14, 1.0)["edge"] + 0.06 * (warp - 0.5)  # wobbly crack lines
    crack = smooth(0.035, 0.0, crack_e) * smooth(0.2, 0.55, mid)  # cracks fade in and out
    lumps = 1 - np.clip(vor(22, 22, 15)["f1"], 0, 1)
    peb, tone = pebbles(17, 34, 0.12)
    h = 0.45 * big + 0.25 * lumps * lumps + 0.12 * grain - 0.55 * crack
    h = np.maximum(h, peb * (0.75 + 0.15 * tone))
    c = mix(DRY_DARK, DRY, np.clip(0.25 + 0.95 * (0.6 * big + 0.4 * mid) + 0.15 * (grain - 0.5), 0, 1))
    c = mix(c, DUST, smooth(0.62, 0.95, h) * 0.85)
    c = mix(c, CRACK, crack * 0.9)
    c = mix(c, STONE_T * (0.85 + 0.3 * tone[..., None]), peb)
    c *= cavity(h, 5, 1.4)[..., None]
    rough = np.clip(0.93 + 0.04 * (grain - 0.5) - 0.06 * peb, 0, 1)
    save_set(folder, "SoilDry", c, rough, h, 14.0)


def furrows(bk, seed):
    u, v = grid()
    wob, n, grain = bk.bake([("noise", 3, 2, seed, 3, 0.5, 0.0, "FBM"), ("noise", 10, 10, seed + 1, 5, 0.55, 0.2, "FBM"), ("noise", 110, 110, seed + 3, 2, 0.5, 0.0, "FBM")])
    wob, n, grain = norm(wob), norm(n), norm(grain)
    clods = vor(40, 40, seed + 2)["f1"]
    phase = TAU * FURROWS * u + (wob - 0.5) * 1.1
    f = 0.5 + 0.5 * np.cos(phase)  # 1 on the ridge crest, 0 in the trough
    crest = f ** 1.4
    lump = 1 - np.clip(clods, 0, 1)
    h = 0.62 * crest + 0.2 * lump * (0.4 + 0.6 * f) + 0.1 * n + 0.06 * grain
    return f, h.astype(np.float32), n, grain, lump


def soil_tilled(bk, folder):
    f, h, n, grain, lump = furrows(bk, 31)
    cr = vor(70, 70, 35)
    crumb = ((cr["cell"] > 0.8) * smooth(0.45, 0.25, cr["f1"])) * smooth(0.35, 0.7, f)
    peb, tone = pebbles(36, 26, 0.07, 0.2)
    h = np.maximum(h + 0.05 * crumb, peb * (0.7 + 0.2 * tone))
    c = mix(TROUGH, RIDGE, np.clip(h * 1.2 + 0.1 * (n - 0.5), 0, 1))
    c = mix(c, CRUMB, crumb * 0.8)
    c = mix(c, STONE_T * (0.8 + 0.3 * tone[..., None]), peb)
    c *= cavity(h, 7, 1.0)[..., None]
    rough = np.clip(0.8 + 0.05 * (grain - 0.5) - 0.06 * (1 - f), 0, 1)
    save_set(folder, "SoilTilled", c, rough, h, 18.0)


def soil_wet(bk, folder):
    f, h, n, grain, lump = furrows(bk, 31)  # the Tilled furrows stay (ART_BIBLE §2.4.3)
    pools, sheen = bk.bake([("noise", 4, 4, 41, 3, 0.5, 0.0, "FBM"), ("noise", 20, 20, 42, 3, 0.5, 0.0, "FBM")])
    pools, sheen = norm(pools), norm(sheen)
    water_level = 0.12 + 0.18 * smooth(0.45, 0.8, pools)
    puddle = smooth(water_level, water_level - 0.05, h)  # 1 where the trough is under water
    h = np.maximum(h, water_level * 0.98)  # the water surface is flat
    c = mix(WET_DARK, WET, np.clip(h * 1.25 + 0.1 * (n - 0.5), 0, 1))
    c = mix(c, PUDDLE, puddle * 0.92)
    c *= cavity(h, 7, 0.9)[..., None]
    rough = np.clip(0.36 + 0.08 * (sheen - 0.5) + 0.06 * f, 0, 1)
    rough = rough * (1 - puddle) + 0.06 * puddle
    save_set(folder, "SoilWet", c, rough, h, 14.0)


def soil_dug(bk, folder):
    grain, warp = bk.bake([("noise", 100, 100, 55, 2, 0.5, 0.0, "FBM"), ("noise", 14, 14, 57, 4, 0.6, 0.0, "FBM")])
    grain, warp = norm(grain), norm(warp)
    big, small = vor(9, 9, 53, 0.95), vor(24, 24, 54)
    edge, tone_c = big["edge"] + 0.05 * (warp - 0.5), big["cell"]
    clod = smooth(0.02, 0.14, edge)  # 0 in the gaps between clods, 1 on a clod
    dome = 1 - np.clip(big["f1"], 0, 1) ** 1.3
    h = clod * (0.45 + 0.35 * dome) + 0.15 * (1 - np.clip(small["f1"], 0, 1)) * clod + 0.05 * grain
    peb, tone = pebbles(56, 30, 0.1, 0.2)
    h = np.maximum(h, peb * (0.8 + 0.15 * tone))
    c = mix(CRACK * 0.85, DRY_DARK, clod)
    c = mix(c, DUG_TOP, clod * smooth(0.45, 0.85, h) * (0.6 + 0.4 * tone_c))
    c = mix(c, STONE_T * (0.8 + 0.3 * tone[..., None]), peb)
    c *= cavity(h, 6, 1.5)[..., None]
    rough = np.clip(0.95 - 0.05 * peb, 0, 1)
    save_set(folder, "SoilDug", c, rough, h, 20.0)


# ---------------------------------------------------------------- detail MaterialVariants


def drone_hull(bk, folder):
    """Hull plating: 4 x 4 panels with chamfered recessed seams, corner rivets, a vent grille or
    a hatch in some panels, faint anisotropic brushing, soft grime in the seams."""
    u, v = grid()
    brush, grime, fine = bk.bake([("noise", 3, 160, 301, 2, 0.5, 0.0, "FBM"), ("noise", 6, 6, 302, 5, 0.55, 0.0, "FBM"), ("noise", 64, 64, 303, 2, 0.5, 0.0, "FBM")])
    brush, grime, fine = norm(brush), norm(grime), norm(fine)
    panels = 4
    px, py = (u * panels) % 1.0, (v * panels) % 1.0
    ix, iy = np.floor(u * panels).astype(int), np.floor(v * panels).astype(int)
    d_edge = np.minimum(np.minimum(px, 1 - px), np.minimum(py, 1 - py))  # 0 at a seam, 0.5 at the centre
    seam = smooth(0.012, 0.004, d_edge)
    bevel = smooth(0.004, 0.03, d_edge)  # the chamfer up from the seam to the panel face
    rivet = np.zeros_like(u)
    for cx in (0.07, 0.93):
        for cy in (0.07, 0.93):
            d = np.hypot(px - cx, py - cy)
            rivet = np.maximum(rivet, smooth(0.022, 0.012, d))
    pid = (ix * 7 + iy * 13) % 5
    # vent grille (pid 1): five slots; hatch (pid 3): an inset square with a handle
    slots = ((pid == 1) & (np.abs(px - 0.5) < 0.28) & (np.abs(py - 0.5) < 0.22) & ((py * 12) % 1.0 < 0.45)).astype(np.float32)
    hatch_d = np.maximum(np.abs(px - 0.5), np.abs(py - 0.5))
    hatch = ((pid == 3) & (np.abs(hatch_d - 0.3) < 0.008)).astype(np.float32)
    handle = ((pid == 3) & (np.abs(px - 0.5) < 0.09) & (np.abs(py - 0.62) < 0.015)).astype(np.float32)
    h = 0.55 * bevel + 0.02 * (brush - 0.5) + 0.01 * fine + 0.25 * rivet - 0.2 * slots - 0.15 * hatch + 0.1 * handle
    plate_tone = 0.9 + 0.05 * (((ix * 3 + iy * 5) % 4) / 3 - 0.5)  # panels differ a touch
    val = plate_tone + 0.06 * (brush - 0.5) + 0.05 * (grime - 0.5)
    val = val * (1 - 0.5 * seam) * (1 - 0.35 * slots) * (1 - 0.3 * hatch) + 0.08 * rivet
    val *= cavity(h, 4, 1.6)
    rough = np.clip(0.34 + 0.12 * grime + 0.04 * brush + 0.25 * seam + 0.1 * slots, 0, 1)
    metal = np.clip(0.55 * (1 - seam) * (1 - slots), 0, 1)
    save_set(folder, "DroneHull", np.clip(val, 0.3, 1.0), rough, h, 16.0, metal)


def crop_leaf(bk, folder):
    """Leaf tissue: thick primary veins round big areoles, thin minor veins round small ones
    (two periodic Voronoi edge networks), soft blotches, slightly glossier veins."""
    blotch, warp = bk.bake([("noise", 6, 6, 313, 4, 0.5, 0.0, "FBM"), ("noise", 10, 10, 314, 3, 0.6, 0.0, "FBM")])
    blotch, warp = norm(blotch), norm(warp)
    major = smooth(0.07, 0.0, vor(5, 5, 311, 1.0)["edge"] + 0.05 * (warp - 0.5))
    minor = smooth(0.05, 0.0, vor(18, 18, 312, 1.0)["edge"])
    h = 0.5 + 0.3 * major + 0.1 * minor + 0.06 * (blotch - 0.5)
    val = 0.85 + 0.12 * major + 0.05 * minor + 0.1 * (blotch - 0.5)
    val *= cavity(h, 3, 0.8)
    rough = np.clip(0.64 + 0.08 * (blotch - 0.5) - 0.1 * major, 0, 1)
    save_set(folder, "CropLeaf", np.clip(val, 0.6, 1.0), rough, h, 10.0)


def crop_skin(bk, folder):
    """Fruit / root skin: smooth with faint mottling, tiny pores and soft growth streaks."""
    mottle, streak = bk.bake([("noise", 6, 6, 321, 4, 0.55, 0.0, "FBM"), ("noise", 3, 40, 323, 3, 0.5, 0.0, "FBM")])
    mottle, streak = norm(mottle), norm(streak)
    pore = smooth(0.14, 0.05, vor(120, 120, 322)["f1"])
    h = 0.5 + 0.05 * (mottle - 0.5) - 0.12 * pore + 0.03 * (streak - 0.5)
    val = 0.9 + 0.16 * (mottle - 0.5) + 0.08 * (streak - 0.5) - 0.1 * pore
    rough = np.clip(0.42 + 0.12 * (mottle - 0.5) + 0.1 * pore, 0, 1)
    save_set(folder, "CropSkin", np.clip(val, 0.6, 1.0), rough, h, 6.0)


def bark(bk, folder):
    """Bark: wandering vertical ridges (a warped cosine, 10 per tile), broken into plates by
    cracks (a stretched periodic Voronoi), deep dark grooves, fine fibre grain."""
    u, v = grid()
    warp, plates_n, grain = bk.bake([("noise", 3, 2, 331, 4, 0.55, 0.0, "FBM"), ("noise", 8, 3, 332, 4, 0.6, 0.0, "FBM"), ("noise", 90, 14, 334, 3, 0.5, 0.0, "FBM")])
    warp, plates_n, grain = norm(warp), norm(plates_n), norm(grain)
    ridge = 0.5 + 0.5 * np.cos(TAU * (10 * u + 1.6 * (warp - 0.5)))
    ridge = smooth(0.15, 0.85, ridge)
    pv = vor(10, 4, 333, 1.0)  # cells narrow across, tall along the trunk
    crack = smooth(0.06, 0.0, pv["edge"]) * smooth(0.35, 0.65, plates_n)
    h = 0.7 * ridge * (1 - 0.6 * crack) + 0.12 * grain + 0.08 * pv["cell"]
    val = 0.58 + 0.32 * ridge + 0.08 * (grain - 0.5) + 0.06 * (pv["cell"] - 0.5) - 0.16 * crack
    val *= cavity(h, 5, 1.3)
    save_set(folder, "Bark", np.clip(val, 0.3, 1.0), np.clip(0.86 + 0.06 * (1 - ridge), 0, 1), h, 18.0)


def planks(bk, folder):
    """Boards: 8 rows, staggered butt joints, flowing grain with growth rings, knots, nail heads
    at each joint, eased (bevelled) board edges."""
    u, v = grid()
    rng = np.random.default_rng(343)
    rows = 8
    row = np.floor(v * rows).astype(int)
    ly = (v * rows) % 1.0
    joints = rng.random(rows)
    shade = rng.uniform(0.82, 1.0, size=(rows, 2))
    grain, rings = bk.bake([("noise", 2, 60, 341, 6, 0.6, 0.6, "FBM"), ("noise", 3, 10, 342, 3, 0.5, 1.5, "FBM")])
    kv = vor(5, 5, 343)
    knots, knot_pick = kv["f1"], kv["cell"]  # f1 in cell units (a cell = 1/5 tile)
    grain, rings = norm(grain), norm(rings)
    lx = (u - joints[row]) % 1.0  # 0 at this row's joint
    half = (lx >= 0.5).astype(int)
    bx = (lx * 2) % 1.0  # position along the board (two boards per row)
    # distances in TILE units (1 = 1024 px): rows are 1/8 tall, boards 1/2 long
    d_edge = np.minimum(np.minimum(ly, 1 - ly) / rows, np.minimum(bx, 1 - bx) * 0.5)
    gap = smooth(0.0022, 0.0008, d_edge)
    ease = smooth(0.0008, 0.007, d_edge)
    ring_lines = 0.5 + 0.5 * np.sin(TAU * (rings * 6 + grain * 1.5))
    knot = np.where(knot_pick > 0.6, smooth(0.075, 0.025, knots), 0.0)
    nail = np.zeros_like(u)
    for jx in (0.025, 0.975):  # two nails at each end of every board
        for jy in (0.3, 0.7):
            d = np.hypot((bx - jx) * 0.5, (ly - jy) / rows)
            nail = np.maximum(nail, smooth(0.0045, 0.0025, d))
    tone = shade[row, half]
    h = 0.55 * ease + 0.06 * (grain - 0.5) + 0.04 * ring_lines - 0.12 * knot - 0.1 * nail
    val = tone * (0.86 + 0.1 * (grain - 0.5) + 0.07 * ring_lines) * (1 - 0.35 * knot) * (1 - 0.55 * gap) + 0.05 * nail
    val *= cavity(h, 4, 1.4)
    rough = np.clip(0.78 + 0.08 * gap - 0.05 * nail, 0, 1)
    save_set(folder, "Planks", np.clip(val, 0.3, 1.0), rough, h, 14.0)


def shingles(bk, folder):
    """Roof shingles: staggered rows of slightly uneven tiles, each thicker at its lower edge and
    with a rounded, chipped lower corner, a dark gap between them."""
    u, v = grid()
    rng = np.random.default_rng(351)
    rows, per_row = 8, 8
    row = np.floor(v * rows).astype(int)
    ly = (v * rows) % 1.0  # 0 at the tile top, 1 at its lower edge
    off = (row % 2) * 0.5 / per_row
    col = np.floor(((u + off) % 1.0) * per_row).astype(int)
    lx = (((u + off) % 1.0) * per_row) % 1.0
    shade = rng.uniform(0.8, 1.0, size=(rows, per_row))
    chip, grit = bk.bake([("noise", 30, 30, 352, 3, 0.6, 0.0, "FBM"), ("noise", 120, 120, 353, 2, 0.5, 0.0, "FBM")])
    chip, grit = norm(chip), norm(grit)
    corner = np.hypot(np.maximum(0, np.abs(lx - 0.5) - 0.38) / 0.12, np.maximum(0, ly - 0.82) / 0.18)
    inside = (corner < 1.0 - 0.25 * chip) & (lx > 0.03) & (lx < 0.97) & (ly > 0.03)
    t = ly
    h = np.where(inside, 0.25 + 0.65 * t + 0.04 * (grit - 0.5), 0.0)
    val = np.where(inside, shade[row, col] * (1.0 - 0.25 * t * t) + 0.06 * (grit - 0.5), 0.36)
    val *= cavity(h, 4, 1.0)
    save_set(folder, "Shingles", np.clip(val, 0.3, 1.0), np.where(inside, 0.82, 0.92), h, 14.0)


def stone(bk, folder):
    """Fieldstone / paving: irregular blocks (Voronoi cells on the torus) with rounded edges,
    per-stone tone, surface pits and soft mortar between them."""
    pits, fine, warp = bk.bake([("noise", 24, 24, 362, 5, 0.6, 0.0, "FBM"), ("noise", 90, 90, 363, 2, 0.5, 0.0, "FBM"), ("noise", 12, 12, 364, 3, 0.6, 0.0, "FBM")])
    pits, fine, warp = norm(pits), norm(fine), norm(warp)
    sv = vor(6, 6, 361, 0.85)
    edge, tone = sv["edge"] + 0.03 * (warp - 0.5), sv["cell"]
    mortar = smooth(0.05, 0.02, edge)
    dome = smooth(0.02, 0.22, edge)
    h = 0.6 * dome + 0.12 * (pits - 0.5) * dome + 0.05 * fine
    val = (0.78 + 0.2 * tone) * (0.9 + 0.12 * (pits - 0.5)) * (1 - mortar) + 0.55 * mortar
    val *= cavity(h, 5, 1.3)
    save_set(folder, "Stone", np.clip(val, 0.3, 1.0), np.clip(0.82 + 0.08 * mortar + 0.04 * (fine - 0.5), 0, 1), h, 16.0)


SOIL = {"SoilDry": soil_dry, "SoilTilled": soil_tilled, "SoilWet": soil_wet, "SoilDug": soil_dug}
DETAIL = {"DroneHull": drone_hull, "CropLeaf": crop_leaf, "CropSkin": crop_skin, "Bark": bark, "Planks": planks, "Shingles": shingles, "Stone": stone}

if __name__ == "__main__":
    a = args_after_dashes()
    only = set(a[a.index("--only") + 1].split(",")) if "--only" in a else None
    families = [x for x in a if x in ("soil", "detail")] or ["soil", "detail"]
    bk = Baker()
    for family in families:
        sets = SOIL if family == "soil" else DETAIL
        print(family)
        for name, fn in sets.items():
            if only is None or name in only:
                fn(bk, os.path.join(OUT, family))
