---
description: P0 — drone visible but does not fly with the terminal
---

# FIX-DRONE

THIS TASK ONLY. The farming drone is **on screen** and the **terminal RUN line advances**, but the drone **does not hop** to the cells the program is executing. Fix movement until `RUN` of the starter script makes the drone fly tile-to-tile in time with the lime line.

Do **not** start `/art`, `/anim`, `/fable`, economy, or UI.

## How it is supposed to work (read these files first)

Server (authority, never tweens parts):

- `src/server/DroneRuntime/DroneAPI.luau` `move_up/down/left/right` → `world:moveDrone` then `world:wait(seconds)`
- `src/server/DroneRuntime/LiveWorld.luau` → `GridService:MoveDrone`
- `src/server/Services/GridService.luau` `MoveDrone` / `PublishDrone`
- `src/shared/Net/RemoteSchema.luau` event **`DroneMoved`** (ServerToClient)
- `src/server/Services/ScriptService.luau` fires `ScriptStatus` `"line"` (this already reaches the terminal)

Client (only place parts move):

- `src/client/Controllers/PlotRenderer.luau` `readDroneCell` / `updateDroneTarget` / `render` / `Net.on("DroneMoved")`
- `src/shared/Util/DroneSignals.luau` `cellFromAttributes` / `cellXY`
- `src/client/Visuals/AssetLibrary.luau` `drone()` / `makeInert`

Contract after a move:

1. `plot.drone.x/y` change
2. attributes: `DroneMoveTime`, **`DroneX`**, **`DroneY`** (numbers), `Drone` Vector3 `(x,y,0)`, `DroneSerial` += 1
3. **`NetService:FireAll("DroneMoved", plot.index, x, y, duration)`**
4. client tween `move` CFrameValue for `duration * TweenFraction` (0.85), Quad InOut
5. RenderStepped: `PivotTo` + `BulkMoveTo` of anchored parts (NEAR only)

Own plot is **always LOD NEAR**. Server never `PivotTo`s the drone. No `loadstring`. No physics movers.

## Why it still looks stuck (check in this order)

The terminal uses a **remote**. If the drone only listens to plot **attributes**, it parks on the charger while the console runs. That is the bug even when the hull is visible.

1. `DroneMoved` missing from schema, not created, or PlotRenderer never `Net.on`s it.
2. `FireAll` runs **before** attributes, or PlotRenderer looks up the plot by the wrong `Index`.
3. `readDroneCell` still requires `typeof == "Vector2"` only → Vector3/`DroneX` ignored → `updateDroneTarget` returns.
4. `updateDroneTarget` early-outs (`sameCell`) on a stale cell; poll only ran on `own` and `own` was false.
5. `tier ~= "near"` or `drone.cell == nil` → RenderStepped skips `BulkMoveTo`.
6. `poses` empty, or an artist `Humanoid`/`Animator` fights CFrames (`makeInert` must destroy those).
7. First pose at world origin (0,0,0) under the baseplate — user may be looking at a **server** station pad, not the client drone.
8. Two interpreter runs (see `/g1`) teleporting the sim; still fix **this** visual pipeline first unless you prove two LiveWorlds.

## Do this

Make **all** of these true. Keep existing names. Do not invent a second renderer.

**Server `MoveDrone`**

- Set `DroneMoveTime` first, then `PublishDrone` (`DroneX`, `DroneY`, `Drone` Vector3), then `DroneSerial += 1`, then `FireAll("DroneMoved", index, x, y, duration)`.
- `DroneMoved` in `RemoteSchema` as ServerToClient Event. `NetService:FireAll` already exists.

**Client `readDroneCell`**

- `DroneSignals.cellFromAttributes(DroneX, DroneY, Drone)`: numbers first, then Vector3 or Vector2.
- Never require Vector2-only.

**Client apply path**

- `updateDroneTarget(plotVisual, instant, cellOverride?)` — remote passes `Vector2.new(x,y)`.
- Listen: `Drone`, `DroneX`, `DroneY`, `DroneSerial`.
- `Net.on("DroneMoved")`: cache by plot `Index`; if the visual exists, set local `DroneMoveTime` and tween.
- `Net.on("ScriptStatus")` for `"line"` / `"running"`: re-read own plot cell (console already works).
- Every RenderStepped, **every NEAR plot**: if published cell ≠ `drone.cell`, `updateDroneTarget`.
- Instant / first pose / teleport (magnitude > 1.5): snap parts **this frame** (`snapDrone`: PivotTo + BulkMoveTo). Do not wait a frame.
- Own plot always NEAR. MID snaps, no tween. FAR destroyed.

**Visual must actually move**

- `makeInert`: Anchored, no collide; destroy scripts, joints, constraints, **Humanoid, Animator, AnimationController**.
- Broken `Assets.Drone` (no visible part Size>0.2, Transparency<0.9) → procedural. Empty placeholder Model must not win.
- Compose flight into existing `move` / `tilt` / `bob` / `spin` values. One RenderStepped BulkMoveTo.

**Tests**

- `DroneSignals.cellFromAttributes` prefers X/Y numbers.
- `lune run tests/run`.
- Do not add a remote the schema does not list.

## Do not

- Revert `Drone` to Vector2-only.
- Tween on the server.
- Beams per path cell, PointLight per tile, trails, `AnimationClip` on the hull.
- Change `GameConfig.Drone.ActionTimes`.
- “Fix” Control Mode hiding the **player** avatar.

## Verify (must all pass)

Studio Play, Control Mode, 3×3, `RUN` the starter script (`move_up` / `harvest` / `move_right` … `charge()`):

1. Lime line in the terminal moves to `move_up()` **and** the drone hops one tile toward the field (not a teleport at the end).
2. Each following `move_*` is a hop with lean; rotors exist.
3. `charge()` lands on the charger pad (0, −1).
4. Stop + Run again: drone does not duplicate, does not freeze on the pad.
5. With **no** `ReplicatedStorage.Assets.Drone`, procedural hull still hops.

If Verify fails, do not start another pack. Print: which of the 8 causes you proved, files changed, what you still need from Studio Output (`FxDebugPrint` on `Workspace.ClientVisuals`).
