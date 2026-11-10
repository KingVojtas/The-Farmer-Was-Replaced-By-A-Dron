# Art Bible: Drone Farm

**Stylized low-poly + PBR (SurfaceAppearance / MaterialVariant) production guide**
Audience: 3D modellers, texture artists, technical artists. No scripting here: wherever a look
needs code to switch on, §8 says so explicitly.

> This document replaces the earlier flat-colour direction. The procedural placeholder visuals
> that the client builds from Parts stay in the game as a **fallback**; finished assets dropped
> into `ReplicatedStorage.Assets` (see §10.3) replace them automatically, with no code changes.

---

## Contents

0. [How to use this Bible](#0-how-to-use-this-bible)
1. [Art direction and colour palette](#1-art-direction-and-colour-palette)
2. [The grid and soil tiles](#2-the-grid-and-soil-tiles)
3. [Crop progression models](#3-crop-progression-models-botany)
4. [The drone and industrial machinery](#4-the-drone-and-industrial-machinery)
5. [Texturing and SurfaceAppearance](#5-texturing-and-surfaceappearance-guidelines)
6. [Blender modelling standards](#6-blender-modelling-standards)
7. [Performance budgets](#7-performance-budgets)
8. [Engine compatibility matrix](#8-engine-compatibility-matrix)
9. [Review gates and delivery checklists](#9-review-gates-and-delivery-checklists)
10. [Appendices](#10-appendices)

---

## 0. How to use this Bible

### 0.1 Toolchain

| Stage | Tool | Output |
|---|---|---|
| Blockout, low-poly modelling, UVs | Blender 4.x | `.blend` source, `.fbx` export |
| High-poly (optional, hard-surface bakes only) | Blender | `_high` collection, never exported |
| Baking and texturing | Adobe Substance 3D Painter (or Blender bake + Krita/Photoshop) | 8-bit PNG map set |
| Tileable materials (soil) | Substance 3D Designer / Painter fill + "make it tile", or Blender | 512² tileable PNG set |
| Import, assembly, lighting | Roblox Studio (3D Importer, Asset Manager, Material Manager) | Models in `ReplicatedStorage.Assets`, MaterialVariants in `MaterialService` |

### 0.2 Engine facts this Bible relies on

These are checked against the engine's API definitions (`build/globalTypes.d.luau`):

* **SurfaceAppearance** (child of a **MeshPart** only):
  * `ColorMap`, `NormalMap`, `RoughnessMap`, `MetalnessMap`, each a **separate image**; there
    is no channel-packed ORM;
  * `AlphaMode` = `Opaque`, `Overlay`, `TintMask` or `Transparency`;
  * a `Color` tint property;
  * `EmissiveMaskContent`, `EmissiveStrength` and `EmissiveTint` (emissive glow);
  * `TexturePack` (optional bundled maps).
* **MaterialVariant** (lives in **MaterialService**, applies to ordinary Parts by material):
  * the same four maps, `AlphaMode`, and emissive mask, strength and tint;
  * `StudsPerTile` (world-space tiling) and `MaterialPattern` = `Regular` or `Organic`.
* **MaterialService** base-material **override**: in Studio's Material Manager, "Set as
  override" makes every Part of that base material (e.g. `Ground`) use your variant.
* Uploaded images are capped at **1024 x 1024** (bigger uploads are downscaled), so never
  author past 1024.

### 0.3 Camera reality

Players see the farm **from above and at an angle**, typically 25–45 studs away, with the
field filling about a third of a 1080p screen. They also see it in the **main menu orbit**: a
slow circle 46 studs out and 30 studs up. Design for **silhouette and colour first**, normal
detail second, and micro-detail almost never.

### 0.4 Units and space

* **1 Blender unit = 1 stud.** Scene Properties, then Units: Unit System *None*, Scale 1.0.
  In the 3D Importer set **File Dimensions = Studs** and check the size readout against the
  specs in this Bible.
* Roblox is **Y-up**. "Forward" for the drone is **-Z** (the eye side).
* Key game dimensions, taken from `GameConfig`:

| Thing | Size (studs) |
|---|---|
| Field tile (Part) | **6 x 0.6 x 6**, tiles **0.4** apart (pitch 6.4) |
| Plot base under the tiles | 1 thick, grass |
| Field size | 3 x 3 at start, up to **10 x 10** |
| Drone hover height | 5 above the tile top |
| Charging Station pad | 6 x 0.4 x 6 at grid cell (0, -1) |
| Factory block (Bioreactor) | 6 x 3 x 6 at grid cell (1, -1) |

---

## 1. Art direction and colour palette

### 1.1 Pillars

1. **Warm hand-made life vs. cold precision tech.** Everything that grows is warm, soft,
   rounded and slightly irregular. Everything built is cool, dark, crisp and symmetric. That
   contrast *is* the game: code (tech) taming nature (organics).
2. **Silhouette first.** Every crop, stage and machine must be identifiable as a black shape at
   40 studs.
3. **Low-poly, high-quality.** Low triangle counts, but with deliberate bevels, clean faceting
   and good PBR texture work. Facets are a style choice, not a lack of polish.
4. **Light means state.** Emissive and Neon surfaces only ever show **state**: battery level,
   "ready", processing, charging, fertilized soil. Nothing glows for decoration.
5. **One kit, one family.** Shared atlases and trim sheets make the world look designed as a
   set (and keep texture memory tiny; see §5).

### 1.2 Shape language

| | Organic (crops, soil, wood) | Tech (drone, machines) |
|---|---|---|
| Primary forms | spheres, teardrops, tapered cones | boxes, cylinders, hexes |
| Edges | soft facets, no hard 90° corners | 45° chamfers, 2-segment bevels on outer edges |
| Symmetry | asymmetric (lean 5–15°, varied heights) | mirrored, radial |
| Detail | lumps, ribs, grain, rings | panel lines, vents, bolts, conduits |
| Proportion | chunky, slightly oversized fruit/heads | compact core with exaggerated "hero" parts (eye, rotors) |

### 1.3 Hue bands and contrast rules

* **Organics:** warm yellows, oranges and browns at **hue 20–60°**, and warm-leaning greens at
  **75–130°**. Organic greens never drift past **140°** towards teal.
* **Tech:** cool blue-greys and cyans at **185–220°**, with a **magenta accent at 300–320°**.
  Copper is the only warm metal; it's the deliberate bridge between the two worlds.
* **Value:** tech hulls are **dark** (sRGB value 15–30 %); crops are **mid-to-bright** (45–90 %).
  A machine next to a ripe crop must read as dark-vs-bright in a grayscale screenshot.
* **Saturation hierarchy:** ripe crops > state lights > machinery accents > soil > environment.
  The ground is never the most saturated thing on screen.
* **No neon on organics**, with one controlled exception: fertilized-soil speckles (§2.4.4).
* **PBR albedo hygiene:** no albedo darker than sRGB `#1A1A1A` or brighter than `#F0F0F0`.
  Metals use a coloured albedo with metalness 1; never paint reflections into the albedo.

### 1.4 Master palette

All values are sRGB. "R/M" means the target **Roughness / Metalness** for that surface.

#### Soil and ground

| Name | Hex | RGB | R / M | Use |
|---|---|---|---|---|
| Soil Dry base | `#8A6544` | 138, 101, 68 | 0.90 / 0 | dry tile surface |
| Soil Dry dark | `#6B4A30` | 107, 74, 48 | 0.92 / 0 | clods, shadows |
| Soil Dry dust | `#A98258` | 169, 130, 88 | 0.95 / 0 | sun-bleached tops |
| Soil crack | `#4E3524` | 78, 53, 36 | 0.95 / 0 | dry cracks |
| Tilled ridge | `#6E4A2F` | 110, 74, 47 | 0.80 / 0 | furrow ridges |
| Tilled trough | `#4A3020` | 74, 48, 32 | 0.78 / 0 | furrow bottoms |
| Tilled crumb | `#8C6040` | 140, 96, 64 | 0.85 / 0 | loose crumbs |
| Soil Wet base | `#4A3324` | 74, 51, 36 | 0.35 / 0 | watered surface |
| Soil Wet dark | `#35241A` | 53, 36, 26 | 0.30 / 0 | saturated patches |
| Puddle | `#2A1D16` | 42, 29, 22 | 0.10 / 0 | standing water spots |
| Fertile base | `#5E4128` | 94, 65, 40 | 0.75 / 0 | fertilized surface |
| Fertile speckle (emissive) | `#8DF56B` | 141, 245, 107 | 0.6 / 0 | glowing nutrient flecks |
| Plot grass | `#4E6B3A` | 78, 107, 58 | 0.85 / 0 | plot base, between tiles |
| Walkway gravel | `#7A7468` | 122, 116, 104 | 0.90 / 0 | walkway row, paths |
| Fence wood | `#8A6A4A` | 138, 106, 74 | 0.80 / 0 | fences, posts |
| Field stone | `#8B8478` | 139, 132, 120 | 0.85 / 0 | rocks, borders |

#### Crops (by stage)

| Crop | Seedling | Mid-growth | Ready | Accent / readiness cue |
|---|---|---|---|---|
| Wild grass | `#7CC85A` | `#8CC255` | `#96C454` tips `#C9C27A` | tips turn straw-gold |
| Wheat | `#8CC94F` | stalk `#7FA04A`, heads `#B9C46A` | stalk `#C7A84A`, heads `#E8C45C`, hi `#F4D987` | heads gold, drooping |
| Carrot | `#6FBF4E` | leaves `#5FAE45`, shoulder `#E07A35` | leaves `#4E9E3A`, root `#F08030`, hi `#FFA45C` | orange shoulder clearly visible |
| Sunflower | `#76C452` | stem `#5A9A3C`, bud `#9AB84A` | petals `#FFD23C` tips `#FFB01F`, disc `#5A3C1E`, seeds `#3E2814` | open yellow disc facing +Z |
| Pumpkin | `#7DC45A` | `#7BAA4A` mottled `#C9B04A` | `#FF9614`, rib shadow `#C46A10`, stem `#6B7A2E` | full orange, glossier (R 0.45) |
| Cactus | `#78B866` | `#66AE5E` | body `#60B05C`, ribs `#4B8E4A`, spines `#E9E2C8` | pink bloom on top `#FF6FA0` |
| Tree | `#6FBA52` | trunk `#7A5434`, canopy `#5A9A48` | trunk `#6E4A2E`, canopy `#4A8C46`, hi `#6DB25A` | full double canopy |

Crop roughness: leaves 0.6–0.7, stalks 0.75, roots and pumpkin skin 0.45–0.55, cactus 0.55,
petals 0.65, bark 0.85. Metalness is always 0.

#### Tech: drone, machines, emissives

| Name | Hex | RGB | R / M | Use |
|---|---|---|---|---|
| Hull dark (gunmetal-blue) | `#1E2530` | 30, 37, 48 | 0.40 / 0.2 | drone body, machine housings |
| Hull mid | `#2E3846` | 46, 56, 70 | 0.38 / 0.3 | arms, secondary panels |
| Panel light | `#4A5668` | 74, 86, 104 | 0.35 / 0.4 | inset panels |
| Ceramic white | `#D7E2EC` | 215, 226, 236 | 0.30 / 0 | accent plates, visor rim |
| Brushed steel | `#8E9AA6` | 142, 154, 166 | 0.35 / 1 | rotor hubs, pipes, pylons |
| Dark steel | `#3C4652` | 60, 70, 82 | 0.45 / 1 | frames, drums, tanks |
| Chrome | `#C9D3DC` | 201, 211, 220 | 0.15 / 1 | small highlights only |
| Copper | `#C27744` | 194, 119, 68 | 0.30 / 1 | charger coils, pipe flanges |
| Rubber / cable | `#1A1D22` | 26, 29, 34 | 0.85 / 0 | cables, grips, tyres |
| Hazard yellow | `#F2B630` | 242, 182, 48 | 0.60 / 0 | warning stripes (paint) |
| Hazard black | `#16181C` | 22, 24, 28 | 0.60 / 0 | warning stripes (paint) |
| Glass | `#9FD8E8` | 159, 216, 232 | 0.05 / 0 | tank shells (55 % transparent) |
| **Neon cyan** (primary tech) | `#3CDCFF` | 60, 220, 255 | emissive | charger, conduits, drone eye (default "online") |
| **Neon lime** (OK / bio) | `#8CFF5A` | 140, 255, 90 | emissive | battery full, processing OK |
| **Neon amber** (warning) | `#FFB547` | 255, 181, 71 | emissive | battery low, busy |
| **Neon red** (fault) | `#FF4D5E` | 255, 77, 94 | emissive | battery empty, error |
| **Neon magenta** (accent) | `#FF3DCB` | 255, 61, 203 | emissive | premium cosmetics, rare accents |
| **Biofluid** | `#4DFFB0` | 77, 255, 176 | emissive | Bioreactor tanks |

#### Environment and sky

| Name | Hex | Use |
|---|---|---|
| Sky zenith | `#6FA8DC` | skybox top |
| Sky horizon | `#CFE3F0` | skybox horizon / Atmosphere colour family |
| Distant hills | `#6E8A66` | backdrop meshes (desaturated, cooler than the field) |
| Shadow tint | `#28303C` | Lighting.Ambient (cool shadows make warm crops pop) |

#### UI tie-in

The in-world state colours match the HUD accents (`src/client/UI/Theme.luau`):
lime `#7FD962` = growth and OK, cyan `#66CCFF` = tech, info and premium, gold `#FFD666` =
featured. In-world neons are the brighter, emissive versions of the same hues, so HUD and world
read as one product.

### 1.5 Lighting and material response

**The game applies these in code** on every client: `src/client/Controllers/LightingController.luau`
(and `Lighting.Technology = Future` in `default.project.json`, since scripts can't set it). Tune
them there, not in Studio: a Studio click is lost on the next build. They are tuned for PBR
assets under Future lighting. The same controller builds a cheap ring of distant hills
(`#6E8A66`, non-colliding, no shadows) and tweens the weather looks on top of this baseline
(§1.5.1).

| Setting | Value | Why |
|---|---|---|
| `Lighting.Technology` | **Future** | per-pixel lights and PBR specular |
| `ClockTime` / `GeographicLatitude` | 14.5 / 35 | warm afternoon sun, readable shadow direction |
| `Brightness` | 2.4 | |
| `ExposureCompensation` | 0.1 | |
| `Ambient` / `OutdoorAmbient` | `#2A3240` / `#8E9AA6` | cool fill: warm-lit tops, cool shadows |
| `EnvironmentDiffuseScale` | 0.6 | sky light on rough surfaces |
| `EnvironmentSpecularScale` | **0.8** | metals and wet soil reflect the sky; at 0 PBR metal looks flat |
| `ShadowSoftness` | 0.25 | crisp-but-soft low-poly shadows |
| `ColorShift_Top` | `#FFF1DC` | warm sun tint |
| **Atmosphere** | Density 0.28, Offset 0.2, Color `#C8D9E8`, Decay `#7A8B9C`, Glare 0.15, Haze 1.0 | depth without washing out the field |
| **BloomEffect** | Intensity 0.8, Size 22, Threshold **1.4** | only emissive/Neon crosses the threshold |
| **SunRaysEffect** | Intensity **0.06**, Spread 0.6 | a subtle god-ray glint when the sun is near the horizon of the menu orbit; stronger values wash out the HUD |
| **ColorCorrectionEffect** | Brightness 0.02, Contrast 0.12, Saturation 0.08, TintColor `#FFF8EE` | |
| DepthOfField | off in play | the main menu already uses a tweened BlurEffect |

**How each material class should react:**

* **Dry soil and leaves (roughness 0.75–0.95):** broad, soft highlights. They must never
  bloom. With these settings, a roughness of 0.85 or more on albedo below 70 % brightness stays
  well under the threshold.
* **Wet soil (0.25–0.45, puddles 0.08–0.15):** small sharp glints from the sun and sky, the
  *only* organic surface allowed visible specular. Keep puddles under 15 % of the tile's area
  so glints read as "wet", not "glass".
* **Ripe pumpkin, carrot and cactus skin (0.45–0.55):** a gentle sheen that helps "ready"
  stand out from the matte unripe stages.
* **Painted hulls (0.35–0.45, metal 0.2–0.4):** mostly diffuse with a clean rim highlight. Panel
  lines in the normal map catch the sun.
* **Bare metal (metal 1, 0.15–0.45):** reflects `EnvironmentSpecularScale` sky. Keep chrome
  small; large chrome areas look like plastic mirrors at this camera distance.
* **Emissive / Neon:** the only surfaces above the Bloom threshold. They glow in the shade and
  in daylight alike, which is why they're reserved for state.

**Bloom and emissive targets** (starting values; tune in a test scene, §9):

| Surface | Method | Starting value |
|---|---|---|
| Drone eye | separate **Neon** MeshPart, no SurfaceAppearance | colour from the paint (`accent`) |
| Battery cells, tool LEDs | SurfaceAppearance emissive mask | `EmissiveStrength` 1.5–2, tint = state neon |
| Charger rings / conduits | emissive mask on the hard-surface trim | 2–3, `#3CDCFF` |
| Bioreactor biofluid | inner mesh with an emissive mask (whole mesh white) | 2, `#4DFFB0` |
| Fertilized speckles | MaterialVariant emissive mask | **0.6–1.0**, `#8DF56B` (glow, no big halo) |

> **Do:** concentrate glow into small, high-contrast shapes (slits, rings, cells).
> **Don't:** put emissive on large surfaces, stack bloom sources, or let white albedo
> (snow-white ceramic, sky reflections) cross the threshold. If a non-emissive surface blooms,
> lower its albedo or raise its roughness, not the global threshold.

### 1.5.1 Weather looks (visual only)

`src/client/Controllers/WeatherFxController.luau` reads the weather (your plot's `Weather`
attribute if it has one, else `Workspace.Weather`, the same value as the HUD chip) and tweens
the look over **1.5 s**. Rules, durations and growth numbers stay in `WeatherService`.

| Weather | Look (on top of the §1.5 baseline) | On your plot |
|---|---|---|
| Sunny | the baseline | no particles |
| Rainy | Atmosphere Density 0.34 (+0.06), Color `#B8C6D3` (cooler grey) | rain streaks from an invisible plate over your plot's Zone only (rate scales with the plot, 60–220/s, lifetime 0.6–1.0 s); up to 3 splash bursts at once on random tiles. Auto-watering is the server's: nothing fakes `Watered` |
| Drought | ColorCorrection Saturation 0.03 (−0.05), TintColor `#FFEBD2`; ColorShift_Top `#FFE6C4`; Atmosphere Haze 1.6, Color `#D6CDBE` | procedural crops lean 25 % toward dry straw `#C9C27A` (artist meshes are skipped, never tinted brown); about 1 dust wisp per second at ground level |

Weather particles switch off while you're out of Control Mode **and** more than 120 studs from
your plot. Tune the looks in `LightingController` (`OVERRIDES`) and the particles in
`WeatherFxController` (`CONFIG`).

---

## 2. The grid and soil tiles

### 2.1 What the game builds (fixed facts)

* The server builds every field tile as an ordinary **Part**: **6 x 0.6 x 6** studs,
  `Material = Ground`, placed on a 1-stud grass plot base. Tiles are **0.4 studs apart**
  (pitch 6.4). The gap is deliberate: the grass gutter between tiles makes the **coordinate grid
  readable** for players writing `get_x()` / `get_y()` code.
* The client shows each tile's **soil state** (Dry / Tilled / Wet, §2.4) with the hook in
  §2.2: your MaterialVariant when it exists, otherwise built-in Ground (Mud when wet) tinted
  with the §1.4 albedo `#8A6544` / `#6E4A2F` / `#4A3324`.
* Crops sit on the tile's top-face centre. The drone and stations live off-field (row -1).

### 2.2 Recommended method: MaterialVariants (seamless by construction)

Because tiles are Parts, the best route to PBR soil is a set of **MaterialVariants**. Their
textures are mapped in **world space** (`StudsPerTile`), not per-tile UVs, so neighbouring
tiles, every side face and any future gap-free field continue the pattern with **zero UV
seams**.

| Variant name | BaseMaterial | StudsPerTile | MaterialPattern | Notes |
|---|---|---|---|---|
| `SoilDry` | Ground | 8 | **Organic** | random rotation and offset hide repetition |
| `SoilTilled` | Ground | **6.4** (= tile pitch) | **Regular** | furrows stay parallel to the grid rows; every tile shows the same furrow layout |
| `SoilWet` | Ground | **6.4** | **Regular** | authored over the **Tilled** height so the furrows stay (wet tiles nearly always carry a crop) |
| `SoilFertile` | Ground | 6.4 | Regular | the furrows read through, plus the emissive speckle mask |

**The renderer hook is in the game** (`src/client/Visuals/SoilLook.luau`; the state comes
from `src/shared/Util/SoilStates.luau`). It runs client-side on every field tile:

* **Drop in a variant** named exactly `SoilDry`, `SoilTilled` or `SoilWet` (BaseMaterial
  Ground) anywhere in MaterialService, folders included. Matching tiles then get
  `Material = Ground` and `MaterialVariant = <name>`, and their `Color` is set to white once
  and never touched again. Variants that replicate in while the game runs are picked up too.
* **Until a name has your variant**, the game creates a placeholder MaterialVariant with that
  name at runtime, so the hook is real from day one. Scripts can't set texture maps, so the
  placeholder has none: the state reads from `Part.Color` (the §1.4 albedo) with Ground, or
  Mud for wet as the glossy stand-in. `USE_PLACEHOLDERS = false` in `SoilLook` draws the
  same states with plain built-in Ground / Mud instead [verify in Studio which reads better].
* `SoilFertile` is reserved and never shown yet.
* Setting `SoilDry` as the Material Manager override for `Ground` is no longer needed (every
  tile is named explicitly); it is harmless if set.

**Colour:** while your variant is present the game keeps the tile's `Color` white, so author
each variant's albedo at its final §2.4 value. `AlphaMode = Opaque` is the default choice;
`TintMask` works too (white = untinted). The harvest flash (§3.5) only shows on placeholder
tiles, since your texture owns the colour.

**Texel density:** 512² over 8 studs = **64 px/stud**. The gameplay camera resolves about
20–30 screen px per stud, so **512² is plenty**; 1024² is wasted memory for soil.

### 2.3 Optional method: a MeshPart tile kit (bevelled silhouette)

If you want chunky bevelled tiles with real edge geometry, build them as MeshParts. Swapping
the server's Parts for meshes is a code change (§8), so treat this as a future upgrade. The
Blender rules below still apply to any modular kit.

**Modelling (Blender):**
1. Start from a cube of **6 x 0.6 x 6**, with the origin at the **centre of the top face**.
2. Bevel the top perimeter by **0.12 studs, 2 segments**, profile 0.5. Leave the bottom edges
   sharp (they're hidden in the plot base).
3. Add a 0.1-stud downward **skirt** so no light leaks through the gap.
4. Add 4–6 low clods (8–12 tris each) only on the bevel ring, never on the flat top (crops
   stand there).
5. Weighted Normal modifier (keep sharp, weight 50), then **Triangulate** on export.
6. Budget: **≤ 150 tris** per tile (10 x 10 = 15k tris).

**UVs that tile without seams:**
* **Top face** = an exact **0–1 square**, unrotated, with no padding gaps at the edges (it must
  wrap). Texel density: 512 px over 6 studs ≈ **85 px/stud**.
* **Bevel + sides** = straight strips on a separate **trim row** (bottom 64 px of a 512 sheet),
  with the strip length a whole multiple of the texture so the side pattern wraps around the
  tile.
* Same **texel density on every face** (check with a checker texture), and no mirrored
  islands on the top.

**Texturing so tiles match each other:**
* Build the top material as a **tileable** texture: in Substance Designer use
  Tile Sampler / Tile Generator; in Painter use a fill layer with the *tiling* option on and
  edge-wrapped height. Bake or derive the normal map from the tileable height, never from a
  non-tiling bake.
* The four tile edges must have **matching height and colour** at the borders (offset the
  texture by 50 % and paint out the cross seam before export).
* Randomise per tile with **variants, not unique textures**: 2–3 mesh variants (clod layouts)
  share one texture set, and level designers rotate tiles in 90° steps.
* **Seam test** (mandatory): a 3 x 3 grid with 0 gap and with 0.4 gap, under the §1.5
  lighting, viewed from 30 studs. No visible line, no lighting step on the normals, no
  brightness jump at the borders.

### 2.4 The four soil states

Common to all states: metalness **0**; albedo values from §1.4; 512² maps (`Color`, `Normal`,
`Roughness`, plus `Emissive mask` for Fertile); tileable.

#### 2.4.1 Dry (bare soil: before planting and after a harvest)

* **Read:** lighter, dusty, broken, "nothing growing here".
* **Height:** a low **macro noise** (clods 0.3–0.8 studs wide, ±0.05 studs) plus **sparse
  cracks** (Voronoi edges, 1–2 px wide, 15 % coverage).
* **Albedo:** a base `#8A6544` with dust `#A98258` on the height peaks (curvature/AO
  generator), and cracks `#4E3524`.
* **Roughness:** 0.88–0.95; cracks 0.95.
* **Substance recipe:** fill (base) → *Grunge Map 012*-style macro mask at 30 % → height-peak
  mask → dust colour → crack generator from height → sharpen normal 0.3.

#### 2.4.2 Tilled (a player-planted crop is on the tile)

* **Read:** worked, ordered, fertile. Distinct **furrows** that run **parallel to the grid
  rows**.
* **Height:** **5 furrows per tile** (pitch 6.4 / 5 ≈ 1.28 studs), a sine-like profile
  0.12 studs deep, a 0.5-stud flat crest; crumbs (small bumps) along the crests.
* **Albedo:** ridges `#6E4A2F` and troughs `#4A3020` driven by the height, with crumbs `#8C6040`.
* **Roughness:** 0.75 in troughs (slightly damp), 0.85 on ridges.
* **Important:** furrows must run along the texture's **U axis** so that, with `StudsPerTile`
  6.4 and the Regular pattern, they line up across every tile and the whole field reads as
  rows.

#### 2.4.3 Watered (darker and glossy)

* **Read:** "this tile was watered". Darker, saturated, glossy, with small puddles in the low
  spots.
* **Height:** reuse the **Tilled** height (watering darkens; it doesn't reshape, and wet tiles
  nearly always carry a planted crop, so the furrows must stay), and fill puddles in the
  lowest **10–15 %** of the height range. Same `StudsPerTile` 6.4 / Regular as `SoilTilled`.
* **Albedo:** base `#4A3324` and saturated patches `#35241A`. Lower the albedo of all lighter
  areas by about 35 % (wet surfaces are darker); puddles `#2A1D16`.
* **Roughness (key map):** **0.30–0.45** overall, **0.08–0.15 in puddles**, and keep a few
  dry crumb tops at 0.6 so it doesn't look like plastic. This map sells the state.
* **Normal:** flatten the normals inside puddles (blend to a flat normal), so puddles reflect
  like water.

#### 2.4.4 Fertilized (glowing speckles)

* **Read:** "boosted soil", warm earth seeded with glowing nutrient flecks. It's the one organic
  surface allowed to glow, and only faintly.
* **Base:** a copy of Tilled with albedo shifted to `#5E4128` and roughness 0.75.
* **Speckles:** an **emissive mask** of small dots (2–5 px at 512, **3–5 % coverage**,
  clustered along the furrow troughs), plus `EmissiveTint` `#8DF56B` and `EmissiveStrength`
  **0.6–1.0**.
* **Albedo under the speckles:** paint the flecks a bright `#B8FF8C` in the ColorMap too, so
  they still read as specks on devices with emissive effects turned down.
* **Bloom check:** at the §1.5 settings the field should look sprinkled, not foggy. If a halo
  forms, reduce coverage before reducing strength.

**Gameplay mapping** (`SoilStates.forTile`):
* Dry (`SoilDry`) = bare soil and wild grass tiles (weeds on unbroken dirt)
* Tilled (`SoilTilled`) = a player-planted crop, planted, growing or ready
* Watered (`SoilWet`) = the tile's `Watered` attribute; it overrides Tilled
* Fertilized (`SoilFertile`) = **reserved** for a future mechanic

The state swap itself is the hook in §2.2.

### 2.5 Plot dressing the game adds

`src/client/Visuals/PlotDressing.luau` dresses every plot client-side. All of it is inert, so
players still walk on the server base. Organic parts are warm wood; tech stays dark and crisp
(§1.1).

| Element | Look | Shown on |
|---|---|---|
| Walkway (row y = -2) | a gravel strip `#7A7468` (Pebble) with plank edging (Fence wood `#8A6A4A`) | your plot |
| Fence | 1.3-stud wooden posts every ≤ 2 tiles and two rails, 1.1 studs outside the field on the left, back and right. The side facing the station row stays **open**, so the drone's path reads clearly | your plot and plots within 120 studs |
| Sign post | a wooden pole and crossbar under the owner billboard. **VIP** = gold cap and gold bands, plus a 👑 icon above the name (never a "[VIP]" text prefix), from the server's `OwnerVip` attribute | your plot and plots within 120 studs |
| Charger extras | two copper coil windings `#C27744` around the pylon. **Idle = dark:** the rings, the pylon light and the server's pad turn dark teal-grey; they light up Neon `#3CDCFF` (rings pulsing) only while your drone charges | your plot |
| Factory extras | a biofluid slit `#4DFFB0` on the front face and an amber work lamp `#FFB547` on the hopper: dark while idle, Neon and flickering / pulsing only while your drone is on the factory. The front window is dark glass (no decoration glow) | your plot |

Nothing is dressed beyond 120 studs. Artist station models (`Assets/Stations/<kind>`) skip
the station extras, since they bring their own detail.

---

## 3. Crop progression models (Botany)

### 3.1 How the game shows a crop (fixed facts)

* Folder per crop and stage: `ReplicatedStorage.Assets.Crops.<cropId>.<stage>`, where the stage
  names are **`sprout`** (Seedling, growth < 50 %), **`growing`** (Mid-Growth, ≥ 50 %) and
  **`ready`** (Ready-to-Harvest).
* **Pivot** (`Model.WorldPivot`) = the centre of the tile's top face, with the plant growing
  up +Y.
* **The game scales your model while it grows** (`Model:ScaleTo`):

| Stage | Displayed scale of the authored model |
|---|---|
| `sprout` | 0.25 → 0.55 |
| `growing` | 0.55 → 0.85 |
| `ready` | 1.00 |

* So **author `sprout` and `growing` bigger than they should finally look**:
  * a sprout authored **2.2 studs tall** shows at about 0.55 → 1.2 studs;
  * a growing model authored at **0.9 x the ready height** shows at about 50 → 75 % of the
    ready height.

  The hand-off between stages then looks continuous.
* Each tile's crop is **rotated by a fixed yaw in 45° steps**. Every model must look good from
  all eight directions.
* **Footprint:** keep a ready crop inside **5.2 x 5.2 studs** (0.4 clearance on each side of a
  6-stud tile), so neighbours never merge into a hedge.

### 3.2 Shared modelling rules

* **Opaque, faceted foliage. No alpha-card leaves.** Transparent cards cost overdraw and sort
  badly on Roblox. Leaves are thin wedges or diamond prisms (4–8 tris per leaf).
* **1 MeshPart per stage model, at most 2** (a second only when part of it must be tinted or
  glow separately). Join everything else in Blender.
* Flat-shaded facets with **weighted normals** on stems for a soft read. Use 3–6 sided
  cylinders for stems, never 12+.
* **Readiness must be legible:** the ready stage changes **colour** (full warm hue),
  **silhouette** (heads, fruit, bloom) and **roughness** (a slightly glossier fruit) at once.
  Never rely on size alone.
* All crops use the **shared crop atlas** (§5.4), UV-mapped onto palette swatches and detail
  strips. There are no per-crop texture sets.

### 3.3 Per-crop specifications

Heights are the **ready** model's authored height H. "Tris" is the per-stage maximum.

#### Wheat (H = 3.3)

| Stage | Silhouette | Tris | Colours |
|---|---|---|---|
| Seedling | 5 straight blades fanning out, 2.2 tall authored | 60 | `#8CC94F` |
| Mid-growth | a 9–11 stalk tuft, green unopened heads, tighter than ready | 180 | stalk `#7FA04A`, heads `#B9C46A` |
| Ready | 11–13 stalks (3 height tiers), **fat gold grain heads drooping 15–25°** outwards | 300 | stalk `#C7A84A`, heads `#E8C45C` → `#F4D987` |

Texture: the grain heads use the atlas **grain strip** (normal-mapped kernel bumps). Stalks are
on palette swatches. Roughness: heads 0.65, stalks 0.75.

#### Carrot (H = 1.8)

| Stage | Silhouette | Tris | Colours |
|---|---|---|---|
| Seedling | 3 tiny feathery leaves on a nub, 2.2 tall authored | 50 | `#6FBF4E` |
| Mid-growth | a leafy dome, a small orange shoulder just breaking the soil | 160 | leaves `#5FAE45`, shoulder `#E07A35` |
| Ready | a **big leafy plume** plus a **chunky orange shoulder (Ø 0.9) clearly above the soil** | 220 | leaves `#4E9E3A`, root `#F08030` / `#FFA45C` |

Texture: the root uses the atlas **ring strip** (horizontal growth rings in the normal map).
Roughness: root 0.5, leaves 0.65.

#### Sunflower (H = 4.0)

| Stage | Silhouette | Tris | Colours |
|---|---|---|---|
| Seedling | 2 round cotyledons on a short stem | 50 | `#76C452` |
| Mid-growth | a tall stem, 2 leaves, a **closed green bud** | 180 | stem `#5A9A3C`, bud `#9AB84A` |
| Ready | a stem, 2–3 leaves, **an open flower head Ø 1.6** (12 petals, a thick seed disc) tilted 15° toward **+Z** (the camera side) | 350 | petals `#FFD23C` → `#FFB01F`, disc `#5A3C1E`, seeds `#3E2814` |

Texture: the disc uses the atlas **seed spiral strip** (normal + darker albedo spiral). Petals
are single-sided-looking wedges, but **modelled with thickness** (no DoubleSided). Roughness:
petals 0.65, disc 0.8.

> The tilt toward +Z is the one case where an asset prefers a direction. Because of the per-tile
> 45° yaw it still looks fine from other sides; just avoid an edge-on head.

#### Pumpkin (H = 2.0)

| Stage | Silhouette | Tris | Colours |
|---|---|---|---|
| Seedling | 2 broad leaves on a stub | 50 | `#7DC45A` |
| Mid-growth | 3–4 big leaves, a small green-to-yellow fruit (Ø 1.2) | 220 | leaves `#5FA040`, fruit `#7BAA4A` / `#C9B04A` |
| Ready | a **squashed ribbed sphere Ø 2.6 x 1.8**, 8 ribs, a curly stem, 2 leaves behind it | 350 | `#FF9614`, ribs `#C46A10`, stem `#6B7A2E` |

Modelling: an 8-segment UV sphere squashed 0.7 in Y, with alternate edge loops pulled in for
the ribs (about 220 tris for the fruit). Roughness: **0.45** skin (the glossy ready cue), 0.6
for unripe.

#### Cactus (H = 3.3)

| Stage | Silhouette | Tris | Colours |
|---|---|---|---|
| Seedling | a small round nub with 4 ridges | 40 | `#78B866` |
| Mid-growth | a 6-sided column with 1 short arm | 140 | `#66AE5E` |
| Ready | a column with **2 arms at different heights**, a flat-ish top and a **small pink bloom** | 220 | body `#60B05C`, ribs `#4B8E4A`, bloom `#FF6FA0` |

Spines: **don't model them**. Paint light dots `#E9E2C8` along the ribs in the atlas **spine
strip**, with a tiny normal bump. The pink bloom is the ready cue (a separate colour island,
roughness 0.6). Body roughness 0.55.

#### Also in the game (same rules)

| Crop | Ready silhouette | H | Tris per stage (S / M / R) |
|---|---|---|---|
| Wild grass | 3–5 leaning blades in a tuft, straw-gold tips when ready | 1.2 | 40 / 60 / 80 |
| Tree | a short trunk, 2 overlapping canopy blobs | 5.0 | 60 / 200 / 300 |

### 3.4 Optimising a fully planted 10 x 10 field

**Triangles:** 100 tiles x **≤ 350** = **≤ 35k tris** for the worst case (all pumpkins and
sunflowers ready). Modern Roblox clients render that easily. Triangles aren't the bottleneck;
**draw objects and texture memory are.**

| Technique | Why it matters |
|---|---|
| **One MeshPart per stage model** (two at most) | fewer render objects per tile: 100 tiles stay at about 100–200 objects |
| **Identical assets everywhere**: the same mesh asset and the same texture asset ids on every tile | the engine loads one copy of each mesh and texture, and identical MeshPart + SurfaceAppearance combinations batch well |
| **One shared crop atlas** (§5.4) for all 7 crops x 3 stages | 1 texture set instead of 21; switching stages never loads new textures |
| Variety from the game's per-tile 45° yaw, not unique meshes | 21 meshes in total for the whole game |
| `RenderFidelity = Automatic` | lower-detail versions far away (the menu orbit, neighbouring plots) |
| `CollisionFidelity = Box` | the cheapest collision data (crops never collide; the game makes them non-colliding anyway) |
| `CastShadow = false` on seedlings and wild grass | tiny shadows are invisible from the gameplay camera but still cost |
| No unions (CSG), no transparency, no alpha cards | unions and transparency are the expensive paths |
| ≤ 1 emissive surface per crop (only the reserved cases) | avoids bloom fill-rate on 100 tiles |

**Per-plot cost sheet (10 x 10 worst case):**

| Item | Objects | Tris | Texture sets |
|---|---|---|---|
| 100 tiles (Parts + MaterialVariant) | 100 | 1.2k | 1–4 (shared soil variants) |
| 100 ready crops | 100–200 | ≤ 35k | 1 (crop atlas) |
| Drone + tool | ≤ 16 | ≤ 2.5k | 1 |
| Stations | ≤ 12 | ≤ 5.5k | 1 trim + 1 decal |
| **Plot total** | **≈ 330** | **≈ 45k** | **≈ 4–7 (all shared across plots)** |

### 3.5 Feedback FX the game adds (don't bake these into models)

The client animates every crop transition on top of your models
(`src/client/Controllers/PlotRenderer.luau`, section "CROP JUICE"). This is **readability,
not decoration**: from the bird's-eye camera a player must see what just happened on a tile.

| Moment | What plays | What it asks of the art |
|---|---|---|
| Planting | a 0.34-stud seed falls from the drone into the tile (0.2 s), then the sprout grows in | keep the `sprout` pivot at the tile top so the seed lands in it |
| Planted → growing | the crop pops to 1.08x and settles; 8 leaf bits (0.4 s) | |
| Ready | the crop pops to 1.12x and settles (the silhouette cue); procedural crops switch from matte Plastic to glossy SmoothPlastic; on **your own** plot a lime neon disc pings across the soil | make the `ready` silhouette clearly different from `growing` (heads, fruit, bloom); the pop only draws the eye to it |
| Ready, idle | a ±2° sway around the pivot (your plot only, at most 36 crops) | the sway pivots at the tile top, so nothing may hang below it |
| Ready, in Control Mode | a small lime dot floats above the crop (hidden when more than 40 tiles are ready) | leave about 0.6 studs of headroom above the tallest part |
| Harvest | 6–12 bits in the crop colour burst up and fade (grey/brown if it wasn't ripe); the tile flashes Soil Dry `#8A6544` | `CropConfig.color` is the burst colour: keep it the crop's dominant ripe colour |
| Watering | 4–6 cyan-white droplets splash (0.3 s) when the drone waters; rain only darkens the soil | |

**Budgets (enforced in code):**
* full FX only on your plot and plots within **80 studs**; other plots only get the growth
  tweens;
* at most **40 live particles** across all plots, and **one burst per tile** at a time;
* every burst comes from **one pooled Attachment per plot** (emitters cloned from one template
  and never `Enabled`);
* **no lights and no trails**; the neon ping only on ready tiles of your own plot;
* neighbouring plots **never sway**.

The particle textures are Roblox built-ins (`rbxasset://textures/particles/SquareParticle.png`
for bits, `rbxasset://textures/smallWhiteCircle.png` for droplets), so nothing needs
uploading. To restyle them, upload a 64 x 64 white-on-transparent PNG and set
`SQUARE_TEXTURE` / `DROP_TEXTURE` in `PlotRenderer`; the colour comes from the emitter.

**Playtest (Studio):**
1. **3 x 3 wheat cycle** (plant, wait, harvest): seed drop → pop + leaf bits → ready pop,
   gloss and lime ping → sway → harvest burst + soil flash. Harvest one early: the burst is
   grey/brown.
2. **6 x 6 full field:** while playing, select `Workspace.ClientVisuals`. `FxParticles` stays
   ≤ 40, `FxSwaying` ≤ 36 and `FxTweens` stays well under 160, and the frame rate holds
   (check the MicroProfiler: Ctrl+Alt+F6).
3. Walk more than 80 studs from a plot: its crops still grow, but no bursts play there
   (`FxFullPlots` drops).
4. Debug only: setting the `FxSwayNeighbours` attribute on `ClientVisuals` to true lets
   nearby plots sway too, and it switches itself off while more than 160 FX tweens are
   running. The default (false) must stay false.

---

## 4. The drone and industrial machinery

### 4.1 The drone (hero asset)

#### Concept

A compact, friendly **quad-rotor farm drone**. It has a dark gunmetal-blue hull with a cool
ceramic visor rim and one large expressive **eye slit** at the front (-Z). A **battery bar**
runs along the top spine, and a modular **tool mount** sits underneath. It should feel like
premium consumer tech (sleek, rounded-chamfered, confident), never military.

#### Dimensions and parts (they must match the in-game rig)

| Part name (exact) | Role | Size / position (studs, relative to pivot = body centre) | Material approach |
|---|---|---|---|
| `Body` | hull | 2.4 x 0.8 x 2.4 core; chamfered top | MeshPart + SurfaceAppearance; `PaintSlot = "primary"` |
| `Arm1`..`Arm4` | arms to the rotors | 0.25 x 0.2 x 1.4 each, toward the 4 diagonals | MeshPart + SA; `PaintSlot = "secondary"` |
| `Rotor1`..`Rotor4` | spinning rotors | Ø 1.5 discs at (±1.6, +0.5, ±1.6) | MeshPart + SA (steel hub, dark blades); **they spin** |
| `Eye` | visor light | 0.6 x 0.35 x 0.2 slit at (0, 0, -1.25) | **Neon** MeshPart, **no** SA; `PaintSlot = "accent"` |
| `BatteryBar` | state indicator | a 1.2 x 0.12 x 0.3 strip on the top spine, 5 cells | MeshPart + SA with an **emissive mask** |
| `ToolMount` | **Attachment** (not a part) inside `Body` | at (0, -0.45, -0.3), +Y up, -Z forward | |

* **Overall footprint** with rotors is about 4.7 x 1.4 x 4.7. It hovers 5 studs above the tile;
  the game adds a 0.35-stud bob and a 14° lean into each move, so nothing may clip when tilted.
* **Rotor pivots:** any part whose name starts with `Rotor` is **spun around the vertical axis
  through its own origin**. In Blender, put each rotor mesh's **origin at its hub centre** and
  model the blades **flat** (horizontal). Keep the four rotor meshes identical (one mesh asset,
  four instances).
* **Hats:** the top of `Body` must stay flat within a 1.2-stud circle around the centre.
  Cosmetic hats are placed 0.4 studs above the body centre.
* **Budget:** **≤ 1,900 tris** for the drone (body 700, arms 4 x 60, rotors 4 x 150, eye 40,
  battery 80, details) plus **≤ 600** for an attached tool. That's ≤ 2,500 in total, and
  **≤ 16 MeshParts**.

#### Hard-surface workflow (Blender)

1. **Blockout** with primitives at the exact sizes above. Check the silhouette from 40 studs
   top-down and from the menu orbit angle.
2. **Low-poly:** 45° chamfers on the major edges, then a **Bevel modifier** (0.04–0.06 studs, 2
   segments, *Harden Normals*) and a **Weighted Normal** modifier. This gives the premium
   "bevelled" read with no normal map.
3. **Optional bake:** for panel lines, vents and screw heads, model a `_high` version
   (subdivision + boolean cuts) and bake **Normal + AO + Curvature** onto the low-poly in
   Substance Painter. Use cage extrusion 0.02; the low-poly must be triangulated *before* baking.
4. **Mirror** left/right and overlap mirrored UVs **only on the arms and rotors** (never on the
   body, where asymmetric decals live).

#### Paint jobs (cosmetics) with SurfaceAppearance

The game recolours `PaintSlot` parts by setting the part's **Color** (`primary` = hull,
`secondary` = arms, `accent` = eye). To make that work with textured parts:

* Give each painted MeshPart's SurfaceAppearance **`AlphaMode = Overlay`**, and author the
  **paintable areas as transparent in the ColorMap's alpha channel**. The part's Color shows
  through those areas, while unpainted details (bolts, vents, decals, bare metal) stay opaque
  and keep their authored colour.
* Paint the transparent areas a neutral mid grey in the RGB as well (the overlay replaces it,
  but it keeps texture previews sensible).
* The normal and roughness maps still apply on painted areas, so panel lines and wear read on
  every paint job.
* Alternative [verify in Studio]: `AlphaMode = TintMask` tints by the SurfaceAppearance's own
  `Color`. Use it only if the paint system is later changed to set that property.

#### Neon and emissive on the drone

* **Eye:** a **separate Neon MeshPart with no SurfaceAppearance**. That's the strongest, most
  reliable bloom, and the game recolours it per paint job. Model it as an inset slit, recessed
  0.05 into a dark bezel (the bezel contrast makes the bloom look sharp, not foggy).
* **Battery bar:** **5 cells** on one MeshPart with a SurfaceAppearance **emissive mask**
  (white cells, black gaps), `EmissiveTint` `#8CFF5A` and `EmissiveStrength` 1.5. Model the
  cells as raised segments with 0.02 gaps so they read even when unlit.
  * Optional state variants for when level-based switching is added later (§8):
    `BatteryBar_Mid` (3 cells amber `#FFB547`) and `BatteryBar_Low` (1 cell red `#FF4D5E`).
* **Rule:** never make the hull itself emissive. At most **3 glowing elements** on the drone
  (eye, battery, one tool LED).

#### Interchangeable tools (attachment points)

The tool system is a future code feature (§8). Build the assets now to this contract:

```
ReplicatedStorage.Assets.Tools
├── WateringCan       Model, pivot = ToolMount point (top centre of the tool), ≤ 600 tris
│   ├── Tank          MeshPart + SA: dark-steel frame, glass window
│   ├── WaterLevel    MeshPart inside the tank, emissive mask, tint #3CDCFF
│   └── Nozzle        MeshPart: a spray bar with 3 jets pointing -Y
└── HarvesterBlades   Model, pivot = ToolMount point, ≤ 600 tris
    ├── Housing       MeshPart + SA: hull mid + hazard-stripe trim
    ├── RotorBladeL   twin blade discs (named Rotor* so they inherit the spin)
    └── RotorBladeR
```

* **Watering Can / Sprayer:** a slim tank slung under the body, a **glass window** showing a
  cyan water level (emissive mask strip), and a nozzle bar with 3 jets. Steel + rubber hoses,
  cyan accent.
* **Harvester Blades:** twin horizontal blade discs Ø 1.2 under the front, a stamped steel
  housing with hazard stripes, a magenta or amber LED. Blades are flat with the origin at the
  hub, so they spin like rotors.
* Both tools fit inside a 2.2 x 0.9 x 2.0 box under the body and **don't hide the eye** from the
  top-down camera.

#### 4.1.1 Program signals the game adds (don't bake these into the model)

The client makes the drone read as a *running program* (`PlotRenderer`; the decisions are in
`src/shared/Util/DroneSignals.luau`, unit-tested). The server's movement is untouched.

| Signal | Who sees it | What plays |
|---|---|---|
| **Battery strip** | every drone | the `BatteryBar` on the spine (procedural: a 1.2 x 0.12 x 0.3 Neon strip at (0, +0.46, +0.78), behind the hat circle): **> 50 %** lime `#8CFF5A`, **15–50 %** amber `#FFB547`, **< 15 %** red `#FF4D5E` with a slow blink. From `Battery` / `BatteryMax`. The visor `Eye` stays the paint's accent. An artist drone's part named `BatteryBar` or `StatusLight` is coloured the same way (make it Neon with no SurfaceAppearance, or Part.Color can't show); otherwise the game adds the strip |
| **Path ghost** | your drone | the last 16 field cells it left get a lime dot on the tile top, fading 0.4 → 1 over 4 s (a pool of 16 parts, no Beams). A `while True:` snake is readable from 20 studs |
| **Tool flash** | your drone | a 0.15 s disc under the ToolMount: lime = plant, cyan = water, gold = harvest. Inferred conservatively: only with the drone exactly over the tile, only ripe harvests, never wild-grass regrowth or rain watering |
| **Charging** | your drone | on the charger cell the battery strip turns cyan `#3CDCFF` and the charger rings pulse |
| **Factory work** | your drone | on the factory cell the biofluid slit flickers and the amber work lamp pulses (§4.3) |
| **Limp** | your drone | a move clearly slower than normal (empty battery, `LimpSlowdown`) flattens the hover bob to 25 % and dims the battery strip |
| **Ground shadow** | your drone | a soft dark ellipse (3.5 x 0.05 x 3.5, `#0E1218`, 55 % transparent) on the tile top under the hover point; it fades out over stations |
| **Rotor wash** | your drone | 3 dust particles (`#A98258`) puff out on the ground where it lifts off a field tile; nothing while idle |

This keeps the glow budget: eye + battery strip (+ one tool LED later) = the §4.1 maximum of 3.

**The procedural stand-in** (used while `Assets/Drone` is missing) follows the same
silhouette: a dark hull (the default *Factory Grey* paint is now hull dark `#1E2530` with hull
mid `#2E3846` arms), a ceramic `#D7E2EC` visor rim with one neon eye slit on -Z, the battery
strip, 4 arms and 4 spinning rotors (12 parts).

### 4.2 Charging Station (grid cell 0, -1)

* **The server part:** a 6 x 0.4 x 6 cyan **Neon pad**. Your model's pivot = the **top-face
  centre of that pad**. Cover it with a **6.1 x 0.3 x 6.1 base plate** (otherwise the pad's
  neon glows through), or leave a 0.2-stud ring of the pad visible as a deliberate glow rim.
* **Concept:**
  * a **hexagonal landing pad** of dark-steel panels with a ceramic-white H-shaped landing mark;
  * **two concentric copper coil rings** around the landing zone, with **cyan emissive
    conduits** running from the coils to a **capacitor pylon** in the back-left corner;
  * the pylon has stacked capacitor drums, a cyan status lamp and cable bundles.

  The vibe is electric, precise and humming.
* **Limits:** **≤ 2.5 studs tall** (the drone lands at 5 studs and must stay visible), pylon
  ≤ 3.5 in one corner only, ≤ **1,500 tris**, ≤ 6 MeshParts.
* **Materials:**
  * brushed steel (M 1, R 0.35) and dark steel (M 1, R 0.45);
  * copper coils (M 1, R 0.3, normal-mapped windings from the trim sheet);
  * rubber cables (R 0.85);
  * landing mark ceramic (R 0.3);
  * emissive conduits `#3CDCFF` (strength 2–3).

### 4.3 Bioreactor / Composter (the Factory, grid cell 1, -1)

* **The server part:** a 6 x 3 x 6 block. Your model's pivot = the **top-face centre of that
  block**. Model a lower housing that **wraps the block** (inner clearance 6.05 x 3 x 6.05,
  extending 3 studs down from the pivot) and rises at most **6 studs above the pivot**.
* **Concept:** where nature becomes fuel, so the model shows both worlds touching.
  * **Organic side (front, +Z, toward the camera):** a wooden-slat **intake hopper** with
    straw spill and a warm amber work light, where crops go in.
  * **Industrial core:** a dark-steel **composting drum** on a frame, with **flanged copper
    pipes** feeding two **glass processing tanks** full of glowing **biofluid** (`#4DFFB0`).
  * **Back:** a **vent stack / chimney** with a hazard-striped cap, plus a small control panel
    with amber and lime lamps.
* **Glass tanks:** one **outer glass shell** (MeshPart, `Transparency` about 0.55, glass colour
  `#9FD8E8`, R 0.05, not emissive) around an **inner biofluid mesh** (opaque, emissive mask
  fully white, tint `#4DFFB0`, strength 2). **Only one transparent layer**: never put
  transparent liquid inside transparent glass (sorting artifacts, double fill cost).
* **Limits:** ≤ **4,000 tris**, ≤ 10 MeshParts, at most 2 emissive surfaces (biofluid + lamps).
* **Readability:** from the gameplay camera, the hopper (warm) and the tanks (green glow) must
  be the first two things you notice, before the pipes.

### 4.4 Shared hard-surface texture strategy

Both machines **and** the tool housings share **one 1024² hard-surface trim sheet** plus
**one 512² decal sheet** (§5.4). The drone gets its own 1024² set because it's the hero asset
and is seen up close in the menu.

---

## 5. Texturing and SurfaceAppearance guidelines

### 5.1 Required maps by asset type

| Map | Colour space | Organic (crops, soil, wood) | Hard-surface (drone, machines, tools) |
|---|---|---|---|
| **Color** (ColorMap) | sRGB | **required**: flat palette colours + soft hand-painted gradients, light AO (≤ 15 % multiply) only | **required**: paint, decals, wear on edges. **Alpha** = paint mask for `PaintSlot` parts (Overlay mode) |
| **Normal** (NormalMap) | linear, tangent-space, **OpenGL (Y+)** [verify on first import] | **recommended**: grain, ribs, rings, clods (low strength) | **required**: bevels, panel lines, vents, screws (baked or trim) |
| **Roughness** (RoughnessMap) | linear grayscale | **required**: this is where "wet" and "ripe" are sold | **required**: paint vs. bare metal vs. rubber vs. glass |
| **Metalness** (MetalnessMap) | linear grayscale, mostly pure 0 or 1 | **skip** (non-metal); if your pipeline needs a map, share one 4 x 4 black image across all organics | **required**: bare metal 1, paint/rubber 0 (worn paint edges 1) |
| **Emissive mask** (EmissiveMaskContent) | linear grayscale | only Fertile soil speckles | only on lights: battery cells, conduits, LEDs, biofluid |

**Rules:**
* No lighting, shadows or reflections painted into Color, except gentle cavity AO.
* Roughness and metalness hold mostly **low-frequency** information, so author or export them
  at **half the Color resolution** (§5.3).
* Keep metalness binary. Grey metalness (0.3–0.7) looks muddy in Roblox's lighting; use it only
  for a thin dust or oxidation overlay.

### 5.2 Substance Painter setup and export preset

* **Project:** Normal Map Format **OpenGL**, Compute Tangent Space Per Fragment on, document
  resolution 2048 (work high, export lower), texel density per §5.3.
* **Baking (hard-surface):** Normal, World-space normal, ID, AO, Curvature, Position,
  Thickness. Use match by mesh name (`_low` / `_high`), triangulate the low-poly first, and set
  the max frontal/rear distance from the cage.
* **Custom export preset "Roblox SA"** (8-bit PNG, padding = **dilation 16 px**):

| File suffix | Channels | Source |
|---|---|---|
| `_Color.png` | RGB = Base Color; **A = paint mask** (hard-surface painted parts) or 1 (everything else) | Base Color (+ user mask channel) |
| `_Normal.png` | RGB = Normal (OpenGL) | Normal + Height mixed |
| `_Roughness.png` | Gray = Roughness | Roughness |
| `_Metalness.png` | Gray = Metallic | Metallic (hard-surface only) |
| `_Emissive.png` | Gray = emissive mask | an Emissive channel converted to grayscale (white = glow) |

* Use the **emissive colour** only for previews in Painter; the in-game tint comes from
  `EmissiveTint`, so the mask is grayscale.
* **Naming:** `T_<Asset>_<Map>.png`, for example `T_Drone_Color.png`,
  `T_CropAtlas_Roughness.png` or `T_SoilWet_Normal.png`.

### 5.3 Resolutions and texture memory

**The ceiling:** 1024 x 1024 per image. Below are the resolutions that look right from this
game's camera (texel targets are px per stud):

| Asset class | Color | Normal | Roughness | Metalness | Emissive | Texel density |
|---|---|---|---|---|---|---|
| Soil variants (x4, tileable) | 512 | 512 | 512 | – | 256 (Fertile only) | 64 px/stud |
| **Crop atlas** (all crops, all stages) | **1024** | 1024 | 512 | – | – | 120–200 px/stud |
| **Drone** (hero) | **1024** | 1024 | 512 | 512 | 256 | about 200 px/stud |
| Tools (2) | share the drone set or a 512 set | 512 | 256 | 256 | 128 | about 150 px/stud |
| Machines **trim sheet** (shared) | 1024 | 1024 | 512 | 512 | 512 | 64–100 px/stud |
| Machines **decal sheet** (shared) | 512 (alpha) | – | – | – | – | – |
| Props (fences, rocks, signs) | 256 | 256 | 256 | – | – | 40 px/stud |
| Cosmetic hats (each) | 256 | 256 | 256 | 256 | – | |

**Approximate GPU memory** (planning numbers; check real values in Studio, §5.6). Roblox
compresses textures on the GPU, and mip-maps add about a third:

| Image | ≈ GPU memory |
|---|---|
| 1024² | **≈ 1.3 MB** (≈ 5.3 MB if it ends up uncompressed RGBA) |
| 512² | ≈ 0.35 MB |
| 256² | ≈ 0.09 MB |

**Game-wide budget for farm content:** **≤ about 12 unique SurfaceAppearance / MaterialVariant
texture sets** and **≤ 25 MB of world textures**. That keeps phones comfortable. The plan
above adds up to about 18 MB:

| Set | ≈ MB |
|---|---|
| Soil x4 | 4.2 |
| Crop atlas | 3.0 |
| Drone | 3.3 |
| Machine trim + decals | 3.8 |
| Tools | 1.0 |
| Hats (6) | 1.5 |
| Props | 0.8 |

**Why top-down allows modest sizes:** at 25–45 studs the field shows about 20–30 screen px per
stud on a 1080p display. Texel densities above about 100 px/stud are only seen in the
menu-orbit close-ups (drone, machines), so only those get 1024².

### 5.4 Packing strategy on Roblox

SurfaceAppearance has **no channel-packed ORM**: every map is its own image. "Packing" therefore
means sharing:

1. **Crop atlas (1024²), the palette + strip layout:**
   * **Top half:** a **palette grid of 32 x 32 px swatches** (all crop colours from §1.4, three
     value steps each). Low-poly faces are UV'd **onto swatches** (whole islands scaled down
     inside one swatch), which gives clean flat colour with near-zero memory.
   * **Bottom half:** 7 **detail strips** (1024 x 64 each): grain kernels, seed spiral, carrot
     rings, pumpkin ribs, cactus spines, bark, leaf veins. These are UV'd where detail matters.
   * The roughness map follows the same layout (one value per swatch, detail in the strips),
     so one atlas set serves 21 models.
2. **Hard-surface trim sheet (1024²):** horizontal strips 64–128 px tall. From top to bottom:
   * painted hull panel with panel lines;
   * bevelled edge strip (wear);
   * vent grille;
   * rivet / bolt strip;
   * hazard stripes;
   * rubber / cable;
   * copper coil windings;
   * brushed steel;
   * dark steel;
   * glass frame;
   * an emissive conduit strip (emissive mask white in that strip only).

   Machines and tools are UV'd onto these strips (straight UV runs, no unique unwraps).
3. **Decal sheet (512², alpha):** labels ("BIO-REACTOR MK1", cell numbers, arrows, warning
   pictograms), applied as small floating quads 0.005 off the surface (no Decals instances).
4. **Reuse asset ids:** every model that uses the atlas or trim must point at **the same
   uploaded image ids**. Upload once, then copy-paste the SurfaceAppearance; never re-import
   the same PNG (that creates a second asset and doubles memory).
5. **Half-resolution secondary maps:** roughness, metalness and emissive at half the Color size.
6. **`TexturePack`:** the current API also offers a `TexturePack` property that bundles maps.
   It's optional; the standard four-map setup above is the supported baseline for this project.

### 5.5 Normal-map strength and stylization

* Stylized low-poly wants **chunky, low-frequency** normals. Bake at a 2048 working size and
  export at the target size; blur micro-noise away.
* Organic normal strength is about 50 % of what you'd use for realism. If grain or clods look
  "noisy" from 30 studs, halve it.
* Avoid normal detail on the flat **top of tiles under crops** and on the top of the drone body
  (hats sit there).

### 5.6 Roblox Studio import pipeline (step by step)

1. **Blender export (FBX):**
   * Selected Objects;
   * Apply Transform, Forward **-Z**, Up **Y**, Apply Scalings *All Local*;
   * Mesh: Apply Modifiers, Triangulate Faces, Smoothing *Face* (keeps weighted normals);
   * no armature, no animation;
   * one object per future MeshPart, named exactly as in this Bible.
2. **3D Importer:** File Dimensions **Studs** (check that the size readout matches the spec,
   e.g. a tile reads 6 x 0.6 x 6), Anchored on, no rig, keep the hierarchy as a Model. Fix the
   pivot (`WorldPivot`) per §3.1 / §4.
3. **Upload textures** in bulk with the **Asset Manager**. Name them exactly as exported.
4. **Create the SurfaceAppearance** under each MeshPart: set the four maps (+ emissive mask),
   `AlphaMode` (Overlay for `PaintSlot` parts, Opaque for everything else, Transparency only on
   the one glass shell), and `EmissiveTint` / `EmissiveStrength`. For a shared set, create it
   once and **copy** it to the other MeshParts.
5. **MeshPart settings:**
   * `RenderFidelity = Automatic`, `CollisionFidelity = Box`, `DoubleSided = false`;
   * `CastShadow` on, except seedlings, grass and tiny props;
   * `Material`: Neon for the eye; anything else for SA parts.
   * The game itself forces Anchored, non-colliding and non-queryable on every asset, and
     strips scripts, welds and constraints. Don't rely on welds; parts are posed by the game.
6. **MaterialVariants:** in the Material Manager, create the 4 soil variants (§2.2), set their
   maps, StudsPerTile and Pattern, and **set `SoilDry` as the `Ground` override**.
7. **Place** finished models in `ReplicatedStorage.Assets` with the exact folder names (§10.3).
8. **Verify:** Developer Console → Memory → **GraphicsTexture** (and GraphicsMeshParts) on a
   test plot; the MicroProfiler (Ctrl+Alt+F6) on a 10 x 10 fully planted plot; and the §9 bloom and
   seam checks.

---

## 6. Blender modelling standards

| Topic | Standard |
|---|---|
| Units | Unit System *None*, Scale 1.0: 1 BU = 1 stud |
| Origins / pivots | crops: tile-top centre; drone: body centre; rotors: hub centre; tools: ToolMount point; stations: top face of the server part |
| Transforms | apply rotation and scale before export (scale 1,1,1) |
| Topology | quads and tris while modelling, **triangulated on export**; no n-gons in the export; no sliver triangles (angles < 5°); no interior or hidden faces; merge by distance 0.001 |
| Shading | flat facets for organics; Bevel + Weighted Normal for hard-surface; Auto Smooth 30° |
| UVs | no overlapping on unique areas; 8 px padding at 1024, 4 px at 512; islands straightened on trim strips; consistent texel density per §5.3 |
| Naming | objects: exact in-game part names (`Body`, `Rotor1`, ...); meshes: `SM_<Asset>_<Part>`; collections: `<Asset>_low`, `<Asset>_high`, `<Asset>_export` |
| Variants | crop stages as separate collections in one `.blend`: `Wheat_sprout`, `Wheat_growing`, `Wheat_ready` |
| Scale reference | keep a 6 x 0.6 x 6 tile and a 4.7-stud drone silhouette as non-exporting reference objects in every `.blend` |

**Source file layout** (outside the Rojo project, e.g. a separate art repo or drive):

```
art/
├── blend/      crops.blend, drone.blend, machines.blend, tiles.blend, props.blend
├── substance/  CropAtlas.spp, Drone.spp, MachineTrim.spp, Soil.sbs / .spp
├── export/
│   ├── fbx/    SM_*.fbx
│   └── tex/    T_*_Color.png, T_*_Normal.png, ...
└── reference/  palette.ase (the §1.4 swatches), mood boards
```

---

## 7. Performance budgets

| Asset | Tris (max) | MeshParts | Texture set | Notes |
|---|---|---|---|---|
| Crop stage model | 80 / 220 / 350 (S / M / R) | 1 (≤ 2) | crop atlas | `CastShadow` off on seedlings |
| Soil tile (MeshPart kit, optional) | 150 | 1 | soil variant | Parts + MaterialVariant cost ~12 tris |
| Drone | 1,900 | ≤ 14 | drone 1024 | ≤ 3 glowing elements |
| Tool | 600 | ≤ 3 | drone set or a 512 tool set | |
| Charging Station | 1,500 | ≤ 6 | trim + decal | pad top ≤ 2.5 studs |
| Bioreactor | 4,000 | ≤ 10 | trim + decal | 1 transparent layer max |
| Cosmetic hat | 300 | ≤ 2 | 256 set | |
| Plot props (fences, posts, rocks) | 2,000 per plot | ≤ 12 | props 256 | static |

**Worst case per plot** (10 x 10, all ready, every prop) is about **50k tris**, about **350
objects** and **≤ 7 texture sets** (all shared). A full server of 24 plots is about 1.2 M tris
total, but plots stream as whole models (`ModelStreamingMode.Atomic`) and distant ones drop
detail via `RenderFidelity`. **Never exceed these numbers without a profiling pass** (§9).

**Client LOD tiers** (`PlotRenderer`; distance from your character or camera to a plot's Zone,
6 studs of hysteresis). Your own plot is **always NEAR**.

| Tier | Distance | Drone | Crops | Effects |
|---|---|---|---|---|
| NEAR | own plot, or < 80 studs | full model (your art), bob / tilt / spin, hats | full stage models / procedural shapes | crop juice, soil states, station decor |
| MID | 80–140 studs | 2 parts (hull + battery strip), snapped to its cell, no tweens | **one plain part per tile**, growing + ready only | soil states (instant), no particles, no sway |
| FAR | > 140 studs | none | none (the server's tiles only) | none; everything is destroyed, not hidden |

So your stage models only ever render on NEAR plots: the per-plot cost sheet above applies to
at most your plot and its close neighbours. `FxDebugPrint = true` on `Workspace.ClientVisuals`
prints the live tier, tween and part counts every 2 s.

---

## 8. Engine compatibility matrix

What finished art does **today** vs. what needs a small **script hook** first. This document
specifies the art only; hooks are tracked as code tasks.

| Feature | Works today (no code) | Needs a script hook |
|---|---|---|
| Crop models per stage (`Assets/Crops/<id>/<stage>`) | ✅ picked up automatically, scaled and rotated by the game | |
| Drone model (`Assets/Drone`, part names, `Rotor*` spin) | ✅ | |
| Drone paint jobs on textured parts (`PaintSlot` + `AlphaMode = Overlay`) | ✅ (the game sets part Color) | |
| Cosmetic hats (`Assets/Hats/<style>`) | ✅ | |
| Station models (`Assets/Stations/charger`, `factory`) | ✅ placed on the server parts | |
| PBR soil on every tile (`SoilDry`) | ✅ the soil hook names every tile (§2.2) | |
| Tilled / Watered soil states (`SoilTilled`, `SoilWet`) | ✅ the soil hook swaps each tile's `MaterialVariant` | |
| Fertilized soil state (`SoilFertile`) | | reserved: needs the mechanic first |
| MeshPart tile kit instead of Parts | | build tiles as MeshParts |
| Interchangeable drone tools (`Assets/Tools`) | | equip tools at `ToolMount` |
| Battery bar showing the charge level | ✅ a Neon `BatteryBar` (no SurfaceAppearance) is coloured by charge (§4.1.1) | per-cell levels on an emissive-mask bar |
| Fertilized gameplay | | a new mechanic (the art is ready) |

---

## 9. Review gates and delivery checklists

### 9.1 Review gates (in order)

1. **Silhouette gate:** black-fill screenshot from the gameplay camera (35 studs) and the menu
   orbit. Every crop, stage, tool and machine must be identifiable.
2. **Value gate:** desaturate the screenshot. Tech reads dark, ripe crops read bright, soil
   sits in between, and the "ready" stage is distinct from "growing" in grayscale.
3. **Palette gate:** sample the colours and compare against §1.4 (within ±6 % on each channel
   is acceptable).
4. **Bloom gate:** with the §1.5 settings, only state surfaces glow. Check Fertile soil at
   midday and at the menu's low sun angle.
5. **Seam gate:** the 3 x 3 tile scene (§2.3) at 0 and 0.4 gap, plus world-space variant
   continuity across tiles.
6. **Performance gate:** a 10 x 10 fully planted test plot (with the procedural fallback
   removed) shows no frame-time spikes in the MicroProfiler on a mid-range phone, and
   GraphicsTexture memory is within the §5.3 budget.

### 9.2 Delivery checklist (per asset)

- [ ] Exact names and folder (§10.3); pivot per §6; scale verified in the importer.
- [ ] Triangle count and MeshPart count within §7.
- [ ] Textures from the shared atlas or trim where required; reused asset ids (no duplicates).
- [ ] Maps per §5.1; Color sRGB, others linear; normal map OpenGL and looks raised in Studio.
- [ ] `AlphaMode` right (Overlay for `PaintSlot` parts; Opaque otherwise; one transparent
      shell at most).
- [ ] Emissive only on state surfaces, with values per §1.5.
- [ ] `RenderFidelity Automatic`, `CollisionFidelity Box`, `DoubleSided` off, `CastShadow`
      per §5.6.
- [ ] No scripts, welds, constraints or unions inside the model.
- [ ] Passed gates 1–6.

### 9.3 Crop-specific checks

- [ ] All 3 stages exist; sprout authored about 2.2 tall, growing about 0.9 H, ready H.
- [ ] Looks right at every 45° yaw; footprint ≤ 5.2 x 5.2.
- [ ] The ready cue changes colour, silhouette and roughness together.

### 9.4 Drone-specific checks

- [ ] Rotor origins at the hub centres, blades flat, all four rotors share one mesh.
- [ ] The eye is a Neon part with no SurfaceAppearance; the battery uses an emissive mask.
- [ ] Nothing clips during the 14° lean or the 0.35-stud bob; the hat area on top is flat.
- [ ] A paint job test: all 6 in-game paint jobs look correct on the textured hull.

---

## 10. Appendices

### 10.1 Production tracker

| # | Asset | Folder / name | Tris | Texture set | Res | Maps | Status |
|---|---|---|---|---|---|---|---|
| 1 | Soil Dry | MaterialVariant `SoilDry` | – | own | 512 | C N R | ☐ |
| 2 | Soil Tilled | `SoilTilled` | – | own | 512 | C N R | ☐ |
| 3 | Soil Wet | `SoilWet` | – | own | 512 | C N R | ☐ |
| 4 | Soil Fertile | `SoilFertile` | – | own | 512 | C N R E | ☐ |
| 5–7 | Wheat x3 | `Crops/wheat/{sprout,growing,ready}` | 60/180/300 | crop atlas | 1024 | C N R | ☐ |
| 8–10 | Carrot x3 | `Crops/carrot/...` | 50/160/220 | crop atlas | | | ☐ |
| 11–13 | Sunflower x3 | `Crops/sunflower/...` | 50/180/350 | crop atlas | | | ☐ |
| 14–16 | Pumpkin x3 | `Crops/pumpkin/...` | 50/220/350 | crop atlas | | | ☐ |
| 17–19 | Cactus x3 | `Crops/cactus/...` | 40/140/220 | crop atlas | | | ☐ |
| 20–22 | Wild grass x3 | `Crops/grass/...` | 40/60/80 | crop atlas | | | ☐ |
| 23–25 | Tree x3 | `Crops/tree/...` | 60/200/300 | crop atlas | | | ☐ |
| 26 | Crop atlas | (texture set) | – | – | 1024 | C N R | ☐ |
| 27 | Drone | `Drone` | ≤ 1,900 | drone | 1024 | C(A) N R M E | ☐ |
| 28 | Watering Can | `Tools/WateringCan` | ≤ 600 | drone / tool | 512 | C N R M E | ☐ |
| 29 | Harvester Blades | `Tools/HarvesterBlades` | ≤ 600 | drone / tool | 512 | C N R M E | ☐ |
| 30 | Charging Station | `Stations/charger` | ≤ 1,500 | trim + decal | 1024 / 512 | C N R M E | ☐ |
| 31 | Bioreactor | `Stations/factory` | ≤ 4,000 | trim + decal | 1024 / 512 | C N R M E | ☐ |
| 32 | Trim sheet | (texture set) | – | – | 1024 | C N R M E | ☐ |
| 33 | Decal sheet | (texture) | – | – | 512 | C(A) | ☐ |
| 34–38 | Hats: antenna, straw, propeller, tophat, halo | `Hats/<style>` | ≤ 300 each | 256 each | 256 | C N R (M) | ☐ |
| 39 | Plot props | (props folder) | ≤ 2,000 | props | 256 | C N R | ☐ |

### 10.2 Naming quick reference

| Thing | Pattern | Example |
|---|---|---|
| Mesh | `SM_<Asset>_<Part>` | `SM_Drone_Body`, `SM_Wheat_ready` |
| Texture | `T_<Set>_<Map>` | `T_CropAtlas_Color`, `T_MachineTrim_Emissive` |
| MaterialVariant | `Soil<State>` | `SoilDry`, `SoilTilled`, `SoilWet`, `SoilFertile` |
| In-game parts (drone) | exact names | `Body`, `Arm1..4`, `Rotor1..4`, `Eye`, `BatteryBar` |
| Attachment | exact name | `ToolMount` |
| Paint attribute | `PaintSlot` = `primary` / `secondary` / `accent` | on `Body`, `Arm*`, `Eye` |

### 10.3 `ReplicatedStorage.Assets` tree

Save models into the repo's `assets/` folder as `.rbxm` (Rojo syncs it to
`ReplicatedStorage.Assets`), or drop them into that folder in Studio; see `assets/README.md`.
A model with no visible part is ignored (logged once) and the procedural stand-in stays.

```
ReplicatedStorage
└── Assets
    ├── Drone                       Model (pivot = body centre, forward -Z)
    │   ├── Body                    PaintSlot = "primary"   (+ Attachment "ToolMount")
    │   ├── Arm1 .. Arm4            PaintSlot = "secondary"
    │   ├── Rotor1 .. Rotor4        spin; origin at hub centre
    │   ├── Eye                     Neon, PaintSlot = "accent"
    │   └── BatteryBar              emissive mask
    ├── Crops
    │   └── <cropId>                grass, wheat, carrot, tree, sunflower, pumpkin, cactus
    │       ├── sprout   (Model)    Seedling
    │       ├── growing  (Model)    Mid-Growth
    │       └── ready    (Model)    Ready-to-Harvest
    ├── Hats
    │   └── <style>                 antenna, straw, propeller, tophat, halo
    ├── Stations
    │   ├── charger                 pivot = top of the 6 x 0.4 x 6 pad
    │   └── factory                 pivot = top of the 6 x 3 x 6 block (Bioreactor)
    └── Tools                       (future hook, §8)
        ├── WateringCan
        └── HarvesterBlades

MaterialService
├── SoilDry       (set as the override for Ground)
├── SoilTilled
├── SoilWet
└── SoilFertile
```

**Enforced by the game for every asset:** `Anchored = true`, `CanCollide = false`,
`CanQuery = false`, `CanTouch = false`, and scripts, constraints and joints are removed. All
motion (drone flight, tilt, hover, rotor spin, crop growth) is tweened on the client;
**never** use physics movers or welds in an asset.
