---
description: ART-5 drone ghost shadow battery wash
---

# ART-5 — drone reads as a running program

Local own-plot NEAR only. Other drones: battery eye only. No PointLights. Path ghost = pooled parts, max 16, **not** Beams per cell.

1. **Path ghost** — fading lime dots on field tiles the drone just left
2. **Ground shadow** — dark ellipsoid ~3.5×0.05×3.5 in BulkMoveTo, offset `(0, -HoverHeight+0.08, 0)`, fade on stations
3. **Battery eye / strip** — >50% `#8CFF5A`, 15–50% `#FFB547`, <15% `#FF4D5E` blink. Read `Battery`/`BatteryMax`
4. **Limp** — long `DroneMoveTime` flattens bob, dims eye
5. **Rotor wash** — while move tween playing, dust `Emit` 3; idle none
6. **Charger** — eye `#3CDCFF`; **factory** — amber flash. Infer actions conservatively from attributes (wrong FX worse than none)

**Verify:** a `while True` snake leaves a visible trail; low battery is obvious from the drone, not only the HUD.
