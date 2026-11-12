# Bug audit (2026-11-11)

Input for `/bugfix` (`.claude/commands/bugfix.md`). Every entry has an id, a severity, a
confidence level, where the bug is (`file:line` at commit `67f1388` plus the uncommitted working
tree), how to reproduce it, and the direction for a fix.

## How this audit was done

* Automated checks, all green: `lune run tests/run` (280/280), `selene src` (0/0/0),
  `stylua --check src tests` (clean), `luau-lsp analyze` (no errors), `rojo build` (builds).
  None of the bugs below is caught by them.
* Read in full: everything in `src/server` and `src/shared/DroneScript`, `Net`, `Config`
  (GameConfig, TechTree hierarchy), `Progression/Tech`.
* Read in part: the drone movement path in `PlotRenderer`, plus `TerminalController`,
  `ControlModeController` (transitions + V-CONSOLE diff), `ShopController` (purchase flow),
  `Net`, `AssetLibrary` and `PlotSpace`.
* **Not audited line by line:** `HudController`, `CurrencyHudController` (except the diff),
  `TechTreeController`, `MainMenuController`, `TutorialController`, `WeatherFxController`,
  `LightingController`, `NotifyController`, `UI/*`, `PlotDressing`, `SoilLook`, and the crop/FX
  half of `PlotRenderer`. `/bugfix` phase 5 covers them (all read by 2026-11-12, see
  "Phase 5 findings").
* Not run in Roblox Studio. Anything that depends on engine behaviour is marked PLAUSIBLE.

Severity: **P0** = a live server can break or be abused · **P1** = data loss or a broken core
loop · **P2** = wrong behaviour that players will notice · **P3** = hygiene / docs / tooling.
Confidence: **CONFIRMED** = proven from the code (or measured) · **PLAUSIBLE** = needs a Studio
check.

## Summary

| ID | Sev | Conf | Status | One line |
|---|---|---|---|---|
| BUG-01 | P0 | CONFIRMED | FIXED (2026-11-11) | `simulate()` is a zero-time "action": one player can freeze the server (≈3.6 s of CPU per second) and flood remotes |
| BUG-02 | P1 | CONFIRMED (race) | FIXED (2026-11-11) | On leave, the field snapshot depends on the order of the `PlayerRemoving` handlers, so the last ≤90 s of field changes can be lost |
| BUG-03 | P1 | CONFIRMED | FIXED (2026-11-11), needs Studio | The terminal can autosave or RUN before the saved scripts load, which overwrites the player's saved slot |
| BUG-04 | P1 | OPEN | OPEN, needs Studio (BUG-05/06 fixed) | FIX-DRONE: the drone hop is still unverified in Studio (the contract is coded; BUG-05/06 are candidate causes) |
| BUG-05 | P2 | PLAUSIBLE | FIXED (2026-11-11), needs Studio | The render-loop poll and the `DroneMoved` remote have no ordering (no serial), so a lagging attribute can tween the drone back |
| BUG-06 | P2 | CONFIRMED | FIXED (2026-11-11) | `lastMoved[plotIndex]` is never cleared; a new owner of a reused plot index starts at the old owner's cell |
| BUG-07 | P2 | CONFIRMED (rare) | FIXED (2026-11-11) | Session lock is per server, not per load: a same-server rejoin after a slow release can load stale data and then get kicked |
| BUG-08 | P2 | CONFIRMED (rare) | FIXED (2026-11-11), needs Studio | BindToClose doesn't wait for loads still in flight, so their lock is left for 300 s ("still being saved" kicks) |
| BUG-09 | P2 | CONFIRMED | FIXED (2026-11-11) | `refine()` spends battery but never publishes it (HUD and drone strip go stale) |
| BUG-10 | P2 | CONFIRMED | FIXED (2026-11-11) | Cargo already aboard while the drone sits on the charger (rejoin) is not banked; `charge()` doesn't unload |
| BUG-11 | P2 | CONFIRMED | FIXED (2026-11-11); the 'dug' look is for /assets | Dig exhaustion is invisible to clients and isn't saved (a rejoin clears it) |
| BUG-12 | P2 | CONFIRMED | FIXED (2026-11-11), needs Studio | Control Mode FOV drifts: the exit FOV tween (1.1 s) outlives the exit (0.9 s); re-entering saves a mid-tween FOV |
| BUG-13 | P2 | CONFIRMED | FIXED (2026-11-11) | Client RUN cooldown (1.2 s) is shorter than the server bucket allows; spam shows "Couldn't reach the server (Rejected)" |
| BUG-14 | P3 | CONFIRMED | FIXED (2026-11-11) | No `.gitattributes` while `core.autocrlf=true` and StyLua demands LF; fresh clones fail `stylua --check` |
| BUG-15 | P3 | CONFIRMED | FIXED (2026-11-11); AtlasOrder is left to /assets | Docs and comments drifted from the code (test count, gates, schema version, leaderstats, dig rule, field saving) |
| BUG-16 | P3 | CONFIRMED | FIXED (2026-11-11) | `GridService:PlantTile` passes the hub weather into an unused parameter (dead code that misleads readers) |
| BUG-17 | P3 | PLAUSIBLE | FIXED (2026-11-11), needs Studio | Tab may indent twice if the TextBox inserts `\t` itself (InputBegan adds 4 spaces, and the tab is also converted) |
| BUG-18 | P3 | CONFIRMED | OPEN, needs Studio (committed in `1ffb8b7`) | 5 client files carry Studio-unverified work (V-CONSOLE, height beam, segmented battery) |
| BUG-19 | P3 | PLAUSIBLE | FIXED (2026-11-12) | `SoilLook.colorTweens` is weak-keyed, but each Tween value references its tile, so departed plots' tiles may never be freed |
| BUG-20 | P3 | CONFIRMED | FIXED (2026-11-12), needs Studio | The Tech Tree's max-tier star glow (endless tween) keeps running after the panel closes |
| BUG-21 | P3 | CONFIRMED (latent) | FIXED (2026-11-12) | A Fade that captures an object before its 9-slice skin lands later restores the flat background and the hidden text |
| BUG-22 | P3 | CONFIRMED | OPEN (listed only) | `pingCard` restores a stroke it captured mid-tween: a quick second unlock or card click leaves a wrong outline |
| BUG-23 | P3 | CONFIRMED | OPEN (listed only) | The open Tech Tree rebuilds every card's cost chips on each currency change (instance churn) |
| BUG-24 | P3 | CONFIRMED | OPEN (listed only, design call) | Skinned buttons lose their AutoButtonColor hover / press feedback (background is transparent) |
| BUG-25 | P3 | PLAUSIBLE | OPEN (listed only) | `Components.hover` can stay at 1.04 on touch (no MouseLeave) and after press-drag-release |

