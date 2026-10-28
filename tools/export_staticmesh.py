"""Export the highest-detail LOD of cooked UE 5.1 StaticMesh packages as Wavefront OBJ in studs.

Finds FStaticMeshLODResources buffers in the export data and the .ubulk file (whichever holds
the most vertices), reads positions, normals, the first UV channel, sections and indices, and
converts Unreal's left-handed centimetre space to Roblox's right-handed stud space
(x, y, z) -> (y, z, -x) / 28 with triangle winding fixed against the stored normals.
The mesh is recentred on its bounding box; the centre (in studs, Roblox axes) is written to the
JSON index so placements can compensate for the importer recentring.
Usage: python export_staticmesh.py <out_dir> <index.json> <mesh.uasset>...
"""
import json
import math
import struct
import sys
from pathlib import Path

import ue_package

CM_PER_STUD = 28


def half(h):
    return struct.unpack("<e", struct.pack("<H", h))[0]


def find_lods(blob):
    """Yield (offset, vertex_count) for every FPositionVertexBuffer header in blob."""
    for i in range(0, len(blob) - 16):
        a, n, c, m = struct.unpack_from("<iiii", blob, i)
        if a == 12 and c == 12 and n == m and 3 <= n < 5_000_000 and i + 16 + n * 12 <= len(blob):
            yield i, n


