# Store art (ASSETS-7): game icon + 3 thumbnails

**Status: paused.** ForgeGUI was out of credits (2026-11-11), and the thumbnails must show the
REAL game, so they come from Studio captures, not from a mockup. A headless render of
`art/fable/look.html` was tried and rejected: it's a flat look-study, not the game.

Rules for all four: the real game look and palette (`docs/ART_BIBLE.md` §1), no text that
pretends to be UI the game doesn't have, nothing from another game. Keep the bottom-right
corner free (Roblox overlays player counts there) and important content inside the centre
80 %.

## Game icon (512 × 512)

ForgeGUI, once credits are back: `type = "icon_gfx"`, style `e6da5ebb-d08e-4d24-9719-a74a4bb3cd16`
v1 ("Drone Farm – Glossy Icons"), `request_id = "dronefarm-gameicon-v1"`, prompt:

> A chunky quadcopter farming drone (dark gunmetal #1E2530 body, ceramic white visor rim, one
> glowing lime #7FD962 eye slit, four rotors with cyan #66CCFF motion-blur discs) hovering
> over a small square of farmland: golden wheat, an orange pumpkin and furrowed brown soil
> on green grass #4E6B3A. Seen from a high 3/4 angle. Bright, cheerful, readable at small
> size. Square game icon with a soft sky-to-grass painted background, no text, no border.

Fallback without credits: a Studio capture of the drone over a ready wheat tile (recipe A,
camera 12 studs away), cropped square.

## Thumbnails (1920 × 1080, Studio captures)

Setup for every capture: Studio → Play (or Play Here), Lighting profile **Sunny**, real
DataStores off is fine. Hide the dev UI (View → turn off "Show Outlines" / selection). Use
the in-game camera, then **File → Screenshot** (or the Roblox screenshot key) at a 1920 × 1080
window, or `Save image` from the Studio viewport. No editing beyond a crop and a mild
contrast tweak.

| # | Shows | Recipe |
|---|---|---|
| A | Bird's-eye farm with a hopping drone | A 5 × 5 field (Grid Expansion I+II) with a mix of states: ready wheat, a pumpkin 2 × 2 square, carrots, one watered (dark) row and one dug tile. Enter **Control Mode**, collapse the terminal (the field fills the frame). RUN a loop that moves (`while True:` + moves) and capture mid-hop: the lean, rotor blur and path ghost dots read best then. |
| B | The terminal running code | Control Mode with the terminal open, a short, readable program (10–15 lines: a `for` loop with `plant` / `harvest`, a `def`). Capture while the lime run-line highlight is on a `move_*` line and the drone is mid-move in the right half of the frame. |
| C | The Tech Tree | Open the Tech Tree with a few nodes researched (Root + part of Botany and Logic), one node selected so the detail panel shows its cost chips. Keep the bright, researched nodes in the centre. |

When ForgeGUI credits are back, `type = "thumbnail"` can polish a capture
(`reference_asset_ids` = the uploaded capture, prompt "clean up and brighten this exact game
screenshot, keep every element and colour, no added text"). Never generate a thumbnail
from scratch: it would show a game that doesn't exist.
