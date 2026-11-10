---
description: ART MODE — run the whole graphics/asset pack in order
---

# /art — ART MODE ON

You are now in **ART MODE** for this conversation. Gameplay (`/g1`–`/g6`) is off-limits. Parser, economy, tech tree data, remotes: do not touch.

## What you do right now

Read and execute these files **in order, in this same turn-sequence**, without waiting for the user to say “next”:

1. `.claude/commands/art-1.md` — drone visible + hero silhouette
2. `.claude/commands/art-2.md` — crop silhouettes
3. `.claude/commands/art-3.md` — soil + plot dressing
4. `.claude/commands/art-4.md` — plant / grow / harvest / water FX
5. `.claude/commands/art-5.md` — drone ghost, shadow, battery, rotor wash
6. `.claude/commands/art-6.md` — charger + factory
7. `.claude/commands/art-7.md` — Assets folder + visible-mesh guard
8. `.claude/commands/art-8.md` — ForgeGUI icon atlas (pause if no PNG)

After each file: one line `ART-n done:` + what changed. Then immediately start the next.

**Stop the chain** only if Verify on that file fails, or the file says `PAUSE FOR USER`. Then tell the user exactly what to generate/drop and which command to run (`/art-8`).

## Hard rules

- Client visuals only unless a file says otherwise.
- `AssetLibrary.makeInert` on every cloned asset.
- Own plot stays LOD NEAR. Don’t add infinite tweens on MID/FAR.
- No PointLight per tile. No full-screen ForgeGUI screenshot as one ImageLabel.
- Existing modules: `LightingController`, `WeatherFxController`, `PlotDressing`, `SoilLook`, `PlotRenderer`, `AssetLibrary`. Extend them. Don’t create a second renderer.
- `docs/ART_BIBLE.md` is the look. Palette: lime `#7FD962` grow, cyan `#66CCFF` tech, gold `#FFD666` featured, hull `#1E2530`.

When the pack finishes (or pauses), list: files changed, what is still procedural, what the user must generate in ForgeGUI.
