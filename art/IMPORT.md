# Studio import guide (`/assets` ASSETS-4, ASSETS-5)

How the generated art gets into the game. The code side is already done: `AssetLibrary` picks
up anything placed at the fixed paths, and everything missing keeps its procedural stand-in.
Nothing here changes gameplay. Look rules: `docs/ART_BIBLE.md`; contract: `assets/README.md`.

## 0. Build the source files

| What | Command | Output |
|---|---|---|
| Drone | `blender -b -P tools/blender/drone.py -- --out tools/blender/out/Drone` | `Drone.fbx` (+ `.glb` preview) |
| 21 crop stages | `blender -b -P tools/blender/crops.py -- --out tools/blender/out/Crops` | `<crop>/<stage>.fbx` |
| Charger + factory | `blender -b -P tools/blender/stations.py -- --out tools/blender/out/Stations` | `charger.fbx`, `factory.fbx` |
| 5 hats | `blender -b -P tools/blender/hats.py -- --out tools/blender/out/Hats` | `<style>.fbx` |
| Preview renders | `blender -b -P tools/blender/preview.py -- --out tools/blender/out` | `previews/{drone,crops,stations,hats}.png` |
| PBR textures | `python tools/build_textures.py` | `art/textures/{soil,hardsurface,crops}/` (already in the repo) |
| Icon atlas | `python tools/build_icon_atlas.py` | `art/IconAtlas.png` + `IconAtlas.luau` |

**Built on 2026-11-11 with Blender 4.5.16 LTS:** every model is in `tools/blender/out/`
(git-ignored, rebuild with the commands above). All within budget: drone 780 tris / 11
parts, crops 36–264 tris each (one mesh, footprint ≤ 5.2), charger 896, factory 530, hats
120–164. Each script prints a tri / part report against the ART_BIBLE §7 budgets and exits
with an error if anything is over budget or too wide. Look at `previews/*.png` before
importing: they use the Control Mode angle, with screen-right = game +X and screen-up = game −Z.

