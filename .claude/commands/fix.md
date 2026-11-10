---
description: Fix the whole game — drone, systems, graphics, animation
---

# /fix — make the game playable and look like the bible

You are in the Roblox repo **The Farmer Was Replaced By A Dron**. Isolated plots. Custom language (Parser AST, **no loadstring**) drives a farming drone on the server. The client tweens from plot attributes **and** `DroneMoved`.

This command is the **whole remaining product pass**: movement, systems, graphics, motion. Execute the phases **in order**. After each phase: `PHASE n done:` + files + how verified. Then immediately the next.

**Stop the chain** if a phase’s Verify fails. Tell the user exactly what to Playtest and which command to re-run (`/fix-drone`, `/g2`, `/art-4`, …). Do not skip ahead.

Fable 5.2 (`/fable`) is **off**. Meshes stay procedural unless `ReplicatedStorage.Assets` already has a real visible model. Do not write Three.js into `src/`.

## Hard rules (every phase)

- No `loadstring`. AST + whitelist builtins. `import` / `simulate` read saved slots. Tech gates use saved `techUnlocks`.
- Server never moves drone parts. Failed actions still take time. Limp-home stays.
- Receipts: grant + PurchaseId, `SaveAsync`, then `PurchaseGranted`.
- ForgeGUI = PNG **slices**, never a full-screen screenshot as one ImageLabel.
- Own plot always LOD NEAR. No infinite tweens on MID/FAR. No PointLight per tile. Particle budget ≤ 40.
- `DroneX`/`DroneY` numbers + `Drone` Vector3 + `DroneSerial` + **`DroneMoved` remote**. Do not revert to Vector2-only.
- Gameplay/parser/economy: `lune run tests/run`.
- Extend existing modules (`PlotRenderer`, `AssetLibrary`, `LightingController`, `WeatherFxController`, `Theme`, `Fade`, `TerminalView`). No second renderer, no second interpreter.

Read once (do not rewrite from memory): `docs/ARCHITECTURE.md`, `docs/ART_BIBLE.md` §1 and §4, `docs/UI_UX_GUIDE.md` (UI phases), `src/shared/Config/GameConfig.luau`.

---

## PHASE 0 — drone flies with the console  (P0)

Read and execute **`.claude/commands/fix-drone.md`** in full.

**Bar:** starter `RUN` → drone hops every `move_*` in time with the lime line, lands on charger. Invisible or frozen drone = stop here.

---

## PHASE 1 — systems so the game is fair  (P0/P1)

Execute each file fully, tests after each:

1. `.claude/commands/g1.md` — one interpreter per drone (mutex, `task.cancel`, no 3s overlap)
2. `.claude/commands/g2.md` — fossils nerf, hay out of factory biomass
3. `.claude/commands/g3.md` — plot Zone, guests out, Control Mode body hidden
4. `.claude/commands/g4.md` — real tutorial (server steps, insert snippets, `print` free)
5. `.claude/commands/g5.md` — pumpkin only ready as 2×2
6. `.claude/commands/g6.md` — Variables with Loops, tile save, per-plot weather

Do not invent a Blocks editor, trading, or campaign.

**Bar:** `lune run tests/run` green. Two rapid RUNs cannot dupe cargo. `while True: dig()` is not the best farm.

---

## PHASE 2 — graphics  (looks like ART_BIBLE from Control Mode)

Execute `.claude/commands/art.md` (art-1 → art-8). If art-8 pauses for a PNG, skip the atlas and continue; do not stall the chain on ForgeGUI.

If `art.md` overlaps work already done, **upgrade** it, do not duplicate folders.

Must be true when Phase 2 ends:

