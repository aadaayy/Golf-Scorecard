"""Trace a course's holes from USGS NAIP aerial photos (public domain) where
OpenStreetMap doesn't have them. A person (or Claude) marks each hole's tee and
green on the pictures; the shapes (greens, fairways, bunkers, water, trees) are
then found by color around those marks.

    python3 trace.py overview CID          course picture, 50 m grid, green candidates G1, G2...
    python3 trace.py zoom CID X0 Y0 X1 Y1 [RES]   detail of a box (grid meters), RES m/px (default 0.35)
    python3 trace.py check CID             planned holes' lengths against the card, and a routing picture
    python3 trace.py build CID             write Tools/CourseImport/traced/CID.json and check pictures

Photos: PHOTOS/CID/ as written by aerial.py (tiles.json, photo-*.jpg, photo-cir-*.jpg, osm.json).
Work files and pictures: WORK/CID/. The plan, WORK/CID/plan.json, is written by hand:
    {"holes": {"1": {"tee": [x, y], "via": [[x, y]], "green": [x, y] or "G4"}, ...},
     "unsure": {"7": "why"}}
Grid coordinates are meters east (x) and south (y) of the top left of the course box.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFont
from scipy import ndimage as ndi
from skimage import measure

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PHOTOS = os.environ.get("PHOTOS", os.path.join(HERE, "photos"))
WORK = os.environ.get("WORK", os.path.join(HERE, "work"))
TRACED = os.path.join(REPO, "Tools", "CourseImport", "traced")
LIBRARY = os.environ.get("LIBRARY", os.path.join(REPO, "course-library", "courses"))
SOURCE = ("Traced by hand and by color from USGS NAIP aerial photos (public domain), "
          "to fill in what OpenStreetMap doesn't have yet.")


def font(size):
    return ImageFont.load_default(size=size)


class Course:
    def __init__(self, cid):
        self.cid = cid
        self.photos = os.path.join(PHOTOS, cid)
        self.work = os.path.join(WORK, cid)
        os.makedirs(self.work, exist_ok=True)
        T = json.load(open(os.path.join(self.photos, "tiles.json")))
        self.T = T
        tiles = T["tiles"]
        self.half = 2 if tiles[0]["pixel"] < 0.45 else 1  # work at about 0.5 m a pixel
        self.PX = tiles[0]["pixel"] * self.half
        self.S = tiles[0]["size"] // self.half
        self.n = max(t["row"] for t in tiles) + 1
        self.X0 = min(t["x0"] for t in tiles)
        self.Y1 = max(t["y1"] for t in tiles)
        self.GM = self.PX * math.cos(math.radians(T["lat"]))  # ground meters a working pixel
        cache = os.path.join(self.work, "photo.npz")
        if os.path.exists(cache):
            z = np.load(cache)
            self.rgb, self.cir = z["rgb"], z["cir"]
        else:
            self.rgb, self.cir = self.mosaic("photo"), self.mosaic("photo-cir")
            np.savez(cache, rgb=self.rgb, cir=self.cir)
        self.H, self.W = self.rgb.shape[:2]
        self.elements = json.load(open(os.path.join(self.photos, "osm.json")))["elements"]
        self.card = json.load(open(os.path.join(LIBRARY, cid, "course.json")))
        # The course's own published scorecard, where the tracer found one (WORK/CID/card.json).
        own = os.path.join(self.work, "card.json")
        if os.path.exists(own):
            fixed = json.load(open(own))
            self.card = dict(self.card, holes=fixed["holes"], tees=fixed.get("tees", self.card.get("tees", [])))
        self.box()
        self._masks = None

    def mosaic(self, kind):
        S, n = self.S, self.n
        m = np.zeros((n * S, n * S, 3), np.uint8)
        for t in self.T["tiles"]:
            ext = t.get("format", "jpg")
            im = Image.open(os.path.join(self.photos, f"{kind}-{t['row']}-{t['col']}.{ext}")).convert("RGB")
            im = im.resize((S, S), Image.BILINEAR)
            m[t["row"] * S:(t["row"] + 1) * S, t["col"] * S:(t["col"] + 1) * S] = np.asarray(im)
        return m

    # Coordinates: lat/lng <-> working pixels <-> grid meters
    def to_px(self, lat, lng):
        x = math.radians(lng) * 6378137
        y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * 6378137
        return (x - self.X0) / self.PX, (self.Y1 - y) / self.PX

    def to_ll(self, px, py):
        x = self.X0 + px * self.PX
        y = self.Y1 - py * self.PX
        return math.degrees(2 * math.atan(math.exp(y / 6378137)) - math.pi / 2), math.degrees(x / 6378137)

    def g2p(self, gx, gy):
        return self.bx0 + gx / self.GM, self.by0 + gy / self.GM

    def p2g(self, px, py):
        return (px - self.bx0) * self.GM, (py - self.by0) * self.GM

    def rings(self, e):
        if e["type"] == "way" and "geometry" in e:
            return [e["geometry"]]
        if e["type"] == "relation":
            return [m["geometry"] for m in e.get("members", []) if m.get("role") == "outer" and "geometry" in m]
        return []

    def box(self):
        """The course box: the golf course outline at the course's spot (or nearest), padded 40 m."""
        from shapely.geometry import Point, Polygon
        loc = self.card["location"]
        cx, cy = self.to_px(loc["lat"], loc["lng"])
        best = None
        for e in self.elements:
            if e.get("tags", {}).get("leisure") != "golf_course":
                continue
            for r in self.rings(e):
                pts = [self.to_px(p["lat"], p["lon"]) for p in r]
                if len(pts) < 4:
                    continue
                poly = Polygon(pts).buffer(0)
                d = 0 if poly.contains(Point(cx, cy)) else poly.distance(Point(cx, cy)) * self.GM
                if d < 300 and (best is None or d < best[0] or (d == best[0] and poly.area < best[2])):
                    best = (d, pts, poly.area, e["tags"].get("name"))
        if best:
            xs, ys = [p[0] for p in best[1]], [p[1] for p in best[1]]
            x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
            self.outline, self.outline_name = best[1], best[3]
        else:
            r = 700 / self.GM
            x0, y0, x1, y1 = cx - r, cy - r, cx + r, cy + r
            self.outline, self.outline_name = None, None
        # A club bigger than its map outline (several courses, one small outline): use the whole photo.
        override = os.path.join(self.work, "box.json")
        if os.path.exists(override) and json.load(open(override)).get("whole"):
            x0, y0, x1, y1 = 0, 0, self.W, self.H
        pad = 40 / self.GM
        self.bx0, self.by0 = max(0, x0 - pad), max(0, y0 - pad)
        self.bx1, self.by1 = min(self.W, x1 + pad), min(self.H, y1 + pad)
        self.extent = ((self.bx1 - self.bx0) * self.GM, (self.by1 - self.by0) * self.GM)

    # What the photo shows
    def masks(self):
        if self._masks is not None:
            return self._masks
        rgb = self.rgb.astype(np.float32)
        nir = self.cir[..., 0].astype(np.float32)
        red = rgb[..., 0]
        ndvi = (nir - red) / (nir + red + 1)
        br = rgb.mean(-1)
        m = ndi.uniform_filter(br, 5)
        m2 = ndi.uniform_filter(br * br, 5)
        sd = np.sqrt(np.maximum(m2 - m * m, 0))
        sd7 = ndi.uniform_filter(sd, 7)
        sm = ndi.gaussian_filter(ndvi, 2) - 0.004 * ndi.gaussian_filter(sd, 2)
        # Thresholds from this photo's own turf: trees are its greenest, roughest parts.
        inside = np.zeros(ndvi.shape, bool)
        inside[int(self.by0):int(self.by1), int(self.bx0):int(self.bx1)] = True
        veg = inside & (ndvi > 0.05)
        t_tree = max(0.2, float(np.percentile(ndvi[veg], 60))) if veg.sum() > 1000 else 0.27
        tree = (ndvi > t_tree) & (sd7 > 5)
        tree = ndi.binary_closing(ndi.binary_opening(tree, iterations=2), iterations=2)
        water = (ndvi < -0.05) & (br < 110) & (sd7 < 9)
        water = ndi.binary_opening(water, iterations=3)
        sand = (br > max(165, float(np.percentile(br[inside], 92)))) & (np.abs(ndvi) < 0.08) & (sd < 10)
        sand = ndi.binary_opening(sand, iterations=1)
        turf = ~tree & ~water & ~sand & (ndvi > -0.02)
        smooth = turf & (sd < 4.5)
        self._masks = dict(ndvi=ndvi, br=br, sd=sd, sm=sm, tree=tree, water=water, sand=sand, turf=turf,
                           smooth=smooth, inside=inside)
        return self._masks

    def green_candidates(self):
        """Smooth, compact patches of turf the size of a green, as candidates G1, G2..."""
        path = os.path.join(self.work, "candidates.json")
        if os.path.exists(path):
            return json.load(open(path))
        M = self.masks()
        a = self.GM
        cand = M["smooth"] & (M["ndvi"] > 0.08) & M["inside"]
        cand = ndi.binary_opening(cand, iterations=2)
        lab, k = ndi.label(cand)
        out = []
        for i, sl in enumerate(ndi.find_objects(lab), 1):
            sub = lab[sl] == i
            area = sub.sum() * a * a
            if not 220 <= area <= 1600:
                continue
            props = measure.regionprops(sub.astype(int))[0]
            if props.solidity < 0.82 or props.axis_minor_length <= 0 or props.axis_major_length / props.axis_minor_length > 2.3:
                continue
            ring = contour(sub, sl, 0.5 / a)
            cy, cx = props.centroid
            gx, gy = self.p2g(sl[1].start + cx, sl[0].start + cy)
            out.append({"x": round(gx, 1), "y": round(gy, 1), "area": round(area), "ring": ring})
        out.sort(key=lambda c: (round(c["y"] / 60), c["x"]))
        for n, c in enumerate(out, 1):
            c["id"] = f"G{n}"
        json.dump(out, open(path, "w"))
        return out

    def plan(self):
        """The hand-written plan. A hole whose tee can't be seen may give "toward": [x, y]
        instead of "tee": the tee is then put at the card's longest yardage from the green
        (or its last bend), in that direction."""
        plan = json.load(open(os.path.join(self.work, "plan.json")))
        card = self.card_holes()
        for n, spec in plan["holes"].items():
            if "tee" not in spec and "toward" in spec:
                g = spec["green"]
                if isinstance(g, str):
                    c = next(c for c in self.green_candidates() if c["id"] == g)
                    g = [c["x"], c["y"]]
                start = spec.get("via", [g])[0]
                bent = sum(math.dist(a, b) for a, b in zip(spec.get("via", []) + [g], (spec.get("via", []) + [g])[1:]))
                yards = [v for v in (card[int(n)].get("yards") or {}).values() if v]
                length = (max(yards) * 0.9144 if yards else {3: 150, 4: 340, 5: 460}.get(card[int(n)]["par"], 300)) - bent
                dx, dy = spec["toward"][0] - start[0], spec["toward"][1] - start[1]
                d = math.hypot(dx, dy) or 1
                spec["tee"] = [round(start[0] + dx / d * length, 1), round(start[1] + dy / d * length, 1)]
                spec["tee_placed"] = True
        return plan

    def sorted_card(self):
        """A card whose pars are listed in sorted order (5s, then 4s, then 3s) with no yardages:
        the real hole order is lost, so each hole's par comes from the photo ("par" in the plan)."""
        pars = [h["par"] for h in self.card["holes"]]
        return (len(pars) >= 9 and len(set(pars)) > 1 and pars == sorted(pars, reverse=True)
                and not any(h.get("yards") for h in self.card["holes"]))

    def card_holes(self):
        holes = {h["number"]: dict(h) for h in self.card["holes"]}
        path = os.path.join(self.work, "plan.json")
        if self.sorted_card() and os.path.exists(path):
            for n, spec in json.load(open(path))["holes"].items():
                if spec.get("par") in (3, 4, 5) and int(n) in holes:
                    holes[int(n)]["par"] = spec["par"]
        return holes

    def hole_points(self, spec, cands):
        """A planned hole's line in working pixels: tee, any bends, the green's middle."""
        g = spec["green"]
        if isinstance(g, str):
            c = next(c for c in cands if c["id"] == g)
            g = [c["x"], c["y"]]
        pts = [spec["tee"]] + spec.get("via", []) + [g]
        return [self.g2p(*p) for p in pts]

    # Pictures
    def picture(self, gx0, gy0, gx1, gy1, res, src="rgb"):
        x0, y0 = self.g2p(gx0, gy0)
        x1, y1 = self.g2p(gx1, gy1)
        x0, y0 = max(0, int(x0)), max(0, int(y0))
        x1, y1 = min(self.W, int(x1)), min(self.H, int(y1))
        arr = self.rgb if src == "rgb" else self.cir
        crop = arr[y0:y1, x0:x1]
        if res < self.GM * 0.95 and self.half > 1:  # finer than the working copy: use the full photos
            crop = self.full_crop(x0, y0, x1, y1, src)
        w, h = max(1, int((x1 - x0) * self.GM / res)), max(1, int((y1 - y0) * self.GM / res))
        im = Image.fromarray(crop).resize((w, h), Image.LANCZOS)
        a = np.asarray(im).astype(np.float32)
        lo, hi = np.percentile(a, 1), np.percentile(a, 99)
        im = Image.fromarray(np.clip((a - lo) / max(1, hi - lo) * 255, 0, 255).astype(np.uint8))
        im = ImageEnhance.Color(im).enhance(1.5)
        gx0, gy0 = self.p2g(x0, y0)

        def to_im(px, py):
            gx, gy = self.p2g(px, py)
            return (gx - gx0) / res, (gy - gy0) / res
        return im, to_im, (gx0, gy0)

    def full_crop(self, x0, y0, x1, y1, src):
        S = self.S * self.half
        kind = "photo" if src == "rgb" else "photo-cir"
        X0, Y0, X1, Y1 = x0 * self.half, y0 * self.half, x1 * self.half, y1 * self.half
        out = np.zeros((Y1 - Y0, X1 - X0, 3), np.uint8)
        for t in self.T["tiles"]:
            tx0, ty0 = t["col"] * S, t["row"] * S
            ix0, iy0, ix1, iy1 = max(X0, tx0), max(Y0, ty0), min(X1, tx0 + S), min(Y1, ty0 + S)
            if ix0 >= ix1 or iy0 >= iy1:
                continue
            im = np.asarray(Image.open(os.path.join(self.photos, f"{kind}-{t['row']}-{t['col']}.{t.get('format', 'jpg')}")).convert("RGB"))
            out[iy0 - Y0:iy1 - Y0, ix0 - X0:ix1 - X0] = im[iy0 - ty0:iy1 - ty0, ix0 - tx0:ix1 - tx0]
        return out

    def grid(self, im, origin, res, step):
        d = ImageDraw.Draw(im)
        f = font(13)
        gx0, gy0 = origin
        w, h = im.size
        for gx in range(int(math.ceil(gx0 / step) * step), int(gx0 + w * res), step):
            x = (gx - gx0) / res
            d.line([(x, 0), (x, h)], fill=(255, 255, 0) if gx % (step * 2) == 0 else (190, 190, 110), width=1)
            d.text((x + 2, 2), str(gx), fill=(255, 255, 0), font=f)
        for gy in range(int(math.ceil(gy0 / step) * step), int(gy0 + h * res), step):
            y = (gy - gy0) / res
            d.line([(0, y), (w, y)], fill=(255, 255, 0) if gy % (step * 2) == 0 else (190, 190, 110), width=1)
            d.text((2, y + 2), str(gy), fill=(255, 255, 0), font=f)

    def draw_map(self, im, to_im):
        """The outline and whatever OpenStreetMap already has, for reference."""
        d = ImageDraw.Draw(im)
        if self.outline:
            d.line([to_im(*p) for p in self.outline + self.outline[:1]], fill=(255, 0, 255), width=2)
        for e in self.elements:
            t = e.get("tags", {})
            col = {"hole": (255, 60, 60), "green": (0, 255, 255), "tee": (60, 120, 255)}.get(t.get("golf"))
            if not col:
                continue
            geoms = [e.get("geometry", [])] if t.get("golf") == "hole" else self.rings(e)
            for r in geoms:
                q = [to_im(*self.to_px(p["lat"], p["lon"])) for p in r]
                if len(q) > 1:
                    d.line(q, fill=col, width=2)
            if t.get("golf") == "hole" and e.get("geometry"):
                q = to_im(*self.to_px(e["geometry"][-1]["lat"], e["geometry"][-1]["lon"]))
                d.text((q[0] + 4, q[1] - 6), str(t.get("ref", "?")), fill=(255, 80, 80), font=font(14))

    def draw_candidates(self, im, to_im):
        d = ImageDraw.Draw(im)
        for c in self.green_candidates():
            q = [to_im(*p) for p in c["ring"]]
            if len(q) > 2:
                d.line(q + q[:1], fill=(0, 255, 255), width=1)
            x, y = to_im(*self.g2p(c["x"], c["y"]))
            d.text((x + 6, y - 6), c["id"], fill=(0, 255, 255), font=font(13))


