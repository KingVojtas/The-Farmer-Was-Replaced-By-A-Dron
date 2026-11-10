# Claude

Do **one** task per turn. Never open `docs/CLAUDE_PROMPTS.md` (deprecated).

## How the user starts a task

They type a **slash command** (Claude Code) or `@` a file in `.claude/commands/`.

| They type | You do |
|---|---|
| `/art` | ART MODE. Read `.claude/commands/art.md` and run the whole graphics pack (art-1 → art-8) in order |
| `/art-1` … `/art-8` | one graphics step |
| `/anim` | ANIM MODE. Read `.claude/commands/anim.md` and run the whole motion pack (anim-1 → anim-8) in order |
| `/anim-1` … `/anim-8` | one motion step |
| `/fable` | Fable 5.2 **full pack**: look + motion HTML + Blender drone/crops/stations + timing. Does not edit `src/` |
| `/fable-1` … `/fable-5` | one Fable step if they split the pack |
| `/fix-drone` | P0: drone must hop with the terminal (`DroneMoved` + attributes) |
| `/fix` | whole remaining pass: drone → g1–g6 → art → anim |
| `/bug-drone` | visibility only (hull on screen) |
| `/g1` `/g2` `/v1` `/fg-hud` … | same |
| a bare id like `BUG-DRONE` | Read `.claude/commands/bug-drone.md` and execute **only** that file |

If the message is only an id, map it: `G1` → `g1.md`, `FG-HUD` → `fg-hud.md`, `V-CONTACT` → `v-contact.md`, `BUG-DRONE` → `bug-drone.md`.

## Hard rules

- No `loadstring`. AST + whitelist builtins.
- `import` / `simulate` read saved slots.
- Tech gates use saved `techUnlocks`.
- Client tweens drones from `DroneMoved` + `DroneX`/`DroneY`/`Drone`; server never moves parts.
- Failed actions still take time. Limp-home stays.
- Receipts: grant + PurchaseId, `SaveAsync`, then `PurchaseGranted`.
- ForgeGUI = PNG **slices**, never a full-screen screenshot as one ImageLabel.
- Gameplay/parser/economy changes: `lune run tests/run`.
- Reply: files changed, how verified, what you skipped.
