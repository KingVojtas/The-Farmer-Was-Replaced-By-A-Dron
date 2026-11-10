---
description: ANIM-2 plant water harvest charge poses
---

# ANIM-2 — the body does the builtin

THIS TASK ONLY. Own-plot NEAR. Infer from attributes (`DroneSignals.action`, charger/factory cell). Wrong pose is worse than none. No new remotes. Tool flash (0.15 s disc) already exists — keep it, add body motion.

## Poses (one at a time, cancel the previous)

| Inferred action | Body (composed on `move` / `tilt`) | Duration |
|---|---|---|
| plant | dip −0.8 Y, slight nose-down, then back | 0.28 s |
| water | yaw wobble ±6° + existing cyan flash | 0.22 s |
| harvest (ripe only) | nose-down scoop then snap back | 0.28 s |
| unripe harvest | skip scoop (grey bits already play) | — |
| charge (on charger, Battery rising) | hold the ANIM-1 land height | while on pad |
| factory | small settle, no scoop | — |

Caps: one action tween at a time. If a move starts, cancel the pose and fly.

Do **not** clone `Assets/Tools` in this step (WateringCan / HarvesterBlades are a later art drop). Procedural body only.

**Verify:** plant wheat on one tile — drone dips as the seed falls. `water()` — yaw + cyan flash. Ripe `harvest()` — scoop + gold flash. Wild-grass regrowth: no dip.
