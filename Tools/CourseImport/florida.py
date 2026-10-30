#!/usr/bin/env python3
"""Fills the course library with every Florida course from open data.

Three steps, each its own command, so the automatic import (course-import.yml)
can run them a little at a time:

  fetch-api   Reads the Florida courses from the OpenGolfAPI open dataset, then asks
              the OpenGolfAPI course API for each course's full scorecard (par,
              stroke index and tee yardages). Keeps what it needs in cache/api/,
              one file per course, so each course is only asked for once. The
              free API allows 1,000 calls a day, so it stops at --limit.
  fetch-osm   Asks OpenStreetMap (through Overpass) for the holes, greens,
              fairways, bunkers, tees and water drawn on Florida's golf courses,
              and keeps them in cache/osm-florida.json.gz.
  build       Turns the cache into course folders in course-library: a course.json
              each, and an SVG drawing per hole where OpenStreetMap has the hole.
              Then run build_index.py to rewrite index.json.

Data credit (both are ODbL 1.0, so the course library stays open under ODbL):
  © OpenStreetMap contributors · Contains data from OpenGolfAPI (opengolfapi.org)

Only uses the Python standard library.

Usage, from the repository's top folder:
  python3 Tools/CourseImport/florida.py fetch-api --dataset opengolfapi-us.ndjson --limit 900
  python3 Tools/CourseImport/florida.py fetch-osm
  python3 Tools/CourseImport/florida.py build course-library
"""
import argparse
import gzip
import json
import math
import os
import re
import shutil
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
API_CACHE = os.path.join(CACHE, "api")
OSM_CACHE = os.path.join(CACHE, "osm-florida.json.gz")
IDS_FILE = os.path.join(HERE, "florida-ids.json")
REPORT_FILE = os.path.join(HERE, "florida-report.json")

API = "https://api.opengolfapi.org/api/v1/courses/"
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter"]
USER_AGENT = "YardageBook-course-import/1.0 (github.com/aadaayy/Golf-Scorecard)"

# Courses already in the library that came from somewhere better (Pompano Beach
# Pines was drawn from its paper card), so the import leaves them alone.
SKIP = {"7beffd3d-73d6-4d7f-b783-2a75403dc10f": "pompano-pines"}


# MARK: fetch-api