Not bugs, but missing content (this is what `/assets` is for): every UI icon is an emoji
fallback (`IconAtlas.assetId = 0`, only `hay` / `wheat` have art), `assets/` contains no models
(drone, crops, stations and hats are all procedural), the game has no sound at all, and every
`MonetizationConfig` id is 0 (the shop shows "COMING SOON").

---

## P0

### BUG-01: `simulate()` costs no real time, so it can be used for CPU and network denial of service

**Status: FIXED (2026-11-11).**

* **Where:** `src/shared/DroneScript/Builtins.luau:258` (`kind = "action"`),
  `src/server/DroneRuntime/DroneAPI.luau:547` (no `world:wait`),
  `src/server/Services/ScriptService.luau:191` (recompiles the slot on every call),
  `src/server/DroneRuntime/Interpreter.luau:657-662` (an action resets `idleSteps` and fires
  `onAction`), `ScriptService.luau:319-321` (`onAction` fires a `ScriptStatus "line"` remote).
* **What happens:** each call compiles the saved slot, builds a SimWorld and runs it. If the
  simulated program never waits (anything without drone actions), the call returns without
  yielding. The outer loop costs about 3 steps per pass. At 2,000 steps/s that is about 666
  calls per second, and every call fires one remote to the client. The inner run's steps don't
  count toward the outer CPU budget, and because `simulate` counts as an action, the
  "stuck loop" guard never trips.
* **Measured:** `Parser.compile` of a 40-line, 3.9 KB slot takes **5.4 ms** (Lune), so 666/s
  is about **3.6 s of server CPU per wall second** from a single player.
* **Repro:** research `simulate`, rename slot 3 to `lab` and fill it with 40 lines of
  `a = 1 + 2 * 3 ...`, then RUN `while True:\n    simulate("lab", 1)`.
