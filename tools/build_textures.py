"""
build_textures.py - procedural PBR texture sets for Drone Farm (ASSETS-3 / ASSETS-5).

    python tools/build_textures.py            # hardsurface + crops
    python tools/build_textures.py crops      # one family: hardsurface | crops
    (soil + detail: tools/blender/textures.py since 2026-11-17; the old sets: add --legacy)

Pure Pillow (no numpy). Every map is SEAMLESS (periodic noise: a small random grid tiled
3 x 3, upscaled bicubic, centre cropped) and palette-true to docs/ART_BIBLE.md §1.4 / §2.4.
Normal maps are OpenGL tangent space (green = +V, the convention Roblox SurfaceAppearance /
MaterialVariant use). Deterministic: the same seed always writes the same pixels.

Outputs (Studio setup: art/IMPORT.md):
  art/textures/soil/<SoilDry|SoilTilled|SoilWet|SoilDug>_{Color,Normal,Roughness,Metalness}.png
      512² tileable MaterialVariant sets (names = Client.Visuals.SoilLook states)
  art/textures/hardsurface/Hardsurface_{Color,Normal,Roughness,Metalness}.png
      1024² trim sheet, 8 horizontal 128 px bands (drone hull, machines; layout in IMPORT.md)
  art/textures/crops/Crops_{Color,Roughness}.png
      512² palette atlas, 8 x 8 swatches of 64 px (crop stage colours; layout in IMPORT.md)
"""

import math
import os
import random
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "textures")


# ---------------------------------------------------------------- helpers


def hexrgb(value):
    return tuple(int(value[i : i + 2], 16) for i in (1, 3, 5))


def lerp(a, b, t):
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return tuple(int(a[i] + (b[i] - a[i]) * t + 0.5) for i in range(3))


def smoothstep(e0, e1, x):
    t = (x - e0) / (e1 - e0)
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return t * t * (3 - 2 * t)


def tile_noise(size, cells, seed, cells_y=None):
    """Seamless value noise in 0..1 (a flat list, row-major). cells_y != cells stretches it."""
    cy = cells_y or cells
    rng = random.Random(seed)
    small = Image.new("L", (cells, cy))
    small.putdata([rng.randint(0, 255) for _ in range(cells * cy)])
    big = Image.new("L", (cells * 3, cy * 3))
    for i in range(3):
        for j in range(3):
            big.paste(small, (i * cells, j * cy))
    up = big.resize((size * 3, size * 3), Image.BICUBIC)
    return [v / 255 for v in up.crop((size, size, size * 2, size * 2)).tobytes()]


def fbm(size, cells, octaves, seed, persistence=0.5):
    acc = [0.0] * (size * size)
    total, amp = 0.0, 1.0
    for octave in range(octaves):
        layer = tile_noise(size, cells * 2**octave, seed + octave * 101)
        for i, v in enumerate(layer):
            acc[i] += v * amp
        total += amp
        amp *= persistence
    # stretch to the full 0..1 range (sums of noise bunch up around 0.5)
    lo, hi = min(acc), max(acc)
    span = (hi - lo) or 1.0
    return [(a - lo) / span for a in acc]


def normal_map(height, size, strength):
    """OpenGL tangent-space normals from a wrapped height field (0..1)."""
    out = bytearray(size * size * 3)
    k = 0
    for y in range(size):
        row = y * size
        up = ((y - 1) % size) * size
        down = ((y + 1) % size) * size
        for x in range(size):
            dx = (height[row + (x + 1) % size] - height[row + (x - 1) % size]) * 0.5 * strength
            dy = (height[down + x] - height[up + x]) * 0.5 * strength
            nx, ny = -dx, dy  # image y runs down, texture V runs up
            inv = 1.0 / math.sqrt(nx * nx + ny * ny + 1.0)
            out[k] = int((nx * inv * 0.5 + 0.5) * 255 + 0.5)
            out[k + 1] = int((ny * inv * 0.5 + 0.5) * 255 + 0.5)
            out[k + 2] = int((inv * 0.5 + 0.5) * 255 + 0.5)
            k += 3
    return Image.frombytes("RGB", (size, size), bytes(out))


