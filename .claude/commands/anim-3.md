---
description: ANIM-3 crop growth interpolation and wind
---

# ANIM-3 — growth is a motion, not a teleport

THIS TASK ONLY. `PlotRenderer` crop pose. Stage pops (1.08 / 1.12) from `/art-4` stay. This fills the **in-between**.

Server `Progress` is 0.1 steps. Client should lerp scale toward the published value (0.15 s Quad Out) so a growing wheat field is a slow rise, not ten clicks.

- `planted` / `growing` / `ready` still swap models/shapes at the existing thresholds. Lerp **inside** a stage so the swap does not double-pop.
- Artist models: `ScaleTo` toward the target; pivot stays tile top.
- Procedural: existing `poseProcedural` / scale path.
- **Wind** (own plot ready sway only, still max 36):
  - Sunny: current ±2°
  - Rainy: ±3.2°, slightly faster
  - Drought: ±0.8°, slower
  Read the same weather source as `WeatherFxController` (plot `Weather` attribute, else `Workspace.Weather`).
- Neighbours never sway. MID/FAR: instant scale, no lerp.

**Verify:** plant a 3×3 of wheat and watch without collapsing the terminal. Crops ease up between progress ticks. Rain makes ready wheat lean more; drought almost still.
