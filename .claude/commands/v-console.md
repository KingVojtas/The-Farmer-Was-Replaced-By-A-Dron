---
description: Control Mode letterbox / reticle
---

# V-CONSOLE

THIS TASK ONLY. ControlModeController + lighting/HUD. Don't change zone detection. Don't lock the mouse. No shooter crosshair.

ENTER (existing camera tween): 24px letterbox bars #0B0F15 (don't cover HUD). FOV 70→55, restore on leave. Faint 32px grid reticle ImageTransparency 0.85 only while terminal is collapsed.

WHILE CONTROLLING: hide OTHER players' characters (LocalTransparencyModifier=1). Keep their drones visible. Optional Contrast +0.04.

LEAVE: reverse letterbox, FOV, reticle.
