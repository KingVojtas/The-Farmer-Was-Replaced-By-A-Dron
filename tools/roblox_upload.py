"""
roblox_upload.py: uploads the game's local assets to Roblox with an Open Cloud API key.

  python tools/roblox_upload.py audio  [--dry-run]   art/audio/*.ogg -> Audio assets; writes
                                                     each id into src/shared/Config/SoundConfig.luau
  python tools/roblox_upload.py textures [--dry-run] art/textures/{soil,detail} PNGs -> Decals -> the
                                                     image ids; writes materials.project.json
                                                     (the MaterialVariants in MaterialService)
  python tools/roblox_upload.py models [--dry-run]   tools/blender/out/**/*.fbx -> Model assets;
                                                     downloads each as assets/<path>.rbxm (Rojo
                                                     syncs it to ReplicatedStorage.Assets)

Needs two environment variables (never commit them):
  ROBLOX_API_KEY      an Open Cloud key (create.roblox.com > Open Cloud > API Keys) with
                      Assets API: Read + Write; for `models` also Legacy Asset: Manage (the
                      download). Restrict it to your IP if you like.
  ROBLOX_CREATOR_ID   your Roblox user id (the owner of the game, so the place may use the assets)

Every upload is recorded in art/roblox_uploads.json (path -> sha256 + asset id): a file that
hasn't changed is never uploaded twice, so a re-run only sends what changed. New Roblox ids
still need moderation (usually minutes) before they play / render in game.
Standard library only.
"""

from __future__ import annotations

import argparse
import glob
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

API = "https://apis.roblox.com"
MANIFEST = os.path.join("art", "roblox_uploads.json")
SOUND_CONFIG = os.path.join("src", "shared", "Config", "SoundConfig.luau")
MODEL_ROOT = os.path.join("tools", "blender", "out")
POLL_SECONDS = 2
POLL_TRIES = 90


def env(name: str) -> str:
    """An environment variable; on Windows also the saved USER variable, so a key set with
    [Environment]::SetEnvironmentVariable(..., "User") works without restarting the shell."""
    value = os.environ.get(name, "")
    if value or sys.platform != "win32":
        return value
    try:
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            return str(winreg.QueryValueEx(key, name)[0])
    except OSError:
        return ""


def load_manifest() -> dict:
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_manifest(manifest: dict):
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(dict(sorted(manifest.items())), f, indent=2)
        f.write("\n")


def sha256(path: str) -> str:
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def key_path(path: str) -> str:
    return path.replace("\\", "/")