**Fixed while building (so old exports must be rebuilt):** the axis mapping in
`_common.py` used to MIRROR the models front to back (the drone's eye ended up at its back).
Helper transforms swung later rotations around the world origin (misplaced drone arms,
scattered leaves and petals). The charger coils stood up as an arch across the landing pad.

## 1. 3D models → `ReplicatedStorage.Assets`

**Without Studio (Open Cloud):** set `ROBLOX_API_KEY` (Assets API Read + Write, Legacy Asset
Manage) and `ROBLOX_CREATOR_ID`, then `python tools/roblox_upload.py models`. It uploads every
FBX as a Model, downloads each as `assets/<path>.rbxm` and records the ids in
`art/roblox_uploads.json`. **[verify]** Open Cloud imports with default settings, not the ones
below: check scale (Drone ≈ the procedural one), pivots and part names before relying on it.

**3D Importer settings (every model):** File → Import 3D. *File Dimensions* = **Studs**, *Rig
General* = **off** (no rig, no animation), *Anchor* = on, *Insert using scene position* = off,
*Set pivot to scene origin* = **on** (the scripts put the pivot where the game expects it).
Opaque only; no Neon is baked (the game colours state parts at runtime).

| Asset | Put the Model at | Pivot (WorldPivot) | Must contain |
|---|---|---|---|
| Drone | `ReplicatedStorage.Assets.Drone` | body centre | `Body`, `Rotor1`..`Rotor4` (origin at each hub, blades flat); optional `Eye`, `BatteryBar`, `PaintSlot` attributes |
| Crop stage | `Assets.Crops.<crop>.<stage>` (crop: grass wheat carrot tree sunflower pumpkin cactus; stage: sprout growing ready) | tile top centre, +Y up | 1–2 MeshParts |
| Charger | `Assets.Stations.charger` | top-face centre of the station tile | `Ring1`..`Ring4`, `PylonLight` |
| Factory | `Assets.Stations.factory` | top-face centre | `Slit`, `Lamp`, `ChimneyCap`, `Hopper`, `Window` |
| Hat | `Assets.Hats.<antenna·straw·propeller·tophat·halo>` | where it sits on the drone's back (body top centre) | ≤ 2 parts; a `Rotor...` part spins (propeller) |

Then **Save to File** (right-click the Model → Save to File… → `.rbxm`) as `assets/<path>.rbxm`
(for example `assets/Drone.rbxm`, `assets/Crops/wheat/ready.rbxm`). Rojo syncs `assets/` to
`ReplicatedStorage.Assets` and doesn't delete what you drop there by hand during `rojo serve`.

**`[AssetLibrary] ignored broken <path>` in Output:** that model has no visible part (no
BasePart with Size > 0.2 and Transparency < 0.9). The procedural stand-in stays. Fix the model;
never leave an empty Model named like an asset.

### SurfaceAppearance (painted look)

Add one `SurfaceAppearance` to each MeshPart and point its four maps at the uploaded PNGs
(Asset Manager → Import, then copy each id):

| Family | Maps (`art/textures/...`) | Used by |
|---|---|---|
| Hard surface trim | `hardsurface/Hardsurface_{Color,Normal,Roughness,Metalness}.png` (1024²) | drone hull, arms, rotors, charger, factory |
| Crop palette | `crops/Crops_Color.png` + `Crops_Roughness.png` (512²) | every crop stage (UV islands on the swatches) |

`AlphaMode` = **Opaque** for every hull part. A fully transparent ColorMap can't be detected by
the visible-part guard and would make the part look invisible. The paint jobs (cosmetics)
recolour parts tagged `PaintSlot`, so keep painted parts' ColorMap light/neutral, or use
`AlphaMode = TintMask` there.

**Trim sheet layout** (UV the parts onto these 128 px bands, top to bottom):

| Band (y px) | Material | R / M |
|---|---|---|
| 0–127 | hull dark `#1E2530` (panel seams every 256 px) | 0.40 / 0.2 |
| 128–255 | hull mid `#2E3846` (seams) | 0.38 / 0.3 |
| 256–383 | panel light `#4A5668` (seams) | 0.35 / 0.4 |
| 384–511 | ceramic white `#D7E2EC` | 0.30 / 0 |
| 512–639 | brushed steel `#8E9AA6` (horizontal brushing) | 0.35 / 1 |
| 640–767 | dark steel `#3C4652` | 0.45 / 1 |
| 768–895 | copper `#C27744` | 0.30 / 1 |
| 896–1023 | hazard stripes `#F2B630` / `#16181C` | 0.60 / 0 |

**Crop atlas layout** (8 rows of 64 px swatches, left to right = ART_BIBLE §1.4 order):
grass, wheat, carrot, sunflower, pumpkin, cactus, tree, soil.

### Playtest checks per model (Control Mode camera, then walk around it)

* **Drone:** hovers 5 studs up; the 0.35-stud bob and 14° lean never clip; rotors spin around
  their own hubs; the eye takes the paint's accent; the battery strip changes colour with
  charge (lime > 50 %, amber, red < 15 % with a blink); hats sit on top without clipping.
* **Each crop:** no jump in world position when the stage swaps (at progress 0.5 and at ready);
  every 45° yaw step still reads; a ready crop changes silhouette AND colour; a fully
  planted 10 × 10 stays smooth (MicroProfiler).
* **Charger:** rings pulse cyan while charging; the drone lands on the pad without sinking.
* **Factory:** slit and lamp light while the drone works there; chimney puffs come out of
  `ChimneyCap`'s top.
* **Hats:** each sits on the body top; the propeller blade spins; nothing pokes through the
  battery strip.

## 2. Soil MaterialVariants (ASSETS-5)

**Done (2026-11-11):** the maps are uploaded and `default.project.json` builds the four
variants into `MaterialService` (ids: `art/ROBLOX_ASSETS.md`). The manual steps below are only
for rebuilding them by hand.

Generated: `art/textures/soil/<State>_{Color,Normal,Roughness,Metalness}.png`, 512² and
seamless. In Studio: View → **Material Manager** → create a MaterialVariant per row (base
material **Ground**), set the four maps to the uploaded PNGs and the values below. Put the
variants anywhere under `MaterialService`. `SoilLook` finds them by NAME and swaps out its
map-less placeholders at runtime.

| Name (exact) | BaseMaterial | StudsPerTile | MaterialPattern | Shown when |
|---|---|---|---|---|
| `SoilDry` | Ground | 8 | Organic | bare soil, wild grass |
| `SoilTilled` | Ground | 6.4 | Regular | a player crop is on the tile |
| `SoilWet` | Ground | 6.4 | Regular | `Watered == true` (same furrows as Tilled) |
| `SoilDug` | Ground | 4 | Organic | `Exhausted == true` (dug up, resting about 25 s) |

`AlphaMode` = Opaque. Don't set them as the Ground override: the server's tiles must stay plain
Ground until the client picks the state. **Check:** plant, water and dig on a 3 × 3 in
Control Mode. Each state is easy to tell apart from 80° above, Wet doesn't look like Dug, the
furrows line up across neighbouring tiles, and no seam shows at tile edges.

## 3. Icon atlas

**Done (2026-11-11):** uploaded as image 110940790391979 (`IconAtlas.luau`). Re-upload after
every rebuild.

`art/IconAtlas.png` (1024², 8 × 8 cells of 128 px, `IconConfig.AtlasOrder`). Asset Manager →
Import → copy the image id → paste it into `src/shared/Config/IconAtlas.luau` `assetId`.
Missing cells keep their emoji. Prompts for the 58 missing icons: `art/icons/PROMPTS.md`.

## 4. UI chrome slices

**Done (2026-11-11):** all 11 uploaded and wired (`UiSlices.luau`, ids in
`art/ROBLOX_ASSETS.md`). Details: `art/ui/README.md` (ASSETS-6).