* **Fix direction:** (1) make every `simulate()` call cost real time on the live world, for
  example `world:wait(math.max(GameConfig.Simulate.MinRealSeconds, ...))` with a new
  `GameConfig.Simulate` key (leave `Drone.ActionTimes` alone); (2) cache the compiled program
  per run, keyed by slot + source, so a loop compiles once; (3) charge the inner run's steps to
  the outer throttle, or give the inner run a shared step counter; (4) don't fire
  `ScriptStatus "line"` for `simulate`, or rate-limit "line" statuses per player (for example
  at most 20/s). The rule "Failed actions still take time" must hold for simulate too.
* **Test:** a `RunGate`/`DroneWorld`-style spec: a live loop of `simulate` on a trivial slot
  makes at most N calls in T virtual seconds, and the compile counter grows by 1 per run.

## P1

### BUG-02: the field save on leave depends on the order of `PlayerRemoving` handlers

**Status: FIXED (2026-11-11).**

* **Where:** `src/server/Services/DataService.luau:214-222` (`runBeforeSave`, then release),
  `src/server/Services/GridService.luau:563-568` (the before-save hook reads
  `plotsByPlayer[player]` and skips a destroyed plot), `GridService.luau:516-526, 590`
  (`removePlot` is connected to `PlayerRemoving` on its own).
* **What happens:** Roblox doesn't guarantee the order connected handlers run in. If
  `removePlot` runs first, the plot is already gone when DataService's hook runs. The final save
  then carries the field from the last autosave, up to 90 s old: crops planted or harvested
  just before leaving revert on rejoin.
* **Fix direction:** one owner for the leave sequence. Either GridService writes
  `data.field = FieldSave.snapshot(...)` inside `removePlot` before destroying anything
  (`DataService:GetData` still works there), or DataService fires a `ProfileReleasing(player)`
  signal after the hooks and GridService destroys the plot from that signal instead of
  `PlayerRemoving`. Make sure it works in both handler orders.
* **Test:** a pure test of the sequencing helper, plus a Studio check: plant, leave within 5 s,
  rejoin, and the crop is there.

### BUG-03: the editor can save or run before the player's scripts have loaded

**Status: FIXED (2026-11-11), needs Studio.**

* **Where:** `src/client/Controllers/TerminalController.luau:88` (`saveSlot`), `:101`
  (`scheduleAutosave`), `:113` (`onTextChanged`), `:217` (`run`), `:277` (`loadScripts`, 3
  tries and then it gives up), `:377` (`InsertSnippet`). The editor TextBox stays editable the
  whole time.
* **What happens:** typing before `GetScripts` answers schedules `SaveScript(slot 1, text)`,
  which overwrites the saved program. If all 3 `GetScripts` tries fail, the editor stays empty
  but live, and editing or RUN (RunScript also saves the source on the server) destroys the
  saved script. A late load also replaces whatever the player typed.
* **Fix direction:** while `loaded == false`, set `TextEditable = false` and show the status,
  and make `saveSlot`, `run`, `switchSlot` and `InsertSnippet` refuse to act. Retry
  `GetScripts` with backoff until it works (it is rate-limited to 0.2/s, so wait 6 s or more
  between tries), and offer a manual retry.

### BUG-04: FIX-DRONE is still unverified in Studio

**Status: OPEN, needs Studio (BUG-05/06 fixed).**

* `.claude/commands/fix-drone.md` lists the P0 "drone doesn't hop with the terminal". The whole
  contract is in place: `DroneMoveTime`, then `DroneX`/`DroneY`/`Drone`, then `DroneSerial`,
  then `FireAll("DroneMoved")` (`GridService.luau:677-687`); the client listens to the
  attributes, the remote and `ScriptStatus`, and polls NEAR plots every frame
  (`PlotRenderer.luau:3384-3409, 3606-3618, 3744-3790`).
* Nothing could be checked without Studio. BUG-05 and BUG-06 are the remaining code-level
  candidates. Run the Verify list from `fix-drone.md` after fixing them.

## P2

### BUG-05: the render poll and the `DroneMoved` remote can fight each other (PLAUSIBLE)

**Status: FIXED (2026-11-11), needs Studio.**

* **Where:** `PlotRenderer.luau:3606-3618` (each frame, the published attributes win whenever
  they differ from `drone.cell`), `:3744-3790` (the remote sets `drone.cell` from its payload).
  The code itself says "attrs can lag" (`:1009`).
