"""Fit Roblox ColorCorrectionEffect settings to the game's colour grade.

Rebuilds, for neutral greys, Unreal 5.1's ColorCorrectAll (shadow/midtone/highlight regions)
followed by its filmic tonemapper and sRGB encoding, once with the game's active
PostProcessVolume settings and once with engine defaults. The difference between the two is
the look the game adds. That transfer curve is then least-squares fitted with Roblox's
contrast/brightness model, out = (in - 0.5) * (1 + Contrast) + 0.5 + Brightness.
Usage: python fit_color_grade.py
"""
import math

# Game PostProcessVolume (all primary maps)
GAME = dict(contrast=1.2, gamma_shadows=1.48, gamma_midtones=1.48, gamma_highlights=1.0, white_clip=1.0)
# Engine defaults
DEFAULT = dict(contrast=1.0, gamma_shadows=1.0, gamma_midtones=1.0, gamma_highlights=1.0, white_clip=0.04)
SLOPE, TOE, SHOULDER, BLACK_CLIP = 0.88, 0.55, 0.26, 0.0  # inherited engine defaults
SHADOWS_MAX, HIGHLIGHTS_MIN, HIGHLIGHTS_MAX = 0.09, 0.5, 1.0


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def color_correct(x, contrast, gamma):
    x = (max(x, 0.0) / 0.18) ** contrast * 0.18
    return x ** (1.0 / gamma)


def color_correct_all(x, s):
    shadows = color_correct(x, s["contrast"], s["gamma_shadows"])
    midtones = color_correct(x, s["contrast"], s["gamma_midtones"])
    highlights = color_correct(x, s["contrast"], s["gamma_highlights"])
    ws = 1 - smoothstep(0, SHADOWS_MAX, x)
    wh = smoothstep(HIGHLIGHTS_MIN, HIGHLIGHTS_MAX, x)
    return shadows * ws + midtones * (1 - ws - wh) + highlights * wh


def film_tonemap(x, white_clip):
    x = max(x, 1e-10)
    toe_scale = 1 + BLACK_CLIP - TOE
    shoulder_scale = 1 + white_clip - SHOULDER
    in_match = out_match = 0.18
    if TOE > 0.8:
        toe_match = (1 - TOE - out_match) / SLOPE + math.log10(in_match)
    else:
        bt = (out_match + BLACK_CLIP) / toe_scale - 1
        toe_match = math.log10(in_match) - 0.5 * math.log((1 + bt) / (1 - bt)) * (toe_scale / SLOPE)
    straight_match = (1 - TOE) / SLOPE - toe_match
    shoulder_match = SHOULDER / SLOPE - straight_match
    log_x = math.log10(x)
    straight = SLOPE * (log_x + straight_match)
    toe = -BLACK_CLIP + (2 * toe_scale) / (1 + math.exp((-2 * SLOPE / toe_scale) * (log_x - toe_match)))
    shoulder = (1 + white_clip) - (2 * shoulder_scale) / (1 + math.exp((2 * SLOPE / shoulder_scale) * (log_x - shoulder_match)))
    toe = toe if log_x < toe_match else straight
    shoulder = shoulder if log_x > shoulder_match else straight
    t = min(1.0, max(0.0, (log_x - toe_match) / (shoulder_match - toe_match)))
    if shoulder_match < toe_match:
        t = 1 - t
    t = (3 - 2 * t) * t * t
    return max(0.0, toe + (shoulder - toe) * t)


def srgb(x):
    x = min(1.0, max(0.0, x))
    return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055


def display(x, s):
    return srgb(film_tonemap(color_correct_all(x, s), s["white_clip"]))


def main():
    # Scene-linear greys from deep shadow to beyond white, log spaced.
    samples = [10 ** (k / 40) for k in range(-160, 41)]
    pairs = []
    for x in samples:
        d_in, d_out = display(x, DEFAULT), display(x, GAME)
        if 0.02 < d_in < 0.98:
            pairs.append((d_in, d_out))
    # Least squares for out = a * in + b, then Contrast = a - 1, Brightness = b - 0.5 * (1 - a)
    n = len(pairs)
    sx = sum(p[0] for p in pairs)
    sy = sum(p[1] for p in pairs)
    sxx = sum(p[0] ** 2 for p in pairs)
    sxy = sum(p[0] * p[1] for p in pairs)
    a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    b = (sy - a * sx) / n
    contrast = a - 1
    brightness = b - 0.5 * (1 - a)
    worst = max(abs(a * i + b - o) for i, o in pairs)
    print("display in -> game display out (selected greys)")
    for x in (0.005, 0.02, 0.05, 0.18, 0.5, 1, 2, 5):
        print(f"  scene {x:<6} default {display(x, DEFAULT):.3f}  game {display(x, GAME):.3f}")
    print(f"fit over {n} samples: Contrast={contrast:.3f} Brightness={brightness:.3f} (max error {worst:.3f})")


if __name__ == "__main__":
    main()