def save_set(folder, name, size, colors, rough, metal, height, strength):
    os.makedirs(folder, exist_ok=True)
    color = Image.new("RGB", (size, size))
    color.putdata(colors)
    color.save(os.path.join(folder, f"{name}_Color.png"), optimize=True)
    roughness = Image.new("L", (size, size))
    roughness.putdata([max(0, min(255, int(r * 255 + 0.5))) for r in rough])
    roughness.save(os.path.join(folder, f"{name}_Roughness.png"), optimize=True)
    metalness = Image.new("L", (size, size))
    metalness.putdata([max(0, min(255, int(m * 255 + 0.5))) for m in metal])
    metalness.save(os.path.join(folder, f"{name}_Metalness.png"), optimize=True)
    normal_map(height, size, strength).save(os.path.join(folder, f"{name}_Normal.png"), optimize=True)
    print(f"  {name}: {size}x{size} Color / Normal / Roughness / Metalness")


# ---------------------------------------------------------------- soil (ART_BIBLE §2.4)

SOIL = 512
DRY, DRY_DARK, DUST, CRACK = map(hexrgb, ("#8A6544", "#6B4A30", "#A98258", "#4E3524"))
RIDGE, TROUGH, CRUMB = map(hexrgb, ("#6E4A2F", "#4A3020", "#8C6040"))
WET, WET_DARK, PUDDLE = map(hexrgb, ("#4A3324", "#35241A", "#2A1D16"))
DUG_TOP = hexrgb("#7A563A")
FURROWS = 4  # across one 512 tile: StudsPerTile 6.4 -> a furrow every 1.6 studs


def furrow_field(seed):
    n = fbm(SOIL, 6, 4, seed)
    wobble = tile_noise(SOIL, 4, seed + 7)
    f, h = [0.0] * (SOIL * SOIL), [0.0] * (SOIL * SOIL)
    for y in range(SOIL):
        for x in range(SOIL):
            i = y * SOIL + x
            phase = 2 * math.pi * FURROWS * x / SOIL + (wobble[i] - 0.5) * 0.8
            f[i] = 0.5 + 0.5 * math.cos(phase)
            h[i] = 0.65 * f[i] + 0.35 * n[i]
    return f, h, n


def pebbles(colors, height, seed, count, tone=(150, 138, 120)):
    """Small round stones pressed into the soil (lighter, raised): a closer look has detail."""
    rng = random.Random(seed)
    for _ in range(count):
        cx, cy = rng.randrange(SOIL), rng.randrange(SOIL)
        r = rng.uniform(2.0, 4.6)
        k = rng.uniform(0.82, 1.12)
        stone = tuple(min(255, int(v * k)) for v in tone)
        for dy in range(-5, 6):
            for dx in range(-5, 6):
                d = (dx * dx + dy * dy) / (r * r)
                if d <= 1:
                    i = ((cy + dy) % SOIL) * SOIL + (cx + dx) % SOIL
                    colors[i] = lerp(colors[i], stone, 0.85 - d * 0.25)
                    height[i] = max(height[i], 0.7 + 0.3 * (1 - d))


def soil_dry(folder):
    h = fbm(SOIL, 8, 5, 11)
    cracks = fbm(SOIL, 5, 3, 23)
    colors, rough, height = [], [], []
    for i in range(SOIL * SOIL):
        v = h[i]
        c = lerp(DRY_DARK, DRY, 0.35 + v * 0.9)
        if v > 0.62:
            c = lerp(c, DUST, (v - 0.62) / 0.38)
        crack = abs(cracks[i] - 0.5) < 0.016
        if crack:
            c = lerp(c, CRACK, 0.85)
        colors.append(c)
        rough.append(0.93 + (v - 0.5) * 0.04)
        height.append(v * 0.6 - (0.35 if crack else 0.0))
    pebbles(colors, height, 15, 70)
    save_set(folder, "SoilDry", SOIL, colors, rough, [0.0] * len(h), height, 6.0)


def soil_tilled(folder):
    f, h, n = furrow_field(31)
    crumbs = tile_noise(SOIL, 64, 37)
    colors, rough = [], []
    for i in range(SOIL * SOIL):
        c = lerp(TROUGH, RIDGE, h[i] * 1.15)
        if crumbs[i] > 0.8 and f[i] > 0.35:
            c = lerp(c, CRUMB, 0.8)
        colors.append(c)
        rough.append(0.79 + (n[i] - 0.5) * 0.04)
    h = list(h)
    pebbles(colors, h, 35, 40)
    save_set(folder, "SoilTilled", SOIL, colors, rough, [0.0] * len(h), h, 9.0)


