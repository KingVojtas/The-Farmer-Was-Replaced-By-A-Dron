---
description: FABLE MODE — full pack (look, motion, drone, crops, stations, timing)
---

# /fable — everything

You are **Claude Fable 5.2**. Run the **whole** visual pack in this turn-sequence. Do not wait for “next”.

You are not the Roblox renderer. Do not edit `src/`. In-game motion stays `PlotRenderer` + TweenService + `BulkMoveTo`. ART_BIBLE: no armature, no baked AnimationClip.

If you are not Fable, say so in one line and still run the pack.

Prefer `/effort medium` if the user set it. Still finish every file below.

## Run in order

0. **Farm look** — `art/fable/look.html`  
   One self-contained HTML. `seek(t)` paints the frame. Slider + play both call `seek`.  
   Control Mode bird’s-eye (FOV ~55), 3×3, pitch 6.4, charger (0,−1), factory (1,−1), walkway, fence. Drone hops `move_up` on a 0.34 s loop (takeoff, 14° lean, faster rotors, settle). One wheat ready, one watered tile. Palette: hull `#1E2530`, grass `#4E6B3A`, dry `#A98258`, lime `#7FD962`, cyan `#3CDCFF`, gold `#FFD666`, chrome `#0B0F15`. Neon only on eye, battery strip, charger pad. This file is the graphic — it must look like the game.

1. `.claude/commands/fable-1.md` — all HTML motion loops in `art/fable/motion/`
2. `.claude/commands/fable-2.md` — Blender drone
3. `.claude/commands/fable-3.md` — Blender crops (all cropIds × sprout/growing/ready)
4. `.claude/commands/fable-4.md` — Blender charger + factory
5. `.claude/commands/fable-5.md` — `art/fable/MOTION.md` timing sheet for `/anim`

After each: one line `FABLE-n done:` + files. Then immediately the next.

If Blender is missing: still write every `.py`, print the exact `blender -b -P …` command, continue.

## Hard rules

- Write under `art/fable/` and `tools/blender/` only. No Three.js in `src/`.
- Meshes: names and pivots from `docs/ART_BIBLE.md` + `assets/README.md`.
- FBX: Forward **−Z**, Up **Y**, 1 BU = 1 stud, triangulate, **no armature, no animation**.
- Timing fits `GameConfig.Drone.ActionTimes` × `TweenFraction` 0.85 (hop 0.34 s).
- Do not touch parser, economy, remotes, `GridService` (`Drone` = Vector3, `DroneSerial`).

When the pack finishes: list every file, which `blender -b -P` to run, and that Studio import is ART_BIBLE §5.6. Next coding-model session: `/anim` using `art/fable/MOTION.md`.