def contour(mask, sl, simplify_px):
    """The outer ring of a mask (cut out at slice sl), in working pixels."""
    pad = np.pad(mask, 1)
    cs = measure.find_contours(pad.astype(float), 0.5)
    if not cs:
        return []
    c = max(cs, key=len)
    c = measure.approximate_polygon(c, simplify_px)
    return [(float(sl[1].start + x - 1), float(sl[0].start + y - 1)) for y, x in c]


def chaikin(ring, k=2):
    for _ in range(k):
        out = []
        for a, b in zip(ring, ring[1:] + ring[:1]):
            out += [(a[0] * .75 + b[0] * .25, a[1] * .75 + b[1] * .25), (a[0] * .25 + b[0] * .75, a[1] * .25 + b[1] * .75)]
        ring = out
    return ring


def card_summary(c):
    lines = []
    for h in c.card["holes"]:
        yards = sorted(v for v in h["yards"].values() if v) if h.get("yards") else []
        span = f"{yards[0]}-{yards[-1]} yd" if yards else "no yards"
        lines.append(f"  {h['number']:2d}  par {h['par']}  {span}")
    if c.sorted_card():
        lines.append("  NOTE: this card lists its pars in sorted order, not hole by hole. Number the holes by\n"
                     "  their routing from the clubhouse, and give every hole its par from the photo in the plan,\n"
                     "  e.g. \"7\": {\"tee\": [..], \"green\": [..], \"par\": 4}. Total par should stay "
                     f"{sum(h['par'] for h in c.card['holes'])}.")
    return "\n".join(lines)


