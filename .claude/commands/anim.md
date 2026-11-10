---
description: ANIM MODE — run the whole motion pack in order
---

# /anim — ANIM MODE ON

You are now in **ANIM MODE**. Gameplay (`/g1`–`/g6`) is off-limits. Parser, economy, tech tree data, remotes: do not touch unless a file says otherwise.

This pack is **motion**. Silhouettes, soil, meshes, ForgeGUI: already `/art` / `/v*`. Do not redo those.

## What you do right now

Read and execute these files **in order, in this same turn-sequence**, without waiting for the user to say “next”:

1. `.claude/commands/anim-1.md` — flight feel (takeoff, bank, rotors, charger land)
2. `.claude/commands/anim-2.md` — action body language (plant / water / harvest / charge)
3. `.claude/commands/anim-3.md` — crop growth interpolation + weather wind
4. `.claude/commands/anim-4.md` — cargo unload / factory bits
5. `.claude/commands/anim-5.md` — terminal line tracks the drone
6. `.claude/commands/anim-6.md` — UI motion kit (panels, toasts, tutorial, unlock)
7. `.claude/commands/anim-7.md` — charger + factory theater
8. `.claude/commands/anim-8.md` — weather rhythm

After each file: one line `ANIM-n done:` + what changed. Then immediately start the next.

**Stop the chain** only if Verify on that file fails. Then tell the user what to playtest and which command to re-run (`/anim-N`).

## Hard rules

- Client visuals only. Server never moves parts. Do not change `GameConfig.Drone.ActionTimes`.
- Keep the movement sync: `Drone` is Vector3 `(x, y, 0)`, `DroneSerial` ticks on every `MoveDrone`, client `readDroneCell` / `DroneSignals.cellXY` accept Vector2 or Vector3. Do not revert to Vector2-only.
- Own plot stays LOD NEAR. No new infinite tweens on MID/FAR.
- Infer actions from published attributes (`DroneSignals.action`, `Cargo`, `Battery`, `DroneSerial`). No new remotes.
- One RenderStepped `BulkMoveTo` for NEAR drones. Compose new motion into existing `move` / `tilt` / `bob` / `spin` NumberValues.
- Particle budget still ≤ 40. No PointLight per tile. No trails. No physics movers, no welds.
- Existing modules: `PlotRenderer`, `AssetLibrary`, `WeatherFxController`, `LightingController`, `TerminalView`, `Fade`, `Theme`, `NotifyController`, `TutorialController`. Extend them. Don’t create a second animator.
- `lune run tests/run` if you touch `DroneSignals` or any shared pure module.

When the pack finishes, list: files changed, which motions play on own-plot NEAR only, what to press in Studio (`RUN` the starter script).
