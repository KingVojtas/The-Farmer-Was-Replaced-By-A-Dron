"""
drone.py - the Drone Farm quad-rotor (ART_BIBLE.md §4.1, assets/README.md). Blender Python.

    blender -b -P tools/blender/drone.py -- --out tools/blender/out/Drone.fbx

v2 (2026-11-17): a sculpted hero drone instead of a box. Same contract as before:
  Body     the lofted, chamfered hull (origin = body centre = world 0,0,0), PaintSlot primary.
           Its top is flat at y = 0.4 inside the 1.2-stud hat circle.
  Chassis  dark details: visor bezel, front vents, belly sensor pod, battery tray, landing skids
  Visor    ceramic trim: the visor rim and two racing strips on the top edges
  Eye      a stadium-shaped Neon lens on -Z (PaintSlot accent)
  BatteryBar  5 bevelled cells on the spine at (0, 0.46, 0.78) (the game colours it by charge)
  Arm1..4  tapered arm + motor pod + rotor guard ring + 3 struts (PaintSlot secondary)
  Rotor1..4  origin at each HUB (game (+-1.6, 0.5, +-1.6)), two tapered, pitched blades + spinner
  ToolMount  an empty at (0, -0.45, -0.3)
Budget: <= 16 MeshParts (13 here), <= 1,900 tris. No armature, no animation, no lights.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

HULL, HULL_MID, CERAMIC = "#1E2530", "#2E3846", "#D7E2EC"
LIME, BLADE = "#8CFF5A", "#2A313C"
CORNERS = [(1, 1), (-1, 1), (1, -1), (-1, -1)]
HUB_Y = 0.5


def vrect(cx, cy, hx, hy, r, z, segs=2):
    """A vertical rounded rectangle in the game x / y plane at depth z (visor frames)."""
    pts = []
    for qx, qy, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ox, oy = cx + qx * (hx - r), cy + qy * (hy - r)
        for s_ in range(segs + 1):
            a = math.radians(a0 + 90 * s_ / segs)
            pts.append((ox + math.cos(a) * r, oy + math.sin(a) * r, z))
    return pts


def build_body(col, m_hull):
    # Five rounded-rectangle rings: a soft belly, the widest band at the waist, a chamfered
    # shoulder and a flat top (y = 0.4) for the hats.
    rings = [
        rounded_rect((0, -0.40, 0), 0.95, 0.95, 0.42),
        rounded_rect((0, -0.24, 0), 1.16, 1.16, 0.52),
        rounded_rect((0, 0.10, 0), 1.20, 1.20, 0.55),
        rounded_rect((0, 0.30, 0), 1.13, 1.13, 0.52),
        rounded_rect((0, 0.40, 0), 1.00, 1.00, 0.45),
    ]
    body = loft("Body", rings, m_hull, col)
    set_origin(body, (0, 0, 0))
    set_prop(body, "PaintSlot", "primary")
    return body


def build_chassis(col, m_mid):
    pieces = []
    # Visor bezel: the dark frame the eye sits in (the bezel contrast keeps the bloom sharp).
    pieces.append(loft("Bezel", [vrect(0, -0.02, 0.62, 0.23, 0.14, -1.13), vrect(0, -0.02, 0.62, 0.23, 0.14, -1.27)], m_mid, col))
    # Front intake vents on the top deck, ahead of the hat circle.
    for k, z in enumerate((-0.92, -0.82, -0.72)):
        pieces.append(box(f"Vent{k}", (0, 0.415, z), (0.86 - k * 0.08, 0.04, 0.05), m_mid, col))
    # Battery tray: a low frame the five cells sit in.
    pieces.append(loft("Tray", [rounded_rect((0, 0.395, 0.78), 0.69, 0.2, 0.06, 1), rounded_rect((0, 0.425, 0.78), 0.67, 0.19, 0.05, 1)], m_mid, col))
    # Belly sensor pod (the tool mount lives here).
    pieces.append(loft("Belly", [
        rounded_rect((0, -0.38, 0), 0.72, 0.86, 0.3, 1),
        rounded_rect((0, -0.52, 0), 0.62, 0.76, 0.26, 1),
        rounded_rect((0, -0.58, 0), 0.46, 0.6, 0.2, 1),
    ], m_mid, col))
    # Landing skids: two rails with turned-up ends, four slanted legs.
    for sx in (1, -1):
        x = sx * 0.8
        pieces.append(tube(f"Rail{sx}", [(x, -0.8, -1.02), (x, -0.9, -0.82), (x, -0.9, 0.82), (x, -0.8, 1.02)], [0.055] * 4, m_mid, col, sides=5))
        for sz in (1, -1):
            pieces.append(tube(f"Leg{sx}{sz}", [(sx * 0.42, -0.5, sz * 0.45), (x, -0.9, sz * 0.55)], [0.05, 0.045], m_mid, col, sides=5))
    chassis = join(pieces, "Chassis", col)
    set_origin(chassis, (0, 0, 0))
    return chassis


def build_visor(col, m_ceramic):
    pieces = [loft("Rim", [vrect(0, -0.02, 0.7, 0.29, 0.18, -1.12), vrect(0, -0.02, 0.7, 0.29, 0.18, -1.24)], m_ceramic, col)]
    for sx in (1, -1):  # racing strips on the top edges, outside the hat circle (|x| >= 0.7)
        pieces.append(loft(f"Strip{sx}", [
            rounded_rect((sx * 0.78, 0.398, 0.0), 0.085, 0.72, 0.06, 1),
            rounded_rect((sx * 0.78, 0.425, 0.0), 0.07, 0.7, 0.05, 1),
        ], m_ceramic, col))
    visor = join(pieces, "Visor", col)
    set_origin(visor, (0, 0, -1.19))
    return visor


def build_eye(col, m_neon):
    # A stadium lens (two half-circles + straight runs), 0.9 x 0.24, 0.06 deep, on -Z.
    def stadium(z):
        pts = []
        for cx, a0 in ((0.33, -90), (-0.33, 90)):
            for s in range(7):
                a = math.radians(a0 + 180 * s / 6)
                pts.append((cx + math.cos(a) * 0.12, 0.0 + math.sin(a) * 0.12, z))
        return pts

    eye = loft("Eye", [stadium(-1.27), stadium(-1.33)], m_neon, col)
    set_origin(eye, (0, 0, -1.3))
    set_prop(eye, "PaintSlot", "accent")
    return eye


def build_battery(col, m_neon):
    cells = []
    for k in range(5):
        x = -0.48 + k * 0.24
        bottom = [(x + 0.11, 0.40, 0.78 + 0.15), (x - 0.11, 0.40, 0.78 + 0.15), (x - 0.11, 0.40, 0.78 - 0.15), (x + 0.11, 0.40, 0.78 - 0.15)]
        top = scaled(bottom, (x, 0, 0.78), 0.8, y=0.52)
        cells.append(loft(f"Cell{k}", [bottom, top], m_neon, col))
    bar = join(cells, "BatteryBar", col)
    set_origin(bar, (0, 0.46, 0.78))
    return bar


def build_arm(i, sx, sz, col, m_mid):
    hub = Vector((sx * 1.6, 0, sz * 1.6))
    out = Vector((sx, 0, sz)).normalized()
    pieces = []
    # Tapered arm, rising gently from the hull waist to the motor pod.
    flat = [(math.cos(a / 6 * 2 * math.pi), 0.62 * math.sin(a / 6 * 2 * math.pi)) for a in range(6)]
    pieces.append(tube("ArmBeam", [(sx * 0.8, 0.02, sz * 0.8), (sx * 1.2, 0.1, sz * 1.2), (sx * 1.5, 0.16, sz * 1.5)], [0.17, 0.14, 0.12], m_mid, col, section=flat))
    # Motor pod under the rotor hub.
    pieces.append(loft("Pod", [
        ring_pts((hub.x, 0.04, hub.z), 0.17, 0.17, 8, math.pi / 8),
        ring_pts((hub.x, 0.24, hub.z), 0.21, 0.21, 8, math.pi / 8),
        ring_pts((hub.x, 0.42, hub.z), 0.15, 0.15, 8, math.pi / 8),
    ], m_mid, col))
    # Guard ring round the blade circle (blades reach 0.75), just under the blade plane.
    pieces.append(torus("Guard", (hub.x, 0.43, hub.z), 0.86, 0.06, m_mid, col, major_segments=16, minor_segments=4))
    # Three struts from the pod out to the ring, under the blades: outward and both sides, so
    # with the arm they make a symmetric cross.
    side = Vector((-out.z, 0, out.x))
    for k, d in enumerate((out, side, -side)):
        a = hub + d * 0.18 + Vector((0, 0.2, 0))
        b = hub + d * 0.84 + Vector((0, 0.4, 0))
        pieces.append(tube(f"Strut{k}", [tuple(a), tuple(b)], [0.04, 0.035], m_mid, col, sides=4))
    arm = join(pieces, f"Arm{i}", col)
    set_origin(arm, (sx * 1.2, 0.1, sz * 1.2))
    set_prop(arm, "PaintSlot", "secondary")
    return arm


def build_rotor(i, sx, sz, col, m_blade):
    hc = (sx * 1.6, HUB_Y, sz * 1.6)
    pieces = []
    # Spinner: a short hex drum and a pointed cap.
    pieces.append(loft("Spinner", [
        ring_pts((hc[0], HUB_Y - 0.06, hc[2]), 0.11, 0.11, 6),
        ring_pts((hc[0], HUB_Y + 0.06, hc[2]), 0.11, 0.11, 6),
        [(hc[0], HUB_Y + 0.14, hc[2])],
    ], m_blade, col, cap_end=False))
    # Two tapered blades with a 12-degree pitch, rounded tips (radius 0.75 = the Bible's 1.5 disc).
    for d in (1, -1):
        xs = (0.08, 0.3, 0.55, 0.7, 0.75)
        widths = (0.06, 0.11, 0.1, 0.07, 0.0)
        pts = [(hc[0] + d * x, HUB_Y + 0.03, hc[2]) for x in xs]
        pieces.append(tube(f"Blade{d}", pts, widths, m_blade, col, section=SEC_BLADE, roll=math.radians(12)))
    rotor = join(pieces, f"Rotor{i}", col)
    set_origin(rotor, hc)
    return rotor


def build():
    scene = reset_scene()
    col = bpy.data.collections.new("Drone_export")
    scene.collection.children.link(col)
    m_hull = material("M_Hull", HULL, roughness=0.45, metallic=0.6)
    m_mid = material("M_HullMid", HULL_MID, roughness=0.5, metallic=0.6)
    m_ceramic = material("M_Ceramic", CERAMIC, roughness=0.3)
    m_neon = material("M_Neon", LIME, roughness=0.4, emissive=LIME)
    m_blade = material("M_Blade", BLADE, roughness=0.6)

    parts = [build_body(col, m_hull), build_chassis(col, m_mid), build_visor(col, m_ceramic), build_eye(col, m_neon), build_battery(col, m_neon)]
    for i, (sx, sz) in enumerate(CORNERS, start=1):
        parts.append(build_arm(i, sx, sz, col, m_mid))
    for i, (sx, sz) in enumerate(CORNERS, start=1):
        parts.append(build_rotor(i, sx, sz, col, m_blade))

    # ToolMount empty (becomes an Attachment if the importer keeps empties).
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=g(0, -0.45, -0.3))
    mount = bpy.context.active_object
    mount.name = "ToolMount"
    mount.parent = parts[0]
    for c in mount.users_collection:
        c.objects.unlink(mount)
    col.objects.link(mount)

    for p in parts:
        shade_flat(p)
    return parts, mount


def checks(parts):
    problems = []
    names = {p.name for p in parts}
    need = {"Body", "Eye", "BatteryBar"} | {f"Arm{i}" for i in range(1, 5)} | {f"Rotor{i}" for i in range(1, 5)}
    missing = need - names
    print("  names:", "OK" if not missing else f"MISSING {sorted(missing)}")
    if missing:
        problems.append(f"missing parts {sorted(missing)}")
    body = next(p for p in parts if p.name == "Body")
    print("  Body origin at world 0:", "OK" if body.location.length < 1e-4 else f"NO {tuple(body.location)}")
    for p in parts:
        if p.name.startswith("Rotor"):
            print(f"  {p.name} origin = hub (game x,y,z) = ({p.location.x:+.2f}, {p.location.z:+.2f}, {-p.location.y:+.2f})")
    # Hat circle: cast rays straight down inside r = 0.6; the highest hit must be the flat top.
    dg = bpy.context.evaluated_depsgraph_get()
    worst = -9.0
    for k in range(25):
        r, a = 0.58 * math.sqrt((k % 5) / 4), (k // 5) / 5 * 2 * math.pi
        hit, loc, *_ = bpy.context.scene.ray_cast(dg, Vector((math.cos(a) * r, math.sin(a) * r, 5)), Vector((0, 0, -1)))
        if hit:
            worst = max(worst, loc.z)
    ok = 0.35 <= worst <= 0.43
    print(f"  hat circle (r 0.6): highest surface y = {worst:+.3f} {'OK' if ok else 'BLOCKED'}")
    if not ok:
        problems.append(f"hat circle: top surface at y = {worst:.3f}, should be 0.40")
    print("  PaintSlot:", {p.name: p.get("PaintSlot") for p in parts if p.get("PaintSlot")})
    return problems


if __name__ == "__main__":
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "Drone.fbx"))
    parts, mount = build()
    body = next(p for p in parts if p.name == "Body")
    parts, problems = finalize(parts, 1900, pivot="center", center_part=body)  # pivot = body centre (contract)
    if len(parts) > 16:
        problems.append(f"{len(parts)} MeshParts > 16 (ART_BIBLE §4.1)")
    tris = report("Drone", parts, 1900)
    problems += checks(parts)
    export(parts + [mount], os.path.splitext(out)[0])
    if tris > 1900:
        problems.append(f"{tris} tris > 1900")
    if problems:
        print("\nPROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
    print("\nStudio import: ART_BIBLE §5.6 -> ReplicatedStorage.Assets.Drone (or assets/Drone.rbxm). Eye: Material Neon, no SurfaceAppearance.")
