# MOTION.md — the frozen motion numbers for `/anim`

Source: the `TIMING` comment blocks in `art/fable/motion/*.html` (FABLE-1) and `look.html`.
Every number fits `GameConfig.Drone.ActionTimes` × `TweenFraction` **0.85**: move 0.4 → **0.34 s**,
plant 0.5, harvest 0.5, water 0.4, charge ≥ 0.5. The server wait wins; where a study looked better
longer it was cut to fit. Nothing here changes a server number.

`move` = CFrameValue, `tilt` / `bob` / `spin` = NumberValues composed in `PlotRenderer.render` →
one `BulkMoveTo`. New values are listed as *added* and must be composed in the same step.
Own-plot NEAR only unless noted; MID stays a snap.

## 1. Flight (hop.html, snake.html)

| Name | Seconds | Easing | Sets |
|---|---|---|---|
| hop | 0.34 | Quad InOut | `move` → target cell CFrame, rotation toward travel in the target |
| takeoffLift | first 15 % = 0.051 | Quad Out | *added* `lift` 0 → 1 (× 0.25 stud on Y) |
| glide | 0.221 (15 %→80 %) | Sine InOut | `lift` 1 → 0.4 |
| settle | last 20 % = 0.068 | Quad InOut | `lift` 0.4 → 0; no Back overshoot (hat clips above 0.15 stud) |
| bank (pitch) | 0.17 out + 0.17 back | Sine Out, reversing | `tilt` 0 → 1 → 0 (× 14°) |
| roll | 0.17 + 0.17 | Sine Out, reversing | *added* `roll` 0 → ±1 → 0 (× 8°), only when sin(yaw change) ≥ 0.2 |
| rotorMove | period 0.22 | period tweened 0.25 s Quad Out | *added* `rotorPeriod`; `spin` += dt·360/period (never reset) |
| rotorIdle | period 0.35 | same tween back after `move` completes | `rotorPeriod` |
| rotorLimp | period 0.7 | same | `rotorPeriod` while `isLimping` |
| bob | 1.6 half period, ±0.35 stud | Sine InOut, reversing, infinite | `bob` (unchanged) |
| limpBob | 0.5 | Linear | `bobScale` 1 → 0.25 (unchanged) |
| teleport / first pose | 0 | — | snap `move`, `lift`=`roll`=0, no takeoff |
| ghostDot | 4.0 | Linear | tile dot transparency 0.4 → 1, pool 16, dropped on the cell left |

## 2. Charger (charge.html)

| Name | Seconds | Easing | Sets |
|---|---|---|---|
| land | 0.34 (the move onto the charger) | Quad InOut | *added* `land` 0 → 3.4 studs (hover 5 → 1.6) |
| landedBob | — | — | `bobScale` × 0.3 while docked |
| padPunch | 0.15 + 0.15, at 90 % of the move | Quad Out, reversing | pad Size X/Z × 1.06 (client overlay or the pad part; restore exact size) |
| ringPulse docked | 0.45 | Sine InOut, reversing | ring Transparency 0 ↔ 0.6 |
| ringPulse charging | 0.28 | same | switch when `Battery` rises on the charger |
| stripCyan | 0.3 | Linear | BatteryBar Color → `#3CDCFF`; shadow → transparent 0.2 s |
| takeoff from pad | the next hop | Quad Out | `land` 3.4 → 0 over that hop |

## 3. Actions (plant.html, harvest.html, water.html)

One pose at a time; a new `move` cancels the pose (reset 0.08 s Quad Out).

| Name | Seconds | Easing | Sets |
|---|---|---|---|
| plantDip | 0.14 + 0.14 | Quad Out, reversing | *added* `poseY` 0 → −0.8; `posePitch` 0 → 8° nose-down |
| seedFall | 0.20 (starts at the dip's bottom) | Quad In | seed part ToolMount → tile top (existing) |
| sproutPop | 0.12 + 0.22 | Quad Out, Sine InOut | crop scale ×1.08 → 1 (existing `/art-4`) |
| harvestScoop | 0.18 | Quad In | `posePitch` 0 → 18°, `poseY` 0 → −0.35 (ripe only) |
| harvestSnap | 0.10 | Quad Out | both → 0 |
| harvestBits | 0.60 | — | 9 bits, gravity −30 (existing pool); unripe = grey bits, **no scoop** |
| waterWobble | 0.055 ×4 | Sine InOut, reversing twice | *added* `poseYaw` 0 → +6° → 0 → −6° → 0 (0.22 total) |
| toolFlash | 0.15 | Quad Out | disc under the ToolMount at the pose's depth (lime / gold / cyan) |
| factorySettle | 0.15 + 0.15 | Sine InOut, reversing | `poseY` 0 → −0.3 on a Cargo drop at the factory |

## 4. Crops and weather (look.html, snake.html)

| Name | Seconds | Easing | Sets |
|---|---|---|---|
| growLerp | 0.15 between Progress ticks | Quad Out | procedural part Size/CFrame, or `Model:ScaleTo` via one NumberValue |
| wind Sunny | half 1.6, ±2° | Sine (shared drivers) | sway angle/period tweened 1.5 s on weather change |
| wind Rainy | half 1.25, ±3.2° | same | |
| wind Drought | half 2.2, ±0.8° | same | |
| rainFade | 0.6 | Quad Out | rain rate + drop speed follow one 0..1 level |
| droughtBreathe | 4.0, ±0.02 | Sine InOut, reversing | a second ColorCorrection, only Drought + in range |

## 5. Terminal and UI (not in the studies; from the same clock)

| Name | Seconds | Easing | Sets |
|---|---|---|---|
| runLineSlide | 0.12 | Quad Out | highlight Position.Y → (line−1)·lineHeight; pulse UIScale 1.04 on a NEW line |
| runHeaderBar | 0.25 in / 0.2 out | Quad Out / In | 2 px lime bar width 0 → 1 while running |
| outputFade | 0.12 | Quad Out | new row TextTransparency 1 → 0 |
| panelOpen | 0.2 / 0.12 | Quad Out | UIScale 0.96 → 1 / 1 → 0.98 |
| toastSlide | 0.2 | Quad Out | 16 px from the right + fade |
| coachBob | 1.4, ±3 px | Sine InOut, reversing | only while the terminal ScreenGui is enabled |
| unlockPing | 0.15 + 0.3 | Quad Out | card UIScale 1.08 once + lime stroke flash |

Budgets: ≤ 40 live particles, no trails, no PointLight per tile, no infinite tweens on MID/FAR.

Next: in a new Claude Code session on the default coding model, run /anim-1
and implement this sheet in PlotRenderer. Do not paste Three.js into Luau.
