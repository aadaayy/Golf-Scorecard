#!/usr/bin/env python3
"""Redraws a course's hole diagrams from a photo of its paper scorecard as clean SVGs.

Reads the colored hole diagrams in one strip of the photo (rough, fairway, greens and
tees, water, bunkers), smooths each feature into vector shapes, and writes one SVG per
hole into the app's asset catalog in the app's own colors. The photo itself never goes
into the app.

Needs: pip install numpy pillow scikit-image scipy (and cairosvg for --preview)

Usage:
  python3 Tools/HoleDrawings/trace_holes.py COURSE_SPEC.json PHOTO.jpg [--preview sheet.png]

The course spec (see pompano-pines.json next to this script) says where each strip of
hole diagrams sits in the photo and the x ranges that separate the holes.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import graph, measure, morphology

# Colors the scan uses for each feature (several samples each); the nearest wins.
SCAN_COLORS = {
    "bg": [(254, 254, 254), (240, 242, 236)],
    "rough": [(213, 221, 182), (196, 208, 155), (228, 234, 210)],
    "fairway": [(156, 192, 139), (132, 173, 114), (145, 183, 125)],
    "green": [(58, 111, 71), (35, 110, 60), (29, 128, 60), (70, 125, 80)],
    "dark": [(14, 23, 14), (40, 40, 40)],
    "water": [(167, 196, 211), (185, 210, 225), (150, 185, 205)],
    "sand": [(225, 210, 130), (235, 215, 150), (215, 200, 110)],
}
CLASSES = list(SCAN_COLORS)

# The app's colors for each feature.
STYLE = {
    "rough": "#DCE8C4",
    "fairway": "#9FCC80",
    "water": "#A9CEEC", "water_edge": "#7DB2DC",
    "sand": "#F0DDA6", "sand_edge": "#D9C07A",
    "green": "#3E9A56", "green_edge": "#2B7340",
    "tee": "#3E9A56",
    "line": "#1F3A2B",
    "flag": "#D8433B",
}

UPSCALE = 6  # work at 6x the scan's resolution so curves come out smooth


def classify(pixels):
    a = pixels.astype(float)
    best = np.full(a.shape[:2], np.inf)
    out = np.zeros(a.shape[:2], int)
    for index, name in enumerate(CLASSES):
        for color in SCAN_COLORS[name]:
            d = ((a - np.array(color)) ** 2).sum(2)
            closer = d < best
            best[closer] = d[closer]
            out[closer] = index
    return out


def is_class(classes, *names):
    return np.isin(classes, [CLASSES.index(n) for n in names])


def remove_badges(classes):
    """Blanks the black numbered circles under each hole."""
    dark = is_class(classes, "dark")
    labels, count = ndimage.label(dark)
    for region in measure.regionprops(labels):
        h = region.bbox[2] - region.bbox[0]
        w = region.bbox[3] - region.bbox[1]
        if 15 <= h <= 45 and 15 <= w <= 45 and region.extent > 0.45:
            cy, cx = region.centroid
            yy, xx = np.ogrid[: classes.shape[0], : classes.shape[1]]
            r = max(h, w) / 2 + 1.5
            classes[(yy - cy) ** 2 + (xx - cx) ** 2 <= r * r] = CLASSES.index("bg")
    return classes


def keep_big(mask, min_size):
    return morphology.remove_small_objects(mask, min_size=min_size)


def masks_for_hole(classes, own):
    m = {}
    body = ~is_class(classes, "bg", "water")
    body = morphology.binary_closing(body, morphology.disk(3))
    body = ndimage.binary_fill_holes(body)
    # Keep only this hole: the biggest patch (a neighbouring hole's edge may peek in).
    labels, count = ndimage.label(body)
    if count:
        sizes = ndimage.sum(body, labels, range(1, count + 1))
        body = labels == (int(np.argmax(sizes)) + 1)
    m["rough"] = body
    near = ndimage.binary_dilation(body, structure=morphology.disk(25))

    water = is_class(classes, "water")
    water = morphology.binary_opening(water, morphology.disk(1))
    water = morphology.binary_closing(water, morphology.disk(3))
    water = keep_big(ndimage.binary_fill_holes(water), 40)
    labels, count = ndimage.label(water)
    # A pond belongs to the hole it sits beside: near this hole's shape and centred in its column.
    centres = ndimage.center_of_mass(water, labels, range(1, count + 1)) if count else []
    m["water"] = np.isin(labels, [i for i, (cy, cx) in zip(range(1, count + 1), centres)
                                  if (near & (labels == i)).any() and own[0] <= cx < own[1]])

    fairway = is_class(classes, "fairway", "green")
    fairway = morphology.binary_opening(fairway, morphology.disk(1))
    fairway = morphology.binary_closing(fairway, morphology.disk(2))
    m["fairway"] = keep_big(ndimage.binary_fill_holes(fairway), 60) & m["rough"]

    greens = is_class(classes, "green") | (is_class(classes, "dark") & morphology.binary_dilation(is_class(classes, "green"), morphology.disk(1)))
    greens = morphology.binary_closing(greens, morphology.disk(1))
    greens = ndimage.binary_fill_holes(greens)
    greens = morphology.binary_opening(greens, morphology.disk(1))
    m["greens"] = keep_big(greens, 6) & ndimage.binary_dilation(body, structure=morphology.disk(2))

    sand = is_class(classes, "sand")
    sand = ndimage.median_filter(sand.astype(np.uint8), size=3).astype(bool)
    sand &= ~ndimage.binary_dilation(~m["rough"], structure=morphology.disk(2))  # not the speckled edges
    m["sand"] = keep_big(sand, 6)
    return m


def shot_line(classes, greens):
    """The thin dark line from the back tee to the green, as a few straight legs."""
    labels, count = ndimage.label(greens)
    regions = measure.regionprops(labels)
    if not regions:
        return None, None
    big = [r for r in regions if r.area >= 25] or regions
    green = min(big, key=lambda r: r.centroid[0])           # topmost sizable patch
    tee = max(regions, key=lambda r: r.bbox[2])              # lowest patch: the back tee
    dark = is_class(classes, "dark")
    cost = np.where(dark, 1.0, 25.0)
    start = tuple(int(v) for v in (tee.bbox[2] - 2, (tee.bbox[1] + tee.bbox[3]) // 2))
    start = (min(start[0], classes.shape[0] - 1), start[1])
    end = tuple(int(round(v)) for v in green.centroid)
    path, _ = graph.route_through_array(cost, start, end, fully_connected=True, geometric=True)
    path = np.array(path, float)
    simple = measure.approximate_polygon(path, tolerance=6.0)
    return simple, green


def turns(line, min_degrees=10):
    """Points where the shot line bends (the dogleg), ignoring tiny wiggles."""
    out = []
    for a, b, c in zip(line, line[1:], line[2:]):
        h1 = math.atan2(b[0] - a[0], b[1] - a[1])
        h2 = math.atan2(c[0] - b[0], c[1] - b[1])
        bend = abs((math.degrees(h2 - h1) + 180) % 360 - 180)
        if bend >= min_degrees and math.dist(a, b) > 12 and math.dist(b, c) > 12:
            out.append(b)
    return out


def contours(mask, tolerance=1.2):
    """Smooth outlines of a mask, in upscaled pixel units (x, y)."""
    big = np.kron(mask.astype(float), np.ones((UPSCALE, UPSCALE)))
    big = ndimage.gaussian_filter(big, sigma=UPSCALE * 0.9)
    padded = np.pad(big, 2)
    outlines = []
    for c in measure.find_contours(padded, 0.5):
        if len(c) < 8:
            continue
        c = measure.approximate_polygon(c, tolerance=tolerance)
        outlines.append([(p[1] - 2, p[0] - 2) for p in c])
    return outlines


def smooth_path(points):
    """A closed Catmull-Rom curve through the points, as SVG cubic Beziers."""
    pts = points[:-1] if len(points) > 2 and points[0] == points[-1] else points
    n = len(pts)
    if n < 3:
        return ""
    d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
    for i in range(n):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    d.append("Z")
    return "".join(d)


def svg_for_hole(classes, number, own):
    classes = remove_badges(classes)
    m = masks_for_hole(classes, own)
    line, green = shot_line(classes, m["greens"])

    layer = lambda mask, fill, stroke=None, width=0: "".join(
        f'<path d="{smooth_path(c)}" fill="{fill}"'
        + (f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round"' if stroke else "")
        + "/>"
        for c in contours(mask)
    )
    parts = [
        layer(m["water"], STYLE["water"], STYLE["water_edge"], 3),
        layer(m["rough"], STYLE["rough"]),
        layer(m["fairway"], STYLE["fairway"]),
        layer(m["sand"], STYLE["sand"], STYLE["sand_edge"], 2),
        layer(m["greens"], STYLE["green"], STYLE["green_edge"], 2.5),
    ]
    u = UPSCALE
    if line is not None:
        pts = " ".join(f"{(x + 0.5) * u:.1f},{(y + 0.5) * u:.1f}" for y, x in line)
        parts.append(f'<polyline points="{pts}" fill="none" stroke="{STYLE["line"]}" stroke-width="3.5" '
                     'stroke-linecap="round" stroke-linejoin="round" opacity="0.85"/>')
        for y, x in turns(line):  # where each shot lands
            parts.append(f'<circle cx="{(x + 0.5) * u:.1f}" cy="{(y + 0.5) * u:.1f}" r="5" fill="#FFFFFF" '
                         f'stroke="{STYLE["line"]}" stroke-width="3"/>')
    if green is not None:  # pin and flag on the green
        gy, gx = green.centroid
        px, py = (gx + 0.5) * u, (gy + 0.5) * u
        parts.append(f'<line x1="{px:.1f}" y1="{py:.1f}" x2="{px:.1f}" y2="{py - 34:.1f}" stroke="{STYLE["line"]}" '
                     'stroke-width="3" stroke-linecap="round"/>')
        parts.append(f'<path d="M{px:.1f},{py - 34:.1f} l20,7 l-20,7 Z" fill="{STYLE["flag"]}"/>')
        parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="4" fill="#FFFFFF"/>')

    # Fit the drawing: bounding box of everything, with a margin.
    ys, xs = np.nonzero(m["rough"] | m["water"])
    margin = 6
    x0, x1 = (xs.min() - margin) * u, (xs.max() + margin + 1) * u
    y0, y1 = (ys.min() - margin - 7) * u, (ys.max() + margin + 1) * u  # room for the flag
    w, h = x1 - x0, y1 - y0
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:.0f} {y0:.0f} {w:.0f} {h:.0f}" '
        f'width="{w / u * 4:.0f}" height="{h / u * 4:.0f}">'
        + "".join(parts)
        + "</svg>\n"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec")
    parser.add_argument("photo")
    parser.add_argument("--assets", default=os.path.join(os.path.dirname(__file__), "..", "..", "GolfScorecard", "Assets.xcassets"))
    parser.add_argument("--preview", help="also render all holes onto one PNG sheet")
    args = parser.parse_args()

    spec = json.load(open(args.spec))
    photo = Image.open(args.photo).convert("RGB")
    scale = photo.width / spec["photoWidth"]
    folder = os.path.join(args.assets, spec["assetFolder"])
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, f, indent=2)

    svgs = {}
    for strip in spec["strips"]:
        x0, y0, x1, y1 = (int(v * scale) for v in strip["box"])
        classes = classify(np.array(photo.crop((x0, y0, x1, y1))))
        bounds = [int(v * scale) for v in strip["holeBounds"]]
        pad = int(12 * scale)  # overlap neighbours a little; only the hole's own patch is kept
        for i, number in enumerate(strip["holes"]):
            left, right = max(bounds[i] - pad, 0), min(bounds[i + 1] + pad, classes.shape[1])
            svg = svg_for_hole(classes[:, left:right].copy(), number, (bounds[i] - left, bounds[i + 1] - left))
            name = f'{spec["id"]}-{number:02d}'
            imageset = os.path.join(folder, name + ".imageset")
            os.makedirs(imageset, exist_ok=True)
            open(os.path.join(imageset, name + ".svg"), "w").write(svg)
            with open(os.path.join(imageset, "Contents.json"), "w") as f:
                json.dump({
                    "images": [{"filename": name + ".svg", "idiom": "universal"}],
                    "info": {"author": "xcode", "version": 1},
                    "properties": {"preserves-vector-representation": True},
                }, f, indent=2)
            svgs[number] = svg
            print("wrote", name)

    if args.preview:
        import cairosvg
        cells = []
        for number in sorted(svgs):
            png = cairosvg.svg2png(bytestring=svgs[number].encode(), output_height=1400)
            cells.append((number, Image.open(__import__("io").BytesIO(png)).convert("RGBA")))
        cell_w, cell_h, cols = 620, 1560, 9
        sheet = Image.new("RGB", (cell_w * cols, cell_h * math.ceil(len(cells) / cols)), "white")
        from PIL import ImageDraw, ImageFont
        draw = ImageDraw.Draw(sheet)
        try:
            font = ImageFont.truetype("DejaVuSans-Bold.ttf", 64)
        except OSError:
            font = ImageFont.load_default()
        for i, (number, img) in enumerate(cells):
            img.thumbnail((cell_w - 40, cell_h - 160))
            cx, cy = (i % cols) * cell_w, (i // cols) * cell_h
            sheet.paste(img, (cx + (cell_w - img.width) // 2, cy + 30), img)
            r = 50
            mx, my = cx + cell_w // 2, cy + cell_h - 80
            draw.ellipse((mx - r, my - r, mx + r, my + r), fill="#1F3A2B")
            draw.text((mx, my), str(number), fill="white", font=font, anchor="mm")
        sheet.save(args.preview)
        print("preview", args.preview, sheet.size)


if __name__ == "__main__":
    sys.exit(main())