* **What happens:** if the remote arrives before the attribute replication, the next frame's
  poll sees the old cell, tweens back to it, and then forward again. That reads as stutter or
  a missing hop.
* **Fix direction:** order updates by `DroneSerial`. Add the serial to the `DroneMoved`
  payload (server: `FireAll("DroneMoved", index, x, y, duration, serial)`), store
  `drone.serial`, and apply a cell from any source (attribute, poll, remote, ScriptStatus) only
  when its serial is newer. The rule "don't add a remote the schema doesn't list" still holds:
  this only extends an existing payload.

### BUG-06: `lastMoved` is stale when a plot index is reused

**Status: FIXED (2026-11-11).**

* **Where:** `PlotRenderer.luau:1009, 3365, 3749`. Entries are written for every plot (FAR
  ones too) and never removed.
* **What happens:** player A leaves, player B joins and gets the same `Index`, and B's drone is
  snapped to A's last cell for one frame, then hops to the charger.
* **Fix direction:** clear `lastMoved[index]` on `untrackPlot` and on `Plots.ChildRemoved`, or
  key it by `OwnerUserId` + index, or by serial (see BUG-05).

### BUG-07: the session lock belongs to the server, not to the load (rare)

**Status: FIXED (2026-11-11).**

* **Where:** `src/server/Data/SessionStore.luau:298` (a lock with our own `sessionId` is always
  accepted), `src/server/Services/DataService.luau:171-174` (a same-server rejoin waits at most
  `ShutdownTimeout` = 25 s for the old release).
* **What happens:** if the old release takes longer than 25 s (retries with backoff, slow
  DataStore), the new load takes the record before the release writes. The release then
  commits the old data, clears the lock, and the new profile's next save sees no lock: "lost",
  and the player is kicked. The new session also played on pre-release data.
* **Fix direction:** give every load its own lock token (for example a GUID per `LoadAsync`)
  and check that token in `write()` instead of the server's sessionId. DataService waits on
  the release itself, not on a timeout. Add a `SessionStore.spec` case for it.

### BUG-08: BindToClose ignores loads that are still in flight (rare)

**Status: FIXED (2026-11-11), needs Studio.**

* **Where:** `DataService.luau:241-261`. `onClose` only waits on `releasingCount`. A load that
  finishes during shutdown releases itself (`:197-199`), but only if the server is still alive
  by then.
* **What happens:** the lock stays for `LockStaleSeconds` (300 s). A player who rejoins
  elsewhere gets "Your data is still being saved on another server" after 8 × 4 s of retries.
* **Fix direction:** count loads in flight too (a `loadingCount`) and wait for them in
  `onClose` (they release at once because `shuttingDown` is true).

### BUG-09: `refine()` doesn't publish the battery

**Status: FIXED (2026-11-11).**

* **Where:** `src/server/DroneRuntime/DroneAPI.luau:442-473`. It calls `spendEnergy` and
  `world:replicate()`, but never `world:publish()`.
* **Fix:** call `world:publish()` after the refine (as `deposit()` does at `:436`).

### BUG-10: cargo isn't banked when the drone is already on the charger

**Status: FIXED (2026-11-11).**

* **Where:** `DroneAPI.luau:175-178` (unload happens only when a move ARRIVES at the charger),
  `:374-408` (`charge()` doesn't unload), `GridService.luau:372` (a new plot puts the drone on
  the charger while `data.cargo` is saved and may be full).
* **What happens:** after a rejoin with a full hold, `charge()` and other calls keep the hold
  full, and `harvest()` fails with "cargo hold is full" while the drone sits on the silo.
* **Fix direction:** unload in `charge()` too (before charging), and/or once in `createPlot`
  when the profile has cargo.

### BUG-11: dig exhaustion is invisible and resets on rejoin

**Status: FIXED (2026-11-11); the 'dug' look is for /assets.**

* **Where:** `DroneAPI.luau:359` (`Growth.exhaust` changes the tile but nothing publishes it),
  `GridService.luau:163-171` (no `Exhausted` attribute), `FieldSave.luau:187` (restore sets
  `exhausted = 0`), `GameConfig.luau:112` (the comment says "bare soil or wild grass"; the code
  allows bare soil only).
