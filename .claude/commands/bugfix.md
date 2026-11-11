---
description: BUGFIX — fix every bug in docs/BUGS.md (P0 → P3), tests for each, then audit the rest of the client
---

# /bugfix: fix the audited bugs

You are a senior Roblox/Luau engineer working in the repo **The Farmer Was Replaced By A Dron**,
a Rojo project inspired by "The Farmer Was Replaced". Players program a farming drone in a
Python-like language. The server parses it into an AST with its own parser (never
`loadstring`), walks it with its own interpreter, and moves the drone's authoritative state.
Clients only render.

Your job: fix **every** bug in `docs/BUGS.md`, in severity order, with a test or a written
Studio check for each one, and do **not** break anything else. You may be Claude, Grok or any
other agent. This file is self-contained.

## Read first (in this order, before touching code)

1. `CLAUDE.md`: the project rules. Never open `docs/archive/CLAUDE_PROMPTS.md`.
2. `docs/BUGS.md`: the bug list with file:line, repro and fix direction. It is your spec.
3. `docs/ARCHITECTURE.md` §1 to §5: how the runtime, data and remotes fit together. Parts of
   it are out of date; BUG-15 lists which.
4. The files each bug names. Read them, don't guess. Line numbers refer to commit `67f1388`
   plus the uncommitted working tree, so they may shift by a few lines.

## Hard rules (break one and the fix is rejected)

- **Never trust the client.** The client sends only raw source strings, slot numbers and
  enum-validated ids. The server re-parses with `Shared/DroneScript/Parser` and gates every
  feature with `Tech.isFeatureUnlocked` built from the **saved** `techUnlocks`. No `loadstring`
  and no `require` of client text.
- `import` and `simulate()` read **saved** script slots, never text from the client.
- **The interpreter is async and never times out.** It yields through `task.wait`, and every
  drone action waits its duration. **Failed actions still take time.** The limp-home rule
  stays: an empty battery can still crawl home.
- **One run per player** (`DroneRuntime/RunGate`). Never two LiveWorlds on one drone.
- **Data:** session-locked `SessionStore`. Currencies, unlocks, scripts, field, cosmetics and
  receipts live in one record. Transactions never yield between validation and mutation.
- **Receipts:** grant + PurchaseId, then `SaveAsync`, and only then `PurchaseGranted`.
  Otherwise `NotProcessedYet`.
- **Drone movement:** the server never moves parts. It publishes `DroneMoveTime`, then
  `DroneX`/`DroneY` (numbers), then `Drone` (Vector3), then `DroneSerial`, then fires
  `DroneMoved`. Clients tween anchored parts (TweenService on value objects, plus one
  RenderStepped `BulkMoveTo`). No physics movers. Your own plot is always LOD NEAR. Never
  revert to a Vector2-only `Drone`.
- No new remotes unless a bug's fix direction allows it. Extending an existing payload (for
  example adding a serial to `DroneMoved`) is fine; update `RemoteSchema`'s comment.
- **Don't change** `GameConfig.Drone.ActionTimes`, economy numbers, the Tech Tree hierarchy
  (`tests/spec/TechTree.spec.luau` pins it and needs the user's sign-off), or any art or visual
  design. Add new config keys instead of retuning existing ones.
- Extend existing modules. No second renderer, interpreter or data layer.
- Don't commit, push or open PRs unless the user tells you to. Leave changes in the working
  tree.

## Order of work

Do one bug at a time: read → fix → test → verify → one line in your log → next bug.

**Phase 1 — P0**
- **BUG-01** `simulate()` zero-time DoS. Required: (a) a minimum real duration per call on the
  live world (a new `GameConfig.Simulate` key, for example `MinRealSeconds = 1`); (b) cache the
  compiled program per run by slot + source; (c) inner steps count toward the outer CPU
  throttle, or the inner run yields on a shared budget; (d) no `ScriptStatus "line"` flood
  (skip it for `simulate`, or rate-limit "line" per player). Add a Lune spec that drives a
  `while True: simulate(...)` loop and asserts a bounded call rate and a single compile.

**Phase 2 — P1**
- **BUG-02** field snapshot on leave: make it independent of `PlayerRemoving` handler order.
  Test the sequencing (a pure helper or an injected-order spec).
- **BUG-03** editor before load: lock the editor, saves, RUN and snippets until `GetScripts`
  succeeds; retry with backoff (respect 0.2/s); show the status.
- **BUG-04** FIX-DRONE: fix BUG-05 and BUG-06 (phase 3) first, then write down the exact
  Studio Verify steps from `.claude/commands/fix-drone.md` for the user. You can't run Studio;
  say so.

**Phase 3 — P2:** BUG-05 (serial ordering, `DroneMoved` payload + client), BUG-06, BUG-07
(per-load lock token + spec), BUG-08 (`loadingCount` in `onClose`), BUG-09, BUG-10 (unload in
`charge()` and/or on plot create + spec), BUG-11 (publish dig exhaustion, keep `FieldSave`
backward compatible; if you add a field, bump nothing unless a migration is needed and test
`Sanitize`), BUG-12 (FOV tween handle + snap), BUG-13 (cooldown / message).

**Phase 4 — P3:** BUG-14 (`.gitattributes`; renormalize only if the user agrees, because it
touches every file), BUG-15 (fix each doc line listed), BUG-16, BUG-17 (keep one Tab path; flag
it for a Studio check), BUG-18 (don't commit; list what the user must check in Studio).

**Phase 5 — audit what wasn't audited.** `docs/BUGS.md` "How this audit was done" lists the
client files nobody has read line by line. Read them: `HudController`, `CurrencyHudController`,
`TechTreeController`, `MainMenuController`, `TutorialController`, `WeatherFxController`,
`LightingController`, `NotifyController`, `UI/*`, `Visuals/PlotDressing`, `Visuals/SoilLook`,
and the crop/FX half of `PlotRenderer`. Look for leaked connections and tweens on rebuilds,
camera ownership fights (MainMenu vs Control Mode), UI that acts before `DataLoaded`, infinite
tweens on MID/FAR plots, particle budget (≤ 40) or "PointLight per tile" violations, and
`nil` shown to the player. Add new findings to `docs/BUGS.md` as BUG-19 onward, in the same
format. Fix the P0/P1 ones with tests; only list the rest.

## Verify after every bug (all must pass)

```bash
lune run tests/run                          # must stay green; add specs, never delete them
stylua --check src tests                    # run `stylua src tests` if it fails
selene src
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=build/globalTypes.None.d.luau --sourcemap=sourcemap.json --flag:LuauSolverV2=false src
rojo build default.project.json -o build/DroneFarm.rbxlx
```

Client-only fixes can't be unit-tested in Lune (the loader only loads pure modules). For those,
move the logic into a pure `Shared/Util` module and test that (as `DroneSignals` and
`PlotFraming` already do), or write the exact Studio steps.

## What to report at the end

For every bug: `BUG-xx: fixed | partly | skipped | needs Studio` + files changed + how you
verified it (spec name or Studio steps) + the reason if it was skipped. Then the new Phase 5
findings, then one Studio playtest checklist that covers every "needs Studio" item. Update
`docs/BUGS.md`: mark each entry **FIXED (date)** or leave it open with a note. Don't delete
entries.
