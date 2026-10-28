"""Convert the game's lensDirt11 bloom dirt mask into a Roblox screen overlay.

Unreal adds the dirt mask on top of bloom, so dark texels add nothing and bright texels add
light. A Roblox ImageLabel alpha-blends, so the overlay keeps the texel colour and uses its
luminance as alpha. The result is box-downsampled to fit Roblox's 1024 px image limit.
Usage: python make_lens_dirt_overlay.py <lensDirt11.png> <out.png> [max_width]
"""
import struct
import sys
import zlib

from make_vignette import write_png

BLACK_LEVEL = 14


def read_png_rgba(path):
    data = open(path, "rb").read()
    width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", data[16:29])
    assert depth == 8 and colour == 6 and interlace == 0, "expects 8-bit RGBA, non-interlaced"
    pos, idat = 8, b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        if tag == b"IDAT":
            idat += data[pos + 8:pos + 8 + length]
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * 4
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return width, height, rows


def main():
    src, out = sys.argv[1], sys.argv[2]
    max_width = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    width, height, rows = read_png_rgba(src)
    factor = max(1, -(-width // max_width))
    out_w, out_h = width // factor, height // factor
    result = []
    for oy in range(out_h):
        row = []
        for ox in range(out_w):
            r = g = b = 0
            for y in range(oy * factor, oy * factor + factor):
                line = rows[y]
                for x in range(ox * factor, ox * factor + factor):
                    r += line[x * 4]
                    g += line[x * 4 + 1]
                    b += line[x * 4 + 2]
            n = factor * factor
            r, g, b = r / n, g / n, b / n
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            peak = max(r, g, b, 1)
            # Full-brightness texel colour with its brightness carried by alpha. Sensor noise in
            # the dark background is cut off and its hue pulled to white so it does not tint the view.
            alpha = max(0.0, min(255.0, (lum - BLACK_LEVEL) * 255 / (255 - BLACK_LEVEL)))
            mix = min(1.0, lum / 96)
            colour = [round(w + (c * 255 / peak - w) * mix * 0.6) for c, w in ((r, 255), (g, 250), (b, 236))]
            row += colour + [round(alpha)]
        result.append(row)
    write_png(out, out_w, out_h, result)
    print(out_w, out_h)


if __name__ == "__main__":
    main()
