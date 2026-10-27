"""Turn Unreal's film grain texture (Marcie_Grain_v3_128_M2_000) into an alpha-blended overlay.

Unreal multiplies scene colour by the grain, which is centred on 0.5. A GUI overlay cannot
multiply, so each texel becomes white (brightening) or black (darkening) with alpha
proportional to its distance from 0.5. Overall strength is left to ImageTransparency.
Usage: python make_grain_overlay.py <grain.png> <out.png>
Requires Pillow.
"""
import sys

from PIL import Image


def main():
    src = Image.open(sys.argv[1]).convert("RGBA")
    out = Image.new("RGBA", src.size)
    pixels = []
    for r, g, b, _ in src.getdata():
        offset = (0.2126 * r + 0.7152 * g + 0.0722 * b - 128) / 128
        alpha = min(255, round(abs(offset) * 4 * 255))
        shade = 255 if offset > 0 else 0
        pixels.append((shade, shade, shade, alpha))
    out.putdata(pixels)
    out.save(sys.argv[2])


if __name__ == "__main__":
    main()
