---
description: ForgeGUI HUD kit implemented in Theme/HUD
---

# FG-HUD

THIS TASK ONLY. Rebuild HUD in Theme.luau + HudController + CurrencyHudController. NEVER parent a full-screen ForgeGUI screenshot as one ImageLabel. Text and numbers stay real instances.

If the user attached PNGs, use them as slices (icons, 9-slice, buttons). If not, match this look with Theme tokens.

ForgeGUI prompt (user generates this if they want PNGs):

> Roblox ScreenGui HUD mockup for a sci-fi farm-drone programming game, 1920x1080, dark mission-control. Top-left MENU ghost + gold boost timers. Top-centre 470x44 status bar: weather + battery lime + water cyan + cargo amber. Top-right currency stack 210px, rows 30px, glyph tiles. Bottom-right dock TECH TREE lime, SHOP gold, HANGAR cyan. Empty centre for 3D farm. Palette #0B0F15 #131921 lime #7FD962 cyan #66CCFF gold #FFD666 red #FF6B6B. 10px corners, 1px #30404C borders, Builder Sans. No cartoon, no mascot, no hearts, no inventory. Centre 60% empty.

Implement: 1px stroke, Radius.M, BackgroundTransparency 0.06. Segmented battery 5 cells. Low battery <15% red pulse. Dock 48px hover 1.04 press 0.97. Don't restyle Tech Tree or Terminal.