def cmd_overview(cid):
    """A whole-course map, and the course in pieces of at most 700 m at 0.5 m a pixel
    (the resolution where greens, tees and fairways show)."""
    c = Course(cid)
    w, h = c.extent
    res = max(0.9, max(w, h) / 1400)
    im, to_im, origin = c.picture(0, 0, w, h, res)
    c.grid(im, origin, res, 100)
    c.draw_map(im, to_im)
    if os.path.exists(os.path.join(c.work, "plan.json")):
        draw_plan(c, im, to_im)
    out = os.path.join(c.work, "overview.png")
    im.save(out)
    print(out, im.size, f"{res:.2f} m/px; course box {w:.0f} x {h:.0f} m; outline: {c.outline_name}")
    nx, ny = max(1, math.ceil(w / 700)), max(1, math.ceil(h / 700))
    for i in range(nx):
        for j in range(ny):
            x0, y0 = i * w / nx - (30 if i else 0), j * h / ny - (30 if j else 0)
            x1, y1 = (i + 1) * w / nx + (30 if i < nx - 1 else 0), (j + 1) * h / ny + (30 if j < ny - 1 else 0)
            cmd_zoom(cid, x0, y0, x1, y1, 0.5, course=c)
    print("Card:")
    print(card_summary(c))


def cmd_zoom(cid, x0, y0, x1, y1, res=0.35, src="rgb", course=None):
    c = course or Course(cid)
    im, to_im, origin = c.picture(float(x0), float(y0), float(x1), float(y1), float(res), src)
    c.grid(im, origin, float(res), 25 if float(res) < 0.6 else 50)
    c.draw_map(im, to_im)
    if os.path.exists(os.path.join(c.work, "plan.json")):
        draw_plan(c, im, to_im)
    out = os.path.join(c.work, f"zoom-{int(float(x0))}-{int(float(y0))}{'-cir' if src != 'rgb' else ''}.png")
    im.save(out)
    print(out, im.size)


