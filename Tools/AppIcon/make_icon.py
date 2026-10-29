"""Draws the Yardage Book app icon: a hole on a cream yardage book page, in ink,
with a red flag and red yardage arcs to the middle of the green.

    python3 Tools/AppIcon/make_icon.py

Writes the 1024 x 1024 app icon and the smaller copy the app shows on its
welcome and About pages (the BookMark image). Needs Pillow.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "..", "GolfScorecard", "Assets.xcassets")

S = 4  # drawn 4x larger, then shrunk, for smooth edges
SIZE = 1024 * S

PAPER = (245, 239, 222)
INK = (38, 46, 52)
RED = (176, 72, 52)
ROUGH = (234, 236, 214)
FAIRWAY = (210, 226, 182)
GREEN = (186, 214, 164)
WATER = (196, 218, 232)
WATER_LINE = (129, 165, 191)
SAND = (236, 222, 186)
TREE = (198, 220, 176)


def p(x, y):
    return (x * S, y * S)


def bezier(points, steps=200):
    """A cubic Bezier through four control points, as a list of points."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = points
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u**3 * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t**3 * x3,
                    u**3 * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t**3 * y3))
    return out


def ribbon(center, widths):
    """A closed shape around a center line, `widths[i]` wide at each point."""
    left, right = [], []
    for i, (x, y) in enumerate(center):
        a = center[max(i - 1, 0)]
        b = center[min(i + 1, len(center) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1
        nx, ny = -dy / n, dx / n
        w = widths[i] / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def scaled(points):
    return [p(x, y) for x, y in points]


def dashed(draw, points, width, dash=22, gap=16, fill=INK):
    points = points + [points[0]]
    on, left = True, dash
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        pos = 0
        while pos < seg:
            step = min(left, seg - pos)
            if on:
                t0, t1 = pos / seg, (pos + step) / seg
                draw.line([p(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0),
                           p(a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)], fill=fill, width=width * S)
            pos += step
            left -= step
            if left <= 0:
                on = not on
                left = dash if on else gap


def inside(poly, pt):
    x, y = pt
    result = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            result = not result
        j = i
    return result


def draw_icon():
    img = Image.new("RGB", (SIZE, SIZE), PAPER)
    d = ImageDraw.Draw(img)

    # Faint grid, like the book's pages
    for v in range(64, 1024, 64):
        d.line([p(v, 0), p(v, 1024)], fill=(230, 224, 206), width=2 * S)
        d.line([p(0, v), p(1024, v)], fill=(230, 224, 206), width=2 * S)

    # The hole: a dogleg from the tee at the bottom left to the green at the top right
    line = bezier([(250, 905), (300, 560), (560, 600), (705, 268)])
    rough_widths = [250 + 70 * math.sin(i / 200 * math.pi) for i in range(len(line))]
    rough = ribbon(line, rough_widths)
    fairway_part = line[60:178]
    fairway = ribbon(fairway_part, [135 + 35 * math.sin(i / len(fairway_part) * math.pi) for i in range(len(fairway_part))])

    # Water to the right of the fairway
    pond = [(560 + 95 * math.cos(a) + 18 * math.sin(3 * a), 650 + 120 * math.sin(a)) for a in
            [i / 60 * 2 * math.pi for i in range(60)]]

    # Trees around the outside
    trees = []
    edge = rough + [rough[0]]
    total = sum(math.dist(a, b) for a, b in zip(edge, edge[1:]))
    spacing, carried = 66, 0.0
    for a, b in zip(edge, edge[1:]):
        seg = math.dist(a, b)
        along = spacing - carried
        while along <= seg:
            t = along / seg
            x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            nx, ny = -(b[1] - a[1]) / seg, (b[0] - a[0]) / seg
            if inside(rough, (x + nx * 10, y + ny * 10)):
                nx, ny = -nx, -ny
            c = (x + nx * 34, y + ny * 34)
            clear = math.dist(c, (712, 262)) > 140 and math.dist(c, (250, 899)) > 90 and math.dist(c, (812, 350)) > 70
            if 40 < c[0] < 984 and 40 < c[1] < 984 and clear and not inside(pond, c) and all(math.dist(c, o) > 62 for o in trees):
                trees.append(c)
            along += spacing
        carried = seg - (along - spacing)

    for c in trees:
        r = 27
        d.ellipse([p(c[0] - r, c[1] - r), p(c[0] + r, c[1] + r)], fill=TREE, outline=INK, width=6 * S)

    d.polygon(scaled(rough), fill=ROUGH)
    dashed(d, rough, 6)
    d.polygon(scaled(pond), fill=WATER)
    for row in range(560, 760, 22):
        wave = [(x, row + 5 * math.sin(x / 14)) for x in range(440, 680, 4)]
        pts = [q for q in wave if inside(pond, q)]
        for a, b in zip(pts, pts[1:]):
            if math.dist(a, b) < 6:
                d.line([p(*a), p(*b)], fill=WATER_LINE, width=3 * S)
    d.line(scaled(pond + [pond[0]]), fill=INK, width=6 * S, joint="curve")
    d.polygon(scaled(fairway), fill=FAIRWAY)
    d.line(scaled(fairway + [fairway[0]]), fill=INK, width=6 * S, joint="curve")

    # Tee box
    d.rounded_rectangle([p(208, 868), p(292, 930)], radius=12 * S, fill=FAIRWAY, outline=INK, width=6 * S)

    # Green, with a bunker beside it
    gx, gy = 712, 262
    d.ellipse([p(772, 318), p(852, 378)], fill=SAND, outline=INK, width=6 * S)
    d.ellipse([p(gx - 92, gy - 74), p(gx + 92, gy + 74)], fill=GREEN, outline=INK, width=8 * S)

    # Red arcs: yards to the middle of the green, only inside the hole
    arcs = Image.new("L", (SIZE, SIZE), 0)
    ad = ImageDraw.Draw(arcs)
    for radius in (290, 520):
        ad.ellipse([p(gx - radius, gy - radius), p(gx + radius, gy + radius)], outline=255, width=7 * S)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(scaled(rough), fill=255)
    arcs = Image.composite(arcs, Image.new("L", (SIZE, SIZE), 0), mask)
    img.paste(Image.new("RGB", (SIZE, SIZE), RED), (0, 0), arcs)

    # The line of play, dashed
    play = line[8:190]
    for i in range(0, len(play) - 6, 10):
        d.line([p(*play[i]), p(*play[i + 5])], fill=INK, width=5 * S)

    # Labels where the arcs cross the line
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 46 * S)
    for radius, text in ((290, "100"), (520, "150")):
        spot = min(line, key=lambda q: abs(math.dist(q, (gx, gy)) - radius))
        w = d.textlength(text, font=font) / S
        box = [p(spot[0] - w / 2 - 12, spot[1] - 30), p(spot[0] + w / 2 + 12, spot[1] + 30)]
        d.rounded_rectangle(box, radius=10 * S, fill=(252, 249, 239), outline=RED, width=6 * S)
        d.text(p(*spot), text, fill=RED, font=font, anchor="mm")

    # Flag on the pin
    d.line([p(gx, gy + 6), p(gx, gy - 190)], fill=INK, width=11 * S)
    d.polygon([p(gx + 4, gy - 190), p(gx + 118, gy - 155), p(gx + 4, gy - 120)], fill=RED, outline=INK, width=4 * S)
    d.ellipse([p(gx - 12, gy - 6), p(gx + 12, gy + 18)], fill=INK)

    return img.resize((1024, 1024), Image.LANCZOS)


def main():
    icon = draw_icon()
    icon.save(os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon.png"))
    mark = os.path.join(ASSETS, "BookMark.imageset")
    os.makedirs(mark, exist_ok=True)
    icon.resize((360, 360), Image.LANCZOS).save(os.path.join(mark, "BookMark.png"))
    with open(os.path.join(mark, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    {\n      "filename" : "BookMark.png",\n      "idiom" : "universal"\n    }\n  ],\n'
                '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    print("wrote AppIcon.png and BookMark.png")


if __name__ == "__main__":
    main()
