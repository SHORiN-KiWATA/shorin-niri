#!/usr/bin/env python3
# 由 matugen 生成：GNOME Shell 只支持 9 种预设强调色，选色相最接近 GTK 强调色的那个
import math
import subprocess

ACCENT = "{{colors.primary_fixed_dim.default.hex}}"

# 取自 libadwaita 的 --accent-* 变量
GNOME_ACCENTS = [
    ("blue", "#3584e4"),
    ("teal", "#2190a4"),
    ("green", "#3a944a"),
    ("yellow", "#c88800"),
    ("orange", "#ed5b00"),
    ("red", "#e62d42"),
    ("pink", "#d56199"),
    ("purple", "#9141ac"),
    ("slate", "#6f8396"),
]

# 色度低于这个值就当作灰色，用 slate
GRAY_CHROMA = 0.03


def hue_chroma(hex_color):
    """sRGB 十六进制 -> OKLCH 的色相(度)和色度"""
    rgb = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    r, g, b = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = [math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s)]
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return math.degrees(math.atan2(b, a)) % 360, math.hypot(a, b)


def nearest_accent(hex_color):
    hue, chroma = hue_chroma(hex_color)
    if chroma < GRAY_CHROMA:
        return "slate"

    def hue_distance(item):
        d = abs(hue_chroma(item[1])[0] - hue)
        return min(d, 360 - d)

    return min((item for item in GNOME_ACCENTS if item[0] != "slate"), key=hue_distance)[0]


accent = nearest_accent(ACCENT)
current = subprocess.run(
    ["gsettings", "get", "org.gnome.desktop.interface", "accent-color"],
    capture_output=True, text=True,
).stdout.strip().strip("'")
if current != accent:
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "accent-color", accent])