def draw_plan(c, im, to_im):
    d = ImageDraw.Draw(im)
    cands = c.green_candidates()
    for n, spec in c.plan()["holes"].items():
        try:
            pts = [to_im(*p) for p in c.hole_points(spec, cands)]
        except (StopIteration, KeyError):
            continue
        d.line(pts, fill=(255, 140, 0), width=3)
        d.ellipse([pts[0][0] - 5, pts[0][1] - 5, pts[0][0] + 5, pts[0][1] + 5], outline=(255, 255, 255), width=2)
        d.text((pts[-1][0] + 7, pts[-1][1] + 2), n, fill=(255, 255, 255), font=font(18))
        d.text((pts[0][0] + 7, pts[0][1] - 18), f"T{n}", fill=(255, 255, 255), font=font(14))


def hole_check(c):
    plan = c.plan()
    cands = c.green_candidates()
    card = c.card_holes()
    rows = []
    for n in sorted(card):
        spec = plan["holes"].get(str(n))
        if not spec:
            rows.append((n, None, card[n], "not planned"))
            continue
        pts = c.hole_points(spec, cands)
        L = sum(math.dist(a, b) for a, b in zip(pts, pts[1:])) * c.GM / 0.9144
        yards = sorted(v for v in card[n]["yards"].values() if v) if card[n].get("yards") else []
        if yards:
            ok = yards[0] * 0.85 - 25 <= L <= yards[-1] * 1.08 + 20
            note = "" if ok else ("SHORT" if L < yards[0] else "LONG")
        else:
            lo, hi = {3: (60, 260), 4: (230, 500), 5: (400, 680)}.get(card[n]["par"], (60, 680))
            note = "" if lo <= L <= hi else "par?"
        rows.append((n, L, card[n], note))
    return rows


