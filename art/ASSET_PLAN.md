# Asset plan (`/assets`, updated 2026-11-11)

Every asset the game can show: its status, source, budget and where it goes. The look is
`docs/ART_BIBLE.md`; the hook contract is `assets/README.md` + `src/client/Visuals/AssetLibrary.luau`.
Statuses: **missing** (nothing yet) · **procedural** (drawn in code, the zero-asset fallback) ·
**generated** (source file in the repo, not yet uploaded/imported) · **script** (a Blender
script builds it; needs a Blender run) · **done** (in the game).

## 1. UI icons (60 keys, `IconConfig.Icons`)

Source: ForgeGUI image type `mixed` (transparent cut-out), one style for all
("Drone Farm – Glossy Icons", built from `art/icons/hay.png` + `wheat.png`). 256×256 source
PNGs in `art/icons/<key>.png`, packed by `tools/build_icon_atlas.py` into ONE texture
`art/IconAtlas.png` (8 columns × 128 px cells, `IconConfig.AtlasOrder`). The atlas is uploaded
(image 132362650788089, 60/60 icons). The 58 non-ForgeGUI icons are rendered from 3D by
`tools/blender/icons.py` (toon shading + Freestyle outline, the game's own models where they exist).

| Group | Keys | Status |
|---|---|---|
| Raw crops | hay, wheat, carrot, wood, sunflower, pumpkin, cactus, fossil | **done** (hay, wheat ForgeGUI; rest Blender) |
| Processed / premium | biomass, biofuel, batteries | **done** (Blender) |
| Drone meters | energy, water, cargo | **done** (Blender) |
| Weather | weather_Sunny, weather_Rainy, weather_Drought | **done** (Blender) |
| UI states | lock, check, star, unknown | **done** (Blender) |
| Tech Tree | loop, grid, tree, watering_can, print, speed, clock, simulate, battery_pack, charger, factory, drone, motor, paint, hat, math, coordinates, variable, list, function, dictionary, import, random, cost | **done** (Blender: game models, props and glyphs) |
| Shop | vip_crown, memory, yield_2x, overclock, starter_pack, boost_micro, boost_grid | **done** (Blender) |
| Hats | hat_antenna, hat_straw, hat_propeller, hat_tophat, hat_halo | **done** (rendered from the hat models) |
| Navigation | tech_tree, shop, hangar | **done** (Blender) |

## 2. 3D models (`ReplicatedStorage.Assets`, all optional: procedural stand-ins exist)

| Asset | Path | Budget (§7) | Source | Status |
|---|---|---|---|---|
| Drone | `Assets.Drone` (Body, Rotor1..4, Eye, BatteryBar, PaintSlot) | ≤ 1,900 tris, ≤ 14 MeshParts | `tools/blender/drone.py` | procedural in game (16 parts: blur discs + spinning blades, ASSETS-2); **generated** FBX (780 tris, 11 parts) |
| Crops × 3 stages | `Assets.Crops.<grass·wheat·carrot·tree·sunflower·pumpkin·cactus>.<sprout·growing·ready>` (21) | 80 / 220 / 350 tris, ≤ 2 MeshParts | `tools/blender/crops.py` | procedural in game; **generated** FBX (all 21, 36–264 tris) |
| Charging Station | `Assets.Stations.charger` | ≤ 1,500 tris, ≤ 6 parts | `tools/blender/stations.py` | procedural decor; **generated** FBX (896 tris) |
| Bioreactor (Factory) | `Assets.Stations.factory` | ≤ 4,000 tris, ≤ 10 parts | `tools/blender/stations.py` | procedural decor; **generated** FBX (530 tris) |
| Hats | `Assets.Hats.<antenna·straw·propeller·tophat·halo>` | ≤ 300 tris, ≤ 2 parts | `tools/blender/hats.py` | procedural in game; **generated** FBX (120–164 tris) |
| Plot props | (code: `PlotDressing`) | ≤ 2,000 tris per plot | procedural | procedural |

## 3. Textures

| Set | Maps | Size | Path | Status |
|---|---|---|---|---|
| Soil MaterialVariants: SoilDry, SoilTilled, SoilWet, SoilDug | Color, Normal, Roughness, Metalness | 512² tileable | `art/textures/soil/` | **done**: uploaded + built into `MaterialService` by Rojo (`materials.project.json`) |
| Detail MaterialVariants: DroneHull, CropLeaf, CropSkin, Bark, Planks, Shingles, Stone | Color, Normal, Roughness (+ Metalness for DroneHull) | 512² tileable, light neutral | `art/textures/detail/` | **done**: uploaded, in `MaterialService`; models pick them through their part sheets (§8) |
| Drone / machines trim | Color, Normal, Roughness, Metalness | 1024² | `art/textures/hardsurface/` | **generated** |
| Crops atlas | Color, Roughness | 512² | `art/textures/crops/` | **generated** |

## 4. UI chrome slices (9-slice PNGs, `UI/Theme` behind a flag)

panel, panel_raised, button_primary, button_secondary, button_danger, tab_on, tab_off,
meter_track, meter_cap, toast, modal_header → `art/ui/<name>.png`, SliceCenter table in
`src/shared/Config/UiSlices.luau`. Status: **done**: uploaded, ids pasted, skins ON via `Theme.skin`.

## 5. Store art

| Asset | Size | Source | Status |
|---|---|---|---|
| Game icon | 512×512 | ForgeGUI `icon_gfx` | missing (paused: credits; spec in `art/store/STORE_ART.md`) |
| Thumbnail 1: bird's-eye farm, hopping drone | 1920×1080 | Studio capture (recipe A) | missing (look.html render rejected: not the real game) |
| Thumbnail 2: terminal running code | 1920×1080 | Studio capture (recipe B) | missing |
| Thumbnail 3: Tech Tree | 1920×1080 | Studio capture (recipe C) | missing |

## 6. Sound (ASSETS-8, approved by the user 2026-11-12)

17 one-shots (hop, land, plant, water, harvest, unripe, dig, fossil, deposit, unload, refine,
research, purchase, click, hover, error) + 2 seamless loops (charge 2 s, ambient 24 s) →
`art/audio/<name>.ogg`, synthesised by `tools/build_sfx.py` (pure Python + ffmpeg; ForgeGUI had
no credits). Event → file → volume, and when each plays: `src/shared/Config/SoundConfig.luau`;
played by `Client.Controllers.SoundController`. Status: **done** (2026-11-13): uploaded, ids in
`SoundConfig`, playing in game. Upload: `python tools/roblox_upload.py audio` (writes the
ids into SoundConfig).

FBX + GLB for every model: `tools/blender/out/` (git-ignored; previews in `previews/`).
**Done (2026-11-13):** all 29 uploaded with `python tools/roblox_upload.py models` and in the
game as `assets/<path>.rbxm` (coloured, turned back and pivoted by `tools/apply_parts.luau`).
Sounds: all 18 uploaded, ids in `SoundConfig`.

## 7. World in low-poly meshes (2026-11-13)

Everything visible is a mesh now; every piece keeps its procedural / Part fallback.

| Group | Pieces | Source | Where in game |
|---|---|---|---|
| Field tile | Soil (bevelled 6 x 0.6 x 6 slab, 92 tris) | `tools/blender/tiles.py` | `Assets.Tiles.Soil`, cloned by the server per tile; SoilLook still sets its soil state |
| Plot dressing | FencePost, FenceRail, Walkway, SignPost | `tools/blender/tiles.py` | `Assets.Dressing.*`, placed and stretched by `PlotDressing` |
| Nature | oak, pine, birch, bush, berry_bush, 3 rocks, 3 flower patches, grass_tuft, log, mushroom | `tools/blender/props.py` | `map/Map.rbxm` |
| Farm life | hay_bale, crate, barrel, cart, scarecrow, well, lamp_post, bench | `tools/blender/props.py` | `map/Map.rbxm` |
| Landmarks / ground | windmill, welcome_sign, plaza, path, pond, hedge | `tools/blender/props.py` | `map/Map.rbxm` |
| Backdrop | hill_a, hill_b, hill_c (faceted, 200 tris) | `tools/blender/props.py` | `map/Map.rbxm` Backdrop (LightingController skips its own hills) |

Pipeline: Blender (`finalize`: Decimate guard, Smart UV, Apply Rot/Scale, pivot check) -> FBX ->
`python tools/roblox_upload.py models` (Map/* lands in `map/props/`, the rest in `assets/`) ->
`tools/apply_parts.luau` (colours, collision, orientation, pivot) -> `lune run tools/build_map`
(fixed seed, never inside a plot slot: `tests/spec/MapLayout.spec.luau`). Previews:
`tools/blender/out/previews/{kit,nature,farm,landmarks}.png`.

Roblox ids of everything uploaded: `art/ROBLOX_ASSETS.md`.

## 8. Farm village, buildings, detail textures (2026-11-13)

**Plots moved.** `GameConfig.Grid.PlotSlots` puts the plots on a 5 x 5 grid (120 x 128 studs
apart) with the spawn village in the free middle cell. Slots 1-8 are the inner ring, so the
first players farm right next to the village; 9-24 are the outer ring. `GridService.plotCenter`
reads the list (the old row formula is only the fallback past slot 24, far north of the map).
**A server must have MaxPlayers <= 24:** the map keeps exactly the 24 slots free.

**Buildings** (`tools/blender/buildings.py`, previews `buildings.png` / `yard.png`): farmhouse,
barn, silo, greenhouse, chicken_coop, water_tower (<= 3,000 tris each, really 250-600),
tool_shed, market_stall, tractor, fence_segment, garden_bed, haystack (<= 600). Walls collide
(Box). Placed at 1.35x so a door fits an avatar.

**Map** (`tools/build_map.luau`, layout in `tools/map_layout.luau`):
* Village: the square (plaza, well, benches, lamps, four market stalls, welcome sign), the
  farmhouse with garden beds, coop and shed, the barn with silo, tractor and haystacks, the
  greenhouse and water tower, the windmill by the pond. A picket fence round it, open at the
  four lanes.
* Roads: double-width path pieces along every gap between slot rows and columns, plus the ring
  road. Lamps alternate along them and stand at a corner of every crossing. Hay, carts, crates
  and scarecrows sit at the crossings, tree avenues line the inner roads, and a picket fence and
  a tree row run outside the ring.
* Countryside: four orchards, a berry field, a hay meadow, a pond with a windmill, forest
  groves and meadows out to 600 studs. Hills at 1,000-1,080 studs.

**Detail textures** (`python tools/build_textures.py detail`): seamless 512² sets with light,
neutral ColorMaps, so `Part.Color` tints them (verified in Studio) and every colour stays the
game's own, cosmetics included. Uploaded with `python tools/roblox_upload.py textures` (PNG ->
Decal -> image id), written to `materials.project.json` (Rojo -> MaterialService). The Blender
material names choose the variant (`_common.VARIANT_RULES`, or `material(..., variant=...)`):
hull / blade / steel -> DroneHull (Metal), leaf / stem / crown -> CropLeaf (Grass), fruit /
root / petal / hay -> CropSkin (Plastic), trunk -> Bark (Wood), wall / door / fence ->
Planks (WoodPlanks), roof -> Shingles (Slate), foundation / chimney -> Stone (Cobblestone).
Glass, Neon, water and soil get none. The part sheet carries `variant`, and `apply_parts` sets
`Material` = the variant's BaseMaterial plus `MaterialVariant`. A cosmetic paint with another
material (SmoothPlastic) simply drops the texture on those parts.

`roblox_upload.py models` also re-finishes a model when only its part sheet changed (a fresh
download of the same asset, then `apply_parts`), so a recolour or a new variant needs no
re-upload.

## 9. v2 art pass (2026-11-17): sculpted models, Blender-baked textures

Same contracts (part names, pivots, PaintSlot, budgets), much more shape. New sculpting helpers
in `tools/blender/_common.py` (`loft`, `tube` with parallel-transport frames, curved `leaf`,
`torus` with a winding twist, `rounded_rect`, `bezier`). Lofts are built outward-facing and
`finalize` re-orients only CLOSED islands, because Roblox draws front faces only and an open
surface (a stalk without caps, a glass shell) flipped inward would vanish; the previews now
cull back faces, so such a hole shows up there first.

| Asset | Before | v2 | Tris / parts |
|---|---|---|---|
| Drone | box hull, flat bars | lofted chamfered hull, rotor guard rings, motor pods, 3-strut guards, pitched tapered blades, landing skids, belly pod, front vents, rounded ceramic visor frame, stadium eye, bevelled battery cells | 1,878 / 13 (<= 1,900 / 16) |
| 21 crop stages | wedges + spheres | curved midrib leaves, 3-tier wheat sheaf with drooping ears, lobed carrot fronds, two-ring sunflower on a thick disc, 20-rib pumpkin with tendril, fluted cactus with elbowed arms, blob-cluster tree with root flare | all inside the §3.3 budgets, <= 4 parts |
| Charger | plate + rings | hex deck, ceramic H (own part), wound copper coils, edge light guides in corner blocks, conduit, banded capacitor pylon with cables | 1,310 / 14 |
| Factory | boxes | louvred housing with pillars, banded drum on A-frames, flanged copper pipes, glass tanks with steel caps round the biofluid (`Slit`), wooden intake funnel + straw spill, lamp bracket, biofuel barrels, chimney with hazard bands | 2,744 / 12 |
| Hats | primitives | drooping straw brim + dented crown + bow, curled top-hat brim, 8-panel beanie with pitched propeller, collared antenna, faceted halo | 240-282 / <= 3 |
| Nature props | 6 x 4 blobs | 7 x 4 hand-cut canopy clusters, flared trunks, tiered jagged pines, petal flowers, curved grass, rimmed mushroom cap with raised spots | within each prop budget |

**Textures:** `blender -b -P tools/blender/textures.py` bakes all 4 soil states and the 7
detail variants at **1024²** (were 512²): Blender's 4D noise on a torus (seamless by
construction) + an exact periodic Voronoi in numpy, cavity AO, normals from height.
`tools/build_textures.py` keeps the trim sheet and the crop palette atlas; its old soil /
detail sets now need `--legacy`.

**Station lights (BUG-28):** the artist charger's `Ring1..4`, `PylonLight`, `Conduit` and the
factory's `Slit` + `Lamp` now light and pulse in game (they never did with the uploaded models).

**Status: done (2026-11-17).** All 34 changed texture maps and 40 models (drone, 21 crops,
2 stations, 5 hats, 11 nature props) were uploaded with `tools/roblox_upload.py` (0 failed).
`materials.project.json`, `assets/` and `map/props/` are updated, and `map/Map.rbxm` was rebuilt
(3,389 props). `tools/studio_smoke.py` passes 11/11. The first run failed "no script errors"
for a few minutes while Roblox was still processing the new variants' TexturePack. Not redone in this pass:
the buildings / farm props / landmarks (`buildings.py`, rest of `props.py`), the tile kit, and the
icon atlas renders (`icons.py` uses the old crop / drone looks until it is re-run).
