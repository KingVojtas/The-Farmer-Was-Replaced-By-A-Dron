"""
Shared helpers for the Drone Farm Blender scripts (drone.py, crops.py, stations.py).

Runs INSIDE Blender (bpy). 1 BU = 1 stud. Blender is +Z up; the FBX / glTF exporters
(Forward -Z, Up Y) map Blender +Z -> Roblox +Y and Blender +Y -> Roblox -Z, so every "height"
below is Blender Z and the game's -Z (the drone's FRONT, the eye) is Blender +Y; the game's
+Z is the camera side. See g() below. ART_BIBLE.md §5.6 / §6: no armature, no animation,
triangulated, Apply Transform.

Import this with:  sys.path.insert(0, os.path.dirname(__file__)); from _common import *
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

# ---------------------------------------------------------------- axis convention
# Game: +X right, +Y up, -Z = the drone's front; the Control Mode camera sits on the +Z side.
# The exporters (Forward -Z, Up Y) ROTATE Blender into Roblox space: Blender (x, y, z) ->
# Roblox (x, z, -y). Measured (tools probe, Blender 4.5): a vertex at Blender +Y lands at
# Roblox -Z in both the FBX and the GLB. So game (x, y, z) == Blender (x, -z, y). An earlier
# version used Blender (x, z, y), a MIRROR: every export came out front-to-back flipped (the
# drone's eye at its back, the sunflower facing away from the camera). Every builder takes
# GAME coordinates and converts exactly once here; the reports print origins back in game
# coordinates so the mapping is verifiable in Studio.


def g(x, y, z):
    """Game (x, y_up, z) -> Blender (x, -z, y): game -Z (front) becomes Blender +Y."""
    return Vector((x, -z, y))


def gsize(sx, sy, sz):
    """Game size (x, y_up, z) -> Blender size (x, z, y): extents, so no sign."""
    return Vector((sx, sz, sy))


# ---------------------------------------------------------------- scene


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.scale_length = 1.0
    return scene


def args_after_dashes():
    argv = sys.argv
    return argv[argv.index("--") + 1 :] if "--" in argv else []


def parse_out(default):
    a = args_after_dashes()
    return a[a.index("--out") + 1] if "--out" in a else default


# ---------------------------------------------------------------- materials


def material(name, hex_color, roughness=0.6, metallic=0.0, emissive=None, alpha=None, roblox=None, variant=None):
    """roblox: an explicit Roblox Material for the part sheet ("Wood", "Pebble", ...); default
    SmoothPlastic (or Neon / Glass / Metal from emissive / alpha / metallic).
    variant: an explicit detail MaterialVariant (VARIANT_BASE key, "" = none) instead of the
    name guess in guess_variant."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    if roblox is not None:
        mat["RobloxMaterial"] = roblox
    if variant is not None:
        mat["RobloxVariant"] = variant
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    r, g_, b = [int(hex_color[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    bsdf.inputs["Base Color"].default_value = (r, g_, b, 1)
    mat.diffuse_color = (r, g_, b, 1)  # viewport / Workbench colour (preview renders)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emissive is not None:
        er, eg, eb = [int(emissive[i : i + 2], 16) / 255 for i in (1, 3, 5)]
        bsdf.inputs["Emission Color"].default_value = (er, eg, eb, 1)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
    return mat


# ---------------------------------------------------------------- primitives (game coords)
# Every transform_apply keeps location=False: a part's origin stays at its own centre, so any
# LATER rotation (a builder yawing an arm, tilting a disc) turns it in place. With Blender's
# default location=True the origin jumps to the world origin and a later rotation swings the
# part around (0, 0, 0) instead (that misplaced the drone arms and every leaf / petal wedge).


def _finish(obj, name, mat, collection):
    obj.name = name
    obj.data.name = "SM_" + name
    if mat is not None:
        obj.data.materials.append(mat)
    for c in obj.users_collection:
        c.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def box(name, center, size, mat, collection, bevel=None):
    """A box at game `center` with game `size`. bevel = (width, segments) or None."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=g(*center))
    obj = bpy.context.active_object
    obj.scale = gsize(*size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel is not None:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width, mod.segments, mod.harden_normals = bevel[0], bevel[1], True
        mod.limit_method = "ANGLE"
    return _finish(obj, name, mat, collection)


def cylinder(name, center, radius, height, mat, collection, sides=6, axis="Y"):
    """A cylinder; axis is the GAME axis it stands along ("Y" = upright)."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=height, location=g(*center))
    obj = bpy.context.active_object
    if axis == "Z":  # game Z == Blender Y
        obj.rotation_euler = (math.radians(90), 0, 0)
    elif axis == "X":
        obj.rotation_euler = (0, math.radians(90), 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(obj, name, mat, collection)


def sphere(name, center, radius, mat, collection, segments=8, rings=6, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=g(*center))
    obj = bpy.context.active_object
    obj.scale = gsize(*scale)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, name, mat, collection)


def cone(name, center, radius, height, mat, collection, sides=6, flip=False):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius, radius2=0, depth=height, location=g(*center))
    obj = bpy.context.active_object
    if flip:
        obj.rotation_euler = (math.radians(180), 0, 0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(obj, name, mat, collection)


def wedge(name, base, tip, width, thickness, mat, collection):
    """A leaf / petal / blade: a thin prism from game point `base` to `tip` (6 tris)."""
    b, t = g(*base), g(*tip)
    d = (t - b)
    length = d.length
    # Built at the world origin along +Y (local coordinates), tapered, aimed, THEN moved to the
    # midpoint, so the taper and the rotation happen around the wedge itself.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.scale = (width, length, thickness)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for v in bm.verts:
        if v.co.y > 0:  # tip end
            v.co.x *= 0.15
            v.co.z *= 0.4
    bm.to_mesh(obj.data)
    bm.free()
    # aim the +Y axis along d
    rot = Vector((0, 1, 0)).rotation_difference(d.normalized())
    obj.rotation_euler = rot.to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.location = (b + t) / 2
    return _finish(obj, name, mat, collection)


def set_origin(obj, game_point):
    """Moves an object's origin to a game-space point without moving its geometry."""
    bpy.context.view_layer.objects.active = obj
    saved = bpy.context.scene.cursor.location.copy()
    bpy.context.scene.cursor.location = g(*game_point)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = saved


def join(objects, name, collection):
    """Joins objects into one mesh named `name` (keeps the first object's origin)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = "SM_" + name
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.001)
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def set_prop(obj, key, value):
    obj[key] = value


def shade_flat(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.shade_flat()


# ---------------------------------------------------------------- export + checks


def tri_count(objects):
    total = 0
    for o in objects:
        dg = bpy.context.evaluated_depsgraph_get()
        mesh = o.evaluated_get(dg).to_mesh()
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
    return total


def export(objects, path_no_ext, glb=True):
    """FBX per ART_BIBLE §5.6 (+ a GLB preview). Only `objects` are exported."""
    os.makedirs(os.path.dirname(path_no_ext), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=path_no_ext + ".fbx",
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        bake_space_transform=True,  # "Apply Transform"
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH", "EMPTY"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        use_triangles=True,
        add_leaf_bones=False,
        bake_anim=False,
        use_armature_deform_only=False,
        path_mode="AUTO",
    )
    import json

    with open(path_no_ext + ".parts.json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(part_sheet(objects), f, indent=1, sort_keys=True)
    if glb:
        bpy.ops.export_scene.gltf(
            filepath=path_no_ext + ".glb",
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_animations=False,
            export_skins=False,
            export_yup=True,
        )
    print(f"  exported {path_no_ext}.fbx" + (" + .glb" if glb else ""))


# ---------------------------------------------------------------- Roblox finalize pass
# The technical-art rules every export follows (on top of ART_BIBLE §5.6 / §7):
#   * clean: merge by distance 0.001, consistent outward normals
#   * Decimate (Collapse) on every mesh, ratio = min(1, budget / tris): a no-op under budget, so
#     flat-shaded hard edges stay crisp; it only bites when a model is over its budget
#   * hard cap MAX_TRIS_PER_MESH per mesh (Roblox allows 20k; we stay under 10k for mobile)
#   * Smart UV Project (66 deg, margin 0.02) so a texture can be added later; the parts keep ONE
#     flat material each, because the game tints state parts / paint slots at runtime
#   * shade flat, Apply Rotation + Scale (location stays: each part keeps its own origin, e.g.
#     a rotor's hub, and the model pivot is the scene origin)
#   * pivot check: "bottom" = the model stands on y = 0 (crops, stations, hats), "center" = the
#     given part's centre is the origin (the drone body)
MAX_TRIS_PER_MESH = 10000
SINK_LIMIT = 0.6  # a crop may sink this far into the 0.6-stud tile (hidden), never deeper


def _edit_all(meshes, action):
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    action()
    bpy.ops.object.mode_set(mode="OBJECT")


def game_bounds(objects):
    """(min, max) of the evaluated world vertices, in GAME coordinates (x, y_up, z)."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objects:
        ev = o.evaluated_get(dg)
        mesh = ev.to_mesh()
        for v in mesh.vertices:
            w = o.matrix_world @ v.co
            pts.append((w.x, w.z, -w.y))
        ev.to_mesh_clear()
    lo = Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    return lo, hi


MIN_MATERIAL_SHARE = 0.05  # a material under 5 % of a mesh's area merges into the dominant one


def _short(mat_name):
    return mat_name[2:] if mat_name.startswith("M_") else mat_name


def split_materials(objects, min_share=MIN_MATERIAL_SHARE):
    """One mesh per material (a Roblox MeshPart has ONE Color / Material; Open Cloud imports
    ignore FBX material colours, so tools/apply_parts.luau colours each part by name).

    * the piece with the largest area keeps the object's name (the game's contract names:
      Body, Hopper, ChimneyCap, ...) and its PaintSlot; the others become <Name>_<Material>
    * materials under `min_share` of the area merge into the dominant one (tiny details)
    * "Rotor*" parts are never split: the game spins each Rotor part around its own centre, so
      the hub stays in one piece with the blades (it takes the dominant colour)
    Every piece keeps the original origin. Returns the new object list.
    """
    out = []
    for o in objects:
        if o.type != "MESH" or len(o.data.materials) <= 1:
            out.append(o)
            continue
        areas = {}
        for poly in o.data.polygons:
            areas[poly.material_index] = areas.get(poly.material_index, 0.0) + poly.area
        total = sum(areas.values()) or 1.0
        dominant = max(areas, key=areas.get)
        keep = {i for i, a in areas.items() if a / total >= min_share}
        if o.name.startswith("Rotor"):
            keep = {dominant}
        for poly in o.data.polygons:  # fold small / disallowed materials into the dominant one
            if poly.material_index not in keep:
                poly.material_index = dominant
        if len(keep) <= 1:
            mat = o.material_slots[dominant].material
            o.data.materials.clear()
            o.data.materials.append(mat)
            for poly in o.data.polygons:
                poly.material_index = 0
            out.append(o)
            continue
        name = o.name
        before = set(bpy.data.objects)
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="MATERIAL")
        bpy.ops.object.mode_set(mode="OBJECT")
        pieces = [o] + [x for x in bpy.data.objects if x not in before]

        def area(p):
            return sum(poly.area for poly in p.data.polygons)

        pieces.sort(key=area, reverse=True)
        for k, p in enumerate(pieces):  # temp names first: the final ones may be taken
            p.name = f"__piece{k}"
        for k, p in enumerate(pieces):
            mat = p.material_slots[p.data.polygons[0].material_index].material
            p.data.materials.clear()
            p.data.materials.append(mat)
            for poly in p.data.polygons:
                poly.material_index = 0
            final = name if k == 0 else f"{name}_{_short(mat.name)}"
            p.name = final
            p.data.name = "SM_" + final
            if k > 0 and "PaintSlot" in p.keys():
                del p["PaintSlot"]
        out += pieces
    return out


def finalize(objects, budget, pivot="bottom", center_part=None, allow_float=False, sink_limit=SINK_LIMIT):
    """Runs the Roblox finalize pass on `objects` (empties are skipped).
    Returns (objects, problems): objects may grow, see split_materials.

    sink_limit: how far below y = 0 a "bottom" model may reach. The game anchors stations on the
    TOP face of their server block, so the factory housing (wrapping the 3-stud block) needs 3.
    """
    center_name = center_part.name if center_part is not None else None
    objects = split_materials(objects)
    if center_name is not None:
        center_part = next(o for o in objects if o.name == center_name)
    meshes = [o for o in objects if o.type == "MESH"]
    problems = []

    def clean():
        bpy.ops.mesh.remove_doubles(threshold=0.001)
        bpy.ops.mesh.normals_make_consistent(inside=False)

    _edit_all(meshes, clean)

    before = tri_count(meshes)
    ratio = min(1.0, budget / before) if before > 0 else 1.0
    for o in meshes:
        mod = o.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
    after = tri_count(meshes)
    for o in meshes:
        tris = tri_count([o])
        if tris > MAX_TRIS_PER_MESH:
            problems.append(f"{o.name}: {tris} tris > {MAX_TRIS_PER_MESH} per mesh")

    _edit_all(meshes, lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02))

    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    lo, hi = game_bounds(meshes)
    if pivot == "bottom":
        low = lo.y
        floating = low > 0.05
        ok = (-sink_limit - 0.01 <= low <= 0.05) or (allow_float and floating)
        detail = f"lowest point y = {low:+.2f}" + (" (floats by design)" if allow_float and floating else "")
        if not ok:
            problems.append(f"pivot: model must stand on y = 0, {detail}")
    else:
        part = center_part or meshes[0]
        plo, phi = game_bounds([part])
        centre = (plo + phi) / 2
        ok = centre.length <= 0.05
        detail = f"{part.name} centre = ({centre.x:+.2f}, {centre.y:+.2f}, {centre.z:+.2f})"
        if not ok:
            problems.append(f"pivot: {detail}, should be the origin")
    size = hi - lo
    print(
        f"   finalize: {len(meshes)} MeshParts (one material each), decimate x{ratio:.2f} ({before} -> {after} tris), "
        f"smart UV, flat, rot+scale applied | size {size.x:.2f} x {size.y:.2f} x {size.z:.2f} studs | "
        f"pivot {pivot}: {detail} {'OK' if ok else 'FAIL'}"
    )
    return objects, problems


def _hex(color):
    """material() stores the #RRGGBB components AS-IS (0..1, no linear conversion), so the hex
    the game should use is simply each component x 255."""
    return "#%02X%02X%02X" % tuple(int(round(max(0.0, min(1.0, c)) * 255)) for c in color[:3])


# Detail MaterialVariants (materials.project.json, tools/build_textures.py "detail"): light,
# neutral PBR sets that the part's Color tints. name -> the BaseMaterial the part must use.
VARIANT_BASE = {
    "DroneHull": "Metal",
    "CropLeaf": "Grass",
    "CropSkin": "Plastic",
    "Bark": "Wood",
    "Planks": "WoodPlanks",
    "Shingles": "Slate",
    "Stone": "Cobblestone",
}
# Which variant a material gets, by words in its name (first match wins; None = stays flat).
VARIANT_RULES = (
    (("soil", "water", "sand", "dirt", "glass", "window", "lamp", "light", "fuel", "slit", "hill", "sail", "shirt", "sack"), None),
    (("roof", "shingle"), "Shingles"),
    (("stone", "rock", "plaza", "towerbase", "foundation", "brick", "chimney", "silobase"), "Stone"),
    (("leaf", "grass", "stem", "stalk", "canopy", "sprout", "pine", "needle", "bush", "hedge", "tuft", "reed", "lily", "cactus", "vine", "crown"), "CropLeaf"),
    (("trunk", "bark", "log", "birch"), "Bark"),
    (("hull", "steel", "blade", "metal", "hub", "iron", "ceramic", "copper", "silo", "tank", "tractor"), "DroneHull"),
    (("wood", "plank", "fence", "sign", "crate", "barrel", "cart", "bench", "post", "shaft", "wheel", "door", "frame", "spar", "twine", "hopper", "wall", "board", "pole", "rings", "stall", "coop", "shed", "barn", "house", "porch"), "Planks"),
    (("pump", "carrot", "root", "fruit", "berry", "disc", "petal", "head", "bud", "mush", "hay", "bale", "straw", "wheat", "sun", "unripe", "bloom", "tail", "veg"), "CropSkin"),
)


def guess_variant(mat, roblox_material):
    """The detail variant for a material: its own "RobloxVariant" property, else by name."""
    if "RobloxVariant" in mat.keys():
        return mat["RobloxVariant"] or None
    if roblox_material in ("Neon", "Glass"):
        return None
    name = mat.name.lower()
    for words, variant in VARIANT_RULES:
        if any(w in name for w in words):
            return variant
    return None


def part_sheet(objects):
    """What Roblox needs per part that FBX can't carry through an Open Cloud import: Color,
    Material, Transparency, attributes, and each part's centre in GAME coordinates (so the
    model pivot can be put back on the scene origin). Read by tools/apply_parts.luau."""
    parts = {}
    for o in objects:
        if o.type != "MESH" or not o.data.materials:
            continue
        mat = o.data.materials[0]
        bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
        color = bsdf.inputs["Base Color"].default_value if bsdf else mat.diffuse_color
        emissive = bsdf is not None and bsdf.inputs["Emission Strength"].default_value > 0
        alpha = bsdf.inputs["Alpha"].default_value if bsdf else 1.0
        metallic = bsdf.inputs["Metallic"].default_value if bsdf else 0.0
        material = "Neon" if emissive else "Glass" if alpha < 0.99 else "Metal" if metallic >= 0.5 else "SmoothPlastic"
        material = mat.get("RobloxMaterial", material)  # an explicit Roblox material wins (Wood, Pebble, ...)
        variant = None if emissive else guess_variant(mat, material)
        if variant is not None:
            material = VARIANT_BASE[variant]  # a MaterialVariant only shows on its BaseMaterial
        lo, hi = game_bounds([o])
        centre = (lo + hi) / 2
        flags = ("Collide", "Query")  # object switches for apply_parts, not attributes
        attributes = {
            k: o[k]
            for k in o.keys()
            if not k.startswith("_") and k not in flags and isinstance(o[k], (str, int, float, bool))
        }
        parts[o.name] = {
            "color": _hex(color),
            "material": material,
            "transparency": round(1 - alpha, 3) if alpha < 0.99 else 0,
            "attributes": attributes,
            "center": [round(centre.x, 4), round(centre.y, 4), round(centre.z, 4)],
            "variant": variant or "",  # a detail MaterialVariant name, "" = flat colour
            "collide": bool(o.get("Collide", False)),  # players bump into it (Box collision)
            "query": bool(o.get("Query", False)),  # raycasts see it (the soil tile)
        }
    return {"pivot": [0, 0, 0], "parts": parts}


def report(title, objects, budget):
    tris = tri_count(objects)
    print(f"\n== {title}: {len(objects)} objects, {tris} tris (budget {budget}) {'OK' if tris <= budget else 'OVER BUDGET'}")
    for o in objects:
        loc = o.location
        print(f"   {o.name:14s} origin game=({loc.x:+.2f}, {loc.z:+.2f}, {-loc.y:+.2f})  props={{{', '.join(f'{k}={o[k]!r}' for k in o.keys() if not k.startswith('_'))}}}")
    return tris
