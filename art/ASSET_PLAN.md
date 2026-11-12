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
(image 110940790391979); keys without art keep their emoji fallback.

| Group | Keys | Status |
|---|---|---|
| Raw crops | hay, wheat, carrot, wood, sunflower, pumpkin, cactus, fossil | hay, wheat **generated**; rest **missing** (prompts ready) |
| Processed / premium | biomass, biofuel, batteries | missing |
| Drone meters | energy, water, cargo | missing |
| Weather | weather_Sunny, weather_Rainy, weather_Drought | missing |
| UI states | lock, check, star, unknown | missing |
| Tech Tree | loop, grid, tree, watering_can, print, speed, clock, simulate, battery_pack, charger, factory, drone, motor, paint, hat, math, coordinates, variable, list, function, dictionary, import, random, cost | missing |
| Shop | vip_crown, memory, yield_2x, overclock, starter_pack, boost_micro, boost_grid | missing |
| Hats | hat_antenna, hat_straw, hat_propeller, hat_tophat, hat_halo | missing |
| Navigation | tech_tree, shop, hangar | missing |

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
| Soil MaterialVariants: SoilDry, SoilTilled, SoilWet, SoilDug | Color, Normal, Roughness, Metalness | 512² tileable | `art/textures/soil/` | **done**: uploaded + built into `MaterialService` by Rojo |
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
played by `Client.Controllers.SoundController`. Status: **generated**, code hooked up, silent
until uploaded (every `assetId` is 0). Upload: `python tools/roblox_upload.py audio` (writes the
ids into SoundConfig).

FBX + GLB for every model: `tools/blender/out/` (git-ignored; previews in `previews/`). Next
step: `python tools/roblox_upload.py models` (Open Cloud key, downloads `assets/<path>.rbxm`), or
the Studio import in `art/IMPORT.md` §1.

Roblox ids of everything uploaded: `art/ROBLOX_ASSETS.md`.
