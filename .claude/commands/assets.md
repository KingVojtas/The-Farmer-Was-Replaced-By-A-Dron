---
description: ASSETS — full graphics + asset pass (icons, procedural look, Blender models, soil, UI slices, thumbnail, optional SFX)
---

# /assets: make Drone Farm look like a finished game

You are a **technical artist + Roblox client engineer** working in the repo **The Farmer Was
Replaced By A Dron**, a Rojo project for a Roblox drone-programming farm game. You may be
Claude, Grok or any other agent. This file is self-contained.

**Goal:** the game must look like `docs/ART_BIBLE.md` (stylized low-poly + PBR) from the
Control Mode bird's-eye camera, and keep looking good with **zero** imported assets (the
procedural fallback is the baseline, not a placeholder). Then replace the fallbacks with real
art wherever art exists.

**Where it stands today:** every UI icon is an emoji fallback (`IconAtlas.assetId = 0`; only
`hay` and `wheat` have PNGs in `art/icons/`). `assets/` holds no models, so the drone, 7 crops
× 3 stages, the charger, the factory and the 5 hats are all procedural parts in
`PlotRenderer`. Soil states are colour/material swaps through `SoilLook`. There is no sound at
all. No `/art`, `/anim` or `/fable` pack has been signed off.

## Read first

1. `CLAUDE.md` (project rules; never open `docs/archive/CLAUDE_PROMPTS.md`).
2. `docs/ART_BIBLE.md`: §0 (toolchain, engine facts, camera), §1 (palette), §2 (soil),
   §3 (crops), §4 (drone, stations), §5 (texturing), §7 (budgets), §9 (review gates), §10.3
   (the Assets tree). **It is the single source of truth for the look.**
3. `assets/README.md` and `src/client/Visuals/AssetLibrary.luau`: the fixed asset paths, the
   pivot contracts and the "visible part" guard.
4. The `PlotRenderer.luau` header (LOD tiers, movement engine, crop juice budgets), plus
   `Visuals/SoilLook.luau`, `Visuals/PlotDressing.luau`, `Controllers/LightingController.luau`
   and `Controllers/WeatherFxController.luau`.
5. `src/shared/Config/IconConfig.luau` (59 icon keys + `AtlasOrder`),
   `src/shared/Config/IconAtlas.luau` (generated), `tools/build_icon_atlas.py`.
6. `tools/blender/_common.py`, `drone.py`, `crops.py`, `stations.py` (axis mapping: game
   `(x, y, z)` = Blender `(x, z, y)`).
7. `art/fable/look.html` + `art/fable/MOTION.md` (the target frame and motion timing), and
   `.claude/commands/art-1.md` … `art-8.md`, `fg-*.md`, `fable-*.md` for detail on each step.
8. `docs/BUGS.md` BUG-11 (dig exhaustion needs a "dug" soil look) and BUG-15 (budget
   disagreements).

## Hard rules

- **Visual only.** Don't touch the parser, interpreter, economy, Tech Tree data, remotes, data
  or receipts. If the art needs data the server doesn't publish yet (for example a dug-tile
  attribute), write it down as a **code hook** for `/bugfix` and don't edit server code.
- Extend the existing modules (`PlotRenderer`, `AssetLibrary`, `SoilLook`, `PlotDressing`,
  `LightingController`, `WeatherFxController`, `UI/Theme`, `UI/Icon`, `UI/Fade`). No second
  renderer.
- Every cloned asset goes through `AssetLibrary.makeInert`: anchored, no collide/query/touch,
  no scripts, joints, Humanoid or Animator. **No armatures and no AnimationClips.** All motion
  stays TweenService on value objects plus `BulkMoveTo`.
