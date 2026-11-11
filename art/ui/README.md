# UI chrome slices (ASSETS-6)

9-slice PNGs drawn by `python tools/build_ui_slices.py` in the `Theme.Colors` palette, at 2x
(SliceScale 0.5 in game). These are slices (corners + stretchable middles), never a
screenshot of a screen. Sizes and SliceCenter rects live in `src/shared/Config/UiSlices.luau`;
`tests/spec/UiSlices.spec.luau` checks them against these files.

| Slice | Size | Used by (`Theme.skin`) |
|---|---|---|
| `panel` | 64×64 | `Components.panel` (Tech Tree / Shop / menu / coach / toast panels) |
| `modal_header` | 64×64 | `Components.modal` header bar |
| `button_primary` | 64×64 | `Theme.button`, TINTED with each button's own colour (lime, gold, cyan, red) |
| `button_secondary` | 64×64 | `Components.ghostButton` |
| `meter_track` | 48×24 | `Components.progressBar` |
| `panel_raised`, `button_danger`, `tab_on`, `tab_off`, `meter_cap`, `toast` | | available to `Theme.skin(object, name)`, not wired yet |

**Status: ON.** All 11 are uploaded (ids in `art/ROBLOX_ASSETS.md`) and pasted into
`UiSlices.List.<name>.assetId`. `UiSlices.Enabled = false` switches every skin off again.
With id 0 a slice keeps the code-built look (colour + UICorner + UIStroke).

**Known limits (by design):**
* A panel that has a `UIListLayout` / `UIGridLayout` keeps the code look: the Skin image would
  be laid out as one of its items.
* On text buttons the text moves into a mirrored `SkinText` label above the Skin (children
  draw over the parent's own text). It follows `Text`, `TextColor3`, `TextSize` and `Font`.
* **Studio check after uploading:** open the Tech Tree, Shop, main menu and a toast. Corners
  are crisp at 100 % and 200 % UI scale, buttons keep their colours and hover tints, labels
  are readable, and no list panel shows a stray image item.
