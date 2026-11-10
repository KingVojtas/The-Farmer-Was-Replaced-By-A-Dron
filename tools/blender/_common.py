"""
Shared helpers for the Drone Farm Blender scripts (drone.py, crops.py, stations.py).

Runs INSIDE Blender (bpy). 1 BU = 1 stud. Blender is +Z up; the FBX exporter maps Blender
+Z -> Roblox +Y and Blender -Y -> Roblox -Z when exported with Forward -Z / Up Y, so every
"height" below is Blender Z, and the game's -Z (the drone's front, the camera side) is
Blender +Y ... see front() below. ART_BIBLE.md §5.6 / §6: no armature, no animation,
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
# Game: +X right, +Y up, -Z = the drone's front (camera side). Blender: +X right, +Z up,
# -Y = forward. The FBX exporter (Forward -Z, Up Y) maps Blender -Y -> Roblox -Z and
# Blender +Z -> Roblox +Y, so game (x, y, z) == Blender (x, z, y). Every builder takes GAME
# coordinates and converts exactly once here; the export report prints origins back in game
# coordinates so the mapping is verifiable in Studio.


def g(x, y, z):
    """Game (x, y_up, z) -> Blender (x, z, y): game -Z (front) becomes Blender -Y (forward)."""
    return Vector((x, z, y))


def gsize(sx, sy, sz):
    """Game size (x, y_up, z) -> Blender size (x, z, y)."""
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


def material(name, hex_color, roughness=0.6, metallic=0.0, emissive=None, alpha=None):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    r, g_, b = [int(hex_color[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    bsdf.inputs["Base Color"].default_value = (r, g_, b, 1)
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
    bpy.ops.object.transform_apply(scale=True)
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
    bpy.ops.object.transform_apply(rotation=True)
    return _finish(obj, name, mat, collection)


def sphere(name, center, radius, mat, collection, segments=8, rings=6, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=g(*center))
    obj = bpy.context.active_object
    obj.scale = gsize(*scale)
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, name, mat, collection)


def cone(name, center, radius, height, mat, collection, sides=6, flip=False):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius, radius2=0, depth=height, location=g(*center))
    obj = bpy.context.active_object
    if flip:
        obj.rotation_euler = (math.radians(180), 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
    return _finish(obj, name, mat, collection)


def wedge(name, base, tip, width, thickness, mat, collection):
    """A leaf / petal / blade: a thin prism from game point `base` to `tip` (6 tris)."""
    b, t = g(*base), g(*tip)
    d = (t - b)
    length = d.length
    bpy.ops.mesh.primitive_cube_add(size=1, location=(b + t) / 2)
    obj = bpy.context.active_object
    obj.scale = (width, length, thickness)
    # taper to the tip
    bpy.ops.object.transform_apply(scale=True)
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
    bpy.ops.object.transform_apply(rotation=True)
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


def report(title, objects, budget):
    tris = tri_count(objects)
    print(f"\n== {title}: {len(objects)} objects, {tris} tris (budget {budget}) {'OK' if tris <= budget else 'OVER BUDGET'}")
    for o in objects:
        loc = o.location
        print(f"   {o.name:14s} origin game=({loc.x:+.2f}, {loc.z:+.2f}, {loc.y:+.2f})  props={{{', '.join(f'{k}={o[k]!r}' for k in o.keys() if not k.startswith('_'))}}}")
    return tris
