# assets/ → `ReplicatedStorage.Assets`

This folder is synced by Rojo (`default.project.json`) to **`ReplicatedStorage.Assets`**, where
`src/client/Visuals/AssetLibrary.luau` looks for art. Anything missing or broken falls back to
the procedural stand-ins in `PlotRenderer`, so the game always runs with zero assets.

**Two ways to add a model:**

1. Save it here as `.rbxm` / `.rbxmx` (Studio: right-click → *Save to File*). The file name is
   the instance name: `assets/Drone.rbxm`, `assets/Crops/wheat/ready.rbxm`, …
2. Or drop it straight into `ReplicatedStorage.Assets` in Studio. The mapping uses
   `$ignoreUnknownInstances`, so Rojo won't delete what you add there while `rojo serve` runs.

**Fixed paths** (don't invent new ones):

```
ReplicatedStorage.Assets
├── Drone                         Model (pivot = body centre)
├── Crops/<cropId>/<stage>        cropId: grass wheat carrot tree sunflower pumpkin cactus
│                                 stage:  sprout | growing | ready
├── Hats/<style>                  Model (pivot = where it sits on the drone's back)
├── Stations/charger, factory     Model (pivot = top of the station tile)
├── Tiles/Soil                    Model, one MeshPart 6 x 0.6 x 6 (pivot = its centre): the SERVER
│                                 clones it for every field tile (GridService.newTilePart)
└── Dressing/FencePost, FenceRail, Walkway, SignPost
                                  PlotDressing's kit: the rail stretches along Z, the walkway along X
```

The world around the plots is NOT here: `map/Map.rbxm` (Workspace.Map) is composed by
`tools/build_map.luau` from `map/props/*.rbxm` (Blender `tools/blender/props.py` and
`buildings.py`).

**Detail textures:** the model parts carry a `MaterialVariant` (DroneHull, CropLeaf, CropSkin,
Bark, Planks, Shingles, Stone; in MaterialService via `materials.project.json`). The maps are
light and neutral, and `Part.Color` tints them, so recolouring a part (PaintSlot, cosmetics)
keeps working. If a part's `Material` is changed to anything but the variant's BaseMaterial,
the variant no longer applies and the plain material shows.

**The game guards every clone** (`AssetLibrary`):

* A model with **no visible part** (no BasePart with Size > 0.2 and Transparency < 0.9) is
  ignored. You'll see `[AssetLibrary] ignored broken <path>` once in Output, and the procedural
  version stays. **Never leave an empty placeholder Model named like an asset.** An empty
  `Drone` Model is exactly what once made the drone invisible.
* Every clone is made inert: Anchored, no collide / query / touch, scripts, constraints and
  joints removed, and MeshParts set to `CollisionFidelity = Box` where the engine allows it.
* Crop sprouts and grass get `CastShadow = false`.

## Checklist

**Crops** (`docs/ART_BIBLE.md` §3)
- [ ] `Model.WorldPivot` = the tile's top centre, +Y up.
- [ ] The game `ScaleTo()`s the model while it grows (sprout 0.25–0.55, growing 0.55–0.85,
      ready 1): author the sprout taller than it should look.
- [ ] Ready footprint ≤ 5.2 x 5.2 studs; one MeshPart per stage (two at most).
- [ ] Opaque only, no alpha-card leaves. CollisionFidelity Box, RenderFidelity Automatic.
- [ ] Ready changes silhouette **and** colour (§3.3), not just size.
- [ ] Playtest: the stage swaps at progress 0.5 and at ready don't jump in world position, and
      every 45° yaw step still looks right.

**Drone** (§4.1)
- [ ] Parts `Body`, `Rotor1`..`Rotor4` (a `Rotor*` part spins around its own origin: model the
      blades flat, origin at the hub). Optional: `Eye` (Neon, `PaintSlot = "accent"`), parts
      with the attribute `PaintSlot = primary | secondary | accent`, and a `BatteryBar` or
      `StatusLight` (Neon, no SurfaceAppearance: the game colours it by battery).
- [ ] ≤ 14 MeshParts, ≤ 1,900 tris (`docs/ART_BIBLE.md` §7). Keep the top of `Body` clear in a 1.2-stud circle (hats sit
      0.4 above the body centre).
- [ ] It hovers 5 studs up with a 0.35 bob and a 14° lean: nothing may clip.
- [ ] Painted MeshParts stay opaque: a SurfaceAppearance with a fully transparent ColorMap
      can't be detected by the guard and would look invisible.

**Stations** (§4.2–§4.3)
- [ ] Pivot = top of the station tile.
- [ ] Neon only for state (charger rings cyan, factory biofluid `#4DFFB0`), never decoration.
