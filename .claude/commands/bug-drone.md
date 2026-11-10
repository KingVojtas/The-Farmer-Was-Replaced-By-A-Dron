---
description: P0 — farming drone is invisible
---

# BUG-DRONE

THIS TASK ONLY. The drone is invisible in play. Fix visibility before any polish.

How it is drawn (read first):

- src/client/Controllers/PlotRenderer.luau `buildDrone()`
- src/client/Visuals/AssetLibrary.luau `drone()` clones `ReplicatedStorage.Assets.Drone` if that Model exists
- If the clone exists, the procedural drone is NEVER built
- RenderStepped BulkMoveTo only for `tier=="near"` AND `drone.cell ~= nil`
- `move.Value` starts at CFrame.identity until plot attribute `Drone` is applied
- ControlModeController hides the PLAYER with LocalTransparencyModifier=1, not the drone. Do not "fix" that by showing the avatar.

Check in this order:

1. `ReplicatedStorage.Assets.Drone` exists in the Studio place (NOT in default.project.json). Empty model, 0-size meshes, Transparency=1, or SurfaceAppearance Overlay with fully-transparent ColorMap → invisible. If broken: ignore it and use procedural. `AssetLibrary.drone()` must return nil unless the model has at least one BasePart with Size magnitude > 0.2 and Transparency < 0.9.
2. `Drone` attribute not a Vector2, or Origin missing → cell stays nil, parts sit at (0,0,0) in/under the baseplate.
3. Own plot classified FAR/MID (own plot MUST be near).
4. applyPaint never runs, parts stay Color3.new() black — still should be visible; if this is it, force a lime/cyan accent even before paint.

Do:

- If artist drone has 0 visible parts, destroy clone and `buildProceduralDrone`.
- On addPlot, `updateDroneTarget(..., instant=true)` so cell is set the same frame. After setting `move.Value` on instant/first pose, also snap the actual parts (don't wait a frame of BulkMoveTo if cell was nil).
- If Drone/Origin arrive late, AttributeChanged then snap.
- Debug behind existing ClientVisuals `FxDebugPrint`: print plot name, tier, cell, part count, first part Transparency/Size/CFrame.

Do not add particles, hats, or new meshes until the procedural drone is visible from Control Mode on a 3x3.

Verify: WATCH/CONTROL, dark hull + cyan/lime eye, hovering ~5 studs above a tile, bobbing.