* **Fix direction:** publish a tile attribute (for example `DugUntil = os.time() + seconds`, or
  `Exhausted = true`/`false` on change) and give SoilLook a "dug" look (an `/assets` item).
  Optionally save the remaining seconds in `FieldSave`. Fix the GameConfig comment.

### BUG-12: Control Mode FOV drift (uncommitted V-CONSOLE work)

**Status: FIXED (2026-11-11), needs Studio.**

* **Where:** `src/client/Controllers/ControlModeController.luau:353-383` (`setConsole`: the
  FOV tween uses `CAMERA_EASING` = EnterTime 1.1 s), `:690-720` (exit uses ExitTime 0.9 s), and
  `:637` (`finishExit` sets the state to Exploring while the FOV is still tweening), `:357` (on entry,
  `savedFov` is read from the live camera).
* **What happens:** re-entering within about 0.2 s of the exit landing saves a mid-tween FOV as
  "normal", so the FOV creeps narrower every time. FOV tweens are never cancelled either.
* **Fix direction:** keep a `fovTween` and cancel it on every transition. Tween the exit with
  ExitTime. In `finishExit`, snap the FOV to the remembered default. Remember the default FOV
  once (the first entry, or `StarterPlayer`/camera default) rather than on every entry.

### BUG-13: the RUN button cooldown is shorter than the server rate limit

**Status: FIXED (2026-11-11).**

* **Where:** `TerminalController.luau:37` (`RUN_COOLDOWN = 1.2`) against
  `src/shared/Net/RemoteSchema.luau:255` (`burst = 3, perSecond = 0.5`).
* **What happens:** about the 7th RUN in quick succession is rejected. The terminal then says
  "Couldn't reach the server (Rejected)" and the server logs a violation.
* **Fix direction:** match the client cooldown to the bucket (2 s or more after the burst, or
  mirror the token bucket on the client), and map `"Rejected"` to "Slow down a moment".

## P3

### BUG-14: line endings

**Status: FIXED (2026-11-11).**

`core.autocrlf=true` on this machine, there is no `.gitattributes`, and `stylua.toml` says
`line_endings = "Unix"`. Git already warns "LF will be replaced by CRLF" for 5 files, and a fresh
clone gets CRLF, which fails `stylua --check`. Fix: add `.gitattributes` with
`* text=auto eol=lf` and binary rules (`*.png`, `*.rbxm`, `*.rbxl`, `*.fbx`, `*.blend`), then
renormalize.

### BUG-15: doc and comment drift

**Status: FIXED (2026-11-11); AtlasOrder is left to /assets.**

* `docs/ARCHITECTURE.md:246` says 208 tests (there are 280).
* `docs/ARCHITECTURE.md` §4 gives `variables` its own gate, but `TechTree.luau:90` puts
  `variables` in `loops`. Checklist step 3 ("`a = 2` errors naming Variables") is therefore
  wrong as well.
* `src/server/Data/DataTemplate.luau:5` says "schema version 2" (it is 3).
* `src/server/Services/DataService.luau:26` says leaderstats are "Harvested, Wheat" (they are
  Harvested, Biomass).
* `src/server/Services/GridService.luau:37` says "Tile states live for the session only" (the
  field has been saved since v3).
* `src/shared/Config/GameConfig.luau:112`: the dig comment is wrong (see BUG-11) and sits above
  the `Collision` block.
