---
description: FABLE-2 Blender drone matching ART_BIBLE
---

# FABLE-2 — drone mesh (Blender Python)

THIS TASK ONLY. `tools/blender/drone.py`. ART_BIBLE.md §4.1 + `assets/README.md`. Units: 1 BU = 1 stud.

## Build

Named objects (exact): `Body`, `Arm1`–`Arm4`, `Rotor1`–`Rotor4`, `Eye`, `BatteryBar`. Optional empty `ToolMount` at (0, −0.45, −0.3).

- Body 2.4 × 0.8 × 2.4, hull `#1E2530`, origin = body centre (world 0,0,0).
- Rotors: origin at **hub**, blades **flat** (horizontal). Positions (±1.6, +0.5, ±1.6).
- Eye: Neon slit on −Z. BatteryBar: 1.2 × 0.12 × 0.3 on the spine, behind a 1.2-radius clear circle on top of Body (hats).
- ≤ 16 objects, ≤ 1,900 tris total. Opaque. No armature. No shapekeys. No lights in the export.

Custom properties on objects (become Roblox attributes if the importer keeps them; also print a checklist): `PaintSlot` = primary | secondary | accent on Body / Arms / Eye.

## Export

Script args after `--`:

```
blender -b -P tools/blender/drone.py -- --out tools/blender/out/Drone.fbx
```

FBX: Selected Objects, Apply Transform, Forward **−Z**, Up **Y**, Apply Scalings All Local, Apply Modifiers, Triangulate, Smoothing Face, **no armature, no animation**. Also write `Drone.glb` next to it for a quick look (GLB is not the Studio import; FBX is).

If Blender is on PATH, run the command. If not, write the `.py` and print the command.

**Verify:** opening the FBX, Body at origin, four `Rotor*` origins at hubs, top of Body clear, tri count printed.