def request(method: str, url: str, key: str, body: bytes | None = None, headers: dict | None = None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    for name, value in (headers or {}).items():
        req.add_header(name, value)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def multipart(fields: dict, file_field: str, file_name: str, content_type: str, data: bytes):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        )
    parts.append(
        (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; filename="{file_name}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode()
        + data
        + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def upload(path: str, asset_type: str, content_type: str, display_name: str, key: str, creator: str) -> str:
    """Creates the asset and waits for its operation. Returns the asset id (a string)."""
    meta = {
        "assetType": asset_type,
        "displayName": display_name[:50],
        "description": "The Farmer Was Replaced By A Drone - " + key_path(path),
        "creationContext": {"creator": {"userId": str(creator)}},
    }
    with open(path, "rb") as f:
        data = f.read()
    body, ctype = multipart({"request": json.dumps(meta)}, "fileContent", os.path.basename(path), content_type, data)
    status, raw = request("POST", f"{API}/assets/v1/assets", key, body, {"Content-Type": ctype})
    if status >= 300:
        raise RuntimeError(f"upload {path}: HTTP {status}: {raw[:400].decode(errors='replace')}")
    operation = json.loads(raw)
    op_id = operation.get("operationId") or operation.get("path", "").split("/")[-1]
    for _ in range(POLL_TRIES):
        if operation.get("done"):
            break
        time.sleep(POLL_SECONDS)
        status, raw = request("GET", f"{API}/assets/v1/operations/{op_id}", key)
        if status >= 300:
            raise RuntimeError(f"poll {path}: HTTP {status}: {raw[:400].decode(errors='replace')}")
        operation = json.loads(raw)
    if not operation.get("done"):
        raise RuntimeError(f"upload {path}: still processing after {POLL_SECONDS * POLL_TRIES} s (operation {op_id})")
    if "error" in operation:
        raise RuntimeError(f"upload {path}: {operation['error']}")
    asset_id = str(operation.get("response", {}).get("assetId", ""))
    if not asset_id.isdigit():
        raise RuntimeError(f"upload {path}: no assetId in {operation}")
    return asset_id


def download(asset_id: str, key: str) -> bytes:
    status, raw = request("GET", f"{API}/asset-delivery-api/v1/assetId/{asset_id}", key)
    if status >= 300:
        raise RuntimeError(
            f"download {asset_id}: HTTP {status} (the key needs Legacy Asset: Manage): "
            + raw[:300].decode(errors="replace")
        )
    location = json.loads(raw).get("location")
    if not location:
        raise RuntimeError(f"download {asset_id}: no location in the reply")
    with urllib.request.urlopen(location, timeout=120) as response:
        data = response.read()
    return gzip.decompress(data) if data[:2] == b"\x1f\x8b" else data


def sheet_digest(fbx: str) -> str:
    """sha256 of a model's Blender part sheet ("" when it has none)."""
    sheet = os.path.splitext(fbx)[0] + ".parts.json"
    return sha256(sheet) if os.path.isfile(sheet) else ""


def finish_model(fbx: str, rbxm: str):
    """Colours, pivot and cleanup from the Blender part sheet (tools/apply_parts.luau). A model
    that can't be finished is deleted, so Rojo never syncs a grey or mis-pivoted model."""
    sheet = os.path.splitext(fbx)[0] + ".parts.json"
    if not os.path.isfile(sheet):
        print(f"     (no part sheet for {key_path(fbx)}: left as imported)")
        return
    result = subprocess.run(["lune", "run", "tools/apply_parts", rbxm, sheet], capture_output=True, text=True)
    print("     " + (result.stdout.strip() or result.stderr.strip()))
    if result.returncode != 0:
        os.remove(rbxm)
        raise RuntimeError(f"apply_parts failed for {key_path(rbxm)}")


# MaterialVariants (MaterialService): name -> (BaseMaterial, StudsPerTile, pattern, folder, maps).
# Soil* = the field tile states (SoilLook); the rest are light neutral detail sets that the part's
# Color tints (tools/build_textures.py "detail"), applied to meshes by tools/apply_parts.luau.
VARIANTS = {
    "SoilDry": ("Ground", 8, "Organic", "soil", ("Color", "Normal", "Roughness")),
    "SoilTilled": ("Ground", 6.4, "Regular", "soil", ("Color", "Normal", "Roughness")),
    "SoilWet": ("Ground", 6.4, "Regular", "soil", ("Color", "Normal", "Roughness")),
    "SoilDug": ("Ground", 4, "Organic", "soil", ("Color", "Normal", "Roughness")),
    "DroneHull": ("Metal", 4, "Regular", "detail", ("Color", "Normal", "Roughness", "Metalness")),
    "CropLeaf": ("Grass", 2, "Organic", "detail", ("Color", "Normal", "Roughness")),
    "CropSkin": ("Plastic", 2, "Organic", "detail", ("Color", "Normal", "Roughness")),
    "Bark": ("Wood", 4, "Regular", "detail", ("Color", "Normal", "Roughness")),
    "Planks": ("WoodPlanks", 6, "Regular", "detail", ("Color", "Normal", "Roughness")),
    "Shingles": ("Slate", 6, "Regular", "detail", ("Color", "Normal", "Roughness")),
    "Stone": ("Cobblestone", 8, "Organic", "detail", ("Color", "Normal", "Roughness")),
}
MATERIALS_PROJECT = "materials.project.json"


def resolve_image_id(decal_id: str, key: str) -> str:
    """An uploaded Decal wraps an Image; textures need the IMAGE id. The decal asset (binary
    or XML) names it in its Texture property."""
    data = download(decal_id, key)
    for match in re.finditer(rb"(?:rbxassetid://|asset/\?id=)(\d+)", data):
        found = match.group(1).decode()
        if found != decal_id:
            return found
    raise RuntimeError(f"decal {decal_id}: no image id inside")


def write_materials_project(manifest: dict):
    """materials.project.json (mounted at MaterialService by default.project.json)."""
    tree = {"$className": "MaterialService"}
    missing = []
    for name, (base, studs, pattern, folder, maps) in VARIANTS.items():
        props = {"BaseMaterial": base, "StudsPerTile": studs, "MaterialPattern": pattern}
        for m in maps:
            entry = manifest.get(f"art/textures/{folder}/{name}_{m}.png")
            if entry is None:
                missing.append(f"{name}_{m}")
                continue
            props[f"{m}Map"] = f"rbxassetid://{entry['assetId']}"
        tree[name] = {"$className": "MaterialVariant", "$properties": props}
    with open(MATERIALS_PROJECT, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"name": "DroneFarmMaterials", "tree": tree}, f, indent="\t")
        f.write("\n")
    print(f"wrote {MATERIALS_PROJECT}" + (f" (missing: {', '.join(missing)})" if missing else ""))


def set_sound_id(name: str, asset_id: str):
    with open(SOUND_CONFIG, encoding="utf-8", newline="") as f:
        source = f.read()
    pattern = re.compile(r"(\n\t" + re.escape(name) + r" = \{\n\t\tassetId = )\d+(,)")
    source, count = pattern.subn(lambda m: m.group(1) + asset_id + m.group(2), source)
    if count != 1:
        raise RuntimeError(f"SoundConfig.luau: no single `{name} = {{ assetId = ...` entry")
    with open(SOUND_CONFIG, "w", encoding="utf-8", newline="") as f:
        f.write(source)


def jobs(kind: str):
    if kind == "textures":
        for name, (_base, _studs, _pattern, folder, maps) in VARIANTS.items():
            for m in maps:
                path = os.path.join("art", "textures", folder, f"{name}_{m}.png")
                yield path, "Decal", "image/png", f"DroneFarm {name} {m}", name
        return
    if kind == "audio":
        for path in sorted(glob.glob(os.path.join("art", "audio", "*.ogg"))):
            name = os.path.splitext(os.path.basename(path))[0]
            yield path, "Audio", "audio/ogg", "DroneFarm " + name, name
    else:
        for path in sorted(glob.glob(os.path.join(MODEL_ROOT, "**", "*.fbx"), recursive=True)):
            rel = os.path.splitext(os.path.relpath(path, MODEL_ROOT))[0]
            # Map props aren't runtime assets: tools/build_map.luau places them into map/Map.rbxm.
            parts = rel.replace("\\", "/").split("/")
            if parts[0] == "Map":
                target = os.path.join("map", "props", *parts[1:]) + ".rbxm"
            else:
                target = os.path.join("assets", rel + ".rbxm")
            yield path, "Model", "model/fbx", "DroneFarm " + key_path(rel), target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("kind", choices=["audio", "models", "textures"])
    parser.add_argument("--dry-run", action="store_true", help="list what would be uploaded, send nothing")
    args = parser.parse_args()

    manifest = load_manifest()
    todo = []
    for path, asset_type, ctype, display, target in jobs(args.kind):
        entry = manifest.get(key_path(path))
        digest = sha256(path)
        fresh = entry is not None and entry.get("sha256") == digest
        todo.append((path, asset_type, ctype, display, target, digest, fresh))
    if not todo:
        print("nothing to upload (build the files first)", file=sys.stderr)
        return 1
    for path, _, _, _, target, _, fresh in todo:
        stale = args.kind == "models" and fresh and manifest[key_path(path)].get("sheet") != sheet_digest(path)
        print(f"{'sheet' if stale else 'skip' if fresh else 'send'}  {key_path(path)}  ->  {target}")
    if args.dry_run:
        return 0

    key = env("ROBLOX_API_KEY")
    creator = env("ROBLOX_CREATOR_ID")
    if not key or not creator.isdigit():
        print("set ROBLOX_API_KEY and ROBLOX_CREATOR_ID first (see the top of this file)", file=sys.stderr)
        return 2

    failures = 0
    for path, asset_type, ctype, display, target, digest, fresh in todo:
        try:
            if fresh:
                asset_id = manifest[key_path(path)]["assetId"]
            elif args.kind == "textures":
                decal_id = upload(path, asset_type, ctype, display, key, creator)
                asset_id = resolve_image_id(decal_id, key)
                manifest[key_path(path)] = {"type": "Image", "sha256": digest, "assetId": asset_id, "decalId": decal_id}
                save_manifest(manifest)
                print(f"  {key_path(path)}: image {asset_id} (decal {decal_id})")
            else:
                asset_id = upload(path, asset_type, ctype, display, key, creator)
                manifest[key_path(path)] = {"type": asset_type, "sha256": digest, "assetId": asset_id}
                save_manifest(manifest)
                print(f"  {key_path(path)}: {asset_type} {asset_id}")
            if args.kind == "textures":
                pass
            elif args.kind == "audio":
                set_sound_id(target, asset_id)
            elif not fresh or not os.path.isfile(target) or manifest[key_path(path)].get("sheet") != sheet_digest(path):
                # A changed part sheet alone (colours, variants) re-finishes the SAME asset from a
                # fresh download: apply_parts must always start from the importer's raw model.
                data = download(asset_id, key)  # first: a failed download must not leave an empty file
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "wb") as f:
                    f.write(data)
                print(f"  -> {key_path(target)}")
                finish_model(path, target)
                manifest[key_path(path)]["sheet"] = sheet_digest(path)
                save_manifest(manifest)
        except Exception as err:  # keep going: one bad file shouldn't stop the batch
            failures += 1
            print(f"  FAILED {key_path(path)}: {err}", file=sys.stderr)
    if args.kind == "textures":
        write_materials_project(manifest)
    print(f"done, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