* The drone's MeshPart budget disagrees: `docs/ART_BIBLE.md` §7 says ≤ 14, while
  `assets/README.md` and the `AssetLibrary` header say ≤ 16. Pick one (the Bible's 14).
* `IconConfig.AtlasOrder` lists 33 of the 59 icon keys, so 26 icons (`energy`, `lock`, `shop`,
  hat icons, ...) can never come from the atlas. That's not a code bug, but `/assets` has to
  extend the order.
* `docs/CLAUDE_PROMPTS.md` is deprecated (CLAUDE.md says never open it) but still tracked:
  delete it or move it to `docs/archive/`.

### BUG-16: dead weather parameter

**Status: FIXED (2026-11-11).**

`GridService.luau:689-692` passes `WeatherService:GetCurrent()` (the hub's weather) into
`Growth.plant`'s unused `_weather` parameter. Remove the parameter from `Growth.plant`,
`SimWorld` and `GridService`, or pass the plot's weather. Right now the code looks like it uses
the wrong weather.

### BUG-17: Tab may indent twice (PLAUSIBLE, check in Studio)

**Status: FIXED (2026-11-11), needs Studio.**

`TerminalController.luau:113-127` converts any `\t` into 4 spaces, and the `InputBegan` Tab
handler (`:311-315`) inserts another 4. If the TextBox inserts `\t` itself, one Tab gives 8
spaces. Check in Studio, then keep exactly one of the two paths.

### BUG-18: uncommitted, unverified client work

**Status: OPEN, needs Studio. Committed in `1ffb8b7` (2026-11-12); only the Studio check is left.**

The working tree held V-CONSOLE (letterbox, FOV, reticle, hiding other players), the
V-CONTACT height beam and the segmented battery HUD in `ControlModeController`,
`CurrencyHudController`, `PlotRenderer`, `TerminalController` and `TerminalView`. They pass
lint and types but have no Studio verification. BUG-12 is inside them. Verify them in Studio,
then let the user decide whether to commit.

## Phase 5 findings (`/bugfix`, 2026-11-11)

Read for this phase: `MainMenuController` + `UIState` (camera ownership vs Control Mode),
`HudController` and `CurrencyHudController` (plot tracking), `TutorialController`,
`WeatherFxController`, `PlotDressing`, `SoilLook`, `NotifyController`, `UI/Icon`, the
`TerminalView` slot tabs and shake, and PlotRenderer's crop destroy / sway / pop paths.
No P0/P1 turned up. Checked and fine: the menu orbit only hands the camera back if it took
it; `UIState` lets only one panel be open; PlotDressing's deferred rebuild stops once its
folder is destroyed; destroyed crops leave the sway list; the tutorial bob only runs while the
terminal is enabled; weather particles have their own caps (the 40-particle budget is for crop
FX). Read on 2026-11-12: `TechTreeController`, `LightingController`, `UI/Components`,
`UI/Fade`, `UI/Theme` (BUG-20 to BUG-25 below). Checked and fine there: the LightingController
profile tweens replace each other per property, the breathe loop only starts from a COMPLETED
ease-in, `adopt` never picks up another controller's effect (no other code makes Lighting
effects), the menu blur is never touched; `Net.invoke` can't throw, so Research's `busy` always
clears; a modal closed and reopened mid-tween stays visible; Fade's per-root tables are emptied
when each fade ends; `string.format("%d")` truncates fractions in Luau (no error on a fractional
wallet).

### BUG-19: SoilLook's tween map may keep departed plots' tiles alive

**Status: FIXED (2026-11-12).** Each colour tween removes its own entry on `Completed`.

* **Where:** `src/client/Visuals/SoilLook.luau:87`. `colorTweens` is `{ [tile] = Tween }` with
  weak KEYS, and a Tween keeps a strong reference to its Instance (the tile). Luau's weak
  tables aren't ephemerons, so a value that references its own key may stop that key from ever
  being collected.
* **Effect:** a few KB per tile of every plot that left this server, kept for the whole
  session (PLAUSIBLE, not measured).
* **Fix direction:** drop the entry when its tween finishes
  (`tween.Completed:Once(function() if colorTweens[tile] == tween then colorTweens[tile] = nil end end)`).

### BUG-20: the max-tier star glow runs after the Tech Tree closes

**Status: FIXED (2026-11-12), needs Studio.**

* **Where:** `src/client/Controllers/TechTreeController.luau` `refresh()` (the `glow` tween,
  `RepeatCount = -1`). The `Card.glow` comment says "only while shown", but nothing cancelled it
  on close, so every researched max-tier node (4 today) kept a UIStroke tween running all session.
* **Fix:** `stopGlows()` runs on both close paths (X button and `UIState`) and puts the stroke
  back to 2 / 0; `refresh()` on the next open starts the glow again.

### BUG-21: Fade can undo a 9-slice skin

**Status: FIXED (2026-11-12) (latent: no current call site triggers it).**

* **Where:** `src/client/UI/Theme.luau` `Theme.skin` (deferred one frame) and
  `src/client/UI/Fade.luau` `capture`. If an object's first fade starts in the frame it was
  built, Fade records BackgroundTransparency 0 / TextTransparency 0 before the skin sets them to
  1, and every later show / restore brings back the flat background and the original text under
  `SkinText`. Today's fades (terminal, Control Mode buttons, toasts) start on input or use
  unskinned frames, so it doesn't show yet.
* **Fix:** `Theme.skin` calls `Fade.setResting` for the two values it changes.

### BUG-22: `pingCard` can restore a stale outline

**Status: OPEN (listed only).**

* **Where:** `TechTreeController.luau` `pingCard`: it reads `stroke.Color` / `Thickness` and
  tweens back to them over 0.3 s. A second ping on the same card inside 0.3 s reads the flash
  values (lime, 4). Clicking another card meanwhile sets the old card's thickness to 1.5, but
  the running tween keeps writing toward 3, so the old card still looks selected.
* **Fix direction:** keep the flash tween on the `Card`, cancel it in `selectNode` / `refresh`
  before they set the stroke, and tween back to the values `refresh` / `selectNode` compute.

### BUG-23: the open Tech Tree rebuilds all cost chips on every currency change

**Status: OPEN (listed only).**

* **Where:** `TechTreeController.luau` `refresh()` (from `refreshIfOpen` on every `Cur_*`
  change): it destroys and rebuilds each unresearched card's chips (frame + icon + label +
  stroke + list) and the detail cost rows. A running drone that deposits while the panel is open
  causes hundreds of new instances per deposit.
