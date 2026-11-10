---
description: ART-8 ForgeGUI icon atlas — pause if no PNG
---

# ART-8 — ForgeGUI icons

`IconConfig.luau` + `Icon.luau`. ONE atlas, `ImageRectOffset` per key. Fallback = current letter glyphs. Never 30 unique TextureIds. Never a full-screen screenshot ImageLabel.

## If the user has not dropped a PNG

`PAUSE FOR USER`. Print this ForgeGUI prompt for them (GUI or Image, 1024 atlas, 8×4 of 128px, transparent):

> Icon atlas, 8x4 grid, 128px cells, transparent background, isometric low-poly, slightly rounded, dark outline 4px, farm-tech. Icons in order row-major: hay, wheat, carrot, wood, sunflower, pumpkin, cactus, fossil, biomass, biofuel, lithium battery, loops, grid, water tank, print, speed, clock, simulate, cargo, paint, hat, math, list, function, dictionary, random, import, sunny, rainy, drought, charger, factory, drone. Palette lime #7FD962 cyan #66CCFF gold #E8C45C orange #F08030. No letters on the icons, no photoreal, no UI chrome.

Then stop the ART chain. When they drop the PNG / rbxassetid, they run `/art-8` again.

## If a PNG or asset id is in the chat / repo

Wire `IconConfig` so HUD currency tiles, Tech Tree card icons, weather chip, and dock buttons use the atlas. Missing keys keep glyphs.

**Verify:** at least weather + one currency icon render from the atlas; the game still runs with atlas missing.
