"""
build_textures.py - procedural PBR texture sets for Drone Farm (ASSETS-3 / ASSETS-5).

    python tools/build_textures.py            # all sets
    python tools/build_textures.py soil       # one family: soil | hardsurface | crops

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


FAMILIES = {
    "soil": lambda: [fn(os.path.join(OUT, "soil")) for fn in (soil_dry, soil_tilled, soil_wet, soil_dug)],
    "hardsurface": lambda: hardsurface(os.path.join(OUT, "hardsurface")),
    "crops": lambda: crops(os.path.join(OUT, "crops")),
}

if __name__ == "__main__":
    wanted = sys.argv[1:] or list(FAMILIES)
    for family in wanted:
        if family not in FAMILIES:
            raise SystemExit(f"unknown family {family!r}: {', '.join(FAMILIES)}")
        print(family)
        FAMILIES[family]()
