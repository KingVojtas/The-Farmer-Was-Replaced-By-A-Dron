---
description: ANIM-8 weather rhythm
---

# ANIM-8 — weather has a beat

THIS TASK ONLY. Visual. Do **not** change `WeatherService` growth numbers, rain soak, or durations.

`WeatherFxController` + `LightingController:SetProfile`. 1.5 s look transitions already exist.

1. **Rain** — existing plot-sized rain plate stays. Make drop speed / rate ease in over 0.6 s when weather becomes Rainy (don’t pop the emitter to full). Splashes stay max 3. Wind from ANIM-3 already leans crops; don’t add a second sway system.
2. **Drought** — existing straw tint + dust. Add a slow ColorCorrection brightness breathe ±0.02, 4 s Sine InOut reversing, only while Drought and Control Mode (or within 120 studs). Cancel on Sunny/Rainy.
3. **Sunny** — no extra particles. If a drought/rain breathe tween is running, kill it.
4. Particles still off when not Control Mode **and** >120 studs from own plot.

**Verify:** force / wait Rainy: rain fades up, crops lean (ANIM-3), HUD chip cool. Drought: dust + faint brightness pulse, crops almost still. Back to Sunny: pulse gone, lighting back to V1 baseline in ~1.5 s.