* **Fix direction:** build the chips once per card and only update the amount colour / stroke
  in `refresh()`.

### BUG-24: skinned buttons have no hover / press feedback

**Status: OPEN (listed only; it changes the look, so it's the user's call).**

* **Where:** `Theme.skin` sets `BackgroundTransparency = 1`, so `AutoButtonColor` has nothing to
  darken on `Theme.button` / `Components.ghostButton` (RUN, STOP, RENAME, modal X, ...). Only
  buttons that also use `Components.hover` still react.
* **Fix direction:** tint the `Skin` ImageLabel on hover / press (for example `ImageColor3`
  x 0.85), or call `Components.hover` on every skinned button.

### BUG-25: `Components.hover` can stick at 1.04

**Status: OPEN (listed only), PLAUSIBLE.**

* **Where:** `src/client/UI/Components.luau` `Components.hover`. On touch, `MouseEnter` fires on
  a tap but `MouseLeave` often doesn't, so the button stays at 1.04. `MouseButton1Up` also sets
  1.04 without checking that the pointer is still over the button.
* **Fix direction:** track `hovered` from MouseEnter / MouseLeave, go back to 1 on `Activated`
  for touch input (`UserInputService.TouchEnabled`), and use `if hovered then 1.04 else 1` on
  release.

## Fix log (`/bugfix`, 2026-11-11)

| ID | Files | Verified by |
|---|---|---|
| BUG-01 | `DroneRuntime/Interpreter` (shared `Budget`), `DroneRuntime/DroneAPI` (min real time), new `DroneRuntime/Simulation` (simulator + compile cache), `Services/ScriptService` (wiring, "line" cap), `Config/GameConfig` (`Simulate.MinRealSeconds`, `Script.MaxLineStatusPerSecond`) | `tests/spec/Simulation.spec.luau` (7; fails with `MinRealSeconds = 0`) |
| BUG-02 | new `Progression/FieldKeeper`, `Services/GridService` | `tests/spec/FieldKeeper.spec.luau` (both handler orders) |
| BUG-03 | `Controllers/TerminalController` | Studio (below) |
| BUG-05/06 | `Services/GridService` (server-wide serial, serial in `DroneMoved`), `Net/RemoteSchema` (comment), `Util/DroneSignals.shouldApply`, `Controllers/PlotRenderer` | `tests/spec/DroneSignals.spec.luau` (+4) + Studio |
| BUG-07 | `Data/SessionStore` (per-load `loadId`) | `tests/spec/SessionStore.spec.luau` (+3; 2 fail on the old code) |
| BUG-08 | `Services/DataService` (`loadingCount`) | Studio (below) |
| BUG-09/10 | `DroneRuntime/DroneAPI`, `Services/GridService` (bank a saved hold on plot create) | `tests/spec/DroneStations.spec.luau` (3) |
| BUG-11 | `DroneRuntime/World`, `LiveWorld`, `SimWorld`, `DroneAPI` (`world:exhaust`), `Progression/Growth` (`Change.exhausted`), `Progression/FieldSave` (8th value), `Services/GridService` (`Exhausted` attribute) | `tests/spec/FieldSave.spec.luau` (+3) |
| BUG-12 | `Controllers/ControlModeController` | Studio (below) |
| BUG-13 | `RateLimiter` moved to `Shared/Net` (the server path re-exports it), `newClientMirror`, `Controllers/TerminalController` | `tests/spec/RateLimiter.spec.luau` (+2) |
| BUG-14 | new `.gitattributes` (the index was already all LF: no renormalize needed) | `git ls-files --eol` |
| BUG-15 | `docs/ARCHITECTURE.md`, `Data/DataTemplate`, `Services/DataService`, `Services/GridService`, `Config/GameConfig`, `assets/README.md`, `Visuals/AssetLibrary`, `tools/build_icon_atlas.py`; `docs/CLAUDE_PROMPTS.md` moved to `docs/archive/` | review |
| BUG-16 | `Progression/Growth`, `SimWorld`, `GridService`, `WeatherService` (`GetCurrent` removed) | type check + tests |
| BUG-17 | `Util/Text.withoutTypedTab`, `Controllers/TerminalController` | `tests/spec/Text.spec.luau` (4) + Studio |
| BUG-19 (2026-11-12) | `Visuals/SoilLook` (`Completed:Once` clears the entry) | review + Studio |
| BUG-20 (2026-11-12) | `Controllers/TechTreeController` (`stopGlows` on close) | review + Studio |
| BUG-21 (2026-11-12) | `UI/Theme` (`Fade.setResting` in `Theme.skin`) | review |

