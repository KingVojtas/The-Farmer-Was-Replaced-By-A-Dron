---
description: One icon atlas for HUD / tech / weather
---

# FG-ICONS

THIS TASK ONLY. IconConfig.luau + Icon.luau. ONE atlas texture, ImageRectOffset per key. Not 30 unique TextureIds.

Keys: hay wheat carrot wood sunflower pumpkin cactus fossil biomass biofuel batteries loops grid water print speed clock simulate cargo paint hat math lists functions dicts random import sunny rainy drought charger factory drone.

Fallback: current letter glyphs if an id is missing. HUD, Tech Tree, weather chip, dock all read IconConfig.

If the user attached a 1024 atlas PNG, wire it. If not, keep glyphs and document the rect grid for when it arrives.
