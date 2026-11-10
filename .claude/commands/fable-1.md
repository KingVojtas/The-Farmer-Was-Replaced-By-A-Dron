---
description: FABLE-1 HTML motion studies for the drone
---

# FABLE-1 — motion bible (HTML, not Roblox)

THIS TASK ONLY. One self-contained HTML file per loop. `seek(t)` paints frame `t` (seconds). No `requestAnimationFrame` as the source of truth — a slider and a play loop both call `seek`. Bird’s-eye, same as Control Mode.

Write to `art/fable/motion/`:

| File | Loop | Must show |
|---|---|---|
| `hop.html` | 0.34 s (`0.4 * 0.85`) | takeoff +0.25 Y, 14° pitch / 8° roll into travel, rotors faster, settle. 3×3 tiles, pitch 6.4 studs |
| `plant.html` | 0.50 s | hop in, dip −0.8 Y, lime seed drop 0.2 s, crop pop 1.08 |
| `harvest.html` | 0.50 s | scoop, gold bits, tile empty |
| `water.html` | 0.40 s | yaw ±6°, cyan droplets, soil darkens |
| `charge.html` | 0.40 s land + hold | hover 5 → 1.6 on cyan pad, rings pulse, strip cyan |
| `snake.html` | ~8 s | `while True` snake on 3×3, lime ghost dots on last 16 cells, battery strip lime→amber |

Look: dark hull quadcopter, one neon eye on −Z, 4 rotors, battery strip. Background `#0B0F15`, tiles `#4E6B3A` / dry `#A98258`. No UI chrome, no soundtrack required.

At the top of each file, an HTML comment block:

```
TIMING (seconds) — copy into /anim
takeoffLift, bankDeg, settle, rotorIdle, rotorMove, landHeight, dipPlant, …
```

**Verify:** open `hop.html` in a browser. Drag the time slider: motion is deterministic. A hop reads as a hop, not a lerp.
