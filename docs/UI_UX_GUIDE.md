# UI/UX Architecture Guide

How the game's interface is structured, how it should look and behave, and which module builds
each piece. All UI is built **in code** (no `.rbxm` files) from the design tokens in
`src/client/UI/Theme.luau` and the building blocks in `src/client/UI/Components.luau`.

**The core rule:** the UI is **display-only**. Every number on screen comes from attributes
that the server publishes (`Cur_*`, `Tech_*`, `Pass_*`, plot attributes). Every button either
opens a panel or sends **one validated id** to the server. The UI never decides an outcome.

---

## 1. Design principles

1. **Mission control, not a spreadsheet.** A dark, calm base with a few bright accent colours
   that each mean one thing: lime = act/grow, cyan = info and premium, gold = featured/VIP,
   red = problem.
2. **The farm is the hero.** The HUD keeps to the screen edges. The centre stays free for the
   3D field and drone, so panels open centred and close quickly.
3. **One thing at a time.** At most one full panel is open (`UIState`). Toasts never block input.
4. **Code is first-class.** Anything that *is* code is set in Roboto Mono and styled like code:
   the terminal, the Tech Tree headlines (`a = 2`, `def F():`) and the script-slot names.
5. **Always explain why.** A greyed-out button says what's missing ("RESEARCH PAINT SHOP",
   "NOT ENOUGH RESOURCES"), and locked code shows the exact research to do.

---

## 2. ScreenGui layers

| DisplayOrder | ScreenGui | Module | Notes |
|---|---|---|---|
| 0 | `DroneHud` | `Controllers/HudController` | Always on; hidden while the main menu is up |
| 1 | `DroneTerminal` | `UI/TerminalView` + `Controllers/TerminalController` | Bottom-left, collapsible; **Control Mode only** (§5b) |
| 2 | `ControlMode` | `Controllers/ControlModeController` | WATCH / CONTROL and LEAVE buttons, bottom-centre |
| 5 | `TechTree` | `Controllers/TechTreeController` | Modal panel |
| 5 | `Shop` | `Controllers/ShopController` | Modal panel |
| 8 | `MainMenu` | `Controllers/MainMenuController` | Full screen, `IgnoreGuiInset = true` |
| 10 | `Toasts` | `Controllers/NotifyController` | Never blocks input |

Every ScreenGui uses `ResetOnSpawn = false`, `ZIndexBehavior = Sibling` and
`ScreenInsets = CoreUISafeInsets` (keeps clear of the Roblox top bar and phone notches).
`HudController` applies a `UIScale` of `clamp(min(w/1280, h/720), 0.65, 1.15)`.

**Panel router:** `UI/UIState.luau`. Register once with
`UIState.register(name, { open, close })`, then open from anywhere with
`UIState.open("Shop", "batteries")`. Opening one panel closes the current one, and gamepad
**B** closes the open panel.

---

## 3. Screen zones

```
+-----------------------------------------------------------------------------------+
| [MENU] 2x GROWTH 4:12      [ SUN Sunny | Battery ===  | Water ==  | Cargo = ]    [Li 1,250 (+)] |
|                                                                        RAW          |
|                                                                        [HY] Hay  340 |
|                                                                        [WH] Wheat 82 |
|                         ( 3D field + drone stay in the centre )        PROCESSED    |
|                                                                        [BM] Biomass 12|
|                                                                                     |
| +---------------------------+                                                       |
| | DRONE TERMINAL   12/40  - |                                                       |
| | main | utils | lab  [REN] |                                                       |
| | 1 | while True:           |                                                       |
| | 2 |     harvest()         |                       [TECH TREE] [SHOP] [HANGAR]     |
| | [RUN] [STOP]      Running |                                                       |
+-----------------------------------------------------------------------------------+
```

| Zone | Content | Anchor |
|---|---|---|
| Top-left | MENU button, active boost timers (gold) | `(0,0)` + 12 px |
| Top-centre | Weather chip and battery / water / cargo meters | `(0.5,0)` + 12 px |
| **Top-right** | **Currency stack** (premium, raw, processed) | `(1,0)` - 12 px |
| Bottom-left | Programming terminal (Control Mode only) | `(0,1)` + 12 px |
| Bottom-centre | WATCH / CONTROL (on your plot) or LEAVE (in Control Mode) | `(0.5,1)` - 16 px |
| Bottom-right | Dock: TECH TREE, SHOP, HANGAR | `(1,1)` - 12 px |
| Centre | Modal panels (Tech Tree, Shop) and toasts under the status bar | `(0.5,0.5)` |

---

## 3b. Iconography and assets

