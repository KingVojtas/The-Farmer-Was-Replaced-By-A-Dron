---
description: ART-1 drone visible + quadcopter silhouette
---

# ART-1 — drone must be on screen and look like a drone

Read `src/client/Controllers/PlotRenderer.luau` `buildDrone` / `buildProceduralDrone` / `updateDroneTarget` / `render`, and `src/client/Visuals/AssetLibrary.luau`.

## Bug

The drone is often invisible. Causes:

1. `AssetLibrary.drone()` clones `ReplicatedStorage.Assets.Drone` even when it has no visible parts (empty model, Transparency 1, 0-size). That **skips** the procedural drone.
2. `BulkMoveTo` only if `tier=="near"` and `drone.cell ~= nil`. First pose can sit at world origin (0,0,0) inside the baseplate.
3. Own plot must stay NEAR.

## Fix

- `AssetLibrary.drone()` returns nil unless the model has ≥1 BasePart with Size magnitude > 0.2 and Transparency < 0.9.
- If the clone is junk, destroy it and `buildProceduralDrone`.
- On `buildPlot`, `updateDroneTarget(instant=true)` **and snap the parts’ CFrames the same frame** (don’t wait for RenderStepped).
- If `Drone` / `Origin` attributes arrive late, snap on AttributeChanged.

## Look (procedural, ART_BIBLE §4.1)

Dark hull `#1E2530` ~2.4×0.8×2.4, ceramic visor rim, **one neon eye slit on -Z**, 4 arms, 4 rotors named `Rotor*`, neon battery strip on the spine. Hover ~5 studs. Bob 0.35, tilt 14°. Top of body clear in a 1.2 circle (hats). Force lime/cyan accent even before paint so a black Metal hull still reads.

Do not import GLB in this step.

**Verify:** Control Mode, 3×3, drone is a dark quadcopter with a glowing eye, hovering over a tile, bobbing, not at the origin.
