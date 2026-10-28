"""Export a cooked UE 5.1 landscape (heightmap + weightmaps) as one PNG for Roblox Terrain.

Pixel (x, y) is landscape vertex (x, y). R/G hold the 16-bit height (R high byte), B holds the
dominant paint layer index (see the printed layer list) and A is 255. Reads the map package via
ue_package/ue_schema and the component data produced by decode_landscape().
Usage: python export_landscape.py <map.umap> <schemas.json> <exe> <out.png> <out.json>
Requires Pillow.
"""
import json
import struct
import sys
from pathlib import Path

from PIL import Image

import ue_package
import ue_schema

STRUCTS = {
    "RelativeLocation": "Vector", "RelativeRotation": "Rotator", "RelativeScale3D": "Vector",
    "WeightmapScaleBias": "Vector4", "HeightmapScaleBias": "Vector4", "MapBuildDataId": "Guid",
    "StateId": "Guid", "BakedTextureMaterialGuid": "Guid", "LastBakedTextureMaterialGuid": "Guid",
    "CachedLocalBox": "Box", "BodyInstance": "schema:BodyInstance",
    "CollisionResponses": "schema:CollisionResponse", "ResponseToChannels": "schema:ResponseContainer",
}
ARRAYS = {
    "MaterialInstances": "object", "WeightmapTextures": "object", "WeightmapLayerAllocations": "schema:WeightmapAlloc",
    "ResponseArray": "schema:ResponseChannel", "MobileMaterialInterfaces": "object", "MobileWeightmapTextures": "object",
    "IrrelevantLights": "object", "LODIndexToMaterialIndex": "int8",
}


def texture_mip0(pkg, export):
    """BGRA8 bytes of mip 0 for an uncompressed Texture2D export (inline or in .ubulk)."""
    d = pkg.data(export)
    i = d.find(b"PF_B8G8R8A8")
    w, h, _, n = struct.unpack_from("<iiii", d, i - 16)
    flags, count, size, offset = struct.unpack_from("<IIIq", d, i + n + 8)
    if flags & 0x0100:  # payload in the .ubulk file
        return w, h, pkg.path.with_suffix(".ubulk").read_bytes()[offset:offset + size]
    start = offset - pkg.path.stat().st_size
    return w, h, pkg.raw[start:start + size]


def main():
    umap, schemas_path, out_png, out_json = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    S = json.load(open(schemas_path))
    pkg = ue_package.Package(umap)
    chain = S["LandscapeComponent"] + S["Primitive"] + S["Scene"] + S["Actor"]
    comps = []
    for e in pkg.exports:
        if pkg.class_name(e) == "LandscapeComponent":
            v, _ = ue_schema.decode(pkg.data(e), chain, 0, STRUCTS, pkg.names, schemas=S, arrays=ARRAYS)
            assert "__stopped_at" not in v, e["name"]
            comps.append(v)

    size_quads = comps[0]["ComponentSizeQuads"]
    max_x = max((c.get("SectionBaseX") or 0) for c in comps) + size_quads
    max_y = max((c.get("SectionBaseY") or 0) for c in comps) + size_quads
    heights = [[0] * (max_x + 1) for _ in range(max_y + 1)]
    layer_ids = {}
    layers = [[255] * (max_x + 1) for _ in range(max_y + 1)]
    textures = {}

    def tex(index):
        if index not in textures:
            textures[index] = texture_mip0(pkg, pkg.exports[index - 1])
        return textures[index]

    for c in comps:
        bx, by = c.get("SectionBaseX") or 0, c.get("SectionBaseY") or 0
        hw, hh, hdata = tex(c["HeightmapTexture"])
        sx, sy, ox, oy = c["HeightmapScaleBias"]
        px0, py0 = round(ox * hw), round(oy * hh)
        weights = []
        for layer, tex_index, channel in [(a.get("LayerInfo", 0), a.get("WeightmapTextureIndex", 0) or 0,
                                           a.get("WeightmapTextureChannel", 0) or 0)
                                          for a in c.get("WeightmapLayerAllocations", []) if isinstance(a, dict)]:
            name = pkg.ref_path(layer).split("/")[-1] if layer else "None"
            layer_ids.setdefault(name, len(layer_ids))
            ww, wh, wdata = tex(c["WeightmapTextures"][tex_index])
            weights.append((layer_ids[name], ww, wdata, (2, 1, 0, 3)[channel]))  # RGBA channel -> BGRA byte
        for y in range(size_quads + 1):
            for x in range(size_quads + 1):
                p = ((py0 + y) * hw + px0 + x) * 4
                heights[by + y][bx + x] = hdata[p + 2] << 8 | hdata[p + 1]
                best, best_w = 255, -1
                for lid, ww, wdata, byte in weights:
                    wv = wdata[(y * ww + x) * 4 + byte]
                    if wv > best_w:
                        best, best_w = lid, wv
                layers[by + y][bx + x] = best

    img = Image.new("RGBA", (max_x + 1, max_y + 1))
    img.putdata([(heights[y][x] >> 8, heights[y][x] & 255, layers[y][x], 255)
                 for y in range(max_y + 1) for x in range(max_x + 1)])
    img.save(out_png)
    flat = [h for row in heights for h in row]
    Path(out_json).write_text(json.dumps({"width": max_x + 1, "height": max_y + 1, "layers": layer_ids,
                                          "min": min(flat), "max": max(flat)}, indent=1))
    print(max_x + 1, max_y + 1, layer_ids, min(flat), max(flat))


if __name__ == "__main__":
    main()