def soil_wet(folder):
    f, h, n = furrow_field(31)  # the Tilled furrows stay (ART_BIBLE §2.4.3)
    pools = fbm(SOIL, 4, 3, 41)
    colors, rough = [], []
    for i in range(SOIL * SOIL):
        c = lerp(WET_DARK, WET, h[i] * 1.2)
        r = 0.35 + (n[i] - 0.5) * 0.06
        if f[i] < 0.14 and pools[i] > 0.55:
            c = lerp(c, PUDDLE, 0.9)
            r = 0.1
        colors.append(c)
        rough.append(r)
    save_set(folder, "SoilWet", SOIL, colors, rough, [0.0] * len(h), h, 7.0)


def soil_dug(folder):
    clods = fbm(SOIL, 12, 3, 53, persistence=0.45)
    grain = tile_noise(SOIL, 96, 59)
    colors, rough, height = [], [], []
    for i in range(SOIL * SOIL):
        v = clods[i]
        clod = smoothstep(0.38, 0.5, v)
        c = lerp(CRACK, DRY_DARK, clod)
        if clod > 0.99:
            c = lerp(c, DUG_TOP, smoothstep(0.62, 0.95, v))
        if grain[i] > 0.82:
            c = lerp(c, CRACK, 0.35)
        colors.append(c)
        rough.append(0.95)
        height.append(clod * 0.6 + v * 0.4)
    pebbles(colors, height, 55, 90)
    save_set(folder, "SoilDug", SOIL, colors, rough, [0.0] * len(clods), height, 12.0)


# ---------------------------------------------------------------- hard surface trim sheet

TRIM = 1024
BAND = TRIM // 8
# (name, colour, roughness, metalness) in ART_BIBLE §1.4 order; band 8 = hazard stripes.
BANDS = (
    ("hull_dark", "#1E2530", 0.40, 0.2),
    ("hull_mid", "#2E3846", 0.38, 0.3),
    ("panel_light", "#4A5668", 0.35, 0.4),
    ("ceramic", "#D7E2EC", 0.30, 0.0),
    ("brushed_steel", "#8E9AA6", 0.35, 1.0),
    ("dark_steel", "#3C4652", 0.45, 1.0),
    ("copper", "#C27744", 0.30, 1.0),
    ("hazard", None, 0.60, 0.0),
)
HAZARD_Y, HAZARD_K = hexrgb("#F2B630"), hexrgb("#16181C")


