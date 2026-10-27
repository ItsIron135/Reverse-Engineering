"""Bake Unreal's tonemapper vignette (VignetteSpace + ComputeVignetteMask) into a PNG overlay.

The engine multiplies linear scene colour by the mask before tonemapping. A Roblox GUI
overlay composites in display space, so the alpha uses mask^(1/2.2) as the display-space
equivalent. Output is black with alpha = 1 - that factor.
Usage: python make_vignette.py <intensity> <width> <height> <out.png>
"""
import math
import struct
import sys
import zlib


def mask(px, py, aspect, intensity):
    scale = math.sqrt(2.0) / math.sqrt(1.0 + aspect * aspect)
    x, y = px * scale * intensity, py * aspect * scale * intensity
    tan2 = x * x + y * y
    return (1.0 / (tan2 + 1.0)) ** 2


def write_png(path, width, height, rows):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    intensity, width, height, out = float(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    aspect = height / width
    rows = []
    for j in range(height):
        row = []
        py = (j + 0.5) / height * 2 - 1
        for i in range(width):
            px = (i + 0.5) / width * 2 - 1
            alpha = 1.0 - mask(px, py, aspect, intensity) ** (1 / 2.2)
            row += [0, 0, 0, max(0, min(255, round(alpha * 255)))]
        rows.append(row)
    write_png(out, width, height, rows)


if __name__ == "__main__":
    main()