## Studio playtest checklist (everything marked "needs Studio")

1. **BUG-04 / 05 / 06, drone hop (fix-drone Verify):** Control Mode on a 3×3, RUN the starter
   script. The lime line reaches `move_up()` and the drone hops one tile (no teleport at the
   end), every `move_*` is a hop with lean, `charge()` lands on the pad (0, −1), Stop + Run
   again doesn't duplicate or freeze the drone, and with no `ReplicatedStorage.Assets.Drone`
   the procedural hull still hops. Then leave with a second account so its plot Index is
   reused by a new joiner: the new drone appears on ITS charger, never on the old owner's last
   cell.
2. **BUG-01:** research `simulate`, RUN `while True:\n    simulate("lab", 1)`. The terminal line
   updates at most once a second, the MicroProfiler / Script Performance stays flat, Stop
   stops it at once.
3. **BUG-02:** plant a crop, leave within 5 s (before an autosave), rejoin with real
   DataStores: the crop is there.
4. **BUG-03:** join on a throttled network (Studio: Network → incoming latency). Until the
   status says "Ready" the editor can't be typed into, and RUN / snippets refuse; the saved
   script is intact afterwards.
5. **BUG-08:** with real DataStores, start a second player's join and shut the server down
   immediately (Studio "Stop"); rejoining on a new server must not say "still being saved".
6. **BUG-10:** fill the hold, leave while the drone is away from the charger, rejoin: the HUD
   Cargo is 0 and the silo has the items.
7. **BUG-11:** `dig()` on bare soil: that tile's `Exhausted` attribute is true for about 25 s,
   then false; rejoin within 25 s and it is still true.
8. **BUG-12:** enter and leave Control Mode quickly 5 times (re-enter right as the camera
   lands): back in exploring, `workspace.CurrentCamera.FieldOfView` is the same as before
   (70 by default).
9. **BUG-13:** press RUN 10 times fast: from the 4th press the status says "Slow down a
   moment ..."; it never says "Couldn't reach the server (Rejected)".
10. **BUG-17:** press Tab in the editor: exactly 4 spaces. Paste text containing tabs: each
    tab becomes 4 spaces.
11. **BUG-18:** V-CONSOLE (letterbox, console FOV 55, reticle only while the terminal is
    collapsed, other players hidden only in Control Mode and visible again after), the
    V-CONTACT height beam (Control Mode only), and the 5-cell battery in the top-right HUD.
    (Already committed in `1ffb8b7`; revert in a follow-up if something is off.)
12. **BUG-20:** research a max-tier node (for example Grid Expansion III), open the Tech Tree:
    the star badge pulses. Close it with X, open it, close it with the HUD button: each time
    the pulse stops and the badge outline is a solid 2 px; on reopen it pulses again.
13. **BUG-19:** stay near other players' plots for a few minutes and let them leave; Developer
    Console > Memory > `Instances` doesn't keep climbing with each departed plot.