def florida_courses(dataset):
    courses = []
    with open(dataset, encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            feature = json.loads(line)
            p = feature.get("properties", feature)
            if p.get("state") != "FL":
                continue
            lng, lat = (feature.get("geometry") or {}).get("coordinates", [None, None])
            courses.append({"id": p["id"], "name": p.get("name") or "", "city": p.get("city") or "",
                            "lat": lat, "lng": lng, "holes": p.get("holes"), "par": p.get("par")})
    courses.sort(key=lambda c: c["id"])
    return courses


def trim_detail(course, detail):
    """Only what the app uses: names, town, place, and the scorecard."""
    keep_tee = ("tee_key", "tee_name", "tee_color", "gender", "par", "yardage")
    keep_hole = ("number", "par", "handicap_index", "yardages")
    return {
        "id": course["id"],
        "dataset_name": course["name"],
        "course_name": detail.get("course_name"),
        "club_name": detail.get("club_name"),
        "city": detail.get("city") or course["city"],
        "lat": detail.get("lat", course["lat"]),
        "lng": detail.get("lng", course["lng"]),
        "holes": detail.get("holes"),
        "par": detail.get("par"),
        "tees": [{k: t.get(k) for k in keep_tee} for t in detail.get("tees") or [] if isinstance(t, dict)],
        "holes_data": [{k: h.get(k) for k in keep_hole} for h in detail.get("holes_data") or [] if isinstance(h, dict)],
    }


def get_json(url, data=None, timeout=60):
    request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_api(args):
    os.makedirs(API_CACHE, exist_ok=True)
    courses = [c for c in florida_courses(args.dataset) if c["id"] not in SKIP]
    todo = [c for c in courses if not os.path.exists(os.path.join(API_CACHE, c["id"] + ".json"))]
    print(f"{len(courses)} Florida courses; {len(courses) - len(todo)} already fetched, {len(todo)} to go", flush=True)
    calls = 0
    for course in todo:
        if calls >= args.limit:
            print(f"Stopped at the limit of {args.limit} calls; the next run carries on")
            break
        calls += 1
        path = os.path.join(API_CACHE, course["id"] + ".json")
        try:
            detail = get_json(API + course["id"])
            record = trim_detail(course, detail.get("course", detail) if isinstance(detail, dict) else {})
        except urllib.error.HTTPError as error:
            if error.code == 404:
                record = {"id": course["id"], "dataset_name": course["name"], "missing": True}
            elif error.code == 429:
                print("The API says we've used today's calls; the next run carries on")
                break
            else:
                print(f"{course['id']}: HTTP {error.code}, skipped for now")
                continue
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            print(f"{course['id']}: {error}, skipped for now")
            continue
        with open(path, "w", encoding="utf-8") as f:
            json.dump(record, f, indent=1, ensure_ascii=False, sort_keys=True)
            f.write("\n")
        time.sleep(args.pause)
    left = sum(1 for c in courses if not os.path.exists(os.path.join(API_CACHE, c["id"] + ".json")))
    print(f"Made {calls} calls; {left} courses left to fetch")


# MARK: fetch-osm

# Florida, cut into squares small enough for Overpass to answer quickly. A square
# that times out is cut into four and asked again.
FLORIDA = (24.3, -87.7, 31.1, -79.9)  # south, west, north, east
TILE = 1.0

OVERPASS_QUERY = """
[out:json][timeout:240];
(way["leisure"="golf_course"]({b}); relation["leisure"="golf_course"]({b}););
out tags geom;
(way["golf"]({b}); relation["golf"]({b}););
out tags geom;
way["golf"="hole"]({b})->.holes;
(way(around.holes:120)["natural"="water"]; relation(around.holes:120)["natural"="water"]["type"="multipolygon"];);
out tags geom;
"""

FEATURE_TAGS = ("golf", "natural", "leisure", "ref", "par", "handicap", "golf:par", "golf:handicap",
                "name", "golf:course:name", "course:name", "course", "type")


def rounded(geometry):
    return [[round(p["lat"], 6), round(p["lon"], 6)] for p in geometry or [] if p]


def overpass(box, depth=0):
    """Every element in the box, cutting it smaller when Overpass can't manage it whole."""
    s, w, n, e = box
    body = urllib.parse.urlencode({"data": OVERPASS_QUERY.format(b=f"{s},{w},{n},{e}")}).encode()
    for attempt in range(3):
        url = OVERPASS[attempt % len(OVERPASS)]
        try:
            answer = get_json(url, data=body, timeout=300)
            if "remark" in answer and "runtime error" in answer["remark"]:
                raise ValueError(answer["remark"])
            return answer.get("elements", [])
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            print(f"  {box}: {error}", flush=True)
            time.sleep(10 * (attempt + 1))
    if depth >= 2:
        raise RuntimeError(f"Overpass couldn't answer for {box}")
    mid_lat, mid_lng = (s + n) / 2, (w + e) / 2
    out = []
    for quarter in ((s, w, mid_lat, mid_lng), (s, mid_lng, mid_lat, e), (mid_lat, w, n, mid_lng), (mid_lat, mid_lng, n, e)):
        out += overpass(quarter, depth + 1)
    return out


def fetch_osm(args):
    s0, w0, n0, e0 = FLORIDA
    tiles = []
    lat = s0
    while lat < n0:
        lng = w0
        while lng < e0:
            tiles.append((round(lat, 3), round(lng, 3), round(min(lat + TILE, n0), 3), round(min(lng + TILE, e0), 3)))
            lng += TILE
        lat += TILE
    found = {}
    try:
        for i, tile in enumerate(tiles, 1):
            elements = overpass(tile)
            for e in elements:
                found[f"{e['type']}/{e['id']}"] = e
            print(f"Square {i} of {len(tiles)}: {len(elements)} features", flush=True)
            time.sleep(2)
    except RuntimeError as error:
        sys.exit(f"{error}; kept the old OpenStreetMap copy")
    elements = []
    for e in found.values():
        tags = {k: v for k, v in (e.get("tags") or {}).items() if k in FEATURE_TAGS}
        item = {"id": f"{e['type']}/{e['id']}", "tags": tags}
        if e["type"] == "way":
            item["geometry"] = rounded(e.get("geometry"))
        elif e["type"] == "relation":
            item["members"] = [{"role": m.get("role", ""), "geometry": rounded(m.get("geometry"))}
                               for m in e.get("members", []) if m.get("type") == "way" and m.get("geometry")]
        else:
            continue
        elements.append(item)
    elements.sort(key=lambda e: e["id"])
    if len([e for e in elements if e["tags"].get("leisure") == "golf_course"]) < 100:
        sys.exit("Overpass gave a half answer (under 100 golf courses); kept the old copy")
    os.makedirs(CACHE, exist_ok=True)
    data = json.dumps({"attribution": "© OpenStreetMap contributors, ODbL 1.0", "elements": elements},
                      separators=(",", ":"), ensure_ascii=False).encode()
    with gzip.GzipFile(OSM_CACHE, "wb", mtime=0) as f:
        f.write(data)
    holes = sum(1 for e in elements if e["tags"].get("golf") == "hole")
    print(f"Kept {len(elements)} OpenStreetMap features, {holes} of them holes")


# MARK: build: scorecards

def slug(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", text.lower())).strip("-")


def tidy_name(name):
    name = re.sub(r"\s+", " ", name or "").strip()
    if name.endswith(" The"):  # "Golf Club Of Amelia Island The" -> "The Golf Club Of Amelia Island"
        name = "The " + name[:-4]
    return name


def tee_names(record):
    """Yardage keys ("black") to the tee's name ("Black"), from the tees list."""
    names = {}
    for tee in record.get("tees") or []:
        key = (tee.get("tee_key") or "").split("-")[0].strip().lower()
        name = (tee.get("tee_name") or "").strip()
        if key and name and key not in names:
            names[key] = name
    return names


def scorecard(record):
    """The course in the app's format, or the reason it can't be played yet."""
    holes = sorted((h for h in record.get("holes_data") or [] if h.get("number")), key=lambda h: h["number"])
    count = len(holes)
    if record.get("missing"):
        return None, "not in the course API"
    if count == 0:
        return None, "no scorecard"
    if count not in (9, 18):
        return None, f"{count} holes (only 9 and 18 work for now)"
    if [h["number"] for h in holes] != list(range(1, count + 1)):
        return None, "hole numbers skip"
    if not all(isinstance(h.get("par"), int) and 3 <= h["par"] <= 6 for h in holes):
        return None, "a hole has no par"

    # Tees: keep the ones with a sensible yardage on every hole, longest first.
    names = tee_names(record)
    keys = []
    for h in holes:
        for key in (h.get("yardages") or {}):
            if key not in keys:
                keys.append(key)
    tees = []
    for key in keys:
        yards = [(h.get("yardages") or {}).get(key) for h in holes]
        if all(isinstance(y, int) and 50 <= y <= 750 for y in yards):
            name = names.get(key.lower()) or key.replace("_", " ").title()
            if name not in [t[0] for t in tees]:
                tees.append((name, key, sum(yards)))
    tees.sort(key=lambda t: -t[2])

    # Stroke index: each number once. A nine with 18-hole numbers (1, 3, 5…) keeps their order.
    indexes = [h.get("handicap_index") for h in holes]
    if all(isinstance(i, int) for i in indexes) and len(set(indexes)) == count:
        if sorted(indexes) != list(range(1, count + 1)):
            if count == 9 and all(1 <= i <= 18 for i in indexes):
                order = sorted(indexes)
                indexes = [order.index(i) + 1 for i in indexes]
            else:
                indexes = [None] * count
    else:
        indexes = [None] * count

    out = []
    for h, index in zip(holes, indexes):
        hole = {"number": h["number"], "par": h["par"]}
        if index is not None:
            hole["handicap"] = index
        hole["yards"] = {name: h["yardages"][key] for name, key, _ in tees}
        out.append(hole)
    return {"tees": [t[0] for t in tees], "holes": out}, None


# MARK: build: OpenStreetMap

def ring_assemble(members):
    """Joins a relation's outer ways into closed rings."""
    pieces = [m["geometry"][:] for m in members if m["role"] in ("outer", "") and len(m["geometry"]) >= 2]
    rings = []
    while pieces:
        ring = pieces.pop()
        changed = True
        while ring[0] != ring[-1] and changed:
            changed = False
            for i, piece in enumerate(pieces):
                if piece[0] == ring[-1]:
                    ring += piece[1:]
                elif piece[-1] == ring[-1]:
                    ring += piece[::-1][1:]
                elif piece[-1] == ring[0]:
                    ring = piece[:-1] + ring
                elif piece[0] == ring[0]:
                    ring = piece[::-1][:-1] + ring
                else:
                    continue
                pieces.pop(i)
                changed = True
                break
        if len(ring) >= 4 and ring[0] == ring[-1]:
            rings.append(ring)
    return rings


def polygons(element):
    if "geometry" in element:
        g = element["geometry"]
        return [g] if len(g) >= 4 and g[0] == g[-1] else []
    return ring_assemble(element.get("members", []))


def inside(point, ring):
    lat, lng = point
    hit = False
    for (a_lat, a_lng), (b_lat, b_lng) in zip(ring, ring[1:]):
        if (a_lat > lat) != (b_lat > lat):
            cross = a_lng + (lat - a_lat) * (b_lng - a_lng) / (b_lat - a_lat)
            if lng < cross:
                hit = not hit
    return hit


def ring_area(ring):
    return abs(sum(a[1] * b[0] - b[1] * a[0] for a, b in zip(ring, ring[1:]))) / 2


def bbox(points):
    lats = [p[0] for p in points]
    lngs = [p[1] for p in points]
    return min(lats), min(lngs), max(lats), max(lngs)


class OSM:
    def __init__(self, path):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            elements = json.load(f)["elements"]
        self.outlines = []   # (area, ring, bbox, name)
        self.holes = []      # golf=hole ways
        self.shapes = []     # (kind, ring, bbox)
        for e in elements:
            tags = e["tags"]
            if tags.get("leisure") == "golf_course":
                for ring in polygons(e):
                    self.outlines.append((ring_area(ring), ring, bbox(ring), tags.get("name", "")))
                continue
            golf = tags.get("golf")
            if golf == "hole" and "geometry" in e and len(e["geometry"]) >= 2:
                self.holes.append(e)
                continue
            kind = {"green": "green", "tee": "tee", "fairway": "fairway", "bunker": "sand",
                    "water_hazard": "water", "lateral_water_hazard": "water"}.get(golf)
            if kind is None and tags.get("natural") == "water":
                kind = "water"
            if kind:
                for ring in polygons(e):
                    self.shapes.append((kind, ring, bbox(ring)))
        self.outlines.sort(key=lambda o: o[0])
        # Each hole goes to the smallest outline its middle sits in.
        self.holes_by_outline = {}
        for hole in self.holes:
            g = hole["geometry"]
            mid = g[len(g) // 2]
            for i, (_, ring, (s, w, n, e2), _) in enumerate(self.outlines):
                if s <= mid[0] <= n and w <= mid[1] <= e2 and inside(mid, ring):
                    self.holes_by_outline.setdefault(i, []).append(hole)
                    break

    def outline_for(self, lat, lng):
        """The smallest golf course outline around the point, or the nearest within about 400 m."""
        for i, (_, ring, (s, w, n, e), _) in enumerate(self.outlines):
            if s <= lat <= n and w <= lng <= e and inside((lat, lng), ring):
                return i
        best, best_d = None, 0.004
        for i, (_, ring, (s, w, n, e), _) in enumerate(self.outlines):
            d = max(s - lat, lat - n, w - lng, lng - e, 0)
            if d < best_d:
                best, best_d = i, d
        return best

    def shapes_near(self, s, w, n, e):
        return [(k, r) for k, r, (bs, bw, bn, be) in self.shapes if bs <= n and bn >= s and bw <= e and be >= w]


def hole_number(tags):
    ref = (tags.get("ref") or "").strip()
    return int(ref) if ref.isdigit() else None


def hole_course_name(tags):
    for key in ("golf:course:name", "course:name", "course"):
        if tags.get(key):
            return tags[key]
    return None


def osm_holes(osm, record, name, count):
    """OpenStreetMap's holes for this course, numbered 1 to count, or None."""
    lat, lng = record.get("lat"), record.get("lng")
    if lat is None or lng is None:
        return None
    index = osm.outline_for(lat, lng)
    if index is None:
        return None
    holes = osm.holes_by_outline.get(index, [])
    groups = {}
    for h in holes:
        groups.setdefault(hole_course_name(h["tags"]), []).append(h)
    words = set(slug(name).split("-")) - {"golf", "course", "club", "country", "the", "at", "of", "and", "cc", "gc"}
    candidates = []
    for group_name, group in groups.items():
        by_number = {}
        for h in group:
            n = hole_number(h["tags"])
            if n is not None:
                by_number.setdefault(n, []).append(h)
        if sorted(by_number) != list(range(1, count + 1)) or any(len(v) != 1 for v in by_number.values()):
            continue
        score = len(words & set(slug(group_name or "").split("-"))) if group_name else 0
        candidates.append((score, group_name is None, {n: v[0] for n, v in by_number.items()}))
    if not candidates:
        return None
    candidates.sort(key=lambda c: (-c[0], not c[1]))
    if len(candidates) > 1 and candidates[0][0] == candidates[1][0]:
        return None  # two loops fit equally well; better no drawing than the wrong one
    return candidates[0][2]


# MARK: build: drawings

STYLE = {
    "rough": "#DCE8C4", "fairway": "#9FCC80",
    "water": "#A9CEEC", "water_edge": "#7DB2DC",
    "sand": "#F0DDA6", "sand_edge": "#D9C07A",
    "green": "#3E9A56", "green_edge": "#2B7340",
    "line": "#1F3A2B", "flag": "#D8433B",
}
UNITS_PER_METER = 3.0


class Frame:
    """Meters around the tee, turned so the hole plays straight up the page."""

    def __init__(self, path):
        self.lat0, self.lng0 = path[0]
        self.kx = math.cos(math.radians(self.lat0)) * 111320
        self.ky = 110540
        ex, ey = self.raw(path[-1])
        self.angle = math.atan2(ex, ey)

    def raw(self, p):
        return (p[1] - self.lng0) * self.kx, (p[0] - self.lat0) * self.ky

    def __call__(self, p):
        x, y = self.raw(p)
        c, s = math.cos(self.angle), math.sin(self.angle)
        return x * c - y * s, x * s + y * c  # y points up the hole


def distance_to_path(point, path):
    px, py = point
    best = math.inf
    for (ax, ay), (bx, by) in zip(path, path[1:]):
        dx, dy = bx - ax, by - ay
        t = 0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(px - ax - t * dx, py - ay - t * dy))
    return best


def centroid(ring):
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def contains(ring, point):
    x, y = point
    hit = False
    for (ax, ay), (bx, by) in zip(ring, ring[1:] + ring[:1]):
        if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
            hit = not hit
    return hit


def corridor(path, width):
    """A rounded band either side of the line of play: the hole's rough."""
    def normal(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        return -dy / length, dx / length
    left, right = [], []
    for i, p in enumerate(path):
        normals = []
        if i > 0:
            normals.append(normal(path[i - 1], p))
        if i < len(path) - 1:
            normals.append(normal(p, path[i + 1]))
        nx = sum(n[0] for n in normals) / len(normals)
        ny = sum(n[1] for n in normals) / len(normals)
        length = math.hypot(nx, ny) or 1
        scale = min(1 / length, 1.6)  # don't let sharp turns spike out
        nx, ny = nx / length * scale, ny / length * scale
        left.append((p[0] + nx * width, p[1] + ny * width))
        right.append((p[0] - nx * width, p[1] - ny * width))

    def cap(center, start_angle):
        # Round the end clockwise, from one side of the band to the other.
        return [(center[0] + width * math.cos(start_angle - math.pi * k / 8),
                 center[1] + width * math.sin(start_angle - math.pi * k / 8)) for k in range(1, 8)]
    end_dir = math.atan2(path[-1][1] - path[-2][1], path[-1][0] - path[-2][0])
    start_dir = math.atan2(path[1][1] - path[0][1], path[1][0] - path[0][0])
    return left + cap(path[-1], end_dir + math.pi / 2) + right[::-1] + cap(path[0], start_dir - math.pi / 2)


def clip(ring, x0, y0, x1, y1):
    """Sutherland–Hodgman against a box."""
    def cut(points, inside_fn, cross_fn):
        out = []
        for i, current in enumerate(points):
            previous = points[i - 1]
            if inside_fn(current):
                if not inside_fn(previous):
                    out.append(cross_fn(previous, current))
                out.append(current)
            elif inside_fn(previous):
                out.append(cross_fn(previous, current))
        return out

    def at_x(x):
        return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]))

    def at_y(y):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]), y)
    points = ring
    for inside_fn, cross_fn in ((lambda p: p[0] >= x0, at_x(x0)), (lambda p: p[0] <= x1, at_x(x1)),
                                (lambda p: p[1] >= y0, at_y(y0)), (lambda p: p[1] <= y1, at_y(y1))):
        if not points:
            break
        points = cut(points, inside_fn, cross_fn)
    return points


