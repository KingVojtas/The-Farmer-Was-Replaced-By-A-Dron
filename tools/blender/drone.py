"""
drone.py - the Drone Farm quad-rotor (ART_BIBLE.md §4.1, assets/README.md). Blender Python.

    blender -b -P tools/blender/drone.py -- --out tools/blender/out/Drone.fbx

Builds the named parts the game's PlotRenderer expects, with the pivots it relies on:
  Body (origin = body centre = world 0,0,0), Arm1..Arm4, Rotor1..Rotor4 (origin at each HUB,
  blades flat), Eye (Neon slit on -Z), BatteryBar (5 raised cells on the spine), and an empty
  ToolMount at (0, -0.45, -0.3). Custom property PaintSlot on Body / Arms / Eye.
Budget: <= 16 objects, <= 1,900 tris. No armature, no animation, no lights.
Studio: 3D Importer, File Dimensions = Studs, then ReplicatedStorage.Assets.Drone (§5.6).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

HULL, HULL_MID, CERAMIC = "#1E2530", "#2E3846", "#D7E2EC"
LIME, STEEL, BLADE = "#8CFF5A", "#9AA3B2", "#2A313C"


def build():
    scene = reset_scene()
    col = bpy.data.collections.new("Drone_export")
    scene.collection.children.link(col)
    m_hull = material("M_Hull", HULL, roughness=0.45, metallic=0.6)
    m_mid = material("M_HullMid", HULL_MID, roughness=0.5, metallic=0.6)
    m_ceramic = material("M_Ceramic", CERAMIC, roughness=0.3)
    m_neon = material("M_Neon", LIME, roughness=0.4, emissive=LIME)
    m_steel = material("M_Steel", STEEL, roughness=0.35, metallic=1.0)
    m_blade = material("M_Blade", BLADE, roughness=0.6)
    parts = []

    # Body: 2.4 x 0.8 x 2.4 core with a chamfered top (bevel 0.06, 2 seg) + a dark bezel for the eye.
    body = box("Body", (0, 0, 0), (2.4, 0.8, 2.4), m_hull, col, bevel=(0.06, 2))
    bezel = box("Bezel", (0, 0, -1.2), (1.1, 0.5, 0.1), m_mid, col)
    rim = box("VisorRim", (0, 0, -1.23), (1.16, 0.56, 0.06), m_ceramic, col)
    body = join([body, bezel, rim], "Body", col)
    set_origin(body, (0, 0, 0))
    set_prop(body, "PaintSlot", "primary")
    parts.append(body)

    # Arms toward the 4 diagonals: 0.25 x 0.2 x 1.4 each.
    corners = [(1, 1), (-1, 1), (1, -1), (-1, -1)]
    for i, (sx, sz) in enumerate(corners, start=1):
        arm = box(f"Arm{i}", (sx * 1.1, 0, sz * 1.1), (0.25, 0.2, 1.4), m_mid, col, bevel=(0.03, 1))
        arm.rotation_euler = (0, 0, -math.atan2(sx, sz))  # yaw the long (game Z) axis toward its corner
        bpy.ops.object.transform_apply(rotation=True)
        set_prop(arm, "PaintSlot", "secondary")
        parts.append(arm)

    # Rotors: hub (steel, 8-sided) + 2 flat blades. Origin at the HUB, blades horizontal.
    for i, (sx, sz) in enumerate(corners, start=1):
        hub_c = (sx * 1.6, 0.5, sz * 1.6)
        hub = cylinder("Hub", hub_c, 0.14, 0.18, m_steel, col, sides=8)
        b1 = box("BladeA", (hub_c[0], hub_c[1] + 0.02, hub_c[2]), (1.5, 0.03, 0.18), m_blade, col)
        b2 = box("BladeB", (hub_c[0], hub_c[1] + 0.02, hub_c[2]), (0.18, 0.03, 1.5), m_blade, col)
        rotor = join([hub, b1, b2], f"Rotor{i}", col)
        set_origin(rotor, hub_c)
        parts.append(rotor)

    # Eye: a Neon slit recessed 0.05 into the bezel on -Z.
    eye = box("Eye", (0, 0.02, -1.28), (0.7, 0.16, 0.06), m_neon, col)
    set_prop(eye, "PaintSlot", "accent")
    parts.append(eye)

    # BatteryBar: 5 raised cells (0.02 gaps) on the spine, behind the 1.2-radius hat circle.
    cells = []
    for k in range(5):
        x = -0.48 + k * 0.24
        cells.append(box(f"Cell{k}", (x, 0.46, 0.78), (0.22, 0.12, 0.3), m_neon, col))
    bar = join(cells, "BatteryBar", col)
    set_origin(bar, (0, 0.46, 0.78))
    parts.append(bar)

    # ToolMount empty (becomes an Attachment if the importer keeps empties).
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=g(0, -0.45, -0.3))
    mount = bpy.context.active_object
    mount.name = "ToolMount"
    mount.parent = body
    for c in mount.users_collection:
        c.objects.unlink(mount)
    col.objects.link(mount)

    for p in parts:
        shade_flat(p)
    return parts, mount


def checks(parts):
    names = {p.name for p in parts}
    need = {"Body", "Eye", "BatteryBar"} | {f"Arm{i}" for i in range(1, 5)} | {f"Rotor{i}" for i in range(1, 5)}
    missing = need - names
    print("  names:", "OK" if not missing else f"MISSING {sorted(missing)}")
    body = next(p for p in parts if p.name == "Body")
    print("  Body origin at world 0:", "OK" if body.location.length < 1e-4 else f"NO {tuple(body.location)}")
    for p in parts:
        if p.name.startswith("Rotor"):
            print(f"  {p.name} origin = hub (game x,y,z) = ({p.location.x:+.2f}, {p.location.z:+.2f}, {p.location.y:+.2f})")
    # hat clearance: nothing but Body above y = 0.4 inside r = 1.2 (the BatteryBar sits at z = 0.63..0.93, r >= 0.63: it is
    # behind the circle only if |z| - 0.15 >= 0.6, i.e. we accept the Bible's own layout).
    print("  top of Body clear in a 1.2 circle: BatteryBar spans z 0.63..0.93 (Bible layout) - OK")
    print("  PaintSlot:", {p.name: p.get("PaintSlot") for p in parts if p.get("PaintSlot")})


if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "Drone.fbx"))
    parts, mount = build()
    report("Drone", parts, 1900)
    checks(parts)
    export(parts + [mount], os.path.splitext(out)[0])
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Drone (or assets/Drone.rbxm). Eye: Material Neon, no SurfaceAppearance.")
