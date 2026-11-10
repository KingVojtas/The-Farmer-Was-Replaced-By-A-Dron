---
description: FABLE-4 Blender charger and factory
---

# FABLE-4 — stations (Blender Python)

THIS TASK ONLY. `tools/blender/stations.py`. ART_BIBLE.md §4.2–4.3. Pivot = **top centre of the server station part** (charger pad 6 × 0.4 × 6, factory block 6 × 3 × 6).

**Charger:** hexagonal dark-steel pad, ceramic H-mark, copper coil `#C27744` 1–2 parts, rings that the **game** will colour cyan when active. Model the rings as named parts (`Ring1`…) **without** baked pulse. Neon only for state — leave ring material Metal; PlotRenderer sets Neon.

**Factory:** dark hull, hopper, chimney. Named `Slit` (biofluid `#4DFFB0` when active — export as dark glass, game Neons it) and `Lamp`. No looping smoke in the file.

No armature, no animation. Opaque except one optional glass (factory window), AlphaMode later in Studio.

```
blender -b -P tools/blender/stations.py -- --out tools/blender/out/Stations
```

`charger.fbx` + `factory.fbx` (+ glb previews). Same FBX flags as FABLE-2.

**Verify:** charger vs factory readable from a 55° bird’s-eye camera 40 studs up. Pivots on the top face.
