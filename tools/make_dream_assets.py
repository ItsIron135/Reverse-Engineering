"""Generate the dreamcore scene's textures: two tileable lawn textures and six seamless sky faces.

Sky colour is a function of elevation only, so the faces join without seams; a few small,
separate cumulus puffs sit just above the horizon on the side faces.
Usage: python make_dream_assets.py <out_dir>
Requires Pillow.
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ZENITH = (28, 140, 214)
HORIZON = (128, 202, 236)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky_colour(elevation):
    """elevation in radians, 0 at the horizon."""
    if elevation <= 0:
        return HORIZON
    return lerp(HORIZON, ZENITH, min(1.0, (elevation / (math.pi / 2)) ** 0.45))


def face(n, direction):
    img = Image.new("RGB", (n, n))
    px = img.load()
    for j in range(n):
        v = (j + 0.5) / n * 2 - 1
        for i in range(n):
            u = (i + 0.5) / n * 2 - 1
            x, y, z = direction(u, v)
            px[i, j] = sky_colour(math.atan2(y, math.hypot(x, z)))
    return img


def add_clouds(img, rng, count):
    n = img.size[0]
    layer = Image.new("L", (n, n), 0)
    draw = ImageDraw.Draw(layer)
    for _ in range(count):
        cx = rng.uniform(0.12, 0.88) * n
        cy = rng.uniform(0.40, 0.47) * n  # just above the horizon (face centre row)
        w = rng.uniform(0.025, 0.05) * n
        for _ in range(rng.randint(10, 16)):  # many small soft puffs with a flatter base
            ox, r = rng.uniform(-w, w), rng.uniform(0.15, 0.4) * w
            oy = -abs(rng.gauss(0, 0.35)) * w * 0.7
            shade = rng.randint(150, 255)
            draw.ellipse((cx + ox - r, cy + oy - r, cx + ox + r, min(cy + oy + r, cy + w * 0.12)), fill=shade)
    layer = layer.filter(ImageFilter.GaussianBlur(n / 160))
    white = Image.new("RGB", (n, n), (250, 252, 255))
    img.paste(white, (0, 0), layer.point(lambda a: min(255, int(a * 1.25))))
    return img


def periodic_noise(n, cells, rng):
    """Tileable smooth value noise in [0, 1]."""
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * n for _ in range(n)]
    for y in range(n):
        gy = y / n * cells
        y0 = int(gy)
        fy = gy - y0
        fy = fy * fy * (3 - 2 * fy)
        for x in range(n):
            gx = x / n * cells
            x0 = int(gx)
            fx = gx - x0
            fx = fx * fx * (3 - 2 * fx)
            a, b = grid[y0 % cells][x0 % cells], grid[y0 % cells][(x0 + 1) % cells]
            c, d = grid[(y0 + 1) % cells][x0 % cells], grid[(y0 + 1) % cells][(x0 + 1) % cells]
            out[y][x] = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    return out


def lawn(n, seed, base, dark, light):
    rng = random.Random(seed)
    mottle = periodic_noise(n, 6, rng)
    fine = periodic_noise(n, 48, rng)
    img = Image.new("RGB", (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            # Gentle light/dark patches around the base colour, like a mown lawn
            t = (mottle[y][x] - 0.5) * 0.55 + (fine[y][x] - 0.5) * 0.25
            px[x, y] = lerp(base, dark, -t * 1.6) if t < 0 else lerp(base, light, t * 1.6)
    # Blades: short strokes, darker roots and lighter tips, drawn with wrap-around so the tile repeats
    draw = ImageDraw.Draw(img)
    for _ in range(int(n * n / 6)):
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        length = rng.uniform(3, 8)
        angle = math.radians(rng.uniform(-30, 30))
        shade = rng.uniform(-1, 1)
        local = mottle[int(y) % n][int(x) % n]
        colour = lerp(dark, light, max(0.0, min(1.0, 0.5 + (local - 0.5) * 0.5 + shade * 0.3)))
        ex, ey = x + math.sin(angle) * length, y - math.cos(angle) * length
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                draw.line((x + ox, y + oy, ex + ox, ey + oy), fill=colour, width=1)
    big = Image.new("RGB", (n * 3, n * 3))
    for i in range(3):
        for j in range(3):
            big.paste(img, (i * n, j * n))
    return big.filter(ImageFilter.GaussianBlur(0.5)).crop((n, n, 2 * n, 2 * n))


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(3)
    n = 1024
    # Roblox skybox faces viewed from inside; elevation only depends on the face's up axis.
    sides = {"ft": None, "bk": None, "lf": None, "rt": None}
    for k, name in enumerate(sides):
        img = face(n, lambda u, v: (u, -v, 1.0))
        add_clouds(img, rng, rng.randint(1, 2))
        img.save(out / f"sky_{name}.png")
    face(n, lambda u, v: (u, 1.0, v)).save(out / "sky_up.png")
    Image.new("RGB", (64, 64), HORIZON).save(out / "sky_dn.png")
    lawn(1024, 11, (104, 168, 40), (66, 128, 24), (150, 204, 72)).save(out / "lawn_a.png")
    lawn(1024, 23, (96, 160, 36), (60, 120, 22), (140, 198, 66)).save(out / "lawn_b.png")
    print("ok")


if __name__ == "__main__":
    main()