def cmd_check(cid):
    c = Course(cid)
    rows = hole_check(c)
    for n, L, h, note in rows:
        yards = sorted(v for v in h["yards"].values() if v) if h.get("yards") else []
        span = f"{yards[0]}-{yards[-1]}" if yards else "-"
        print(f"  {n:2d} par {h['par']}  card {span:>9} yd  traced {'' if L is None else round(L):>4} yd  {note}")
    # Holes should follow on: each tee near the last green.
    plan = c.plan()["holes"]
    cands = c.green_candidates()
    gaps = []
    for n in range(2, len(rows) + 1):
        a, b = plan.get(str(n - 1)), plan.get(str(n))
        if a and b:
            gap = math.dist(c.hole_points(a, cands)[-1], c.hole_points(b, cands)[0]) * c.GM
            if gap > 250:
                gaps.append(f"{n - 1}->{n}: {gap:.0f} m")
    if gaps:
        print("  long walks from green to next tee:", ", ".join(gaps))
    w, h = c.extent
    res = max(0.9, max(w, h) / 1700)
    im, to_im, origin = c.picture(0, 0, w, h, res)
    c.grid(im, origin, res, 100)
    draw_plan(c, im, to_im)
    out = os.path.join(c.work, "routing.png")
    im.save(out)
    print(out)