| Surface | Bar |
|---|---|
| Lighting | ART_BIBLE §1.5 (Technology Future, ClockTime 14.5, Atmosphere, Bloom). `LightingController` |
| Drone | Dark hull `#1E2530`, ceramic visor, **one neon eye on −Z**, 4 `Rotor*`, battery strip. Hover ~5, bob 0.35, tilt 14°. Visible-mesh guard |
| Crops | Ready = **colour + silhouette** (wheat droop, carrot shoulder, sunflower disc, pumpkin squash, cactus pink ball). Opaque, ≤8 parts/tile, CastShadow false on sprouts/grass |
| Soil | empty → Dry, planted → Tilled, Watered → Wet. MaterialVariants if present |
| Plot kit | Walkway y=−2, low fence gaps at stations, sign; VIP = gold trim not `"[VIP]"` text. Client dressing, CanCollide false |
| Stations | Charger cyan rings only while drone on pad; factory biofluid slit only while working. Neon = state |
| FX | Plant seed-drop, grow pop, ready lime ping, harvest bits, water droplets. Own NEAR. Pool, `Emit`, Enabled false |
| Ghost / limp | Last 16 field cells lime dots; battery eye lime/amber/red; long `DroneMoveTime` = limp |
| LOD | Own always NEAR. MID snap, no particles. FAR **destroy** visuals |
| HUD | Theme tokens, 1px stroke, segmented battery, dock hover. No new panels in this phase |

Palette: lime `#7FD962` grow, cyan `#66CCFF` tech, gold `#FFD666` featured, hull `#1E2530`, grass `#4E6B3A`.

**Bar:** Control Mode, terminal collapsed: you can tell crop type, wet vs dry, charger vs factory, and that the program is running, without reading the HUD.

---

## PHASE 3 — animation  (the farm feels alive)

Execute `.claude/commands/anim.md` (anim-1 → anim-8).

Do not change `ActionTimes`. Keep `DroneMoved` as the movement trigger. Compose into existing NumberValues / CFrameValue.

Must be true when Phase 3 ends:

| Motion | Bar |
|---|---|
| Flight | Takeoff +0.25 Y, 14° pitch / ~8° roll, rotors faster while moving, charger land hover 5→~1.6 |
| Poses | plant dip, water yaw + cyan flash, ripe harvest scoop. Infer `DroneSignals.action`. Wrong pose worse than none |
| Growth | Scale eases between 0.1 Progress ticks. Rain lean more, drought almost still. Max 36 own-plot sways |
| Cargo | Cargo drop on charger → bits toward sign; factory → hopper + chimney |
| Terminal | Lime line **slides** with `ScriptStatus "line"`; RUN header bar; output fade-in; error shakes **frame** 7px not camera |
| UI | Tech/Shop/Hangar Fade + UIScale 0.96→1. Toasts slide. Tutorial bob. Unlock card ping once. No CanvasGroup on the terminal |
| Stations | Pad punch on land, rings faster while charging; factory hopper jitter + smoke only on cargo drop |
| Weather | Rain eases in; drought brightness breathe ±0.02; 1.5s lighting profiles. Visual only |

**Bar:** `while True` snake on 3×3 is readable from 20 studs: hops, ghost trail, terminal line, battery strip.

---

## PHASE 4 — UI juice already specified  (only if still missing)

If Phase 2/3 did not cover them, execute in order (skip any already done):

- `.claude/commands/v9.md` — HUD/terminal juice
- `.claude/commands/v-console.md` — Control Mode letterbox
- `.claude/commands/v-contact.md` — shadow, rotor wash, height beam

Do **not** run `/fg-*` unless the user dropped ForgeGUI PNGs in the chat. If no PNGs, keep Theme procedural chrome.

---

## Done

Print:

1. Phases completed / stopped
2. Files changed (grouped by phase)
3. `lune run tests/run` result
4. What the user must Playtest in Studio (starter RUN, wheat cycle, Tech Tree open, rain if possible)
5. What is still procedural vs waiting on `assets/` FBX or ForgeGUI atlas

If you had to skip a phase, name the command to run next. Do not claim the drone flies unless Phase 0 Verify passed in code **and** you listed the Studio check.
