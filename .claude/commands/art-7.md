---
description: ART-7 Assets folder + mesh guard
---

# ART-7 — make dropping real meshes safe

`AssetLibrary` + Rojo. Do **not** invent new paths. Contract is already in the module comment.

1. Ensure a Rojo-friendly folder exists for assets if the project can hold it (e.g. `assets/` synced to `ReplicatedStorage.Assets`, **or** document that artists drop into Studio `ReplicatedStorage.Assets` because `default.project.json` doesn’t map it). Prefer a real `assets/README.md` with the checklist already in `AssetLibrary`.
2. Harden `cloneModel`: reject models with 0 visible parts (same rule as ART-1). Log once: `[AssetLibrary] ignored broken Drone`.
3. After clone: `makeInert`, `CollisionFidelity` Box on MeshParts if present, `CastShadow false` on crop sprout/grass.
4. Don’t add placeholder empty Models named `Drone` — an empty Model is what made the drone invisible.

**Verify:** with **no** `ReplicatedStorage.Assets.Drone`, procedural drone still shows. With a broken empty Model named Drone, procedural still shows.
