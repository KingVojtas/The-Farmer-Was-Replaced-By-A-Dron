---
description: ANIM-6 UI motion kit
---

# ANIM-6 — panels, toasts, tutorial, unlock

THIS TASK ONLY. `Fade.luau`, `Theme.Motion`, `NotifyController`, `TutorialController`, Tech Tree / Shop open. No new panels. No CanvasGroup (it blurs code text).

Tokens stay `Theme.Motion` Fast 0.12 / Base 0.2 / Slow 0.35.

1. **Panel open** (Tech Tree, Shop, Hangar, Main Menu if they use Fade): on show, UIScale 0.96 → 1 with Quad Out `Base`. On hide, 1 → 0.98 + Fade. Skip if already mid-tween.
2. **Toasts** — `NotifyController`: slide in from the right 16 px (`Position` + fade). Stack still max 3. Dismiss already fades; keep it.
3. **Tutorial coach** — docked banner: idle bob ±3 px Y, 1.4 s Sine InOut reversing. Stop the bob when the banner is hidden. Primary button hover 1.04 / press 0.97 if not already.
4. **Research unlock** — when a tech node flips owned (existing replication): that card UIScale pulse 1.08 and a 0.3 s lime stroke flash. Once. Don’t loop.
5. Currency HUD already pops on gain (`Icon.pulse`) — leave it.

**Verify:** open TECH TREE: panel scales in, text stays sharp. A notify slides from the right. Tutorial banner (new save) gently bobs. Unlocking one node pings that card only.
