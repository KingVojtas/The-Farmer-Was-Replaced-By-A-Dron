---
description: ANIM-7 charger and factory theater
---

# ANIM-7 — stations react to the drone

THIS TASK ONLY. Own-plot NEAR. `refreshStations` / `PlotDressing`. Neon only for **state** (ART-6). Idle stays dark.

## Charger (cell 0, −1)

- Already: cyan rings pulse, pad Neon, battery strip cyan, shadow fades.
- Add: on **arrival** (cell became charger this move): pad UI-less world scale punch 1 → 1.06 → 1 in 0.3 s (the pad part, or a client overlay). Rings spin-up: pulse period 0.45 → 0.28 while charging, back when it leaves.
- Battery strip already changes colour; don’t add a second light.

## Factory (cell 1, −1)

- Already: biofluid slit `#4DFFB0` + work lamp while the drone is on the cell.
- Add: hopper 0.1 s positional jitter (2 px / 0.08 stud, 3 cycles) when ANIM-4 would also fire (cargo drop on factory). Chimney: 2–3 smoke puffs from the existing FX pool, only then.
- Idle factory: no jitter, no smoke, slit dark.

Skip MID/FAR. Don’t replace server station parts (attributes live on them). Client dressing only.

**Verify:** drone lands on charger — pad punches, rings faster, strip cyan. Leaves — idle dark. Factory with cargo — hopper ticks and chimney puffs once; empty visit is only the slit.