def parse_buffers(blob, p, n):
    pos = p + 16
    positions = [struct.unpack_from("<fff", blob, pos + k * 12) for k in range(n)]
    pos += n * 12
    # FStaticMeshVertexBuffer: [strip flags] NumTexCoords, NumVertices, bFullPrecisionUVs, bHighPrecisionTangents
    for skip in range(0, 12):
        num_tex, nv, full_uv, high_tan = struct.unpack_from("<iiii", blob, pos + skip)
        if 1 <= num_tex <= 8 and nv == n and full_uv in (0, 1) and high_tan in (0, 1):
            pos += skip + 16
            break
    else:
        raise ValueError("vertex buffer header not found")
    tan_size, tan_count = struct.unpack_from("<ii", blob, pos)
    pos += 8
    normals = []
    for k in range(tan_count):
        base = pos + k * tan_size
        if tan_size == 8:  # 2 x FPackedNormal (TangentX, TangentZ), signed bytes
            x, y, z, _ = struct.unpack_from("<bbbb", blob, base + 4)
            normals.append((x / 127.0, y / 127.0, z / 127.0))
        else:  # 2 x FPackedRGBA16N
            x, y, z, _ = struct.unpack_from("<hhhh", blob, base + 8)
            normals.append((x / 32767.0, y / 32767.0, z / 32767.0))
    pos += tan_count * tan_size
    uv_size, uv_count = struct.unpack_from("<ii", blob, pos)
    pos += 8
    uvs = []
    per_vertex = uv_count // n
    for k in range(n):
        base = pos + k * per_vertex * uv_size
        if uv_size == 4:
            u, v = struct.unpack_from("<HH", blob, base)
            uvs.append((half(u), half(v)))
        else:
            uvs.append(struct.unpack_from("<ff", blob, base))
    pos += uv_count * uv_size
    # FColorVertexBuffer: [strip flags] Stride, NumVertices, [bulk array]
    for skip in range(0, 8):
        stride, cn = struct.unpack_from("<ii", blob, pos + skip)
        if stride in (0, 4) and cn in (0, n):
            pos += skip + 8
            if cn:
                es, ec = struct.unpack_from("<ii", blob, pos)
                pos += 8 + es * ec
            break
    # FRawStaticIndexBuffer: b32Bit, bulk array of bytes
    for skip in range(0, 12):
        is32, es, count = struct.unpack_from("<iii", blob, pos + skip)
        if is32 in (0, 1) and es == 1 and count > 0 and count % (4 if is32 else 2) == 0:
            pos += skip + 12
            break
    else:
        raise ValueError("index buffer not found")
    width = 4 if is32 else 2
    indices = list(struct.unpack_from("<%d%s" % (count // width, "I" if is32 else "H"), blob, pos))
    return positions, normals, uvs, indices


def find_sections(blob, before, index_count):
    """Locate the FStaticMeshSection array preceding the buffers."""
    for stride in range(20, 64, 4):
        for i in range(max(0, before - 4000), before):
            c = struct.unpack_from("<i", blob, i)[0]
            if not 1 <= c <= 64 or i + 4 + c * stride > before:
                continue
            secs = [struct.unpack_from("<iiiii", blob, i + 4 + k * stride) for k in range(c)]
            if secs[0][1] != 0:
                continue
            ok, nxt = True, 0
            for mat, first, tris, vmin, vmax in secs:
                if first != nxt or tris <= 0 or not 0 <= mat < 64 or vmin > vmax:
                    ok = False
                    break
                nxt = first + tris * 3
            if ok and nxt == index_count:
                return [{"material": s[0], "first": s[1], "triangles": s[2]} for s in secs]
    return [{"material": 0, "first": 0, "triangles": index_count // 3}]


def export(uasset, out_dir):
    pkg = ue_package.Package(uasset)
    mesh = next(e for e in pkg.exports if pkg.class_name(e) == "StaticMesh")
    candidates = []
    inline = pkg.data(mesh)
    for p, n in find_lods(inline):
        candidates.append((n, inline, p))
    bulk_path = Path(uasset).with_suffix(".ubulk")
    if bulk_path.exists():
        bulk = bulk_path.read_bytes()
        for p, n in find_lods(bulk):
            candidates.append((n, bulk, p))
    n, blob, p = max(candidates, key=lambda c: c[0])
    positions, normals, uvs, indices = parse_buffers(blob, p, n)
    sections = find_sections(blob, p, len(indices))

    conv = lambda v: (v[1] / CM_PER_STUD, v[2] / CM_PER_STUD, -v[0] / CM_PER_STUD)
    rpos = [conv(v) for v in positions]
    rnorm = [(nm[1], nm[2], -nm[0]) for nm in normals]
    lo = [min(v[k] for v in rpos) for k in range(3)]
    hi = [max(v[k] for v in rpos) for k in range(3)]
    centre = [(lo[k] + hi[k]) / 2 for k in range(3)]

    name = Path(uasset).stem
    lines = [f"# {name} exported from Your Happy Place (UE 5.1)", f"o {name}"]
    lines += ["v %.5f %.5f %.5f" % (v[0] - centre[0], v[1] - centre[1], v[2] - centre[2]) for v in rpos]
    lines += ["vn %.4f %.4f %.4f" % nm for nm in rnorm]
    lines += ["vt %.5f %.5f" % (uv[0], 1 - uv[1]) for uv in uvs]
    flipped = 0
    for s in sections:
        lines.append(f"usemtl {name}_mat{s['material']}")
        for t in range(s["triangles"]):
            a, b, c = indices[s["first"] + t * 3: s["first"] + t * 3 + 3]
            pa, pb, pc = rpos[a], rpos[b], rpos[c]
            e1 = [pb[k] - pa[k] for k in range(3)]
            e2 = [pc[k] - pa[k] for k in range(3)]
            fn = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            vn = [rnorm[a][k] + rnorm[b][k] + rnorm[c][k] for k in range(3)] if rnorm else fn
            if sum(fn[k] * vn[k] for k in range(3)) < 0:
                b, c = c, b
                flipped += 1
            lines.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % (a + 1, a + 1, a + 1, b + 1, b + 1, b + 1, c + 1, c + 1, c + 1))
    (Path(out_dir) / f"{name}.obj").write_text("\n".join(lines) + "\n")
    return {"vertices": n, "triangles": len(indices) // 3, "sections": len(sections),
            "centre": centre, "size": [hi[k] - lo[k] for k in range(3)], "flipped": flipped}


def main():
    out_dir, index_path = sys.argv[1], sys.argv[2]
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    index = {}
    for uasset in sys.argv[3:]:
        try:
            index[Path(uasset).stem] = export(uasset, out_dir)
            print(Path(uasset).stem, index[Path(uasset).stem]["vertices"], "verts")
        except Exception as e:  # report and continue with the rest
            index[Path(uasset).stem] = {"error": str(e)}
            print(Path(uasset).stem, "ERROR", e)
    Path(index_path).write_text(json.dumps(index, indent=1))


if __name__ == "__main__":
    main()
