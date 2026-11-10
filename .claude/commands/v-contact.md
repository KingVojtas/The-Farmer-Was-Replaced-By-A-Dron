---
description: Drone shadow, rotor wash, height beam
---

# V-CONTACT

THIS TASK ONLY. Own plot NEAR only. No PointLights.

1. Ground shadow ~3.5x0.05x3.5, transparency 0.55, in BulkMoveTo, offset (0, -HoverHeight+0.08, 0). Fade over a station
2. Rotor wash: while moveTween playing, dust Emit 3 per move. Idle none. Limp fewer
3. Height beam: cyan Beam width 0.04 transparency 0.85, Control Mode only
4. Charger land: 0.3s scale punch on the shadow

Skip MID/FAR.