def hardsurface(folder):
    grime = fbm(TRIM, 8, 4, 71)
    streaks = tile_noise(TRIM, 8, 73, cells_y=256)  # horizontal brushing: slow along x, fast along y
    colors, rough, metal, height = [], [], [], []
    for y in range(TRIM):
        band = y // BAND
        _, hexc, r0, m0 = BANDS[band]
        local = y % BAND
        edge = local < 3 or local >= BAND - 3  # a recessed seam between bands
        for x in range(TRIM):
            i = y * TRIM + x
            seam = edge or (band <= 2 and x % 256 < 3)  # panel lines on the hull bands
            if hexc is None:
                stripe = ((x + local) // 32) % 2 == 0
                c = HAZARD_Y if stripe else HAZARD_K
            else:
                base = hexrgb(hexc)
                shade = (grime[i] - 0.5) * 0.10
                if band == 4:
                    shade += (streaks[i] - 0.5) * 0.18
                c = lerp(base, (0, 0, 0) if shade < 0 else (255, 255, 255), abs(shade))
            if seam:
                c = lerp(c, (10, 12, 16), 0.6)
            colors.append(c)
            rough.append(r0 + (grime[i] - 0.5) * 0.08 + (0.15 if seam else 0.0))
            metal.append(0.0 if seam else m0)
            height.append(0.0 if seam else 0.5 + (streaks[i] - 0.5) * (0.08 if band == 4 else 0.02))
    save_set(folder, "Hardsurface", TRIM, colors, rough, metal, height, 18.0)


# ---------------------------------------------------------------- crop palette atlas

CROP_SWATCHES = (  # rows of the 8 x 8 atlas (ART_BIBLE §1.4 "Crops (by stage)"); r = roughness
    ("grass", ("#7CC85A", "#8CC255", "#96C454", "#C9C27A"), 0.7),
    ("wheat", ("#8CC94F", "#7FA04A", "#B9C46A", "#C7A84A", "#E8C45C", "#F4D987"), 0.65),
    ("carrot", ("#6FBF4E", "#5FAE45", "#E07A35", "#4E9E3A", "#F08030", "#FFA45C"), 0.6),
    ("sunflower", ("#76C452", "#5A9A3C", "#9AB84A", "#FFD23C", "#FFB01F", "#5A3C1E", "#3E2814"), 0.6),
    ("pumpkin", ("#7DC45A", "#7BAA4A", "#C9B04A", "#FF9614", "#C46A10", "#6B7A2E"), 0.45),
    ("cactus", ("#78B866", "#66AE5E", "#60B05C", "#4B8E4A", "#E9E2C8", "#FF6FA0"), 0.6),
    ("tree", ("#6FBA52", "#7A5434", "#5A9A48", "#6E4A2E", "#4A8C46", "#6DB25A"), 0.7),
    ("soil", ("#8A6544", "#6E4A2F", "#4A3324", "#6B4A30"), 0.9),
)


def crops(folder):
    size, cell = 512, 64
    color = Image.new("RGB", (size, size), (128, 128, 128))
    rough = Image.new("L", (size, size), 166)
    for row, (_, swatches, r) in enumerate(CROP_SWATCHES):
        for col, hexc in enumerate(swatches):
            box = (col * cell, row * cell, (col + 1) * cell, (row + 1) * cell)
            color.paste(hexrgb(hexc), box)
            rough.paste(int(r * 255 + 0.5), box)
    os.makedirs(folder, exist_ok=True)
    color.save(os.path.join(folder, "Crops_Color.png"), optimize=True)
    rough.save(os.path.join(folder, "Crops_Roughness.png"), optimize=True)
    print(f"  Crops: {size}x{size} palette atlas, {len(CROP_SWATCHES)} rows of 64 px swatches")


# ---------------------------------------------------------------- detail MaterialVariants
# Light, NEUTRAL tileable sets: Roblox multiplies a MaterialVariant's ColorMap by the part's
# Color (measured in Studio, 2026-11-13), so the hue stays the part's (the drone's paint slots,
# the crop colours, the barn red) and the texture adds only light / shadow / relief.

DETAIL = 512


def gray(v):
    g = max(0, min(255, int(v * 255 + 0.5)))
    return (g, g, g)


def detail_set(folder, name, colors, rough, height, strength, metal=None):
    save_set(folder, name, DETAIL, colors, rough, metal or [0.0] * len(colors), height, strength)


def drone_hull(folder):
    """Hull panels: a 4 x 4 panel grid with recessed seams, corner rivets, soft grime."""
    grime = fbm(DETAIL, 6, 4, 301)
    fine = tile_noise(DETAIL, 64, 303)
    panel = DETAIL // 4
    colors, rough, metal, height = [], [], [], []
    for y in range(DETAIL):
        py = y % panel
        for x in range(DETAIL):
            px = x % panel
            i = y * DETAIL + x
            seam = px < 3 or py < 3
            rivet = False
            for cx, cy in ((12, 12), (panel - 12, 12), (12, panel - 12), (panel - 12, panel - 12)):
                if (px - cx) ** 2 + (py - cy) ** 2 <= 9:
                    rivet = True
            v = 0.9 + (grime[i] - 0.5) * 0.14 + (fine[i] - 0.5) * 0.04
            if seam:
                v = 0.42
            elif rivet:
                v = 1.0
            colors.append(gray(v))
            rough.append(0.6 if seam else 0.34 + grime[i] * 0.16)
            metal.append(0.0 if seam else 0.55)
            height.append(0.0 if seam else (0.85 if rivet else 0.5 + (fine[i] - 0.5) * 0.03))
    detail_set(folder, "DroneHull", colors, rough, height, 10.0, metal)


def crop_leaf(folder):
    """Leaf: a main vein every 128 px, fine side veins on the diagonal, soft blotches."""
    blotch = fbm(DETAIL, 5, 4, 311)
    wob = tile_noise(DETAIL, 8, 313)
    colors, rough, height = [], [], []
    for y in range(DETAIL):
        for x in range(DETAIL):
            i = y * DETAIL + x
            main = abs(((y + (wob[i] - 0.5) * 10) % 128) - 64) < 2.2
            side_phase = ((x + (y % 128 if (y % 128) < 64 else 128 - y % 128)) % 32)
            side = side_phase < 1.6
            v = 0.86 + (blotch[i] - 0.5) * 0.16
            h = 0.5 + (blotch[i] - 0.5) * 0.1
            if side:
                v, h = v + 0.06, h + 0.12
            if main:
                v, h = 1.0, 0.85
            colors.append(gray(v))
            rough.append(0.62 + (blotch[i] - 0.5) * 0.1)
            height.append(h)
    detail_set(folder, "CropLeaf", colors, rough, height, 5.0)


def crop_skin(folder):
    """Fruit skin: smooth, faint mottling, tiny pores, the odd soft highlight streak."""
    mottle = fbm(DETAIL, 6, 4, 321)
    pores = tile_noise(DETAIL, 128, 323)
    streak = tile_noise(DETAIL, 4, 325, cells_y=32)
    colors, rough, height = [], [], []
    for i in range(DETAIL * DETAIL):
        pore = pores[i] > 0.86
        v = 0.9 + (mottle[i] - 0.5) * 0.12 + (streak[i] - 0.5) * 0.05
        if pore:
            v -= 0.12
        colors.append(gray(v))
        rough.append(0.42 + (mottle[i] - 0.5) * 0.12)
        height.append(0.5 - (0.12 if pore else 0.0) + (mottle[i] - 0.5) * 0.05)
    detail_set(folder, "CropSkin", colors, rough, height, 4.0)


def bark(folder):
    """Bark: deep vertical grooves that wander, cross cracks, rough everywhere."""
    wander = tile_noise(DETAIL, 6, 331, cells_y=3)
    cracks = fbm(DETAIL, 8, 3, 333)
    grain = tile_noise(DETAIL, 96, 335)
    colors, rough, height = [], [], []
    for y in range(DETAIL):
        for x in range(DETAIL):
            i = y * DETAIL + x
            phase = 2 * math.pi * (x / 48 + (wander[i] - 0.5) * 0.8)
            ridge = 0.5 + 0.5 * math.cos(phase)
            crack = abs(cracks[i] - 0.5) < 0.02
            h = ridge * 0.8 + grain[i] * 0.2 - (0.4 if crack else 0.0)
            v = 0.55 + ridge * 0.4 + (grain[i] - 0.5) * 0.08 - (0.2 if crack else 0.0)
            colors.append(gray(v))
            rough.append(0.88)
            height.append(max(0.0, h))
    detail_set(folder, "Bark", colors, rough, height, 9.0)


def planks(folder):
    """Boards: 8 rows of 64 px, staggered butt joints, grain along x, a few knots."""
    grain = tile_noise(DETAIL, 4, 341, cells_y=96)
    rng = random.Random(343)
    rows = 8
    row_h = DETAIL // rows
    shade = [rng.uniform(0.84, 1.0) for _ in range(rows * 2)]
    joints = [rng.randrange(0, DETAIL) for _ in range(rows)]
    knots = [(rng.randrange(DETAIL), rng.randrange(DETAIL), rng.uniform(5, 9)) for _ in range(9)]
    colors, rough, height = [], [], []
    for y in range(DETAIL):
        row = y // row_h
        ly = y % row_h
        for x in range(DETAIL):
            i = y * DETAIL + x
            side = 0 if (x - joints[row]) % DETAIL < DETAIL // 2 else 1
            seam = ly < 2 or (x - joints[row]) % (DETAIL // 2) < 2
            v = shade[row * 2 + side] * (0.9 + (grain[i] - 0.5) * 0.2)
            h = 0.6 + (grain[i] - 0.5) * 0.12
            for kx, ky, kr in knots:
                dx = min(abs(x - kx), DETAIL - abs(x - kx))
                dy = min(abs(y - ky), DETAIL - abs(y - ky))
                d = (dx * dx) / (kr * kr * 2.2) + (dy * dy) / (kr * kr)
                if d < 1:
                    v *= 0.7 + 0.3 * d
                    h -= 0.1 * (1 - d)
            if seam:
                v, h = 0.4, 0.0
            colors.append(gray(v))
            rough.append(0.78 if not seam else 0.9)
            height.append(h)
    detail_set(folder, "Planks", colors, rough, height, 8.0)


def shingles(folder):
    """Roof shingles: staggered rows, each tile darker toward its lower edge, gaps between."""
    rng = random.Random(351)
    rows, width = 8, 64
    row_h = DETAIL // rows
    shade = {(r, c): rng.uniform(0.82, 1.0) for r in range(rows) for c in range(DETAIL // width + 1)}
    grit = tile_noise(DETAIL, 96, 353)
    colors, rough, height = [], [], []
    for y in range(DETAIL):
        row = y // row_h
        ly = y % row_h
        offset = (width // 2) if row % 2 else 0
        for x in range(DETAIL):
            i = y * DETAIL + x
            col = ((x + offset) % DETAIL) // width
            lx = (x + offset) % width
            gap = lx < 2
            t = ly / row_h  # 0 at the top of the tile, 1 at its bottom edge
            v = shade[(row, col)] * (1.0 - 0.28 * t * t) + (grit[i] - 0.5) * 0.06
            h = 0.25 + 0.7 * t
            if gap or ly < 2:
                v, h = 0.38, 0.0
            colors.append(gray(v))
            rough.append(0.82)
            height.append(h)
    detail_set(folder, "Shingles", colors, rough, height, 7.0)


def stone(folder):
    """Stone wall / paving: irregular blocks (wrapped Voronoi) in darker mortar."""
    rng = random.Random(361)
    cells = 6
    step = DETAIL / cells
    seeds = {(cx, cy): ((cx + rng.uniform(0.15, 0.85)) * step, (cy + rng.uniform(0.15, 0.85)) * step, rng.uniform(0.8, 1.0))
             for cx in range(cells) for cy in range(cells)}
    detail = fbm(DETAIL, 8, 4, 363)
    colors, rough, height = [], [], []
    for y in range(DETAIL):
        gy = int(y // step)
        for x in range(DETAIL):
            gx = int(x // step)
            d1 = d2 = 1e9
            tone = 1.0
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    sx, sy, st = seeds[((gx + ox) % cells, (gy + oy) % cells)]
                    sx += (gx + ox - (gx + ox) % cells) * step
                    sy += (gy + oy - (gy + oy) % cells) * step
                    d = (x - sx) ** 2 + (y - sy) ** 2
                    if d < d1:
                        d1, d2, tone = d, d1, st
                    elif d < d2:
                        d2 = d
            edge = math.sqrt(d2) - math.sqrt(d1)
            i = y * DETAIL + x
            mortar = edge < 5
            v = tone * (0.86 + (detail[i] - 0.5) * 0.18)
            h = min(1.0, 0.4 + edge / 40) + (detail[i] - 0.5) * 0.1
            if mortar:
                v, h = 0.5, 0.0
            colors.append(gray(v))
            rough.append(0.9 if mortar else 0.82)
            height.append(h)
    detail_set(folder, "Stone", colors, rough, height, 9.0)


DETAIL_SETS = (drone_hull, crop_leaf, crop_skin, bark, planks, shingles, stone)

FAMILIES = {
    "soil": lambda: [fn(os.path.join(OUT, "soil")) for fn in (soil_dry, soil_tilled, soil_wet, soil_dug)],
    "detail": lambda: [fn(os.path.join(OUT, "detail")) for fn in DETAIL_SETS],
    "hardsurface": lambda: hardsurface(os.path.join(OUT, "hardsurface")),
    "crops": lambda: crops(os.path.join(OUT, "crops")),
}

# soil + detail are made by tools/blender/textures.py since 2026-11-17 (1024², Blender-baked).
# These 512² Pillow versions only run on request with --legacy, so a plain run can't overwrite them.
SUPERSEDED = ("soil", "detail")

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--legacy"]
    wanted = args or [f for f in FAMILIES if f not in SUPERSEDED]
    for family in wanted:
        if family not in FAMILIES:
            raise SystemExit(f"unknown family {family!r}: {', '.join(FAMILIES)}")
        if family in SUPERSEDED and "--legacy" not in sys.argv:
            raise SystemExit(f"{family}: made by tools/blender/textures.py now (blender -b -P tools/blender/textures.py -- {family}); "
                             "pass --legacy to write the old 512² Pillow set instead")
        print(family)
        FAMILIES[family]()
