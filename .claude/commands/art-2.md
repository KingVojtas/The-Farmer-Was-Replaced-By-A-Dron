---
description: ART-2 crop silhouettes readable from bird's-eye
---

# ART-2 — procedural crops

`PlotRenderer` shapes + `CropConfig`. `AssetLibrary.crop()` still wins when a real model exists. Opaque parts only, no alpha cards, no unions. `CastShadow false` on grass and sprouts. ≤8 parts per tile.

Ready must change **colour + silhouette**, not only scale. ART_BIBLE.md §3.3.

| Crop | Ready read |
|---|---|
| grass | straw-gold tips `#C9C27A` |
| wheat | gold heads droop 15–25°, max 6 parts |
| carrot | orange **shoulder** sphere breaking the soil |
| sunflower | disc + 6–8 petals, head tilted, max 10 parts |
| pumpkin | squashed Y 0.7, 2–3 ribs, SmoothPlastic; green when unripe |
| cactus | column + arms; ready pink ball `#FF6FA0` |
| tree | trunk + 2 canopy balls, ~5 studs at scale 1 |

MID LOD: keep 1 part per tile. Don’t add sway on neighbours.

**Verify:** 3×3 with mixed ready crops is identifiable from Control Mode without reading HUD.
