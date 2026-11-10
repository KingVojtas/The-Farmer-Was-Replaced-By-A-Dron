---
description: ANIM-5 terminal line tracks the running drone
---

# ANIM-5 — console and drone are one show

THIS TASK ONLY. `TerminalView` + `TerminalController`. Do **not** change `ScriptStatus` payload or `ScriptService`.

The line highlight already jumps (`highlightLine`). Make it **move** and stay readable while the drone hops.

1. **Running line** — tween highlight `Position.Y` to `(line-1)*lineHeight` in `Theme.Motion.Fast` (0.12 s). Lime bar (`RunLine`). Gutter number of that line = Accent lime while running.
2. **Pulse** — on each `ScriptStatus "line"`, UIScale 1 → 1.04 → 1 on the highlight (0.15 s). Don’t pulse every render, only on a new line number.
3. **RUN header** — while `setRunning(true)`, a 2 px lime bar on the **terminal header** (not over the 3D field). Width eases 0→1 over 0.25 s, then sits. `setRunning(false)` eases out.
4. **Output** — new `appendOutput` rows fade TextTransparency 1→0 in `Theme.Motion.Fast`. Errors still `shake()` the frame 7 px / 0.2 s, never the camera.
5. **Editor** — caret stays a normal TextBox. No fake typing animation.

If highlight already exists but is instant, only add the tween + pulse + header bar.

**Verify:** `RUN` starter script with the terminal open. The lime line slides to `move_up()`, then `harvest()`, in time with the drone. Output lines fade in. A syntax error still shakes the panel.
