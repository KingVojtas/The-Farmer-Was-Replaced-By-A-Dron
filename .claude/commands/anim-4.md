---
description: ANIM-4 cargo unload and factory bits
---

# ANIM-4 — cargo leaving the drone is visible

THIS TASK ONLY. Own-plot NEAR. Particle pool already in `PlotRenderer` (one Attachment, `Emit`, `Enabled` false, ≤40 live).

Infer, don’t add remotes:

1. **Unload** — `Cargo` drops while the drone cell is the charger. Burst 4–8 bits from the drone toward the sign post / silo (plot dressing). Colour = hay/crop gold `#C9C27A` unless you know the currency colour. 0.45 s, then gone.
2. **Factory** — `Cargo` drops (or factory work inferred) while on the factory cell: 3–5 bits **into** the hopper, then 2 cyan/green bits up the chimney. Biofluid `#4DFFB0`.
3. Skip if `Cargo` went **up** (harvest). Skip if the drop is 0. Skip MID/FAR.
4. At most one unload burst at a time. Don’t steal the harvest burst’s budget on the same frame — harvest wins.

**Verify:** starter script harvests 3 grass and `charge()`. When it docks, bits fly off the drone toward the sign and cargo HUD ticks down. Factory with cargo: bits into the hopper, not a second harvest explosion on the pad.