- **Movement contract:** don't break the drone pipeline (`DroneX`/`DroneY`/`Drone`/
  `DroneSerial` + `DroneMoved` → client tween). The drone model must contain `Body` and
  `Rotor1`..`Rotor4` (the hub is each rotor's origin, blades modelled flat). Optional: `Eye`,
  `BatteryBar`/`StatusLight` (Neon, no SurfaceAppearance) and `PaintSlot` attributes.
- **Fixed paths only:** `ReplicatedStorage.Assets.Drone`,
  `Assets.Crops.<grass|wheat|carrot|tree|sunflower|pumpkin|cactus>.<sprout|growing|ready>`,
  `Assets.Hats.<antenna|straw|propeller|tophat|halo>`, `Assets.Stations.<charger|factory>`.
  **Never leave an empty placeholder Model named like an asset**: that once made the drone
  invisible.
- **Budgets (ART_BIBLE §7):** crop stage 80 / 220 / 350 tris (sprout / growing / ready), at
  most 2 MeshParts; drone ≤ 1,900 tris and ≤ 14 MeshParts (README says 16; use 14); charger
  ≤ 1,500 tris / 6 parts; bioreactor ≤ 4,000 / 10; hat ≤ 300 / 2; plot props ≤ 2,000 per
  plot. Textures ≤ 1024² (Roblox downscales anything bigger); one shared atlas per family.
- **Runtime budgets:** your own plot is always LOD NEAR. No infinite tweens on MID/FAR plots.
  At most 40 live particles. No PointLight per tile, no Trails, no Beams per path cell.
- **Neon only for state:** the drone eye, the battery strip, the charger rings and the factory
  biofluid `#4DFFB0`. Never for decoration.
- **Palette:** hull `#1E2530` / `#2E3846`, ceramic `#D7E2EC`, plot grass `#4E6B3A`, dry soil
  `#8A6544` / dust `#A98258`, wet `#4A3324`, lime "grow" `#7FD962`, cyan "tech" `#66CCFF`
  (charger `#3CDCFF`), gold "featured" `#FFD666`, chrome UI `#0B0F15`. Crop stage colours are
  in ART_BIBLE §1.4. Ready must change **silhouette and colour**, not just size.
- **UI art = PNG slices** (9-slice panels, buttons, tabs, meter caps), never a full-screen
  screenshot as one ImageLabel. The terminal's TextBox stays a real TextBox.
- **Readability first:** every crop stage, soil state and station must read at the Control
  Mode bird's-eye view (≈80° down, FOV 55, 3×3 up to 10×10). Check it, don't assume it.
- If ForgeGUI says `insufficient_credits` / `upgrade_url`: stop paid calls, tell the user they
  are out of ForgeGUI credits (https://forgegui.com/plans), and continue with the free steps.
- Don't commit or push unless the user says so.

## Deliverables (in this order; after each one write `ASSETS-n done:` + files + how verified)

### ASSETS-0: plan (no art yet)
Write `art/ASSET_PLAN.md`: a table of every asset (the 59 icons, the drone, 21 crop stages, 2
stations, 5 hats, soil variants, UI slices, game icon/thumbnail, SFX) with its status (missing
/ procedural / done), its source (ForgeGUI, Blender script, hand-made, procedural), budget and
target path. Keep it updated as you go.

### ASSETS-1: icon set (all 59 keys)
- One style for all of them: chunky, readable at 24 px, soft top light, 2 px dark outline,
  transparent background, palette-true colour from each key's `color` in `IconConfig`.
- With the ForgeGUI tools: create **one** style (`style_create`, from `hay.png`/`wheat.png` as
  reference), then `generation_image` per key with that style, then `remove_background`.
  Otherwise use any image tool, as long as the style stays consistent.
- Save each one as `art/icons/<key>.png`, then run
  `python tools/build_icon_atlas.py --import <key> <png>` per key and rebuild with
  `python tools/build_icon_atlas.py`.
- `IconConfig.AtlasOrder` holds only 33 keys today: **extend it** to every key (it's a visual
  config list; keep the existing order and append). The script sizes the rows itself. Then
  `lune run tests/run` (IconConfig.spec checks capacity and order) must stay green.
- **PAUSE FOR USER:** they upload `art/IconAtlas.png` in Studio's Asset Manager and paste the
  id into `IconAtlas.luau` `assetId`. Rebuilding keeps that id.

### ASSETS-2: procedural fallback upgrade (looks good with zero assets)
- **Drone:** a readable quadcopter silhouette from above (ART_BIBLE §4.1): hull, ceramic visor
  rim, one neon eye slit on −Z, a 5-cell battery strip, 4 arms and 4 rotors with blur discs.
  ≤ 16 parts. Keep the top of the body clear (a 1.2-stud circle for hats).
- **Crops:** 7 crops × 3 stages, each ready silhouette distinct from above (wheat drooping
  gold heads, carrot orange shoulder, sunflower open disc facing +Z, pumpkin ribbed orange,
  cactus ribs + pink bloom, tree double canopy, grass straw tips). Keep part counts in line
  with the §3.4 10×10 field rules.
- **Soil:** improve the Dry / Tilled / Wet looks in `SoilLook` (furrows, sheen), and add the
  "Dug" look behind a `SoilStates` value once the server publishes it (code hook for BUG-11).
- **Plot dressing / stations / lighting / weather:** walkway, fence, sign, charger rings,
  factory hopper and chimney, Lighting + Atmosphere per §1.5, and rain/dust per §1.5.1. All of
  it within the runtime budgets above.
- **Verify:** `Workspace.ClientVisuals.FxDebugPrint = true` in Studio. The printed part, tween
  and particle counts for a full 10×10 must stay inside the budgets. Write those Studio steps
  in your report.

### ASSETS-3: Blender hero assets (drone, 21 crop stages, 2 stations, 5 hats)
- Extend `tools/blender/drone.py`, `crops.py`, `stations.py`, and add `hats.py` for antenna,
  straw, propeller, tophat and halo. They must build the exact part names and pivots the game
  expects, triangulate, apply transforms, and export FBX to `tools/blender/out/`. Print a
  tri/part report per asset against the §7 budgets.
- PBR: a ColorMap / Normal / Roughness / Metalness PNG set per family (≤ 1024², shared
  atlases), baked or procedural, saved under `art/textures/<family>/`.
- Run `blender -b -P tools/blender/<x>.py -- --out ...`. **If Blender isn't installed**
  (it isn't on this machine's PATH), still write and lint the scripts and print the exact
  commands for the user.
- Optional: ForgeGUI `generation_model_3d` concept meshes, but only if you then
  `generation_remesh_3d` them under budget and split/rename them to the rig contract (rotors
  must be separate parts with their origin at the hub). Never import a generated mesh that
  breaks the contract.

### ASSETS-4: Studio import guide (the user does this part)
Write `art/IMPORT.md`: 3D Importer settings (File Dimensions = Studs, no rig), where each
model goes under `ReplicatedStorage.Assets`, how to Save to File as `assets/<path>.rbxm`, the
SurfaceAppearance setup, and what `[AssetLibrary] ignored broken ...` means. Add one
playtest check per asset (pivot doesn't jump at the stage swap, every 45° yaw reads right,
nothing clips with the 0.35 bob and the 14° lean).

### ASSETS-5: soil MaterialVariants
512² tileable PBR sets for SoilDry, SoilTilled and SoilWet (+ SoilDug), named exactly as
`SoilLook` expects, with `StudsPerTile` as in ART_BIBLE §2.2. Document the MaterialService
setup in `art/IMPORT.md`.

### ASSETS-6: UI chrome slices
9-slice PNGs (panel, raised panel, primary/secondary/danger button, tab on/off, meter track
and cap, toast, modal header), plus the rect/`SliceCenter` table, wired through `UI/Theme`
behind a flag so the code-built look stays the fallback. Follow `fg-hud.md`, `fg-term.md`,
`fg-shop.md` and `fg-tech.md`.

### ASSETS-7: game icon + thumbnails
A 512×512 game icon and 3 thumbnails at 1920×1080 (bird's-eye farm with a hopping drone, the
terminal running code, the Tech Tree), following `fg-thumb.md`. Real game look and palette;
no text that pretends to be UI the game doesn't have.

### ASSETS-8 (optional, ask the user first): sound
An SFX list (drone hop, land on charger, plant, water, harvest, unripe harvest, dig/fossil,
deposit, refine, charge loop, research, purchase, UI click/hover, error) + one calm ambient
loop, with ForgeGUI `generation_sound_effect` / `generation_music` or anything else. Deliver
the files to `art/audio/` + a hook table (event → file → volume). **Don't add a
SoundController unless the user says yes.**

## Verify (after every deliverable that touched `src/`)

```bash
lune run tests/run
stylua --check src tests
selene src
rojo build default.project.json -o build/DroneFarm.rbxlx
```

Plus the Studio checks you listed. Anything you couldn't check in Studio is marked
**needs Studio**.

## Final report

Per deliverable: done / partly / paused (why) + files + how verified. Then: what is still
procedural, what the user has to generate, upload or import (with exact paths and ids to
paste), the code hooks you need from `/bugfix`, and one Studio playtest checklist.