def area(ring):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:] + ring[:1]))) / 2


def drawing(osm, way):
    """One hole as an SVG in the app's yardage book colors, or None."""
    geo = way["geometry"]
    frame = Frame(geo)
    path = [frame(p) for p in geo]
    length = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(path, path[1:]))
    if length < 60 or length > 700:
        return None
    pad = 0.0012
    s, w, n, e = bbox(geo)
    nearby = [(kind, [frame(p) for p in ring[:-1]]) for kind, ring in osm.shapes_near(s - pad, w - pad, n + pad, e + pad)]
    start, end = path[0], path[-1]

    greens = [r for k, r in nearby if k == "green"]
    green = next((r for r in greens if contains(r, end)), None)
    if green is None and greens:
        near = min(greens, key=lambda r: math.dist(centroid(r), end))
        green = near if math.dist(centroid(near), end) < 35 else None
    tees = [r for k, r in nearby if k == "tee" and math.dist(centroid(r), start) < 45]
    fairways = [r for k, r in nearby if k == "fairway"
                and (distance_to_path(centroid(r), path) < 30 or any(contains(r, p) for p in path[1:-1]))
                and not distance_to_path(centroid(r), path) > 60]
    width = 28.0
    for ring in fairways + ([green] if green else []):
        width = max(width, min(55.0, max(distance_to_path(p, path) for p in ring) + 6))
    sands = [r for k, r in nearby if k == "sand" and distance_to_path(centroid(r), path) < width + 4]
    waters = [r for k, r in nearby if k == "water" and min(distance_to_path(p, path) for p in r) < width + 12]

    rough = corridor(path, width)
    xs = [p[0] for p in rough]
    ys = [p[1] for p in rough]
    x0, x1, y0, y1 = min(xs) - 12, max(xs) + 12, min(ys) - 12, max(ys) + 12

    def svg_ring(ring):
        # Page coordinates: x right, y down.
        return "M" + "L".join(f"{p[0] * UNITS_PER_METER:.1f},{-p[1] * UNITS_PER_METER:.1f}" for p in ring) + "Z"

    def layer(rings, fill, stroke=None, stroke_width=0):
        out = []
        for ring in rings:
            ring = clip(ring, x0, y0, x1, y1)
            if len(ring) < 3 or area(ring) < 4:
                continue
            extra = f' stroke="{stroke}" stroke-width="{stroke_width}" stroke-linejoin="round"' if stroke else ""
            out.append(f'<path d="{svg_ring(ring)}" fill="{fill}"{extra}/>')
        return out

    parts = []
    parts += layer(waters, STYLE["water"], STYLE["water_edge"], 3)
    parts += layer([rough], STYLE["rough"])
    parts += layer(fairways, STYLE["fairway"])
    parts += layer(sands, STYLE["sand"], STYLE["sand_edge"], 2)
    parts += layer(([green] if green else []) + tees, STYLE["green"], STYLE["green_edge"], 2.5)
    u = UNITS_PER_METER
    points = " ".join(f"{p[0] * u:.1f},{-p[1] * u:.1f}" for p in path)
    parts.append(f'<polyline points="{points}" fill="none" stroke="{STYLE["line"]}" stroke-width="3.5" '
                 'stroke-linecap="round" stroke-linejoin="round" opacity="0.85"/>')
    # Where the line turns more than a little: a shot lands there.
    turns = []
    for a, b, c in zip(path, path[1:], path[2:]):
        h1 = math.atan2(b[1] - a[1], b[0] - a[0])
        h2 = math.atan2(c[1] - b[1], c[0] - b[0])
        turn = abs((h2 - h1 + math.pi) % (2 * math.pi) - math.pi)
        if turn > math.radians(12) and math.dist(b, start) > 80 and math.dist(b, end) > 60:
            turns.append(b)
    for p in turns[:2]:
        parts.append(f'<circle cx="{p[0] * u:.1f}" cy="{-p[1] * u:.1f}" r="5" fill="#FFFFFF" stroke="{STYLE["line"]}" stroke-width="3"/>')
    px, py = end[0] * u, -end[1] * u
    parts.append(f'<line x1="{px:.1f}" y1="{py:.1f}" x2="{px:.1f}" y2="{py - 34:.1f}" stroke="{STYLE["line"]}" '
                 'stroke-width="3" stroke-linecap="round"/>')
    parts.append(f'<path d="M{px:.1f},{py - 34:.1f}L{px + 20:.1f},{py - 27:.1f}L{px:.1f},{py - 20:.1f}Z" fill="{STYLE["flag"]}"/>')
    parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="4" fill="#FFFFFF"/>')

    vx0, vx1 = x0 * u, x1 * u
    vy0, vy1 = -y1 * u - 40, -y0 * u  # room for the flag at the top
    vw, vh = vx1 - vx0, vy1 - vy0
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vx0:.0f} {vy0:.0f} {vw:.0f} {vh:.0f}" '
            f'width="{vw / 1.5:.0f}" height="{vh / 1.5:.0f}">' + "".join(parts) + "</svg>\n")


