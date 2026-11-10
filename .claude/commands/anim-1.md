---
description: ANIM-1 drone flight feel
---

# ANIM-1 — the drone flies, it does not slide

THIS TASK ONLY. `PlotRenderer` `updateDroneTarget` / `render` / `refreshLimp`. Own-plot NEAR. MID stays a snap.

Read `GameConfig.Drone.TweenFraction` (0.85). Client tween length = `DroneMoveTime * TweenFraction`. Do not change server waits.

## Motion

1. **Takeoff** — first 15 % of the move tween: extra +0.25 stud Y on `move` (or a `lift` NumberValue composed in `render`). Then the rest of the path.
2. **Bank** — existing 14° pitch tilt stays. Add a small **roll** into the travel direction (max ~8°) that reverses with the same tween. Strafe left/right should lean; forward/back should pitch.
3. **Settle** — last 20 % of the tween: Quad InOut into the cell. No Back overshoot bigger than 0.15 stud (it would clip the hat).
4. **Rotors** — `spin` loop period: idle 0.35 s, while `moveTween` playing 0.22 s, limp 0.7 s. Tween the period, don’t restart from 0 every cell.
5. **Charger land** — when the target cell is the charger (`DroneSignals.stationAt`) and this is a one-step move (not a teleport): hover height 5 → ~1.6 over the pad during the tween, then bob resumes small. Leaving the charger: lift back to 5 in the next takeoff.
6. **Teleport / first pose** (`instant` or Magnitude > 1.5): snap, no takeoff, no land.

Keep `BulkMoveTo` as the only writer of part CFrames. Do not `PivotTo` in a second path.

**Verify:** `RUN` the starter script. Each `move_*` is a hop with a lean and faster rotors. Arriving on the charger visibly drops. Idle over a field tile only bobs. MID neighbours still snap.
