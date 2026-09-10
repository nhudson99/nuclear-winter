"""Print the node / mesh / animation summary of a GLB, for verifying exports."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def read_glb(path: Path) -> dict:
    data = path.read_bytes()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError(f"{path} is not a GLB")
    offset = 12
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        if chunk_type == 0x4E4F534A:
            return json.loads(data[offset + 8:offset + 8 + chunk_length])
        offset += 8 + chunk_length
    raise ValueError("no JSON chunk")


def main() -> None:
    path = Path(sys.argv[1])
    gltf = read_glb(path)
    print(f"{path.name}: {path.stat().st_size / 1024:.0f} KB")
    print("nodes:", len(gltf.get("nodes", [])))
    print("root nodes:", [gltf["nodes"][i]["name"] for i in gltf["scenes"][0]["nodes"]])
    for mesh in gltf.get("meshes", []):
        prims = mesh["primitives"]
        attrs = sorted(prims[0]["attributes"])
        total = sum(gltf["accessors"][p["indices"]]["count"] // 3 for p in prims)
        print(f"mesh {mesh['name']}: {len(prims)} primitives, {total} tris, attrs {attrs}")
    print("materials:", [m["name"] for m in gltf.get("materials", [])])
    print("images:", [(i.get("name"), i.get("mimeType")) for i in gltf.get("images", [])])
    print("skins:", [(s.get("name"), len(s["joints"])) for s in gltf.get("skins", [])])
    for anim in gltf.get("animations", []):
        times = [gltf["accessors"][s["input"]] for s in anim["samplers"]]
        duration = max(t["max"][0] for t in times)
        print(f"animation {anim['name']}: {len(anim['channels'])} channels, {duration:.2f}s")


if __name__ == "__main__":
    main()
