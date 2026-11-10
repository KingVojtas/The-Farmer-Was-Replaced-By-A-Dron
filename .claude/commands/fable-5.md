---
description: FABLE-5 timing sheet for /anim — no gameplay rewrite
---

# FABLE-5 — freeze the motion numbers

THIS TASK ONLY. Read the HTML comments from `art/fable/motion/*.html` (FABLE-1). Write **one** markdown file:

`art/fable/MOTION.md`

Table: name, seconds, easing, what `/anim` should set on `move` / `tilt` / `bob` / `spin`.

Must stay inside `GameConfig.Drone.ActionTimes` × `TweenFraction` 0.85. If a study was prettier at 0.7 s, **cut it** to 0.34 s for a hop — the server wait wins.

End the file with:

```
Next: in a new Claude Code session on the default coding model, run /anim-1
and implement this sheet in PlotRenderer. Do not paste Three.js into Luau.
```

Do **not** edit `src/` in this step.

**Verify:** every row has a number that fits the action time. No “TODO”.
