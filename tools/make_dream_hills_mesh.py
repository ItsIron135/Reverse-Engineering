"""Build the dreamcore hills as a grid of smooth mesh tiles in one GLB.

Roblox terrain is rendered from coarser voxels far from the camera, which turns gentle slopes
into visible rings and terraces at a distance. A MeshPart with RenderFidelity Precise keeps its
full shape at any range, so the hills are meshes instead.

Every tile's vertices are relative to its own bounding-box centre; tiles.json records each
tile's centre and size so Studio can place them exactly whatever the importer's scale.
Usage: python make_dream_hills_mesh.py <out_dir>
Requires numpy.
"""
import json
import struct
import sys
from pathlib import Path

import numpy as np

HALF, TILE, STEP, SEED = 2000, 250, 10, 17
UV_STUDS = 12  # one grass texture repeat per 12 studs


def perlin(seed):
    rng = np.random.default_rng(seed)
    perm = rng.permutation(256)
    perm = np.concatenate([perm, perm])
    angles = rng.uniform(0, 2 * np.pi, 256)
    grads = np.stack([np.cos(angles), np.sin(angles)], axis=1)

    def noise(x, y):
        xi, yi = np.floor(x).astype(int), np.floor(y).astype(int)
        xf, yf = x - xi, y - yi
        xi, yi = xi & 255, yi & 255

        def dot(ix, iy, dx, dy):
            g = grads[perm[perm[ix] + iy]]
            return g[..., 0] * dx + g[..., 1] * dy

        u = xf ** 3 * (xf * (xf * 6 - 15) + 10)
        v = yf ** 3 * (yf * (yf * 6 - 15) + 10)
        n00 = dot(xi, yi, xf, yf)
        n10 = dot(xi + 1, yi, xf - 1, yf)
        n01 = dot(xi, yi + 1, xf, yf - 1)
        n11 = dot(xi + 1, yi + 1, xf - 1, yf - 1)
        a = n00 + (n10 - n00) * u
        b = n01 + (n11 - n01) * u
        return (a + (b - a) * v) * 1.41  # roughly -1..1

    return noise


NOISE_A, NOISE_B = perlin(SEED), perlin(SEED + 5)


def height(x, z):
    # Only broad, smooth swells, same scales as the old terrain hills
    return 95 * NOISE_A(x / 650, z / 650) + 22 * NOISE_B(x / 320 + 40.5, z / 320 + 40.5)


def normals(x, z):
    e = 0.5
    dx = (height(x + e, z) - height(x - e, z)) / (2 * e)
    dz = (height(x, z + e) - height(x, z - e)) / (2 * e)
    n = np.stack([-dx, np.ones_like(dx), -dz], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def pad4(b, fill=b"\0"):
    return b + fill * (-len(b) % 4)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    k = TILE // STEP + 1
    idx = []
    for i in range(k - 1):
        for j in range(k - 1):
            a, b, c, d = i * k + j, i * k + j + 1, (i + 1) * k + j, (i + 1) * k + j + 1
            idx += [a, b, c, c, b, d]  # counter-clockwise seen from above
    indices = np.array(idx, dtype=np.uint32).tobytes()

    blob, views, accessors, meshes, nodes, tiles = b"", [], [], [], [], []

    def add(data, target, count, ctype, kind, lo=None, hi=None):
        nonlocal blob
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob = pad4(blob + data)
        acc = {"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": kind}
        if lo is not None:
            acc["min"], acc["max"] = lo, hi
        accessors.append(acc)
        return len(accessors) - 1

    for tx in range(-HALF, HALF, TILE):
        for tz in range(-HALF, HALF, TILE):
            gx, gz = np.meshgrid(np.arange(k) * STEP + tx, np.arange(k) * STEP + tz, indexing="ij")
            gx, gz = gx.astype(float), gz.astype(float)
            gy = height(gx, gz)
            centre = [tx + TILE / 2, (gy.max() + gy.min()) / 2, tz + TILE / 2]
            pos = np.stack([gx - centre[0], gy - centre[1], gz - centre[2]], axis=-1).reshape(-1, 3).astype(np.float32)
            nrm = normals(gx, gz).reshape(-1, 3).astype(np.float32)
            uv = np.stack([gx / UV_STUDS, gz / UV_STUDS], axis=-1).reshape(-1, 2).astype(np.float32)
            name = f"Hill_{(tx + HALF) // TILE}_{(tz + HALF) // TILE}"
            p = add(pos.tobytes(), 34962, len(pos), 5126, "VEC3", pos.min(0).tolist(), pos.max(0).tolist())
            nn = add(nrm.tobytes(), 34962, len(nrm), 5126, "VEC3")
            t = add(uv.tobytes(), 34962, len(uv), 5126, "VEC2")
            ii = add(indices, 34963, len(idx), 5125, "SCALAR")
            meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": p, "NORMAL": nn, "TEXCOORD_0": t}, "indices": ii}]})
            nodes.append({"name": name, "mesh": len(meshes) - 1})
            tiles.append({"name": name, "centre": centre, "size": [TILE, float(gy.max() - gy.min()), TILE]})

    gltf = {
        "asset": {"version": "2.0", "generator": "make_dream_hills_mesh.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = pad4(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(blob), 0x004E4942) + blob
    (out / "dream_hills.glb").write_bytes(glb)
    (out / "tiles.json").write_text(json.dumps({"spawnHeight": float(height(np.array(0.0), np.array(0.0))), "tiles": tiles}))
    print(len(tiles), "tiles,", len(glb) // 1024, "KB")


if __name__ == "__main__":
    main()