def polys(mask, gm, min_m2, simplify_m=0.8):
    out = []
    lab, n = ndi.label(mask)
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        sub = ndi.binary_fill_holes(lab[sl] == i)
        area = sub.sum() * gm * gm
        if area < min_m2:
            continue
        ring = contour(sub, sl, simplify_m / gm)
        if len(ring) >= 4:
            out.append((area, ring))
    return out


def line_mask(shape, lines, width=1):
    im = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(im)
    for g in lines:
        d.line([tuple(p) for p in g], fill=1, width=width)
    return np.asarray(im, bool)


def poly_mask(shape, rings):
    im = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(im)
    for r in rings:
        if len(r) > 2:
            d.polygon([tuple(p) for p in r], fill=1)
    return np.asarray(im, bool)


def find_green(c, M, gp, cands, spec):
    """The green at a planned point: a candidate, the smooth turf patch there, or a plain oval."""
    if isinstance(spec["green"], str):
        return next(x for x in cands if x["id"] == spec["green"])["ring"], "candidate"
    gm = c.GM
    r = int(32 / gm)
    ix, iy = int(round(gp[0])), int(round(gp[1]))
    win = (slice(max(0, iy - r), iy + r), slice(max(0, ix - r), ix + r))
    cand = M["smooth"][win] & (M["ndvi"][win] > 0.05)
    cand = ndi.binary_opening(cand, iterations=2)
    lab, k = ndi.label(cand)
    best = None
    for i in range(1, k + 1):
        ys, xs = np.nonzero(lab == i)
        area = len(xs) * gm * gm
        dist = np.min(np.hypot(xs + win[1].start - gp[0], ys + win[0].start - gp[1])) * gm
        if 250 <= area <= 1000 and dist < 4 and (best is None or dist < best[0]):
            best = (dist, i, area)
    if best:
        blob = ndi.binary_closing(lab == best[1], iterations=3)
        blob = ndi.binary_fill_holes(blob)
        props = measure.regionprops(blob.astype(int))[0]
        if props.solidity > 0.88 and props.axis_major_length < 2.0 * max(props.axis_minor_length, 1):
            ring = contour(blob, win, 0.5 / gm)
            if len(ring) >= 4:
                return chaikin(ring, 1), "found"
    # A plain oval about 24 by 20 m across the line of play
    a, b = 12 / gm, 10 / gm
    return [(gp[0] + a * math.cos(t), gp[1] + b * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 24, endpoint=False)], "oval"


def find_fairway(c, M, line, ok):
    """Fairway along a hole: the healthier, smoother turf near the line, from about 40 m past the tee."""
    from skimage.filters import threshold_otsu
    gm = c.GM
    g = np.array(line)
    seg = np.hypot(*np.diff(g, axis=0).T) * gm
    L = seg.sum()
    if L < 200:
        return []
    cum = np.concatenate([[0], np.cumsum(seg)])
    ss = np.arange(min(60, L * 0.25), L - 15, 3.0)
    pts = np.array([np.interp(ss, cum, g[:, 0]), np.interp(ss, cum, g[:, 1])]).T
    tang = np.gradient(pts, axis=0)
    tang = ndi.uniform_filter1d(tang, 9, axis=0)
    tang /= np.linalg.norm(tang, axis=1)[:, None] + 1e-9
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    offs = np.arange(-45, 45.1, 1.0)
    X = pts[:, 0][:, None] + nrm[:, 0][:, None] * offs[None, :] / gm
    Y = pts[:, 1][:, None] + nrm[:, 1][:, None] * offs[None, :] / gm

    def sample(a):
        return ndi.map_coordinates(a, [Y.ravel(), X.ravel()], order=1, mode="nearest").reshape(X.shape)
    v = sample(ndi.gaussian_filter(M["sm"], 2))
    good = sample(ok.astype(float)) > 0.5
    vals = v[good]
    if len(vals) < 300:
        return []
    thr = threshold_otsu(vals)
    fw = (v > thr) & good
    fw = ndi.binary_opening(fw, structure=np.ones((3, 3)))
    fw = ndi.binary_closing(fw, structure=np.ones((5, 5)))
    left = np.full(len(ss), np.nan)
    right = np.full(len(ss), np.nan)
    c0 = 45
    for i in range(len(ss)):
        lab, k = ndi.label(fw[i])
        best = None
        for j in range(1, k + 1):
            idx = np.nonzero(lab == j)[0]
            if len(idx) < 14:
                continue
            dc = 0 if idx[0] <= c0 <= idx[-1] else min(abs(idx[0] - c0), abs(idx[-1] - c0))
            if dc > 10:
                continue
            if best is None or dc < best[0] or (dc == best[0] and len(idx) > best[1]):
                best = (dc, len(idx), idx[0], idx[-1])
        if best:
            left[i] = offs[best[2]]
            right[i] = min(offs[best[3]], offs[best[2]] + 55)
    has = ~np.isnan(left)
    out = []
    lab, k = ndi.label(has)
    for j in range(1, k + 1):
        idx = np.nonzero(lab == j)[0]
        if len(idx) < 10:
            continue
        for e in (left, right):
            e[idx] = ndi.median_filter(e[idx], 7, mode="nearest")
            e[idx] = ndi.uniform_filter1d(e[idx], 5, mode="nearest")
        lp = [(pts[i, 0] + nrm[i, 0] * left[i] / gm, pts[i, 1] + nrm[i, 1] * left[i] / gm) for i in idx]
        rp = [(pts[i, 0] + nrm[i, 0] * right[i] / gm, pts[i, 1] + nrm[i, 1] * right[i] / gm) for i in idx]
        out.append(chaikin(lp + rp[::-1], 2))
    return out


