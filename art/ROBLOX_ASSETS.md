# Roblox asset IDs (uploaded 2026-11-11)

Published with the ForgeGUI Roblox connection (creator: the game owner's own Roblox account,
so the place can use them). All 24 images are
**approved** by Roblox moderation. Each one is already wired into the game, so nothing has to
be imported in Studio.

| Source file | Roblox image id | Used in |
|---|---|---|
| `art/IconAtlas.png` (60 icons, 2026-11-12) | 132362650788089 | `src/shared/Config/IconAtlas.luau` `assetId` (the first atlas, hay + wheat only, was 110940790391979) |
| `art/ui/panel.png` | 71234864559639 | `src/shared/Config/UiSlices.luau` |
| `art/ui/panel_raised.png` | 125527694578856 | `UiSlices.luau` |
| `art/ui/button_primary.png` | 130947479507092 | `UiSlices.luau` |
| `art/ui/button_secondary.png` | 132145751526912 | `UiSlices.luau` |
| `art/ui/button_danger.png` | 97912749381870 | `UiSlices.luau` |
| `art/ui/tab_on.png` | 138361535416806 | `UiSlices.luau` |
| `art/ui/tab_off.png` | 139054084268412 | `UiSlices.luau` |
| `art/ui/meter_track.png` | 131501624954044 | `UiSlices.luau` |
| `art/ui/meter_cap.png` | 109685872050737 | `UiSlices.luau` |
| `art/ui/toast.png` | 70604590024042 | `UiSlices.luau` |
| `art/ui/modal_header.png` | 88439635007101 | `UiSlices.luau` |
| `art/textures/soil/SoilDry_Color.png` | 96408927938055 | `default.project.json` → `MaterialService.SoilDry` |
| `art/textures/soil/SoilDry_Normal.png` | 135620649572866 | `MaterialService.SoilDry` |
| `art/textures/soil/SoilDry_Roughness.png` | 91185130991949 | `MaterialService.SoilDry` |
| `art/textures/soil/SoilTilled_Color.png` | 139059942987760 | `MaterialService.SoilTilled` |
| `art/textures/soil/SoilTilled_Normal.png` | 99996297489389 | `MaterialService.SoilTilled` |
| `art/textures/soil/SoilTilled_Roughness.png` | 111222851939129 | `MaterialService.SoilTilled` |
| `art/textures/soil/SoilWet_Color.png` | 120446566952641 | `MaterialService.SoilWet` |
| `art/textures/soil/SoilWet_Normal.png` | 122305854462384 | `MaterialService.SoilWet` |
| `art/textures/soil/SoilWet_Roughness.png` | 128394061467620 | `MaterialService.SoilWet` |
| `art/textures/soil/SoilDug_Color.png` | 102764113147878 | `MaterialService.SoilDug` |
| `art/textures/soil/SoilDug_Normal.png` | 81910203093634 | `MaterialService.SoilDug` |
| `art/textures/soil/SoilDug_Roughness.png` | 103767256605018 | `MaterialService.SoilDug` |

The soil Metalness maps weren't uploaded: they are all black (soil is never metal), which is
the same as no map.

**What changes in game:**
* All 60 icons show their art from the atlas (2026-11-12): `hay` / `wheat` from ForgeGUI, the other
  58 rendered from 3D by `tools/blender/icons.py` in the same toon style. No emoji fallbacks left.
* The 9-slice skins are ON (`UiSlices.Enabled = true`): panels, modal headers, both button
  kinds and progress meters draw the slices. If anything looks off in Studio, set
  `UiSlices.Enabled = false` to get the code-built look back at once.
* Rojo builds the four soil MaterialVariants into `MaterialService` (properties
  `ColorMapContent` / `NormalMapContent` / `RoughnessMapContent`). `Client.Visuals.SoilLook`
  finds them by name and uses them instead of its map-less placeholders.

**3D models and sounds (2026-11-13, `tools/roblox_upload.py`, Open Cloud key).** All 29 models
(drone, 21 crop stages, charger, factory, 5 hats) and all 18 sounds are uploaded to the owner's
account. The ids live in `art/roblox_uploads.json` (path, sha256 and asset id; a file only
uploads again when it changes):
* **Sounds:** the ids are written into `src/shared/Config/SoundConfig.luau` (`assetId`), so the
  game plays them. Verified in Studio: the ambient and charge loops load and play.
* **Models:** downloaded as `assets/<path>.rbxm` (Rojo syncs them to `ReplicatedStorage.Assets`)
  and finished by `tools/apply_parts.luau`, because Open Cloud's FBX import keeps geometry,
  names and scale but drops the material colours, turns the model 180° about Y and wraps it
  as a package. The script fixes all three from the Blender part sheet
  (`tools/blender/out/<path>.parts.json`): colour / material / transparency / PaintSlot per
  part, back to the contract orientation, pivot on the scene origin, PackageLink removed.
  Verified in Studio: `tools/studio_smoke.py --checks all` passes 18/18 with the mesh models.

**World models (2026-11-13).** 36 more low-poly models through the same pipeline (ids in
`art/roblox_uploads.json`): the soil tile and the plot dressing kit (`assets/Tiles`,
`assets/Dressing`, used at runtime), and 31 map props in `map/props/` (not synced: `lune run
tools/build_map` composes them into `map/Map.rbxm` = Workspace.Map: 1,822 props, 3,852
MeshParts, nothing inside any plot slot; `tests/spec/MapLayout.spec.luau`). Verified in Studio
over MCP: the server's field tiles are MeshParts, the dressing kit is in use, the map and its hill
backdrop load, and `tools/studio_smoke.py` passes.

**Village and textures (2026-11-13).** 12 buildings (`tools/blender/buildings.py`) joined the
map props, and every model was re-exported with detail MaterialVariants and uploaded again (77
models). 34 texture maps went up as images (`python tools/roblox_upload.py textures`: PNG ->
Decal -> the image id read from the Decal), and the 11 MaterialVariants (4 soil, 7 detail) are
written to `materials.project.json`, which Rojo builds into MaterialService. The map is the
village layout (`art/ASSET_PLAN.md` §8).

**Rebuilding an image:** if you regenerate a PNG (atlas, slice, texture), it has to be uploaded
again and its id replaced here and in the file listed. Roblox ids point to a fixed upload.
