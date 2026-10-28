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


def value_noise(rng, cells):
    grid = [[rng.random() for _ in range(cells + 2)] for _ in range(cells + 2)]

    def sample(x, y):  # x, y in [0, cells]
        x0, y0 = int(x), int(y)
        fx, fy = x - x0, y - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a, b = grid[y0][x0], grid[y0][x0 + 1]
        c, d = grid[y0 + 1][x0], grid[y0 + 1][x0 + 1]
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

    return sample


def add_clouds(img, rng, count):
    """Small fair-weather cumulus: a domed envelope with a flat base, eroded by fractal noise,
    lit from above (bright tops, faint blue-grey undersides)."""
    n = img.size[0]
    px = img.load()
    for _ in range(count):
        w = rng.uniform(0.05, 0.09) * n  # half width in pixels
        h = w * rng.uniform(0.45, 0.6)
        cx = rng.uniform(0.15, 0.85) * n
        base = rng.uniform(0.41, 0.47) * n  # just above the horizon row
        octaves = [value_noise(rng, 4 * 2 ** k) for k in range(5)]
        lumps = [(rng.uniform(-0.7, 0.7), rng.uniform(0.35, 0.75)) for _ in range(rng.randint(3, 5))]
        x0, x1 = int(cx - w * 1.2), int(cx + w * 1.2)
        y0, y1 = int(base - h * 1.6), int(base + 2)
        for y in range(max(0, y0), min(n, y1)):
            for x in range(max(0, x0), min(n, x1)):
                u = (x - cx) / w  # -1..1
                v = (base - y) / h  # 0 at base, 1 at the top of the dome
                if v < -0.02:
                    continue
                # dome: union of a few lumps along the top
                dome = max(1 - ((u - lx) / (r * 1.25)) ** 2 - ((v - r * 0.6) / r) ** 2 for lx, r in lumps)
                dome = min(dome, 1.0) * min(1.0, (v + 0.02) * 12)  # crisp flat base
                fx, fy = (u + 1.2) / 2.4, (v + 0.1) / 1.8
                f = sum(octaves[k](fx * 4 * 2 ** k * 0.999, fy * 4 * 2 ** k * 0.999) * 0.5 ** k for k in range(5)) / 1.94
                d = dome + (f - 0.5) * 0.9
                alpha = max(0.0, min(1.0, (d - 0.05) / 0.35))
                if alpha <= 0:
                    continue
                light = 0.80 + 0.20 * min(1.0, max(0.0, v * 1.3 + (f - 0.5)))
                cloud = (round(236 * light + 19), round(240 * light + 15), round(248 * light + 7))
                bg = px[x, y]
                px[x, y] = tuple(round(bg[i] * (1 - alpha) + cloud[i] * alpha) for i in range(3))
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
