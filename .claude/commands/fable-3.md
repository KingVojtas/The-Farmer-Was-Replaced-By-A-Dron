---
description: FABLE-3 Blender crops three stages each
---

# FABLE-3 — crop meshes (Blender Python)

THIS TASK ONLY. `tools/blender/crops.py`. ART_BIBLE.md §3. Pivot = **tile top centre**, +Y up. Ready footprint ≤ 5.2 × 5.2. One mesh per stage (two max). Opaque, no alpha cards. CastShadow false on sprout and grass.

Crops: `grass` `wheat` `carrot` `tree` `sunflower` `pumpkin` `cactus`  
Stages: `sprout` | `growing` | `ready`

Ready must change **silhouette and colour**, not only scale. Game `ScaleTo`s: author sprout **taller** than it will look (sprout scale 0.25–0.55 in game).

Silhouette cheat sheet (ready):

| Crop | Read |
|---|---|
| grass | straw-gold tips `#C9C27A` |
| wheat | gold heads droop 15–25° |
| carrot | orange shoulder sphere breaking soil |
| sunflower | disc + petals, head tilt toward +Z |
| pumpkin | squashed Y 0.7, ribs; green unripe is growing |
| cactus | column + arms; ready pink `#FF6FA0` |
| tree | trunk + 2 canopy balls, ~5 studs at scale 1 |

Export:

```
blender -b -P tools/blender/crops.py -- --out tools/blender/out/Crops
```

Writes `out/Crops/<cropId>/<stage>.fbx` (and `.glb` preview). Same FBX flags as FABLE-2.

**Verify:** wheat ready ≠ wheat growing in grayscale. All pivots at (0,0,0) tile top. No n-gons after triangulate.
