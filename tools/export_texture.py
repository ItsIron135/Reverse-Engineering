"""Decode mip 0 of cooked UE 5.1 Texture2D packages (legacy .uasset/.uexp/.ubulk) to PNG.

Supports PF_B8G8R8A8, PF_DXT1, PF_DXT5, PF_BC5 and PF_BC7. Large textures are downscaled to fit
Roblox's 1024 px limit.
Usage: python export_texture.py <out_dir> <texture.uasset>...
Requires Pillow and texture2ddecoder.
"""
import struct
import sys
from pathlib import Path

import texture2ddecoder
from PIL import Image

DECODERS = {
    "PF_DXT1": texture2ddecoder.decode_bc1,
    "PF_DXT5": texture2ddecoder.decode_bc3,
    "PF_BC5": texture2ddecoder.decode_bc5,
    "PF_BC7": texture2ddecoder.decode_bc7,
}
BLOCK = {"PF_DXT1": 8, "PF_DXT5": 16, "PF_BC5": 16, "PF_BC7": 16}


def decode(uasset):
    uasset = Path(uasset)
    header_size = uasset.stat().st_size
    raw = uasset.with_suffix(".uexp").read_bytes()
    i = raw.index(b"PF_")
    w, h, _, n = struct.unpack_from("<iiii", raw, i - 16)
    fmt = raw[i:i + n].rstrip(b"\0").decode()
    mip_count = struct.unpack_from("<i", raw, i + n + 4)[0]
    pos = i + n + 8
    # Mips are listed largest first; take the first one with a payload we can reach.
    for _ in range(mip_count):
        flags, count, size, offset = struct.unpack_from("<IIIq", raw, pos)
        if flags & 0x0100:
            ubulk = uasset.with_suffix(".ubulk")
            data = ubulk.read_bytes()[offset:offset + size] if ubulk.exists() else b""
            after = pos + 20
        elif flags & 0x20:  # unused mip, no payload
            data, after = b"", pos + 20
        else:
            data = raw[pos + 20:pos + 20 + size]
            after = pos + 20 + size
        mw, mh, _ = struct.unpack_from("<iii", raw, after)
        pos = after + 12
        if len(data) == size and size:
            break
    else:
        raise ValueError("no mip payload")
    if fmt == "PF_B8G8R8A8":
        pixels = data
    else:
        pixels = DECODERS[fmt](data, mw, mh)
    image = Image.frombytes("RGBA", (mw, mh), pixels, "raw", "BGRA")
    if max(image.size) > 1024:
        scale = 1024 / max(image.size)
        image = image.resize((round(mw * scale), round(mh * scale)), Image.LANCZOS)
    return image, fmt


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for path in sys.argv[2:]:
        try:
            image, fmt = decode(path)
            image.save(out / (Path(path).stem + ".png"))
            print(Path(path).stem, fmt, image.size)
        except Exception as e:
            print(Path(path).stem, "ERROR", e)


if __name__ == "__main__":
    main()
