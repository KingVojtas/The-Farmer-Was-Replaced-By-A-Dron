"""
build_ui_slices.py - the 9-slice UI chrome PNGs (ASSETS-6).

    python tools/build_ui_slices.py

Writes art/ui/<name>.png. Every slice is drawn at 2x (SliceScale 0.5 in game, so it stays
crisp on high-DPI screens), supersampled 4x for clean anti-aliased corners, and uses the
Theme.Colors palette (src/client/UI/Theme.luau). The sizes and SliceCenter rects MUST match
src/shared/Config/UiSlices.luau (tests/spec/UiSlices.spec.luau checks the PNGs' sizes).
"button_primary" is a light neutral bevel: the game tints it with each button's own colour
(ImageColor3), so one image serves lime, gold, cyan and red buttons.
These are SLICES (corners + stretchable middles), never a screenshot of a whole screen.
"""

import os

from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "ui")
SS = 4  # supersampling


def hexrgba(value, alpha=255):
    return tuple(int(value[i : i + 2], 16) for i in (1, 3, 5)) + (alpha,)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t + 0.5) for i in range(4))


def rounded(size, radius, fill_top, fill_bottom, border=None, border_px=0, highlight=None,
            lip=None, corners=(True, True, True, True)):
    """A vertical-gradient rounded rect. size = (w, h) at 2x; returns an RGBA image."""
    w, h = size[0] * SS, size[1] * SS
    r = radius * SS
    shape = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255, corners=corners)
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        gd.line((0, y, w, y), fill=lerp(fill_top, fill_bottom, y / max(1, h - 1)))
    if lip is not None:  # a darker bottom lip: the pressed-in bevel of a button
        lip_h = lip[1] * SS
        gd.rectangle((0, h - lip_h, w, h), fill=lip[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if border is not None and border_px > 0:
        img.paste(Image.new("RGBA", (w, h), border), (0, 0), shape)
        inner = Image.new("L", (w, h), 0)
        b = border_px * SS
        ImageDraw.Draw(inner).rounded_rectangle((b, b, w - 1 - b, h - 1 - b), max(0, r - b), fill=255,
                                                corners=corners)
        img.paste(grad, (0, 0), inner)
    else:
        img.paste(grad, (0, 0), shape)
    if highlight is not None:  # a 1 px (at 1x) light line just inside the top edge
        hl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        b = (border_px + 1) * SS
        ImageDraw.Draw(hl).rectangle((b, b, w - 1 - b, b + 2 * SS), fill=highlight)
        hl.putalpha(ImageChops.multiply(hl.getchannel("A"), shape))  # never outside the shape
        img = Image.alpha_composite(img, hl)
    return img.resize(size, Image.LANCZOS)


# name: (size at 2x, builder). Keep in step with UiSlices.luau.
PANEL, PANEL_TOP, PANEL_BOTTOM = "#131921", "#1A222D", "#10151C"
BORDER, BORDER_BRIGHT = "#303C4C", "#4E5E74"
SLICES = {
    "panel": ((64, 64), lambda s: rounded(s, 20, hexrgba(PANEL_TOP), hexrgba(PANEL_BOTTOM),
                                          hexrgba(BORDER), 2, (255, 255, 255, 16))),
    "panel_raised": ((64, 64), lambda s: rounded(s, 20, hexrgba("#2C3747"), hexrgba("#232C39"),
                                                 hexrgba(BORDER_BRIGHT), 2, (255, 255, 255, 26))),
    "button_primary": ((64, 64), lambda s: rounded(s, 12, (255, 255, 255, 255), (214, 220, 228, 255),
                                                   None, 0, (255, 255, 255, 120),
                                                   lip=((150, 158, 170, 255), 5))),
    "button_secondary": ((64, 64), lambda s: rounded(s, 12, hexrgba("#243041"), hexrgba("#1A222D"),
                                                     hexrgba(BORDER), 2, (255, 255, 255, 20))),
    "button_danger": ((64, 64), lambda s: rounded(s, 12, hexrgba("#FF8080"), hexrgba("#E05656"),
                                                  None, 0, (255, 255, 255, 90),
                                                  lip=(hexrgba("#A83A3A"), 5))),
    "tab_on": ((64, 48), lambda s: rounded(s, 12, hexrgba("#8FE073"), hexrgba("#6CC250"), None, 0,
                                           (255, 255, 255, 90), corners=(True, True, False, False))),
    "tab_off": ((64, 48), lambda s: rounded(s, 12, hexrgba("#1A222D"), hexrgba("#131921"),
                                            hexrgba(BORDER), 2, None, corners=(True, True, False, False))),
    "meter_track": ((48, 24), lambda s: rounded(s, 12, hexrgba("#06090D"), hexrgba("#0E141B"),
                                                hexrgba(BORDER), 2)),
    "meter_cap": ((24, 24), lambda s: rounded(s, 12, hexrgba("#B4F59C"), hexrgba("#7FD962"), None, 0,
                                              (255, 255, 255, 140))),
    "toast": ((64, 64), lambda s: rounded(s, 20, hexrgba("#121821", 245), hexrgba("#0B0F15", 245),
                                          hexrgba(BORDER_BRIGHT), 2, (255, 255, 255, 18))),
    "modal_header": ((64, 64), lambda s: rounded(s, 20, hexrgba("#202A37"), hexrgba("#19212C"),
                                                 hexrgba(BORDER), 2, (255, 255, 255, 22),
                                                 corners=(True, True, False, False))),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, (size, build) in SLICES.items():
        build(size).save(os.path.join(OUT, f"{name}.png"), optimize=True)
        print(f"  {name}.png {size[0]}x{size[1]}")
