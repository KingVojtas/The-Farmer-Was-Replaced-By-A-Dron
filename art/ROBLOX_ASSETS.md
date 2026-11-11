# Roblox asset IDs (uploaded 2026-11-11)

Published with the ForgeGUI Roblox connection (creator: the game owner's own Roblox account,
so the place can use them). All 24 images are
**approved** by Roblox moderation. Each one is already wired into the game, so nothing has to
be imported in Studio.

| Source file | Roblox image id | Used in |
|---|---|---|
| `art/IconAtlas.png` | 110940790391979 | `src/shared/Config/IconAtlas.luau` `assetId` |
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
* `hay` and `wheat` icons show their art from the atlas; the other 58 keep their emoji until
  their icons are generated (`art/icons/PROMPTS.md`), the atlas is rebuilt and re-uploaded.
* The 9-slice skins are ON (`UiSlices.Enabled = true`): panels, modal headers, both button
  kinds and progress meters draw the slices. If anything looks off in Studio, set
  `UiSlices.Enabled = false` to get the code-built look back at once.
* Rojo builds the four soil MaterialVariants into `MaterialService` (properties
  `ColorMapContent` / `NormalMapContent` / `RoughnessMapContent`). `Client.Visuals.SoilLook`
  finds them by name and uses them instead of its map-less placeholders.

**Not uploaded: the 3D models.** ForgeGUI can only publish models it generated itself, not
GLBs from outside. The Blender exports in `tools/blender/out/` need either a Studio import
(`art/IMPORT.md` §1) or a Roblox Open Cloud API key used directly.

**Rebuilding an image:** if you regenerate a PNG (atlas, slice, texture), it has to be uploaded
again and its id replaced here and in the file listed. Roblox ids point to a fixed upload.
