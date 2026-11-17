"""
icons.py - renders the UI icons (IconConfig keys) from 3D, in one consistent toon style.

    blender -b -P tools/blender/icons.py -- --out tools/blender/out/icons [--only carrot,lock]
    then:  python tools/build_icon_atlas.py --import <key> tools/blender/out/icons/<key>.png
           python tools/build_icon_atlas.py

Style (matches art/icons/hay.png + wheat.png): chunky shapes, flat cel shading (shadow / base /
highlight bands via Shader to RGB), a thick dark outline (Freestyle), transparent background,
3/4 view. Three sources:
  * the GAME's own models (drone, stations, hats, crops) via their builder scripts, so an icon
    always looks like the thing in the world;
  * small icon props built here (crate, droplet, bone, battery, padlock, ...);
  * extruded glyphs for abstract ideas (loop, list, function, ...), from Windows' Segoe UI
    Symbol / Bahnschrift / Consolas (falls back to Blender's built-in font elsewhere).
Renders 512 x 512 RGBA PNGs; build_icon_atlas.py trims and fits them to 256.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403
import crops as crop_builders  # noqa: E402
import drone as drone_builder  # noqa: E402
import hats as hat_builders  # noqa: E402
import stations as station_builders  # noqa: E402

OUTLINE = "#1B2033"
FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
SYMBOL = os.path.join(FONTS, "seguisym.ttf")
BOLD = os.path.join(FONTS, "seguibl.ttf")
MONO = os.path.join(FONTS, "consolab.ttf")

LIME, CYAN, GOLD, PURPLE = "#8CFF5A", "#66CCFF", "#FFD24A", "#C48CFF"
ORANGE, RED, CREAM, STEEL = "#FF9A2E", "#FF6B6B", "#F1E6CC", "#AEB8C6"


# ------------------------------------------------------------------ render setup
def rgb(hex_color):
    """A #RRGGBB (sRGB) colour as LINEAR floats: what shader nodes and line styles expect, so
    the rendered PNG (Standard view transform) comes out at the exact hex colour."""

    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return tuple(lin(int(hex_color[i : i + 2], 16) / 255) for i in (1, 3, 5))


def toon(name, hex_color, emissive=False):
    """Flat cel material: shadow / base / highlight bands from the sun (EEVEE Shader to RGB)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    r, g_, b = rgb(hex_color)
    if emissive:
        emit.inputs["Color"].default_value = (r, g_, b, 1)
        emit.inputs["Strength"].default_value = 1.15
        return mat
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    shadow = (r * 0.66, g_ * 0.66, b * 0.72, 1)
    high = (r + (1 - r) * 0.38, g_ + (1 - g_) * 0.38, b + (1 - b) * 0.38, 1)
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, shadow
    els[1].position, els[1].color = 0.18, (r, g_, b, 1)
    hi = els.new(0.82)
    hi.color = high
    nt.links.new(diff.outputs["BSDF"], s2r.inputs["Shader"])
    nt.links.new(s2r.outputs["Color"], bw.inputs["Color"])
    nt.links.new(bw.outputs["Val"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    return mat


def toonify(objects):
    """Swaps the game models' Principled materials for toon ones of the same colour."""
    cache = {}
    for o in objects:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            m = slot.material
            if m is None or m.name.startswith("T_"):
                continue
            if m.name not in cache:
                bsdf = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes else None
                col = bsdf.inputs["Base Color"].default_value if bsdf else m.diffuse_color
                emissive = bsdf is not None and bsdf.inputs["Emission Strength"].default_value > 0
                # Principled colours are linear: back to sRGB hex so toon() converts it once.
                def srgb(c):
                    c = max(0.0, min(1.0, c))
                    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

                hexc = "#%02X%02X%02X" % tuple(int(round(srgb(c) * 255)) for c in col[:3])
                cache[m.name] = toon("T_" + m.name, hexc, emissive)
            slot.material = cache[m.name]


def setup_scene(size=512):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    try:
        scene.eevee.taa_render_samples = 16
    except AttributeError:
        pass
    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    # Thick dark outline: silhouette + border only (no creases: low-poly edges stay clean).
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 1.0
    view_layer = bpy.context.view_layer
    view_layer.use_freestyle = True
    fs = view_layer.freestyle_settings
    lineset = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("Outline")
    lineset.select_by_visibility = True
    lineset.select_by_edge_types = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = False
    lineset.select_external_contour = True
    if lineset.linestyle is None:  # an empty factory scene has no line style yet
        lineset.linestyle = bpy.data.linestyles.new("IconOutline")
    lineset.linestyle.color = rgb(OUTLINE)
    lineset.linestyle.thickness = 14
    lineset.linestyle.thickness_position = "CENTER"
    # Key light from the upper left front.
    sun_data = bpy.data.lights.new("IconSun", "SUN")
    sun_data.energy = 3.2
    sun = bpy.data.objects.new("IconSun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(-28), math.radians(-35))
    scene.collection.objects.link(sun)


def frame_camera(objects, direction=(0.55, 1.0, 0.7), fill=1.08):
    """Orthographic camera looking at the objects from `direction` (Blender axes), fitted."""
    meshes = [o for o in objects if o.type == "MESH"]
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        mesh = ev.to_mesh()
        pts += [o.matrix_world @ v.co for v in mesh.vertices]
        ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (lo + hi) / 2
    d = Vector(direction).normalized()
    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("IconCam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = center + d * 50
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_end = 200
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    local = [inv @ p for p in pts]
    w = max(p.x for p in local) - min(p.x for p in local)
    h = max(p.y for p in local) - min(p.y for p in local)
    cam_data.ortho_scale = max(w, h) * fill
    # Re-centre on the projected box (the bbox centre isn't the image centre in 3/4 views).
    cx = (max(p.x for p in local) + min(p.x for p in local)) / 2
    cy = (max(p.y for p in local) + min(p.y for p in local)) / 2
    cam_data.shift_x = cx / cam_data.ortho_scale
    cam_data.shift_y = cy / cam_data.ortho_scale
    bpy.context.scene.camera = cam
    return cam


# ------------------------------------------------------------------ building blocks
def fresh():
    reset_scene()
    col = bpy.data.collections.new("Icon")
    bpy.context.scene.collection.children.link(col)
    return col


def glyph(text, color, font=SYMBOL, col=None, extrude=0.1, x=0.0, y=0.0, scale=1.0):
    """An extruded, bevelled glyph standing upright, facing the camera side (+Y)."""
    curve = bpy.data.curves.new("Glyph", type="FONT")
    curve.body = text
    if os.path.isfile(font):
        curve.font = bpy.data.fonts.load(font, check_existing=True)
    curve.align_x, curve.align_y = "CENTER", "CENTER"
    curve.extrude = extrude
    curve.bevel_depth = 0.025
    curve.bevel_resolution = 1
    curve.size = scale
    obj = bpy.data.objects.new("Glyph", curve)
    (col or bpy.context.scene.collection).objects.link(obj)
    obj.rotation_euler = (math.radians(90), 0, math.radians(180))
    obj.location = (x, 0, y)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    obj.data.materials.append(toon("T_glyph_" + color, color))
    return obj


def T(name, hexc, emissive=False):
    return bpy.data.materials.get("T_" + name) or toon("T_" + name, hexc, emissive)


def bolt_mesh(name, color, col, scale=1.0, depth=0.25):
    """A lightning bolt as an extruded polygon (game x / y plane, facing +Y in Blender)."""
    pts = [(0.15, 1.0), (-0.45, -0.05), (-0.02, -0.05), (-0.2, -1.0), (0.48, 0.18), (0.05, 0.18), (0.3, 1.0)]
    bm = bmesh.new()
    front = [bm.verts.new((x * scale, depth / 2, y * scale)) for x, y in pts]
    back = [bm.verts.new((x * scale, -depth / 2, y * scale)) for x, y in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts)
    for i in range(n):
        bm.faces.new([front[i], front[(i + 1) % n], back[(i + 1) % n], back[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    obj.data.materials.append(T("bolt_" + color, color))
    return obj


def torus(name, center, major, minor, mat, col, rot=(90, 0, 0), seg=24):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg, minor_segments=8, location=g(*center))
    obj = bpy.context.active_object
    obj.rotation_euler = tuple(math.radians(a) for a in rot)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.name = name
    obj.data.materials.append(mat)
    for c in obj.users_collection:
        c.objects.unlink(obj)
    col.objects.link(obj)
    return obj


# ------------------------------------------------------------------ icon props (game coords)
def i_carrot(col):
    root = cone("Root", (0, 0, 0), 0.55, 2.4, T("carrot", ORANGE), col, sides=10, flip=True)
    root.rotation_euler = (0, math.radians(40), 0)
    leaves = [wedge(f"Leaf{k}", (0.7, 0.85, 0), (0.7 + dx, 1.9, dz), 0.35, 0.12, T("leaf", "#4FCB4A"), col)
              for k, (dx, dz) in enumerate(((-0.4, 0.1), (0.1, -0.1), (0.5, 0.05)))]
    return [root] + leaves


def i_wood(col):
    out = []
    for k, (x, y) in enumerate(((-0.55, 0.0), (0.55, 0.0), (0.0, 0.95))):
        out.append(cylinder(f"Log{k}", (x, y, 0), 0.55, 2.2, T("bark", "#9C6B42"), col, sides=10, axis="Z"))
        out.append(cylinder(f"Ring{k}", (x, y, 1.11), 0.46, 0.04, T("ring", "#E8C48A"), col, sides=10, axis="Z"))
    return out


def i_sunflower(col):
    out = [cylinder("Disc", (0, 0, 0.05), 0.55, 0.25, T("seed", "#5A3A1E"), col, sides=12, axis="Z")]
    for k in range(10):
        a = k / 10 * 2 * math.pi
        out.append(wedge(f"Petal{k}", (math.cos(a) * 0.5, math.sin(a) * 0.5, 0), (math.cos(a) * 1.35, math.sin(a) * 1.35, 0), 0.45, 0.1, T("petal", "#FFD23F"), col))
    return out


def i_fossil(col):
    m = T("bone", CREAM)
    out = [cylinder("Shaft", (0, 0, 0), 0.28, 2.2, m, col, sides=8, axis="X")]
    for sx in (-1, 1):
        for sy in (-1, 1):
            out.append(sphere(f"Knob{sx}{sy}", (sx * 1.15, sy * 0.28, 0), 0.38, m, col, segments=10, rings=6))
    return out


def i_biomass(col):
    m = T("biomass", "#7FD962")
    out = [sphere("Pile", (0, 0, 0), 1.0, m, col, segments=12, rings=8, scale=(1.25, 0.75, 1.1))]
    for k, (x, y, z) in enumerate(((0.6, 0.55, 0.3), (-0.5, 0.5, 0.4), (0.0, 0.7, -0.3))):
        out.append(sphere(f"Lump{k}", (x, y, z), 0.42, T("biomass2", "#5DBA49"), col, segments=8, rings=6))
    return out


def i_biofuel(col):
    out = [box("Can", (0, 0, 0), (1.5, 2.1, 0.9), T("canister", "#2BB3A3"), col, bevel=(0.12, 2))]
    out.append(cylinder("Cap", (0.4, 1.2, 0), 0.25, 0.35, T("capsteel", STEEL), col, sides=8))
    out.append(box("Window", (0, -0.1, -0.46), (0.8, 1.1, 0.06), T("fuel", "#4DFFB0", True), col))
    return out


def i_battery(col, x=0.0, scale=1.0):
    body = cylinder(f"Cell{x}", (x, 0, 0), 0.55 * scale, 2.0 * scale, T("cell", CYAN), col, sides=12)
    cap = cylinder(f"CellCap{x}", (x, 1.1 * scale, 0), 0.3 * scale, 0.22 * scale, T("gold", GOLD), col, sides=12)
    return [body, cap]


def i_batteries(col):
    out = i_battery(col)
    b = bolt_mesh("Bolt", "#FFFFFF", col, scale=0.55, depth=0.15)
    b.location = g(0, 0, -0.6)
    return out + [b]


def i_battery_pack(col):
    out = []
    for k, x in enumerate((-1.15, 0.0, 1.15)):
        out += i_battery(col, x=x, scale=0.9)
    out.append(box("Strap", (0, 0, 0), (3.4, 0.35, 1.05), T("strap", "#2E3846"), col))
    return out


def i_water(col):
    m = T("water", "#3FB6FF")
    return [sphere("Drop", (0, 0, 0), 1.0, m, col, segments=14, rings=10),
            cone("Tip", (0, 1.2, 0), 0.86, 1.3, m, col, sides=14)]


def i_cargo(col):
    out = [box("Crate", (0, 0, 0), (2.0, 2.0, 2.0), T("crate", "#E3A14A"), col, bevel=(0.06, 1))]
    for k, y in enumerate((-0.55, 0.55)):
        out.append(box(f"Plank{k}", (0, y, -1.02), (1.9, 0.18, 0.05), T("plank", "#B9773A"), col))
    for sx in (-1, 1):
        for sy in (-1, 1):
            out.append(box(f"Corner{sx}{sy}", (sx * 0.92, sy * 0.92, 0.92), (0.3, 0.3, 0.3), T("corner", STEEL), col))
    return out


def i_cloud(col, y=0.0, color="#B9C7D8"):
    m = T("cloud" + color, color)
    return [sphere("C1", (-0.7, y, 0), 0.7, m, col, segments=12, rings=8),
            sphere("C2", (0.1, y + 0.35, 0), 0.9, m, col, segments=12, rings=8),
            sphere("C3", (0.9, y, 0), 0.65, m, col, segments=12, rings=8)]


def i_rain(col):
    out = i_cloud(col, y=0.5)
    m = T("rain", "#3FB6FF")
    for k, x in enumerate((-0.6, 0.15, 0.9)):
        out.append(sphere(f"Drop{k}", (x, -0.75 - (k % 2) * 0.35, 0.2), 0.22, m, col, segments=8, rings=6, scale=(1, 1.5, 1)))
    return out


def i_drought(col):
    out = [box("Soil", (0, -0.6, 0), (2.4, 0.4, 2.4), T("drysoil", "#C9813E"), col, bevel=(0.05, 1))]
    for k, (x, z, rot) in enumerate(((-0.4, 0.2, 30), (0.4, -0.3, -50), (0.0, 0.6, 80))):
        crack = box(f"Crack{k}", (x, -0.38, z), (1.0, 0.04, 0.08), T("crack", "#5A3418"), col)
        crack.rotation_euler = (0, 0, math.radians(rot))
        out.append(crack)
    out.append(cone("Flame", (0, 0.6, 0), 0.6, 1.5, T("flame", ORANGE), col, sides=8))
    out.append(cone("FlameCore", (0, 0.45, 0.15), 0.35, 0.9, T("flamecore", GOLD), col, sides=8))
    return out


def i_lock(col):
    out = [box("Body", (0, -0.3, 0), (1.8, 1.5, 0.8), T("lockbody", "#8A96A8"), col, bevel=(0.1, 2))]
    out.append(torus("Shackle", (0, 0.55, 0), 0.6, 0.15, T("shackle", "#C9D2DE"), col, rot=(90, 0, 0)))
    out.append(cylinder("Keyhole", (0, -0.25, -0.42), 0.16, 0.05, T("keyhole", "#1E2530"), col, sides=10, axis="Z"))
    return out


def i_watering_can(col):
    m = T("can", "#4FA3E0")
    out = [cylinder("Body", (0, 0, 0), 0.9, 1.4, m, col, sides=14)]
    spout = cylinder("Spout", (1.1, 0.35, 0), 0.14, 1.4, m, col, sides=8, axis="X")
    spout.rotation_euler = (0, math.radians(-35), 0)
    out.append(spout)
    out.append(torus("Handle", (-0.6, 0.5, 0), 0.45, 0.1, T("canhandle", "#2F6FA8"), col, rot=(90, 0, 0)))
    return out


def i_motor(col):
    out = [cylinder("Stator", (0, 0, 0), 0.75, 1.0, T("motor", "#3A4554"), col, sides=14)]
    out.append(cylinder("Bell", (0, 0.65, 0), 0.6, 0.3, T("bell", STEEL), col, sides=14))
    for k in range(2):
        blade = box(f"Blade{k}", (0, 0.85, 0), (3.0, 0.06, 0.35), T("blade", ORANGE), col)
        blade.rotation_euler = (0, 0, math.radians(90 * k + 20))
        out.append(blade)
    return out


def i_paint(col):
    out = [cylinder("Bucket", (0, 0, 0), 0.85, 1.4, T("bucket", "#D9DEE6"), col, sides=14)]
    out.append(cylinder("Paint", (0, 0.72, 0), 0.78, 0.06, T("paint", "#FF5FA2"), col, sides=14))
    out.append(sphere("Drip", (0.6, 0.2, -0.75), 0.2, T("paint", "#FF5FA2"), col, segments=8, rings=6, scale=(1, 1.8, 1)))
    out.append(torus("Handle", (0, 0.75, 0), 0.85, 0.05, T("bhandle", "#5C6675"), col, rot=(0, 0, 0)))
    return out


def i_memory(col):
    out = [box("Chip", (0, 0, 0), (2.4, 0.3, 1.4), T("chip", "#1F6E4A"), col, bevel=(0.03, 1))]
    for k in range(4):
        out.append(box(f"Ram{k}", (-0.85 + k * 0.57, 0.22, 0.05), (0.42, 0.18, 0.6), T("ram", "#2E3846"), col))
    for k in range(7):
        out.append(box(f"Pin{k}", (-1.05 + k * 0.35, -0.1, -0.75), (0.16, 0.12, 0.2), T("gold", GOLD), col))
    return out


def i_gift(col):
    out = [box("Box", (0, 0, 0), (1.9, 1.6, 1.9), T("gift", "#FF6B8B"), col, bevel=(0.05, 1))]
    out.append(box("RibbonX", (0, 0, 0), (0.35, 1.65, 1.95), T("ribbon", GOLD), col))
    out.append(box("RibbonZ", (0, 0, 0), (1.95, 1.65, 0.35), T("ribbon", GOLD), col))
    out.append(torus("BowL", (-0.35, 1.0, 0), 0.32, 0.1, T("ribbon", GOLD), col, rot=(90, 0, 30)))
    out.append(torus("BowR", (0.35, 1.0, 0), 0.32, 0.1, T("ribbon", GOLD), col, rot=(90, 0, -30)))
    return out


def i_bag(col):
    out = [box("Bag", (0, 0, 0), (1.8, 1.9, 0.9), T("bag", GOLD), col, bevel=(0.08, 2))]
    out.append(torus("Handle", (0, 1.05, 0), 0.5, 0.09, T("baghandle", "#B98A16"), col, rot=(90, 0, 0)))
    return out


def i_coin(col):
    out = [cylinder("Coin", (0, 0, 0), 1.0, 0.3, T("coin", GOLD), col, sides=20, axis="Z")]
    g_ = glyph("$", "#C98A12", BOLD, col, extrude=0.06, scale=1.1)
    g_.location = (0, 0.2, 0)
    return out + [g_]


def i_tech_tree(col):
    m_node, m_link = T("node", CYAN), T("link", "#2E86C1")
    nodes = [(0, 1.0, 0), (-0.9, -0.5, 0), (0.9, -0.5, 0)]
    out = [sphere(f"Node{k}", p, 0.45, m_node, col, segments=12, rings=8) for k, p in enumerate(nodes)]
    for k, (x, y, _z) in enumerate(nodes[1:]):
        link = cylinder(f"Link{k}", (x / 2, (y + 1.0) / 2, 0), 0.1, 1.75, m_link, col, sides=6)
        link.rotation_euler = (0, math.atan2(x, 1.5) * (-1 if x > 0 else -1), 0)
        out.append(link)
    return out


def i_sun(col):
    out = [cylinder("Core", (0, 0, 0), 0.75, 0.35, T("sun", GOLD), col, sides=16, axis="Z")]
    for k in range(8):
        a = k / 8 * 2 * math.pi
        ray = cone(f"Ray{k}", (math.cos(a) * 1.2, math.sin(a) * 1.2, 0), 0.24, 0.6, T("ray", "#FFB627"), col, sides=4)
        # the cone points along Blender +Z: lay it into the game x/y plane, pointing outward
        ray.rotation_euler = (0, math.radians(90), 0)
        bpy.context.view_layer.update()
        ray.rotation_euler = (math.radians(-90) + 0, 0, 0)
        ray.rotation_euler = (0, 0, 0)
        ray.rotation_mode = "XYZ"
        direction = Vector((math.cos(a), 0, math.sin(a)))  # Blender x / z = game x / y
        ray.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
        out.append(ray)
    return out


def i_plus(col, at, size=0.9):
    x, y, z = at
    m = T("plus", "#8CFF5A")
    return [box("PlusH", (x, y, z), (size, size * 0.3, size * 0.3), m, col),
            box("PlusV", (x, y, z), (size * 0.3, size, size * 0.3), m, col)]


def i_grid(col, color="#7FD962", plus=False):
    out = [box("Plate", (0, -0.15, 0), (2.4, 0.2, 2.4), T("plate", "#2E3846"), col, bevel=(0.04, 1))]
    for i in range(3):
        for j in range(3):
            out.append(box(f"Tile{i}{j}", (-0.75 + i * 0.75, 0.05, -0.75 + j * 0.75), (0.62, 0.22, 0.62),
                           T("tile" + color, color), col, bevel=(0.03, 1)))
    if plus:
        out += i_plus(col, (1.15, 0.7, -1.0))
    return out


def i_boost_micro(col):
    return [bolt_mesh("Bolt", CYAN, col)] + i_plus(col, (0.75, 0.75, 0), 0.7)


def i_clock(col, color=CYAN):
    out = [cylinder("Face", (0, 0, 0), 1.0, 0.3, T("face", "#EAF2FA"), col, sides=20, axis="Z")]
    out.append(torus("Rim", (0, 0, 0), 1.0, 0.12, T("rim" + color, color), col, rot=(90, 0, 0)))
    out.append(box("HandH", (0, 0.28, -0.2), (0.12, 0.62, 0.06), T("hand", "#1E2530"), col))
    out.append(box("HandM", (0.22, 0.0, -0.2), (0.5, 0.1, 0.06), T("hand", "#1E2530"), col))
    out.append(box("Button", (0, 1.15, 0), (0.3, 0.25, 0.25), T("rim" + color, color), col))
    return out


def i_gear(col, color):
    m = T("gear" + color, color)
    out = [cylinder("Hub", (0, 0, 0), 0.8, 0.4, m, col, sides=16, axis="Z")]
    for k in range(8):
        a = k / 8 * 2 * math.pi
        tooth = box(f"Tooth{k}", (math.cos(a) * 0.9, math.sin(a) * 0.9, 0), (0.32, 0.32, 0.4), m, col)
        tooth.rotation_euler = (0, -a, 0)
        out.append(tooth)
    out.append(cylinder("Hole", (0, 0, -0.21), 0.28, 0.03, T("hole", "#1E2530"), col, sides=12, axis="Z"))
    return out


def i_overclock(col):
    out = i_gear(col, "#8A96A8")
    b = bolt_mesh("Bolt", ORANGE, col, scale=0.7, depth=0.2)
    b.location = g(0, 0, -0.35)
    return out + [b]


def i_die(col):
    out = [box("Die", (0, 0, 0), (1.8, 1.8, 1.8), T("die", "#F4F0FF"), col, bevel=(0.18, 2))]
    pip = T("pip", "#7A4FD0")
    for x, y in ((-0.45, 0.45), (0.45, -0.45), (0, 0)):  # front face: 3
        out.append(sphere("PipF", (x, y, -0.88), 0.16, pip, col, segments=8, rings=6, scale=(1, 1, 0.4)))
    for x, z in ((-0.45, -0.45), (0.45, 0.45)):  # top face: 2
        out.append(sphere("PipT", (x, 0.88, z), 0.16, pip, col, segments=8, rings=6, scale=(1, 0.4, 1)))
    out.append(sphere("PipR", (0.88, 0, 0), 0.16, pip, col, segments=8, rings=6, scale=(0.4, 1, 1)))  # right: 1
    return out


def i_flask(col):
    glass = T("flask", PURPLE)
    out = [sphere("Bulb", (0, -0.35, 0), 0.95, glass, col, segments=14, rings=10)]
    out.append(cylinder("Neck", (0, 0.75, 0), 0.3, 0.9, glass, col, sides=12))
    out.append(cylinder("Lip", (0, 1.22, 0), 0.4, 0.14, T("lip", "#8E5BD9"), col, sides=12))
    out.append(sphere("Bubble", (0.3, -0.2, -0.75), 0.18, T("bubble", "#F1E6FF", True), col, segments=8, rings=6))
    return out


def i_arrow_down(col):
    m = T("arrow", PURPLE)
    shaft = box("Shaft", (0, 0.45, 0), (0.6, 1.3, 0.5), m, col)
    head = cone("Head", (0, -0.6, 0), 0.95, 1.0, m, col, sides=4, flip=True)
    return [shaft, head]


def i_crown(col):
    gold = T("crown", GOLD)
    out = [cylinder("Band", (0, 0, 0), 1.0, 0.55, gold, col, sides=16)]
    for k in range(5):
        a = k / 5 * 2 * math.pi + math.pi / 2
        out.append(cone(f"Spike{k}", (math.cos(a) * 0.82, 0.62, math.sin(a) * 0.82), 0.28, 0.75, gold, col, sides=6))
        out.append(sphere(f"Gem{k}", (math.cos(a) * 0.82, 1.05, math.sin(a) * 0.82), 0.12, T("gem", RED), col, segments=8, rings=6))
    out.append(sphere("FrontGem", (0, 0, -1.0), 0.18, T("gem2", CYAN), col, segments=8, rings=6))
    return out


def i_hangar(col):
    parts, _mount = drone_builder.build()
    home = parts[0].users_collection[0]
    for side in (-1, 1):
        slab = box(f"Roof{side}", (side * 1.45, 2.0, 0), (3.2, 0.25, 3.6), T("roof", CYAN), home)
        slab.rotation_euler = (0, math.radians(28 * side), 0)
        parts.append(slab)
        parts.append(box(f"Wall{side}", (side * 2.75, 0.6, 0), (0.25, 2.2, 3.6), T("wall", "#2E86C1"), home))
    return parts


# ------------------------------------------------------------------ game models
def m_crop(name):
    def build(col):
        return crop_builders.BUILDERS[name]("ready", col)
    return build


def m_hat(style):
    def build(col):
        return dict(hat_builders.HATS)[style](col)
    return build


def m_station(kind):
    def build(col):
        return station_builders.build_charger(col) if kind == "charger" else station_builders.build_factory(col)
    return build


def m_drone(col):
    parts, _mount = drone_builder.build()
    return parts


def g1(text, color, font=SYMBOL, **kw):
    def build(col):
        return [glyph(text, color, font, col, **kw)]
    return build


def g2(*items):
    """Several glyphs side by side: (text, color, font, x, y, scale)."""
    def build(col):
        return [glyph(t, c, f, col, x=x, y=y, scale=s) for t, c, f, x, y, s in items]
    return build


# key -> (builder, view)   view: "model" (3/4 from above) or "front" (glyphs, flat-ish props)
ICONS = {
    "carrot": (i_carrot, "model"),
    "wood": (i_wood, "model"),
    "sunflower": (i_sunflower, "front"),
    "pumpkin": (m_crop("pumpkin"), "model"),
    "cactus": (m_crop("cactus"), "model"),
    "fossil": (i_fossil, "model"),
    "biomass": (i_biomass, "model"),
    "biofuel": (i_biofuel, "model"),
    "batteries": (i_batteries, "model"),
    "energy": (lambda col: [bolt_mesh("Energy", LIME, col)], "front"),
    "water": (i_water, "model"),
    "cargo": (i_cargo, "model"),
    "weather_Sunny": (i_sun, "front"),
    "weather_Rainy": (i_rain, "front"),
    "weather_Drought": (i_drought, "model"),
    "lock": (i_lock, "model"),
    "check": (g1("\u2714", LIME), "front"),
    "star": (g1("\u2605", GOLD), "front"),
    "unknown": (g1("?", "#AEB8C6", BOLD), "front"),
    "loop": (g1("\u21BB", LIME), "front"),
    "grid": (i_grid, "model"),
    "tree": (m_crop("tree"), "model"),
    "watering_can": (i_watering_can, "model"),
    "print": (g1(">_", CYAN, MONO), "front"),
    "speed": (g1("\u23E9", CYAN), "front"),
    "clock": (i_clock, "front"),
    "simulate": (i_flask, "model"),
    "battery_pack": (i_battery_pack, "model"),
    "charger": (m_station("charger"), "model"),
    "factory": (m_station("factory"), "model"),
    "drone": (m_drone, "model"),
    "motor": (i_motor, "model"),
    "paint": (i_paint, "model"),
    "hat": (m_hat("tophat"), "model"),
    "math": (g1("\u2211", PURPLE), "front"),
    "coordinates": (g1("x,y", PURPLE, MONO), "front"),
    "variable": (g1("x=", PURPLE, MONO), "front"),
    "list": (g1("[]", PURPLE, MONO), "front"),
    "function": (g1("f()", PURPLE, MONO), "front"),
    "dictionary": (g1("{}", PURPLE, MONO), "front"),
    "import": (i_arrow_down, "front"),
    "random": (i_die, "model"),
    "cost": (i_coin, "front"),
    "vip_crown": (i_crown, "model"),
    "memory": (i_memory, "model"),
    "yield_2x": (g1("2\u00D7", GOLD, BOLD), "front"),
    "overclock": (i_overclock, "front"),
    "starter_pack": (i_gift, "model"),
    "boost_micro": (i_boost_micro, "front"),
    "boost_grid": (lambda col: i_grid(col, CYAN, plus=True), "model"),
    "hat_antenna": (m_hat("antenna"), "model"),
    "hat_straw": (m_hat("straw"), "model"),
    "hat_propeller": (m_hat("propeller"), "model"),
    "hat_tophat": (m_hat("tophat"), "model"),
    "hat_halo": (m_hat("halo"), "model"),
    "tech_tree": (i_tech_tree, "front"),
    "shop": (i_bag, "model"),
    "hangar": (i_hangar, "model"),
}

VIEWS = {"model": (0.55, 1.0, 0.75), "front": (0.16, 1.0, 0.2)}


def render_icon(key, out_dir):
    builder, view = ICONS[key]
    col = fresh()
    objects = builder(col)
    objects = [o for o in objects if o is not None]
    setup_scene()
    toonify(objects)
    for o in objects:
        if o.type == "MESH":
            shade_flat(o)
    frame_camera(objects, VIEWS[view])
    path = os.path.abspath(os.path.join(out_dir, key + ".png"))  # Blender resolves relative paths oddly
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"  icon {key:16s} -> {path}")


if __name__ == "__main__":
    a = args_after_dashes()
    out = parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "icons"))
    only = a[a.index("--only") + 1].split(",") if "--only" in a else list(ICONS)
    os.makedirs(out, exist_ok=True)
    failed = []
    for key in only:
        try:
            render_icon(key, out)
        except Exception as err:  # keep going: one broken builder shouldn't stop the batch
            failed.append(f"{key}: {err}")
            print(f"  FAILED {key}: {err}")
    if failed:
        print("\nFAILED:\n  " + "\n  ".join(failed))
        sys.exit(1)
