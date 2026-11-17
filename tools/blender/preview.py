"""
preview.py - renders contact sheets of the exported models (the .glb previews next to each
.fbx), so they can be reviewed before any Studio import. Blender Python.

    blender -b -P tools/blender/preview.py -- --out tools/blender/out

Writes <out>/previews/{drone,crops,stations,hats}.png: Workbench engine (no GPU needed),
material colours, studio light, the Control Mode camera angle (~60 degrees down, from the
+Z / camera side). Crops: 7 rows (grass .. cactus) x 3 columns (sprout, growing, ready),
shown at the scale the game shows each stage (sprout 0.4, growing 0.7, ready 1.0).
Orthographic, so every row has the same scale; screen-right is game +X and screen-up game -Z,
exactly like the Control Mode camera.
"""

import glob
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import *  # noqa: E402,F403

STAGE_SCALE = {"sprout": 0.4, "growing": 0.7, "ready": 1.0}
CROPS = ("grass", "wheat", "carrot", "tree", "sunflower", "pumpkin", "cactus")


def import_glb(path, game_offset, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location = o.location + g(*game_offset)
            o.scale = (o.scale[0] * scale, o.scale[1] * scale, o.scale[2] * scale)
    return new


def ground(size, center):
    bpy.ops.mesh.primitive_plane_add(size=size, location=g(*center))
    plane = bpy.context.active_object
    plane.data.materials.append(material("M_PreviewGround", "#4E6B3A", 0.9))


def render(path, target, distance, width=1600, height=1000, ortho=None, pitch=60, front=False):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "WORLD"
    shading.show_backface_culling = True  # like Roblox: an inward-facing surface shows up as a hole
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.043, 0.059, 0.082)
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 50
    if ortho is not None:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    cam_data.clip_end = 500
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    # ~60 degrees down, from the camera side (+Z in game = -Y... game z maps to Blender y)
    # front=True looks from game -Z instead (model fronts face -Z)
    pitch = math.radians(pitch)
    tx, ty, tz = target
    side = -1 if front else 1
    cam.location = g(tx, ty + distance * math.sin(pitch), tz + side * distance * math.cos(pitch))
    direction = g(tx, ty, tz) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"  wrote {path}")


def sheet(name, out, build, target, distance, width=1600, height=1000, ortho=None, **view):
    a = args_after_dashes()
    if "--sheets" in a and name not in a[a.index("--sheets") + 1].split(","):
        return
    reset_scene()
    build()
    render(os.path.join(out, "previews", name + ".png"), target, distance, width, height, ortho, **view)


if __name__ == "__main__":
    # Absolute: Blender resolves a relative render path against the drive root, not the cwd.
    out = os.path.abspath(parse_out(os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")))

    def drone():
        ground(14, (0, -1.0, 0))  # under the landing skids (they reach y = -0.95)
        import_glb(os.path.join(out, "Drone.glb"), (0, 0, 0))

    def crops():
        ground(60, (9, 0, 0))
        for row, crop in enumerate(CROPS):
            for col, stage in enumerate(("sprout", "growing", "ready")):
                path = os.path.join(out, "Crops", crop, stage + ".glb")
                if os.path.isfile(path):
                    # grass on top (far = game -Z), cactus at the bottom; stages left -> right
                    import_glb(path, (col * 6.4, 0, (row - 3) * 6.4), STAGE_SCALE[stage])

    def crops_ready():
        ground(70, (19, 0, 0))
        for i, crop in enumerate(CROPS):
            path = os.path.join(out, "Crops", crop, "ready.glb")
            if os.path.isfile(path):
                import_glb(path, (i * 6.4, 0, 0))

    def stations():
        ground(24, (3.2, -0.01, 0))
        import_glb(os.path.join(out, "Stations", "charger.glb"), (0, 0, 0))
        import_glb(os.path.join(out, "Stations", "factory.glb"), (6.4, 0, 0))

    def hats():
        ground(30, (6, -0.01, 0))
        for i, path in enumerate(sorted(glob.glob(os.path.join(out, "Hats", "*.glb")))):
            import_glb(path, (i * 3.2, 0, 0))

    def kit():
        ground(40, (8, -0.02, 0))
        for i, (rel, x) in enumerate((("Tiles/Soil", 0), ("Dressing/FencePost", 5), ("Dressing/FenceRail", 7),
                                      ("Dressing/Walkway", 12), ("Dressing/SignPost", 19))):
            path = os.path.join(out, *rel.split("/")) + ".glb"
            if os.path.isfile(path):
                import_glb(path, (x, 0.3 if rel == "Tiles/Soil" else 0, 0))

    def props_row(names, spacing):
        def build():
            ground(spacing * len(names) + 10, (spacing * (len(names) - 1) / 2, -0.02, 0))
            for i, name in enumerate(names):
                path = os.path.join(out, "Map", name + ".glb")
                if os.path.isfile(path):
                    import_glb(path, (i * spacing, 0, 0))
        return build

    nature = ["oak", "pine", "birch", "bush", "berry_bush", "rock_small", "rock_medium", "rock_large",
              "flowers_yellow", "flowers_pink", "flowers_white", "grass_tuft", "log", "mushroom"]
    farm = ["hay_bale", "crate", "barrel", "cart", "scarecrow", "well", "lamp_post", "bench", "hedge", "welcome_sign"]
    sheet("kit", out, kit, (9, 1, 0), 60, 1800, 700, ortho=26)
    sheet("nature", out, props_row(nature, 6.5), (6.5 * 6.5, 2, 0), 150, 2200, 600, ortho=96)
    sheet("farm", out, props_row(farm, 7.5), (7.5 * 4.5, 1.5, 0), 120, 2200, 600, ortho=78)
    big = ["farmhouse", "barn", "silo", "greenhouse", "chicken_coop", "water_tower"]
    small = ["tool_shed", "market_stall", "tractor", "fence_segment", "garden_bed", "haystack"]
    sheet("buildings", out, props_row(big, 22), (55, 5, 0), 250, 2200, 800, ortho=135, pitch=30, front=True)
    sheet("yard", out, props_row(small, 8), (20, 1.5, 0), 120, 2200, 700, ortho=50, pitch=30, front=True)
    sheet("landmarks", out, props_row(["windmill", "plaza", "pond", "path"], 30), (45, 3, 0), 200, 2000, 800, ortho=125)
    sheet("drone", out, drone, (0, 0, 0), 30, 1400, 1000, ortho=7.5)
    sheet("drone_front", out, drone, (0, 0, 0), 30, 1400, 1000, ortho=7.0, pitch=22, front=True)
    sheet("crops", out, crops, (6.4, 1, 0), 120, 1000, 1500, ortho=44)
    sheet("crops_ready", out, crops_ready, (19.2, 1.5, 0), 80, 2200, 700, ortho=46, pitch=35)
    sheet("stations", out, stations, (3.2, 1, 0), 60, 1600, 1000, ortho=15)
    sheet("hats", out, hats, (6.4, 0.5, 0), 60, 1800, 700, ortho=16)
