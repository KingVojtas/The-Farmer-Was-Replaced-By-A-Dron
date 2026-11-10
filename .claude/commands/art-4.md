---
description: ART-4 plant grow harvest water FX
---

# ART-4 — crop juice

`PlotRenderer` FX pool (one Attachment per plot, `Emit` bursts, `Enabled` stays false). Full FX: own plot NEAR only. ≤40 particles on screen. No Lights per tile.

- **Plant:** seed-drop 0.2s from ~3 studs if the drone is on that tile
- **planted→growing:** pop 1.08 then settle + 8 leaf bits
- **→ready:** silhouette pop + brief lime ping; Control Mode ready marker (hide if >40 ready tiles); own-plot sway ±2° max 36
- **Harvest ripe:** 6–12 bits in crop colour; **unripe:** grey-brown
- **Watered true:** 4–6 droplets + soil already darkens; Watered false: no FX

**Verify:** one wheat cycle (plant, wait ready, harvest, water) is readable with the terminal collapsed.
