# Icon prompts (ASSETS-1)

ForgeGUI ran out of credits on 2026-11-11 before the first icon (one `icon_gfx` image costs
1,600 credits; 58 icons ≈ 93k). Everything else is ready: when credits are back, generate each
row below and drop the result into `art/icons/<key>.png`.

**Every request uses:**
* `type = "icon_gfx"` (the style's reference images only condition this family, not `mixed`)
* `style_id = "e6da5ebb-d08e-4d24-9719-a74a4bb3cd16"`, `style_version = 1`
  ("Drone Farm – Glossy Icons", made from `hay.png` + `wheat.png`; the brief carries outline,
  light, palette and the 24 px readability rule)
* `count = 1`, `request_id = "dronefarm-icon-<key>-v1"`
* the prompt below + this suffix: *"Game icon. Fully transparent background, no backdrop, no
  badge, no circle behind it."*

If a result comes back with a painted background, run ForgeGUI `remove_background` on it.
Then, per key: `python tools/build_icon_atlas.py --import <key> <downloaded.png>`, and once all
are in: `python tools/build_icon_atlas.py`. Upload `art/IconAtlas.png` (Studio → Asset Manager
→ Import, or Creator Dashboard → Images), paste the id into `src/shared/Config/IconAtlas.luau`
`assetId`. Rebuilds keep the id; re-upload after a rebuild and paste the new id.

| Key | Prompt |
|---|---|
| carrot | A single fat orange carrot with a bushy bright green leaf top, lying diagonally (leaves top-right, tip bottom-left). |
| wood | Two chunky cut logs stacked, warm brown bark, pale rings on the cut faces. |
| sunflower | One big sunflower head facing the viewer: bright yellow petals, dark brown seed disc, short green stem and leaf. |
| pumpkin | One round ribbed orange pumpkin with a short olive-green stem and a curly leaf. |
| cactus | A cute saguaro cactus with two raised arms, green ribs, cream spines and one pink flower on top. |
| fossil | A cream-white dinosaur bone fossil, chunky dog-bone shape with a few soil specks. |
| biomass | A glossy lime-green blob of compost biomass in a small cube-shaped pile, with a recycle-arrow swirl pressed into it. |
| biofuel | A chunky teal canister of biofuel with a glowing #4DFFB0 liquid window and a droplet emblem. |
| batteries | A premium lithium battery cell, cyan #66CCFF glowing body with a gold cap and a lightning bolt. |
| energy | A bold lime-green lightning bolt with a bright glossy highlight. |
| water | A big glossy cyan water droplet. |
| cargo | A sturdy wooden crate with metal corner brackets, golden-orange wood. |
| weather_Sunny | A smiling-free bright yellow sun with chunky rounded rays. |
| weather_Rainy | A soft blue-grey cloud with three fat blue raindrops falling. |
| weather_Drought | A cracked dry orange-brown soil tile with a small heat flame above it. |
| lock | A chunky slate-grey padlock, closed, with a keyhole. |
| check | A bold lime-green check mark. |
| star | A plump golden five-point star. |
| unknown | A slate-grey rounded question-mark shape. |
| loop | Two thick golden arrows chasing each other in a circle (a loop symbol). |
| grid | A small 3 x 3 farm field of soil tiles seen from above at an angle, golden outline. |
| tree | A round little tree with a double green canopy and a short brown trunk. |
| watering_can | A cyan metal watering can pouring three droplets. |
| print | A cyan speech bubble with three dots inside. |
| speed | A cyan double fast-forward arrow. |
| clock | A round cyan alarm clock with two bells on top. |
| simulate | A cyan glass lab flask with bubbling liquid. |
| battery_pack | A chunky lime-green battery pack with three charge bars. |
| charger | A cyan glowing charging pad with a plug and a lightning bolt. |
| factory | A small green-teal bioreactor tank with a chimney and a glowing #4DFFB0 window. |
| drone | A small chunky quadcopter farming drone, 3/4 top view: dark gunmetal body, ceramic white visor rim, one lime eye slit, four rotors with cyan blur discs. |
| motor | A steel-grey gear with a small motor shaft. |
| paint | A magenta paint bucket with a dripping brush. |
| hat | A purple top hat with a band. |
| math | A violet plus sign and minus sign as chunky tiles. |
| coordinates | A violet map pin over a small grid. |
| variable | A violet luggage-style tag with a string. |
| list | A violet clipboard with three bullet lines. |
| function | A violet jigsaw puzzle piece. |
| dictionary | A violet closed book with a bookmark ribbon. |
| import | A violet tray with a downward arrow going into it. |
| random | A violet die showing five pips. |
| cost | A violet receipt slip with a folded corner. |
| vip_crown | A shiny golden crown with three rounded points and a cyan gem. |
| memory | A cyan computer memory chip (RAM stick). |
| yield_2x | A golden wheat bundle with a small bold "2x" stamp (the only icon with text: "2x"). |
| overclock | An orange-gold lightning bolt bursting out of a gear. |
| starter_pack | A golden gift box with a lime ribbon bow. |
| boost_micro | A small green sprout in a soil mound with a sparkle. |
| boost_grid | A lime-green rocket taking off. |
| hat_antenna | A small red-tipped radio antenna on a round base. |
| hat_straw | A wide-brim straw hat with a red band. |
| hat_propeller | A blue cap with a small propeller on top. |
| hat_tophat | A grey top hat with a dark band. |
| hat_halo | A glowing pale-gold halo ring. |
| tech_tree | A lime-green microscope. |
| shop | A golden shopping cart. |
| hangar | A cyan drone hangar door (arched garage) with the drone silhouette inside. |