# MARK: build

def same_course(a, b):
    strip = dict(a)
    strip.pop("version", None)
    other = dict(b)
    other.pop("version", None)
    return strip == other


def build(args):
    library = args.library
    courses_folder = os.path.join(library, "courses")
    ids = json.load(open(IDS_FILE)) if os.path.exists(IDS_FILE) else {}
    used = set(ids.values()) | set(SKIP.values())
    osm = OSM(OSM_CACHE) if os.path.exists(OSM_CACHE) else None
    report = {"fetched": 0, "added": 0, "with_drawings": 0, "with_yardages": 0, "skipped": {}}
    seen = set()
    records = []
    for name in sorted(os.listdir(API_CACHE)) if os.path.isdir(API_CACHE) else []:
        if name.endswith(".json"):
            records.append(json.load(open(os.path.join(API_CACHE, name), encoding="utf-8")))
    report["fetched"] = len(records)
    built = set()
    for record in records:
        card, problem = scorecard(record)
        if card is None:
            report["skipped"].setdefault(problem, []).append(tidy_name(record.get("course_name") or record.get("dataset_name")))
            continue
        name = tidy_name(record.get("course_name") or record.get("club_name") or record.get("dataset_name"))
        city = (record.get("city") or "").strip()
        key = (name.lower(), city.lower(), tuple(h["par"] for h in card["holes"]))
        if key in seen:
            report["skipped"].setdefault("listed twice", []).append(name)
            continue
        seen.add(key)
        cid = ids.get(record["id"])
        if not cid:
            for candidate in (slug(name), slug(f"{name} {city}"), slug(f"{name} {city}") + "-" + record["id"][:4]):
                if candidate and candidate not in used:
                    cid = candidate
                    break
            ids[record["id"]] = cid
            used.add(cid)
        course = {"id": cid, "name": name, "town": f"{city}, FL" if city else "Florida", "tees": card["tees"],
                  "holes": card["holes"]}
        drawings = {}
        if osm:
            holes = osm_holes(osm, record, name, len(card["holes"]))
            if holes:
                mismatched = sum(1 for h in card["holes"]
                                 if str(holes[h["number"]]["tags"].get("par", h["par"])) != str(h["par"]))
                if mismatched <= 1:
                    for h in card["holes"]:
                        svg = drawing(osm, holes[h["number"]])
                        if svg:
                            drawings[f"{cid}-{h['number']:02d}"] = svg
                            h["map"] = f"{cid}-{h['number']:02d}"
        folder = os.path.join(courses_folder, cid)
        path = os.path.join(folder, "course.json")
        old = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else None
        old_svgs = {}
        if os.path.isdir(folder):
            for f in os.listdir(folder):
                if f.endswith(".svg"):
                    old_svgs[f[:-4]] = open(os.path.join(folder, f), encoding="utf-8").read()
        version = (old or {}).get("version", 0)
        if old is None or not same_course(old, course) or old_svgs != drawings:
            version += 1
        course["version"] = max(version, 1)
        if os.path.isdir(folder):
            shutil.rmtree(folder)
        os.makedirs(folder)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(course, f, indent=2, ensure_ascii=False)
            f.write("\n")
        for map_name, svg in drawings.items():
            with open(os.path.join(folder, map_name + ".svg"), "w", encoding="utf-8") as f:
                f.write(svg)
        built.add(cid)
        report["added"] += 1
        report["with_drawings"] += bool(drawings)
        report["with_yardages"] += bool(card["tees"])
    # Courses this import made before but no longer can are left alone; only its own ids are touched.
    with open(IDS_FILE, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(ids.items())), f, indent=1)
        f.write("\n")
    report["skipped_counts"] = {k: len(v) for k, v in sorted(report["skipped"].items())}
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    print(f"Fetched {report['fetched']}; built {report['added']} courses, {report['with_yardages']} with yardages, "
          f"{report['with_drawings']} with hole drawings. Skipped: {report['skipped_counts']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("fetch-api")
    p.add_argument("--dataset", required=True, help="opengolfapi-us.ndjson from github.com/opengolfapi/data")
    p.add_argument("--limit", type=int, default=900, help="most API calls this run")
    p.add_argument("--pause", type=float, default=0.5, help="seconds between calls")
    sub.add_parser("fetch-osm")
    p = sub.add_parser("build")
    p.add_argument("library", help="the course-library folder")
    args = parser.parse_args()
    {"fetch-api": fetch_api, "fetch-osm": fetch_osm, "build": build}[args.command](args)


if __name__ == "__main__":
    main()
