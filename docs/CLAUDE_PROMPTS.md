# Prompt pack — index only

The long catalog is gone. Each task is a **Claude Code slash command** in `.claude/commands/`.

**Graphics pack (one command):**

```
/art
```

That turns ART MODE on and runs `art-1` → `art-8`. Single step: `/art-1` … `/art-8`.

**Motion pack (one command):**

```
/anim
```

That turns ANIM MODE on and runs `anim-1` → `anim-8` (flight, poses, growth, cargo, terminal, UI, stations, weather). Single step: `/anim-1` … `/anim-8`.

**Fable 5.2 (full pack):**

```
/model fable
/effort medium
/fable
```

Look HTML + all motion loops + Blender drone, crops, stations + `MOTION.md`. Then Studio FBX import. `/anim` on a coding model.

**Fix the drone (P0 — visible but not flying):**

```
/fix-drone
```

**Fix the whole game (drone → systems → graphics → animation):**

```
/fix
```

If `/fix` is too big for one session, run `/fix-drone` first, then `/g1` … `/g6`, then `/art`, then `/anim`.

Do not paste this index. Do not ask Claude to “read CLAUDE_PROMPTS.md”.

| Command | What |
|---|---|
| `/ctx` | Read architecture. No code |
| `/fix-drone` | **P0** drone hops with the terminal |
| `/fix` | **full pass** drone + g1–g6 + art + anim |
| `/bug-drone` | **P0** invisible drone |
| `/g1` | Interpreter mutex |
| `/g2` | Fossils + hay economy |
| `/g3` | Plot griefing |
| `/g4` | Tutorial |
| `/g5` | Pumpkin 2×2 |
| `/g6` | Variables, tile save, per-plot weather |
| `/anim` | **Motion pack** (anim-1 → anim-8) |
| `/anim-1` … `/anim-8` | flight / poses / growth / cargo / terminal / UI / stations / weather |
| `/fable` | Fable 5.2 **full pack** (look, loops, drone, crops, stations, timing) |
| `/fable-1` … `/fable-5` | studies / drone / crops / stations / timing — **one per message** |
| `/v1` … `/v11` | Visual pack A |
| `/fg-hud` `/fg-term` `/fg-tech` `/fg-shop` `/fg-icons` `/fg-thumb` `/fg-drone3d` | ForgeGUI |
| `/v-contact` | Shadow / rotor wash |
| `/v-console` | Control Mode letterbox |

Order: `/fix-drone` → `/g1` → `/g2`… then `/art` → `/anim`. Or one shot `/fix`. Never `/fg-drone3d` before the drone hops.

If slash commands do not appear: restart Claude Code in this folder, or `@.claude/commands/bug-drone.md` and say “do this file only”.