def corridor_fairway(c, M, line, ok, half_width=17):
    """Fairway along a hole where color alone doesn't show it: the open turf within
    about 17 m of the line of play, from 50 m past the tee to just short of the green."""
    from shapely.geometry import LineString, Point
    gm = c.GM
    ln = LineString(line)
    L = ln.length * gm
    if L < 200:
        return []
    start = min(60, L * 0.25) / gm
    stop = (L - 22) / gm
    pts = [ln.interpolate(t) for t in np.linspace(start, stop, 40)]
    part = LineString([(p.x, p.y) for p in pts])
    zone = part.buffer(half_width / gm, cap_style=1)
    shape = M["tree"].shape
    zm = poly_mask(shape, [list(zone.exterior.coords)])
    fw = zm & ok & ~M["tree"]
    fw = ndi.binary_opening(fw, iterations=int(2.5 / gm))
    on_line = line_mask(shape, [[(p.x, p.y) for p in pts]], width=3)
    lab, k = ndi.label(fw)
    keep = np.isin(lab, np.unique(lab[on_line & (lab > 0)]))
    keep = ndi.binary_fill_holes(ndi.binary_closing(keep, iterations=int(3 / gm)))
    out = []
    for area, ring in polys(keep, gm, 400, 1.5):
        from shapely.geometry import Polygon
        poly = Polygon(ring).buffer(0).buffer(4 / gm).buffer(-6 / gm).buffer(2 / gm)
        for g in getattr(poly, "geoms", [poly]):
            if g.area * gm * gm >= 400:
                out.append(chaikin(list(g.exterior.coords)[:-1], 2))
    return out


