"""Decode a cooked UE 5.1 PF_FloatRGBA TextureCube (legacy .uexp from retoc) into 6 sRGB PNG faces.

The HDR values are scaled so the given percentile of luminance maps to white, then encoded to
sRGB. Faces are written in the cooked order: +X, -X, +Y, -Y, +Z, -Z.
Usage: python extract_cubemap_faces.py <texture.uexp> <out_dir> [percentile]
Requires Pillow.
"""
import struct
import sys
from pathlib import Path

from PIL import Image


def srgb_byte(x):
    x = 0.0 if x <= 0 else 1.0 if x >= 1 else x
    v = 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
    return int(v * 255 + 0.5)


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    percentile = float(sys.argv[3]) if len(sys.argv) > 3 else 99.5
    raw = src.read_bytes()
    start = raw.index(b"PF_FloatRGBA")
    width, height, depth, name_len = struct.unpack_from("<iiii", raw, start - 16)
    faces = depth & 0x7FFFFFFF
    assert faces == 6, "not a cube map"
    flags, count, size, offset = struct.unpack_from("<IIIq", raw, start + name_len + 8)
    assert size == width * height * 8 * faces
    data = raw[start + name_len + 28:start + name_len + 28 + size]
    halves = memoryview(data).cast("e")
    face_len = width * height * 4

    # Exposure: percentile of luminance across all faces maps to 1.0
    lums = sorted(
        0.2126 * halves[i] + 0.7152 * halves[i + 1] + 0.0722 * halves[i + 2]
        for i in range(0, len(halves), 4 * 16)
    )
    white = max(lums[min(len(lums) - 1, int(len(lums) * percentile / 100))], 1e-6)
    print(f"{width}x{height}x{faces}, luminance p{percentile} = {white:.4f}")

    lut_cache = {}
    out.mkdir(parents=True, exist_ok=True)
    for f in range(faces):
        base = f * face_len
        pixels = bytearray(width * height * 3)
        for p in range(width * height):
            i = base + p * 4
            for c in range(3):
                v = halves[i + c] / white
                key = round(v, 4)
                b = lut_cache.get(key)
                if b is None:
                    b = srgb_byte(v)
                    lut_cache[key] = b
                pixels[p * 3 + c] = b
        Image.frombytes("RGB", (width, height), bytes(pixels)).save(out / f"face{f}.png")
        print("wrote face", f)


if __name__ == "__main__":
    main()