Every resource, product, Tech Tree node and status is shown with an **icon**. Icons are always
`ImageLabel`s, built by `src/client/UI/Icon.luau` from one catalogue,
`src/shared/Config/IconConfig.luau`:

| Field | Meaning |
|---|---|
| `assetId` | Roblox image asset id. **`0` = not uploaded yet** |
| `emoji` | fallback drawn *inside* the ImageLabel while `assetId` is 0 (or if the image hasn't loaded after 5 s) |
| `color` | tile tint, glow, pulse and "+N" colour |
| `overlay` | optional stamp on the icon (Double Yield shows "2x") |

**The Robux icon is Roblox's own** (`rbxasset://textures/ui/common/robux.png`, which ships
with every client and is what Roblox's purchase prompts use), tinted to match each button. No
upload is needed.

### Adding your own icon art

1. Make a **256 x 256 PNG** with a transparent background: a flat, stylised icon with a bold
   silhouette that still reads at 20 px. Use the Art Bible palette (`docs/ART_BIBLE.md` §1.4)
   and keep a 16 px margin.
2. Upload it in Studio's **Asset Manager** (Bulk Import), or on the Creator Dashboard under
   Development Items → Images/Decals.
3. Copy the **asset id** (for a Decal, use the image id it creates, not the decal id) and paste
   it into `IconConfig`, e.g. `wheat = { assetId = 123456789, emoji = "🌾", ... }`.
4. That's it: every place using that key (HUD, Shop, Tech Tree, cost chips) switches from the
   emoji to the image. `lune run tests/run` checks every key is still valid.

### The icon atlas (generated icons, ONE texture)

The 33 core icons (crops, resources, weather, stations, drone, Tech Tree basics) share **one
texture**, `art/IconAtlas.png`: an 8-column grid of 128 px cells in `IconConfig.AtlasOrder`.
`Icon.luau` crops each key's cell with `ImageRectOffset` / `ImageRectSize`. There is never one
TextureId per icon.

| Step | Command / place |
|---|---|
| Add or replace one icon (any transparent PNG; it's trimmed and fitted) | `python tools/build_icon_atlas.py --import <key> <file.png>`, saved to `art/icons/<key>.png` |
| Rebuild the atlas + the generated `src/shared/Config/IconAtlas.luau` | `python tools/build_icon_atlas.py` |
| Go live | upload `art/IconAtlas.png` (Asset Manager), paste the image id into `assetId` in `IconAtlas.luau` (rebuilds keep it) |

Fallbacks: atlas `assetId = 0` (not uploaded), a key with no cell yet, or a texture that hasn't
loaded after 5 s all show the emoji. A dedicated per-icon `assetId` in `IconConfig` wins over
the atlas. After adding icons, rebuild, **re-upload** and paste the new id.

### Icon building blocks

| Component | What it is | Used for |
|---|---|---|
| `Icon.new(key, size)` | ImageLabel + `Fallback` TextLabel (emoji) + `Overlay` TextLabel ("2x") + UIScale for pulses | cost chips, buttons, badges |
| `Icon.tile(key, size, {glow})` | the icon on a rounded tile: tinted background, UIGradient sheen, UIStroke (neon when `glow`) | HUD rows, Shop art, Tech Tree nodes |
| `Icon.robux(size, color)` | the official Robux ImageLabel | every Robux price button |
| `handle.pulse(strength)` | pops the icon (Back-ease UIScale 1 → 1.35 → 1); tiles also flash their glow stroke | currency gains, battery full |

### Status icons

| Icon key | Fallback | Shown on |
|---|---|---|
| `lock` | 🔒 | padlock **overlay** covering a locked Tech Tree node's icon |
| `check` | ✅ | corner badge on researched nodes (green ring) |
| `star` | ⭐ | corner badge on researched **max-tier** upgrades (Grid III, Battery III, Servo II, Cargo II), with an endlessly **pulsing gold glow** |

### Styling rules (applied everywhere)

* **UICorner** on every frame, tile and button (radius scales with size).
* **UIStroke** for crisp outlines: currency-coloured on rows; **neon** (2 px, opaque) on premium
  items (Lithium row, gamepass cards, premium cosmetics, Batteries and Starter Pack cards).
* **UIGradient** for the high-tech fill: currency rows fade from a tint of their colour into the
  panel colour, cards and tiles get a top-down sheen, and the battery bar fills lime → cyan.
* **UIListLayout / UIGridLayout** align every icon + text pair. HUD rows use a horizontal
  UIListLayout with **UIFlexItem (Fill)** on the name, so amounts hug the right edge at any
  width. Shop pages use UIGridLayout cards, and buttons centre `[icon][price]` with a
  horizontal list.

---

## 4. Main HUD (`HudController`)

### 4.1 Currency stack (top-right): `CurrencyHudController`

Every tracked resource is an **icon + amount** row, with the drone battery on top:

```
[⚡ Battery ............ 86% [▬▬▬▬ ]]   <- battery %, lime->cyan bar; red + blinking outline at <= 15 %
[💎 Lithium ............ 1,250] [+]    <- premium: neon cyan outline; "+" opens Shop > Lithium Batteries
RAW
[🌿 Hay .................. 340]
[🌾 Wheat ................. 82]  +6    <- a gain pops the icon and floats "+N" up out of it
[🥕 Carrots ............... 15]
[🎃 Pumpkins ............... 4]        <- a raw row appears once that crop is farmable (or you own some)
PROCESSED
[♻️ Biomass ................ 12]
[⛽ Biofuel ................. 3]
```

**Exact hierarchy** (built in code; names are the Instance names):

```
DroneHud (ScreenGui, DisplayOrder 0, UIScale)
└── Currencies (Frame)          AnchorPoint (1,0) · Position (1,-12, 0,12) · 230 px · AutomaticSize Y
    │                           UIListLayout (Vertical, 4 px)
    ├── Energy (Frame)          UICorner · UIStroke · UIGradient · UIPadding · UIListLayout (Horizontal)
    │   ├── IconTile (Frame)    UICorner · UIGradient · UIStroke
    │   │   └── Icon (ImageLabel)  ── Fallback (TextLabel "⚡") ── Overlay (TextLabel)
    │   ├── Name (TextLabel "Battery")   + UIFlexItem (FlexMode Fill)
    │   ├── Value (TextLabel "86%")
    │   └── Bar (Frame) ── Fill (Frame + UIGradient lime->cyan)
    ├── Premium (Frame)         UIListLayout (Horizontal)
    │   ├── Row_batteries (Frame, neon UIStroke)   IconTile 💎 · Name · Value
    │   └── Buy (TextButton "+")
    ├── RAWHeader (TextLabel)
    ├── Row_hay · Row_wheat · Row_carrot · Row_wood · Row_sunflower · Row_pumpkin · Row_cactus · Row_fossil
    ├── PROCESSEDHeader (TextLabel)
    └── Row_biomass · Row_biofuel
```

* **Rows:** 32 px tall with a 24 px icon tile. The name is muted (and fills the remaining
  width); the amount uses Builder Sans ExtraBold 16. Formatting: `1,234`, then `123.4K`, then
  `1.23M`.
* **Visibility:** raw rows show when `Tech.farmableCurrencies(unlocks)` contains the currency or
  the amount is above 0, so the list grows with the tech tree. Processed and premium rows are
  always shown.
* **Animation on gain:**
  * the amount counts up (0.35 s `NumberValue` tween) and flashes lime;
  * the icon pulses (stronger for bigger relative gains) and the tile's outline flashes;
  * a "+N" in the currency colour floats 24 px up out of the icon and fades over 0.8 s;
  * the row's content pops 4 px up and settles (0.3 s). All gain feedback stays in the HUD:
    nothing floats over the 3D field, where it would be unreadable in Control Mode.

  The first value after joining never animates.
* **Battery row:** shows the percentage from the own plot's `Battery` / `BatteryMax`. At 15 % or
  below the value turns red and the outline blinks red; it pulses once when charging reaches
  100 %.
* **Data:** the player attributes `Cur_<id>` and `Tech_<id>`, and the own plot's
  `Battery` / `BatteryMax`.

### 4.2 Status bar (top-centre)

A 440 x 44 panel: the **weather icon tile** (☀️ / 🌧️ / 🔥, colour-coded) and name, then
**Water** 💧 and **Cargo** 📦 meters, each an icon tile plus a bar. Water turns red when
empty, cargo when full. The battery lives in the currency stack (4.1), so it isn't shown twice.

* **Weather chip:** the icon tile and name sit on a rounded chip tinted from
  `Theme.WeatherColors`, the same palette `LightingController` uses for the world (sunny warm
  `#FFF1DC`, rain cool `#B8C6D3`, drought dust `#D6CDBE`). It reads your plot's `Weather`
  attribute first, then `Workspace.Weather`.
* **Ready to harvest:** while any tile of your plot is ready, a 9 px lime dot sits on the
  cargo icon. When more tiles become ready, the cargo tile's outline pulses lime, at most once
  every 4 s, so a field ripening tile by tile never spams.

### 4.3 Menu corner (top-left) and dock (bottom-right)

* MENU (ghost button) reopens the main menu. Next to it, gold text lists active boosts with
  their icon and a countdown (`🌱 2x GROWTH 4:12   🌾 1.5x YIELD 0:58`).
* The dock has 48 px **icon + label** buttons (UIGradient sheen; hover 1.04, press 0.97):
  **🔬 TECH TREE** (lime, primary), **🛒 SHOP** (gold) and **🛸 HANGAR** (cyan, which opens
  Shop > Drone Hangar).

---

## 5. Programming terminal (`TerminalView`, `TerminalController`)

```
+--------------------------------------------------+
| DRONE TERMINAL                    12/40 lines [-] |  header 34 px (gold + "VIP" for VIP owners)
| (main) (utils) (lab)                   [RENAME]  |  slot tabs 30 px, names in Roboto Mono
| +----------------------------------------------+ |
| |  1 | while True:                             | |  editor: gutter + multiline TextBox
| |  2 |     if can_harvest():                   | |  running line = dark-green bar
| |  3 |         harvest()                       | |  error line   = dark-red bar
| +----------------------------------------------+ |
| | --- program started ---                      | |  output: print (white), hint (amber),
| | Unloaded 3 items into the silo.              | |  info (cyan), error (red), system (muted)
| +----------------------------------------------+ |
| [RUN] [STOP]                            Running  |
+--------------------------------------------------+
```

* **Size** 36 % x 62 % of the screen (min 340 x 280, max 580 x 740). The minus button
  collapses it to the header.
* **Slot tabs:** three saved scripts. A slot's **name is its module name** for `import`.
  Switching tabs saves the slot you left (only if it changed). RENAME opens an inline box that
  is pre-checked with the shared `ScriptNames.validate` and then confirmed by the server.
* **Editor helpers:** Tab inserts 4 spaces. Enter keeps the indentation and adds one level
  after a line ending in `:`. Autosave runs 3 s after the last keystroke.
* **RUN** pre-compiles locally with the same Parser and the replicated unlocks, so mistakes
  show instantly. It then sends **only the source text**; the server recompiles against saved
  research.
* **States:** Idle, then Uploading, then Running (lime), then Finished, Stopped (amber) or
  Error on line N (red).
* **Running indicator:** while a program runs, a thin 2 px lime sweep loops along the bottom
  edge of the header (indeterminate progress), never a spinner over the field.
* **Errors** (compile or runtime) get the dark-red line bar **and** a 0.2 s elastic shake of
  the terminal frame (7 px, never the camera). A shake that's already playing isn't
  restarted, so bursts of errors can't jitter it. Never shrink the terminal below
  340 x 280.

---

## 5a. Tutorial coach (`TutorialController`, server: `TutorialService`)

One banner docked on top of the terminal (so it only shows in Control Mode and fades with the
terminal), lime-outlined: "TUTORIAL 2 / 6", one short sentence, one primary button. The
button **never asks for typed syntax**: it RUNs, opens the Tech Tree, or inserts the next legal
snippet at the caret (at the top when the editor has no caret; if the snippet wouldn't fit
the drone's line limit, it replaces the program and a toast says so).

| Step | Goal | Button |
|---|---|---|
| 1 | press RUN (the starter harvests 3 grass tiles) | RUN |
| 2 | harvest the whole 3 x 3 (9 crops) | INSERT SWEEP (rows 1 and 2, no loops needed) |
| 3 | research Loops (9 Hay: exactly the starter field) | OPEN TECH TREE |
| 4 | a program really loops | INSERT LOOP (`repeat 3 times:`) |
| 5 | bring Hay home to the charger | INSERT HAY RUN (`while True:` + `can_harvest()`) |
| 6 | research Wheat, then plant it | OPEN TECH TREE, then INSERT PLANTING |

The **server** owns the step (`PlayerData.tutorial`, published as the `TutorialStep` /
`TutorialDone` attributes) and only advances on what it sees itself: a run starting, the
harvest counter, research, a live loop pass, a Hay unload at the charger, a wheat crop on
the field. Once done, the coach is destroyed and never built again, also after rejoining.
Veterans (Wheat researched and 50+ harvests) skip it. The snippets live in
`Shared/Config/TutorialConfig.luau`; `tests/spec/Tutorial.spec.luau` proves each compiles
with exactly its step's research and does its job on a simulated 3 x 3.

## 5b. Exploration and Control Mode (`ControlModeController`)

The game has two modes. The **terminal only exists on screen in Control Mode**.

```
                 click WATCH / CONTROL                    camera tween done
  ┌───────────┐ ────────────────────────► ┌──────────┐ ─────────────────► ┌─────────────┐
  │ Exploring │                           │ Entering │                    │ Controlling │
  └───────────┘ ◄──────────────────────── └──────────┘ ◄── (B while       └─────────────┘
        ▲          camera tween done        ┌─────────┐      entering)          │ LEAVE / gamepad B
        └───────────────────────────────────│ Exiting │◄────────────────────────┘
                                            └─────────┘
  Death / reset / character removed / plot gone  →  Exploring instantly (no tween)
```

| | Exploration | Control Mode |
|---|---|---|
| Camera | standard Roblox camera (`Custom`, 3rd/1st person) | `Scriptable`, fixed bird's-eye view above your grid |
| Character | walks, jumps, visits other plots | movement **locked** (PlayerModule `Controls:Disable()`) |
| Terminal | hidden | fades in (bottom-left) |
| Bottom-centre button | **WATCH / CONTROL** (only while standing on *your* plot) | **LEAVE** |
| HUD, dock, panels | available | available (they open over the bird's-eye view) |

### Workspace setup: the plot Zone

* Each plot model (`Workspace.Plots.Plot_N`) contains an **invisible part named `Zone`**
  (attribute `PlotZone = true`). The server's `GridService` builds and **resizes** it with the
  plot base, so it grows with Grid Expansion; nothing is hand-placed.
* It covers the whole plot base (field, station row, walkway) + 1 stud on every side, from the
  ground up to **30 studs**, and is `Transparency 1`, `CanCollide / CanTouch / CanQuery =
  false`, `CastShadow = false`, Anchored, Locked.
* **Detection is a spatial check, not Touched/TouchEnded.** Ten times a second the client
  converts `HumanoidRootPart.Position` into the zone's object space and tests it against the
  half-size (`Shared/Util/PlotFraming.inside`). Leaving needs **1.5 studs past the edge**
  (hysteresis), so the button never flickers on the boundary. Only the plot whose
  `OwnerUserId` is the local player is checked.

### ScreenGui placement

| ScreenGui | DisplayOrder | Content |
|---|---|---|
| `DroneTerminal` | 1 | the coding terminal; **starts disabled**, faded in and out by Control Mode |
| `ControlMode` | 2 | `Control` (WATCH / CONTROL, lime, 260 x 60) and `Leave` (LEAVE, ghost with a red stroke, 220 x 60), both bottom-centre (same spot), with the same UIScale rule as the HUD |

Fades use `UI/Fade.luau`, which tweens every descendant's transparency and keeps text crisp
(no CanvasGroup).

### Camera

* **Enter:** the camera's current CFrame (behind the head) tweens over **1.1 s**, Sine InOut,
  to the bird's-eye CFrame. `PlotFraming.solve` picks a distance that fits the field **plus
  the station row** vertically, and fits the field into the screen area **right of the
  terminal** (38 % of the width is reserved). The view is shifted so the grid sits centred in
  that free area.
* The default look-down angle is **80°** (`CONFIG.ViewAngle`; 90 = perfectly straight down).
  Screen-up is grid "up" (world -Z) and screen-right is grid x.
* **Leave:** the camera tweens back over **0.9 s** to the entry pose, re-anchored to the
  current head position. Then `CameraType = Custom` and `CameraSubject = Humanoid`, and
  movement is restored.
* **Re-framing:** a Grid Expansion while watching (the plot's `Size` changes) or a window
  resize re-tweens the view in 0.5 s.
* **Ready markers:** in Control Mode every ready crop on your plot shows a small lime dot
  (an unlit BillboardGui: 0.15 studs + 8 px, so it still reads from the bird's-eye
  camera). With more than 40 ready tiles the dots hide: they would only be noise.
  `PlotRenderer` draws them and checks `ControlModeController:IsActive()` 4 times a
  second. The crop FX themselves are in `docs/ART_BIBLE.md` §3.5.

### Edge cases handled

* **While coding, your character is safe:** it's hidden from your own bird's-eye view
  (LocalTransparencyModifier 1), non-colliding and anchored on the walkway, and the Reset
  button is disabled. Guests can't reach it anyway (plot walls + server eject,
  `PlotGuardService`).
* **Death while in Control Mode:** an instant exit (no tween) so the camera and controls are
  never left broken (the ControlModule outlives the character), and then, once the new
  character stands on your walkway, you go **straight back into Control Mode** instead of
  being dumped into Exploration.
* **Respawn otherwise:** a new character starts in Exploration with the default camera.
* **The player's plot removed or streamed out:** an instant exit.
* **Main menu opened during Control Mode:** the terminal and buttons hide instantly and fade
  back when the menu closes. The menu no longer touches the camera after the join orbit.
* **First person or shift-lock before entering:** a render-step guard keeps the mouse free and
  the character visible while the camera is scriptable.
* **Gamepad:** **B** closes an open panel; with no panel open it means LEAVE (one press never
  does both).
* **Double clicks** during a transition are ignored. Leaving mid-flight reverses from the
  current camera position.
* The farm program keeps running on the server in both modes; the mode is presentation only.

### Studio playtest checklist

1. Spawn on your plot: WATCH / CONTROL fades in. Walk off: it fades out. Walk onto another
   player's plot: no button.
2. Click it: you can't move or jump (keyboard, gamepad, touch), and the camera flies to the
   bird's-eye view with the grid right of the terminal. Terminal + LEAVE fade in.
3. LEAVE: the camera flies back smoothly and you can walk again.
4. Reset while in Control Mode: after respawn the camera is normal and you can walk.
5. Research a Grid Expansion while watching: the view re-frames and the zone grows.
6. Resize the window while watching: the view re-frames.
7. Enter from first person and from shift-lock: the mouse is free and your character is
   visible.
8. Open MENU, the Shop and the Tech Tree while watching, then close them: the mode is intact.
9. With ready crops on your plot, enter Control Mode: lime dots appear above them. Leave:
   they disappear.

---

## 6. Tech Tree (`TechTreeController`)

A pannable, zoomable **graph** whose layout comes entirely from the data
(`TechTree.tier`, `lane` and `branch`):

```
                    CORE  [while True:] -> [Wheat]   [Grid I]-[Grid II]-[Grid III]
 +---------- BOTANY ---------+------- SYSTEM & DRONE -------+-------- LOGIC & DATA --------+
 |  plant("carrot")          |  set_speed()   get_time()     |  1 + 1                        |
 |  water()   plant("tree")  |  (print() is free from start) |  (x, y)        a = 2          |
 |  sunflower  pumpkin       |  simulate()                   |  [1, 2, 3]     def F():       |
 |  Watering Cans            |  Battery/Servo/Cargo/Paint    |  {1: 2} get_cost() import ... |
 |  plant("cactus")          |  Battery II ... Wardrobe      |                               |
 |  dig()                    |  Battery III  Fast Charger    |                               |
 +---------------------------+-------------------------------+-------------------------------+
                                                              [ DETAIL DRAWER  300 px ]
```

* **Canvas:** 3 columns, each 4 lanes x 186 px wide; rows are 136 px. Root sits above the
  middle column. Each branch has a faint tinted band in its colour (Botany lime, System cyan,
  Logic violet, Core gold).
* **Node card** (168 x 86), with a top-down UIGradient sheen and a branch-coloured UIStroke:

  ```
  TextButton <nodeId>
  ├── IconTile (38 px)  ── Icon (ImageLabel, e.g. 🥕 for Carrots, 🧩 for def F():)
  │   └── Lock (Frame, dark overlay) ── Icon 🔒        <- visible while LOCKED
  ├── Headline (TextLabel: code in Roboto Mono, or name)
  ├── Subtitle (TextLabel: name / branch)
  ├── Status (TextLabel "READY")                      <- available and affordable
  ├── Badge (Frame, round, on the top-right corner)  <- ✅ researched / ⭐ max tier (pulsing gold glow)
  └── Chips (Frame, UIListLayout) ── cost chips: [currency icon] amount, red when short
  ```
* **States:**
  * *locked*: dimmed card with the padlock overlay on the icon
  * *available and affordable*: border in the branch colour plus READY
  * *available but short*: neutral border; the short cost chips are red
  * *researched*: green fill, lime border and a ✅ badge
  * *researched max-tier* (Grid III, Battery III, Servo II, Cargo II): gold border and a ⭐
    badge whose ring pulses forever
* **Connectors** (rotated 3 px frames) are lime when both ends are researched, bright when only
  the prerequisite is, and faint otherwise.
* **Detail drawer:** a 56 px glowing icon tile of the node, then branch, code, name, description, an UNLOCKS list (features and stat
  bonuses), REQUIRES (with `[x]` or `[ ]` per prerequisite), and COST as "have / need" per
  currency (each with its currency icon), then the **RESEARCH** button. The button only sends the node id.
* **Navigation:** right or middle-drag pans, the scroll wheel scrolls, and `-`/`+` zoom
  between 0.5 and 1.0.

---

## 7. Shop (`ShopController`)

```
+-----------------------------------------------------------------------------+
| SHOP                                                                    [X] |
+-----------------+-----------------------------------------------------------+
| > Featured      |  +----------+ +----------+ +----------+ +----------+      |
|   Gamepasses    |  | [LIMITED]| |  [BEST]  | |[BEST VAL]| | [POPULAR]|      |
|   Lithium Batt. |  |   PACK   | |    OC    | |    Li    | |    x2    |      |
|   Boosts        |  | Starter  | | Overclock| | Lithium  | | Grid     |      |
|   Drone Hangar  |  | Pack     | | Module   | | Reactor  | | Boost    |      |
|                 |  | ends in  | | + 50 %   | | 4,000 Li | | 30 min   |      |
|                 |  | 47:12:03 | | faster   | |          | |          |      |
|                 |  | [(R) 249] | | [(R) 599] | |[(R)1499] | | [(R) 89]  |      |
|                 |  +----------+ +----------+ +----------+ +----------+      |
+-----------------+-----------------------------------------------------------+
```

* **Tabs:** Featured (the Starter Pack while it's offered, Overclock, best-value Batteries,
  Grid Boost), **Gamepasses** (VIP, Expanded Memory, 2x Yield, Overclock), **Lithium Batteries**
  (4 bundles), **Boosts** (with the active timer), and **Drone Hangar** (cosmetics).
* **Card** (218 x 252): UICorner, a UIGradient sheen and a UIStroke (**neon** in the accent
  colour for premium items: gamepasses, Batteries and the Starter Pack).

  ```
  Frame <product name>                      (inside a ScrollingFrame page with UIGridLayout 218 x 252)
  ├── Art (Frame, tinted UIGradient)
  │   ├── IconTile (68 px, glow) ── Icon (ImageLabel: 👑 VIP · ⚡ Overclock · 🌾"2x" Double Yield ·
  │   │                                    💾 Expanded Memory · 💎 Batteries · 🌱/🚀 Boosts · 🎁 Starter Pack)
  │   └── Badge (TextLabel ribbon: BEST VALUE / POPULAR / LIMITED / BEST)
  ├── Content (Frame, UIListLayout vertical)
  │   ├── Title · Description · "+ perk" lines (passes) · Status (countdown / active boost)
  └── Buy (TextButton, UIListLayout horizontal centred)
      ├── RobuxIcon (ImageLabel, rbxasset://textures/ui/common/robux.png)
      └── Price (TextLabel "599")
  ```
* **Buy button states:** price (Robux icon + number), "..." while the Roblox prompt is open,
  **OWNED** (no icon) for owned passes, and **COMING SOON** while the product id is 0.
* **Drone Hangar tiles** (160 x 196): paint jobs show colour swatches; hats show their icon
  tile (📡 👒 🧢 🎩 😇; neon for premium). Buttons read EQUIPPED / EQUIP / RESEARCH <node>,
  or **💎 + price** (and "CONFIRM <price>?" on the first click) for premium items.
* **Prices** come from `MarketplaceService:GetProductInfo` (cached, pcall'd). The config
  `price` is only a fallback. An id of `0` shows **COMING SOON** and can't be clicked.
* **Display metadata** lives in `MonetizationConfig` (`category`, `description`, `badge`,
  `order`, `icon`, and `perks` for passes). Grant data is never read by the client.

### Purchase flows (the client never grants anything)

**Developer Product** (Batteries, Boosts, Starter Pack):

```
Client: click price -> button shows "..." -> PromptProductPurchase(id)
Roblox: charges the player -> ProcessReceipt on the SERVER (ReceiptService)
Server: ReceiptProcessor (dedupe by PurchaseId -> apply grant + record id, no yields)
        -> profile:SaveAsync() -> success? PurchaseGranted : NotProcessedYet (Roblox retries)
Server -> client: PurchaseGranted remote -> gold toast "Thank you! ..."; Cur_* attributes update the HUD
Client: PromptProductPurchaseFinished -> button back to its price
```

**Gamepass:** `PromptGamePassPurchase(id)`. The **server** listens to
`PromptGamePassPurchaseFinished`, sets `Pass_<Key>`, and the card flips to **OWNED**.

**Cosmetic (Lithium Batteries):** the first click turns the button into "CONFIRM 150 Li?" for
3 s, and a second click sends `BuyCosmetic(id)`. The server checks the **saved** balance,
deducts it and records ownership in one step, then saves. Equipping sends
`EquipCosmetic(slot, id)`.

**Store hygiene:** prices are always visible before any prompt, there are no random rewards
or loot boxes, a timed offer shows its real end time (`StarterPackEndsAt` from the server),
and cosmetics never change gameplay.

---

## 8. Main menu (`MainMenuController`)

* Shown on join (and from MENU). It's a full-screen CanvasGroup: a left-to-right dark gradient,
  the title **DRONE FARM** (FARM in lime, 72 px ExtraBold), and the tagline
  "Write code. Grow crops. Automate everything."
* Buttons are 280 px wide: **PLAY** (lime, 54 px tall; shows "LOADING YOUR FARM..." until
  `DataLoaded`), then TECH TREE, SHOP (gold text) and HOW TO PLAY (toggles a 5-step card on the
  right).
* While it's open, a Lighting `BlurEffect` tweens to 18, and on the first open the **camera**
  slowly orbits your plot (a tweened `NumberValue` angle; only the camera moves). The HUD and
  terminal are hidden.
* Opening the Tech Tree or Shop from here closes the menu automatically through UIState.

---

## 9. Toasts (`NotifyController`)

These are 360 px cards under the status bar, at most 3 at once (the oldest is pushed out).
Each has a 4 px accent bar by kind (research and success lime, purchase gold, info cyan,
warning amber, error red), pops in with a Back-ease scale, and fades out after 3.5 s. Sources
are the `Notify` remote, the `PurchaseGranted` remote, and `NotifyController.show(kind, text)`
from any controller.

---

## 10. Design tokens (`Theme.luau`)

| Token | Value | Use |
|---|---|---|
| `Background` | `#0B0F15` | panel bodies, inputs |
| `Panel` / `PanelLight` / `Raised` | `#131921` / `#1E2631` / `#283240` | surfaces by elevation |
| `Border` / `BorderBright` | `#303C4C` / `#4E5E74` | 1 px strokes |
| `Text` / `Muted` / `Faint` | `#DEE6F2` / `#808EA2` / `#4E5A6C` | text hierarchy |
| `Accent` | `#7FD962` lime | primary action, growth, researched |
| `Info` / `Premium` | `#66CCFF` cyan | info, Lithium Batteries |
| `Gold` | `#FFD666` | featured, VIP, purchases |
| `Danger` / `Warning` | `#FF6B6B` / `#FFC457` | errors, shortages |
| Branches | Botany lime, System cyan, Logic `#C48CFF`, Core gold | Tech Tree |

* **Type:** Builder Sans (UI: Medium 13-15, Bold for buttons, ExtraBold for headings and
  amounts) and Roboto Mono (code). Never use more than three sizes in one component.
* **Spacing:** 4 / 8 / 12 / 16 / 24 (`Theme.Space`). **Radii:** 6 / 10 / 14 (`Theme.Radius`).
* **Motion:** Fast 0.12 s (hover/press), Base 0.2 s (open/close, bars), Slow 0.35 s (fades,
  counters). Quad Out by default, Back Out for pop-ins. Motion confirms an action; it should
  never delay one.
* **Surfaces:** `Components.panel` adds a 1 px border and a subtle top-to-bottom sheen
  (`UIGradient`, white to `#C8CDD7`).

---

## 11. Platforms and accessibility

* **Touch:** every tappable control is at least 30 px tall at scale 1 (dock buttons 48 px).
  The UIScale floor of 0.65 keeps phone layouts legible.
* **Gamepad:** **B** closes the open panel, and the Roblox selection system can reach every
  TextButton.
* **Colour is never the only signal:** states also carry text (DONE / READY / LOCKED / OWNED,
  "have / need" numbers).
* **Safe areas:** `ScreenInsets.CoreUISafeInsets` on every ScreenGui except the full-screen menu.

---

## 12. Where things live

| Concern | File |
|---|---|
| Tokens and builder helpers | `src/client/UI/Theme.luau` |
| Reusable widgets (panel, modal, chip, bar, badge, hover) | `src/client/UI/Components.luau` |
| Icon catalogue (asset ids, emoji fallbacks, colours) | `src/shared/Config/IconConfig.luau` |
| Icon ImageLabels, tiles, Robux icon, pulses | `src/client/UI/Icon.luau` |
| Top-right currency HUD (icons, battery %, gain animation) | `src/client/Controllers/CurrencyHudController.luau` |
| One-panel-at-a-time router | `src/client/UI/UIState.luau` |
| HUD shell (status bar, menu corner, dock) | `src/client/Controllers/HudController.luau` |
| Terminal view and behaviour | `src/client/UI/TerminalView.luau`, `src/client/Controllers/TerminalController.luau` |
| Tech Tree graph | `src/client/Controllers/TechTreeController.luau` |
| Shop and Drone Hangar | `src/client/Controllers/ShopController.luau` |
| Main menu | `src/client/Controllers/MainMenuController.luau` |
| Toasts | `src/client/Controllers/NotifyController.luau` |
| Exploration / Control Mode (zone, camera, control lock) | `src/client/Controllers/ControlModeController.luau` |
| Crisp UI fades | `src/client/UI/Fade.luau` |
| Zone test and bird's-eye framing math | `src/shared/Util/PlotFraming.luau` |
| Crop growth / plant / harvest FX and ready markers | `src/client/Controllers/PlotRenderer.luau`, `src/shared/Util/CropTransitions.luau` |
| Boot order (Init, then Start) | `src/client/ClientMain.client.luau` |