def cmd_build(cid):
    from shapely.geometry import Polygon
    c = Course(cid)
    M = c.masks()
    gm = c.GM
    plan = c.plan()
    cands = c.green_candidates()
    card = c.card_holes()
    lines, greens, kinds = {}, {}, {}
    for n in sorted(card):
        spec = plan["holes"].get(str(n))
        if not spec:
            continue
        pts = c.hole_points(spec, cands)
        lines[n] = pts
        ring, how = find_green(c, M, pts[-1], cands, spec)
        greens[n] = ring
        kinds[n] = how
    shape = M["tree"].shape
    green_mask = poly_mask(shape, greens.values())
    near_line = ndi.distance_transform_edt(~line_mask(shape, lines.values())) * gm
    ok = M["turf"] & ~ndi.binary_dilation(green_mask, iterations=int(5 / gm)) & ~ndi.binary_dilation(M["sand"], iterations=1)
    fairways = {}
    for n, pts in lines.items():
        if card[n]["par"] >= 4:
            fairways[n] = find_fairway(c, M, pts, ok) or corridor_fairway(c, M, pts, ok)
    fw_mask = poly_mask(shape, [r for rs in fairways.values() for r in rs])
    # Bunkers: sand near the holes
    bunkers = []
    for area, ring in polys(M["sand"] & (near_line < 50), gm, 10, 0.4):
        xs, ys = [p[0] for p in ring], [p[1] for p in ring]
        w, h = (max(xs) - min(xs)) * gm, (max(ys) - min(ys)) * gm
        if area > 1500 or min(w, h) < 2.0 or area / (w * h + 1e-6) < 0.3:
            continue
        sub = poly_mask((int(max(ys)) + 2, int(max(xs)) + 2), [ring])
        props = measure.regionprops(sub.astype(int))
        if props and props[0].axis_minor_length * gm < 3.0:  # a cart path, not a bunker
            continue
        bunkers.append(chaikin(ring, 1))
    # Water the map doesn't have yet, near the holes
    mapped_water = []
    for e in c.elements:
        t = e.get("tags", {})
        if t.get("natural") == "water" or t.get("water") or t.get("golf") in ("water_hazard", "lateral_water_hazard"):
            mapped_water += [[c.to_px(p["lat"], p["lon"]) for p in r] for r in c.rings(e)]
    mw = ndi.binary_dilation(poly_mask(shape, mapped_water), iterations=int(4 / gm))
    water = [chaikin(r, 1) for a, r in polys(M["water"] & (near_line < 120) & ~mw, gm, 150, 1.0)]
    # Trees: crowns packed into the tree cover near the holes, kept off the playing areas
    keep_off = ndi.binary_dilation(green_mask | fw_mask | M["sand"] | M["water"], iterations=2)
    tz = M["tree"] & (near_line < 70) & ~keep_off
    dt = ndi.distance_transform_edt(tz) * gm
    taken = np.zeros_like(tz)
    trees = []
    order = np.argsort(dt.ravel())[::-1]
    yy, xx = np.unravel_index(order[:600000], dt.shape)
    for y, x in zip(yy, xx):
        rr = dt[y, x]
        if rr < 1.8:
            break
        if taken[y, x]:
            continue
        rr = min(rr, 8.0)
        rp = int(rr / gm) + 1
        y0, y1, x0, x1 = max(y - rp, 0), min(y + rp + 1, shape[0]), max(x - rp, 0), min(x + rp + 1, shape[1])
        Y, X = np.ogrid[y0:y1, x0:x1]
        taken[y0:y1, x0:x1] |= ((X - x) ** 2 + (Y - y) ** 2) <= (rr * 0.85 / gm) ** 2
        lat, lng = c.to_ll(x, y)
        trees.append([round(lat, 7), round(lng, 7), round(float(rr), 1)])

    def ll(p):
        lat, lng = c.to_ll(*p)
        return [round(lat, 7), round(lng, 7)]

    def ring_ll(r):
        r = list(r)
        q = [ll(p) for p in r]
        return q + q[:1]
    out = {"source": SOURCE,
           "holes": [{"hole": n, "par": card[n]["par"], "line": [ll(p) for p in pts]} for n, pts in sorted(lines.items())],
           "greens": [{"hole": n, "ring": ring_ll(r)} for n, r in sorted(greens.items())],
           "fairways": [{"hole": n, "ring": ring_ll(r)} for n, rs in sorted(fairways.items()) for r in rs],
           "bunkers": [{"ring": ring_ll(r)} for r in bunkers],
           "water": [{"ring": ring_ll(r)} for r in water if Polygon(r).buffer(0).area * gm * gm >= 150],
           "trees": trees}
    if c.sorted_card():
        out["pars_from_photo"] = True
    if plan.get("unsure"):
        out["unsure"] = {str(k): v for k, v in plan["unsure"].items()}
    os.makedirs(TRACED, exist_ok=True)
    path = os.path.join(TRACED, f"{cid}.json")
    json.dump(out, open(path, "w"), separators=(",", ":"))
    print(path, {k: len(v) for k, v in out.items() if isinstance(v, list)})
    print("greens:", ", ".join(f"{n} {kinds[n]}" for n in sorted(kinds)))
    # Check pictures, one per nine
    for part, holes in (("front", [n for n in lines if n <= 9]), ("back", [n for n in lines if n > 9])):
        if not holes:
            continue
        xs = [p[0] for n in holes for p in lines[n]]
        ys = [p[1] for n in holes for p in lines[n]]
        gx0, gy0 = c.p2g(min(xs), min(ys))
        gx1, gy1 = c.p2g(max(xs), max(ys))
        span = max(gx1 - gx0, gy1 - gy0) + 120
        res = max(0.5, span / 1500)
        im, to_im, origin = c.picture(gx0 - 60, gy0 - 60, gx1 + 60, gy1 + 60, res)
        d = ImageDraw.Draw(im, "RGBA")
        for t in trees:
            x, y = to_im(*c.to_px(t[0], t[1]))
            r = t[2] / res
            d.ellipse([x - r, y - r, x + r, y + r], outline=(20, 90, 20, 200))
        for rs, col in ((water, (60, 140, 255, 140)), ([r for v in fairways.values() for r in v], (140, 230, 90, 110)),
                        (bunkers, (255, 230, 150, 200)), (list(greens.values()), (30, 200, 80, 170))):
            for r in rs:
                q = [to_im(*p) for p in r]
                if len(q) > 2:
                    d.polygon(q, fill=col, outline=(255, 255, 255, 200))
        for n in holes:
            q = [to_im(*p) for p in lines[n]]
            d.line(q, fill=(255, 140, 0, 255), width=2)
            d.text((q[-1][0] + 8, q[-1][1] - 8), str(n), fill=(255, 255, 255, 255), font=font(18))
        pic = os.path.join(c.work, f"traced-{part}.png")
        im.save(pic)
        print(pic, im.size)


if __name__ == "__main__":
    cmd, cid, *rest = sys.argv[1:]
    {"overview": cmd_overview, "zoom": cmd_zoom, "check": cmd_check, "build": cmd_build}[cmd](cid, *rest)
