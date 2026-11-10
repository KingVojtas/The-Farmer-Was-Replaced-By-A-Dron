---
description: ART-3 soil states + plot dressing
---

# ART-3 — ground and plot kit

Extend `SoilLook` and `PlotDressing`. Tiles stay server Parts.

Soil (ART_BIBLE §2):

- empty / wild grass → SoilDry
- player crop planted/growing/ready → SoilTilled
- Watered → SoilWet (overrides)
- If MaterialVariants `SoilDry` / `SoilTilled` / `SoilWet` exist, use them. Else Color+Material fallback. Fertile skip.

Dressing (client, CanCollide false; players walk on the **server** base):

- Walkway `y=-2` gravel `#7A7468`
- Low wood fence `#8A6A4A`, gaps at the station row
- Sign on a post; VIP = gold trim, not a spoofable `"[VIP]"` text prefix
- Plot grass base toward `#4E6B3A`

LOD: own plot full; neighbours fence+sign; far none.

**Verify:** watered tile is obviously wet; a planted wheat tile doesn’t look like empty dirt; fence doesn’t block the drone path.
