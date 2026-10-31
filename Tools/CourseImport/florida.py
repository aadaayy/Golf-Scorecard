#!/usr/bin/env python3
"""Fills the course library with every Florida course from open data.

Three steps, each its own command, so the automatic import (course-import.yml)
can run them a little at a time:

  fetch-api   Reads the Florida courses from the OpenGolfAPI open dataset, then asks
              the OpenGolfAPI course API for each course's full scorecard (par,
              stroke index and tee yardages). Keeps what it needs in cache/api/,
              one file per course, so each course is only asked for once. The
              free API stops after about 500 calls a day, so it stops at --limit.
  fetch-osm   Reads the holes, greens, fairways, bunkers, tees and water drawn on
              Florida's golf courses from an OpenStreetMap extract (Geofabrik's
              Florida file, filtered by osmium) and keeps them in one file.
  build       Turns the cache into course folders in course-library: a course.json
              each, and an SVG drawing per hole where OpenStreetMap has the hole.
              Then run build_index.py to rewrite index.json.

Data credit (both are ODbL 1.0, so the course library stays open under ODbL):
  © OpenStreetMap contributors · Contains data from OpenGolfAPI (opengolfapi.org)

Only uses the Python standard library.

Usage, from the repository's top folder:
  python3 Tools/CourseImport/florida.py fetch-api --dataset opengolfapi-us.ndjson --limit 490
  python3 Tools/CourseImport/florida.py fetch-osm golf.geojsonseq osm.json.gz   (course-import.yml makes golf.geojsonseq)
  python3 Tools/CourseImport/florida.py build course-library --osm osm.json.gz
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
IDS_FILE = os.path.join(HERE, "florida-ids.json")
REPORT_FILE = os.path.join(HERE, "florida-report.json")

API = "https://api.opengolfapi.org/api/v1/courses/"
DAILY_CALLS = 490  # the free API answers about 500 calls a day, then says to wait
USAGE_FILE = os.path.join(CACHE, "api-calls.json")
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
                            "lat": lat, "lng": lng, "holes": p.get("holes"), "par": p.get("par"),
                            "zip": p.get("postal_code") or ""})
    # Fetch order: Miami-Dade, Broward and Palm Beach first, then the rest of
    # Florida in bands working south to north (the Keys first, the Panhandle last).
    courses.sort(key=lambda c: (region(c)[0], c["lat"] if c["lat"] is not None else 99, c["id"]))
    return courses


# Bands of Florida for the fetch order, south to north, after the three counties.
REGIONS = [
    (0, "Miami-Dade, Broward and Palm Beach"),
    (1, "South Florida (the Keys, Naples, Fort Myers)"),
    (2, "South Central (Sarasota, Sebring, Port St. Lucie)"),
    (3, "Central (Tampa, Orlando, Melbourne)"),
    (4, "North Central (Ocala, Gainesville, Daytona)"),
    (5, "North and the Panhandle (Jacksonville, Tallahassee, Pensacola)"),
]


def south_florida_county(code, lat, lng):
    """Miami-Dade, Broward or Palm Beach from the zip code, or None."""
    if len(code) >= 5 and code[:5].isdigit():
        z = int(code[:5])
        if 33010 <= z <= 33018 or 33030 <= z <= 33035 or z == 33039 or 33054 <= z <= 33056 or 33100 <= z <= 33299:
            return "Miami-Dade"
        if z in (33004, 33009, 33441, 33442) or 33019 <= z <= 33029 or 33060 <= z <= 33084 or 33300 <= z <= 33399:
            return "Broward"
        if 33400 <= z <= 33499 and z not in (33440, 33455, 33471, 33475):
            return "Palm Beach"
        return None
    # No zip code: the strip of the east coast the three counties cover.
    if lat is not None and lng is not None and 25.2 <= lat <= 26.98 and -80.9 <= lng <= -79.9:
        return "South Florida"
    return None


def region(course):
    """(band number, name) of a course for the fetch order."""
    lat = course.get("lat")
    if south_florida_county(course.get("zip", ""), lat, course.get("lng")):
        return REGIONS[0]
    if lat is None:
        return REGIONS[-1]
    for number, top in ((1, 27.0), (2, 28.0), (3, 29.0), (4, 30.0)):
        if lat < top:
            return REGIONS[number]
    return REGIONS[5]


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
    for number, name in REGIONS:
        print(f"  {name}: {sum(1 for c in todo if region(c)[0] == number)} to go", flush=True)
    # Stay under the API's daily allowance however often this runs: count calls per UTC day.
    today = time.strftime("%Y-%m-%d", time.gmtime())
    usage = json.load(open(USAGE_FILE)) if os.path.exists(USAGE_FILE) else {}
    used = usage.get(today, 0)
    limit = min(args.limit, max(DAILY_CALLS - used, 0))
    print(f"{used} calls already made today; making at most {limit}", flush=True)
    calls = 0
    for course in todo:
        if calls >= limit:
            print(f"Stopped at the limit of {limit} calls; the next run carries on")
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
                print(f"The API says we've used today's calls after {calls - 1} more; the next run carries on")
                used = max(used, DAILY_CALLS - calls)  # don't try again today
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
    with open(USAGE_FILE, "w", encoding="utf-8") as f:
        json.dump({today: used + calls}, f)
        f.write("\n")
    left = sum(1 for c in courses if not os.path.exists(os.path.join(API_CACHE, c["id"] + ".json")))
    print(f"Made {calls} calls; {left} courses left to fetch")


# MARK: fetch-osm

FEATURE_TAGS = ("golf", "natural", "leisure", "ref", "par", "handicap", "golf:par", "golf:handicap",
                "name", "golf:course:name", "course:name", "course")


def fetch_osm(args):
    """Reads golf features from an OpenStreetMap extract that osmium exported as GeoJSON
    lines (see course-import.yml), and keeps the ones the drawings need: golf course
    outlines, holes, greens, tees, fairways, bunkers, and water near a golf course."""
    def flip(ring):
        return [[round(lat, 6), round(lng, 6)] for lng, lat in ring]

    courses, golf, water = [], [], []
    with open(args.geojson, encoding="utf-8") as f:
        for line in f:
            line = line.strip().lstrip("\x1e")
            if not line:
                continue
            feature = json.loads(line)
            props = feature.get("properties") or {}
            geometry = feature.get("geometry") or {}
            tags = {k: v for k, v in props.items() if k in FEATURE_TAGS}
            item = {"id": f"{props.get('@type', '')}/{props.get('@id', '')}", "tags": tags}
            kind = geometry.get("type")
            if kind == "LineString":
                item["line"] = flip(geometry["coordinates"])
            elif kind == "Polygon":
                item["rings"] = [flip(geometry["coordinates"][0])]
            elif kind == "MultiPolygon":
                item["rings"] = [flip(polygon[0]) for polygon in geometry["coordinates"]]
            else:
                continue
            if tags.get("leisure") == "golf_course" and "rings" in item:
                courses.append(item)
            elif tags.get("golf") in ("hole", "green", "tee", "fairway", "bunker", "water_hazard", "lateral_water_hazard"):
                golf.append(item)
            elif tags.get("natural") == "water" and "rings" in item:
                water.append(item)

    # Water only where it touches a golf course: Florida has far too many lakes to keep them all.
    cell = 0.05
    grid = {}
    for c in courses:
        s, w, n, e = bbox([p for ring in c["rings"] for p in ring])
        for i in range(int(math.floor((s - 0.002) / cell)), int(math.floor((n + 0.002) / cell)) + 1):
            for j in range(int(math.floor((w - 0.002) / cell)), int(math.floor((e + 0.002) / cell)) + 1):
                grid.setdefault((i, j), []).append((s - 0.002, w - 0.002, n + 0.002, e + 0.002))
    near = []
    for item in water:
        s, w, n, e = bbox([p for ring in item["rings"] for p in ring])
        boxes = {b for i in range(int(math.floor(s / cell)), int(math.floor(n / cell)) + 1)
                 for j in range(int(math.floor(w / cell)), int(math.floor(e / cell)) + 1) for b in grid.get((i, j), [])}
        if any(bs <= n and bn >= s and bw <= e and be >= w for bs, bw, bn, be in boxes):
            near.append(item)
    elements = sorted(courses + golf + near, key=lambda e: e["id"])
    if len(courses) < 100:
        sys.exit("The extract has under 100 golf courses, which looks wrong; kept the old copy")
    data = json.dumps({"attribution": "© OpenStreetMap contributors, ODbL 1.0", "elements": elements},
                      separators=(",", ":"), ensure_ascii=False).encode()
    with gzip.GzipFile(args.out, "wb", mtime=0) as f:
        f.write(data)
    holes = sum(1 for e in golf if e["tags"].get("golf") == "hole")
    print(f"Kept {len(courses)} golf courses, {holes} holes, {len(golf) - holes} other golf shapes and {len(near)} ponds and lakes")


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
    if record.get("missing"):
        return None, "not in the course API"
    if not holes:
        return None, "no scorecard"
    if [h["number"] for h in holes] != list(range(1, len(holes) + 1)):
        return None, "hole numbers skip"
    if not all(isinstance(h.get("par"), int) and 3 <= h["par"] <= 6 for h in holes):
        return None, "a hole has no par"
    # Scorecards are often padded with made-up par 4s past the last real hole, so
    # take the first 18 or 9 holes, and check them against the course's total par.
    total, stated = record.get("par"), record.get("holes")
    counts = [n for n in (18, 9) if len(holes) >= n]
    if not counts:
        return None, f"only {len(holes)} holes"
    if isinstance(total, int):
        fits = [n for n in counts if sum(h["par"] for h in holes[:n]) == total]
        if not fits:
            return None, "pars don't add up to the course's par"
        count = stated if stated in fits else fits[0]
    else:
        count = stated if stated in counts else counts[0]
        if len(holes) != count:
            return None, "can't tell how many holes it has"
    holes = holes[:count]
    if not any(h.get("yardages") for h in holes) and not any(h.get("handicap_index") for h in holes) \
            and all(h["par"] == 4 for h in holes):
        return None, "placeholder scorecard (every hole par 4, nothing else)"

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
        self.holes = []      # golf=hole lines
        self.shapes = []     # (kind, ring, bbox)
        for e in elements:
            tags = e["tags"]
            rings = [r for r in e.get("rings", []) if len(r) >= 4]
            if tags.get("leisure") == "golf_course":
                for ring in rings:
                    self.outlines.append((ring_area(ring), ring, bbox(ring), tags.get("name", "")))
                continue
            golf = tags.get("golf")
            if golf == "hole":
                if len(e.get("line", [])) >= 2:
                    self.holes.append({"tags": tags, "geometry": e["line"]})
                continue
            kind = {"green": "green", "tee": "tee", "fairway": "fairway", "bunker": "sand",
                    "water_hazard": "water", "lateral_water_hazard": "water"}.get(golf)
            if kind is None and tags.get("natural") == "water":
                kind = "water"
            if kind:
                for ring in rings:
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


def hole_label(tags):
    """(loop, number) from a hole's tags: ref "7", or "Baytree 7", with the loop also
    taken from a course name tag. The loop is None when the hole doesn't say."""
    label = (tags.get("ref") or tags.get("name") or "").strip()
    match = re.match(r"^(.*?)[\s#:-]*(\d{1,2})$", label)
    if not match:
        return None, None
    loop = next((tags[k] for k in ("golf:course:name", "course:name", "course") if tags.get(k)), None) or match[1]
    return (slug(loop) or None), int(match[2])


NAME_FILLER = {"golf", "course", "club", "country", "the", "at", "of", "and", "cc", "gc", "g", "c", "nine", "9", "18"}


def numbered(holes, count):
    """{number: hole} when the holes are numbered 1 to count, each once; otherwise None."""
    by_number = {}
    for h in holes:
        n = hole_label(h["tags"])[1]
        if n is None or n in by_number:
            return None
        by_number[n] = h
    return by_number if sorted(by_number) == list(range(1, count + 1)) else None


def osm_holes(osm, record, name, count):
    """OpenStreetMap's holes for this course, numbered 1 to count, or None when
    there's no clear answer (better no drawing than another course's)."""
    lat, lng = record.get("lat"), record.get("lng")
    if lat is None or lng is None:
        return None
    index = osm.outline_for(lat, lng)
    if index is None:
        return None
    holes = osm.holes_by_outline.get(index, [])
    if not holes:
        return None
    words = [w for w in slug(name).split("-") if w not in NAME_FILLER]
    loops = {}
    for h in holes:
        loops.setdefault(hole_label(h["tags"])[0], []).append(h)

    def score(loop):
        return sum(1 for w in (loop or "").split("-") if w in words and w not in NAME_FILLER)

    candidates = []  # (score, holes by number)
    whole = numbered(holes, count)
    if whole:
        candidates.append((0, whole))
    for loop, group in loops.items():
        if loop is not None and len(loops) > 1:
            by_number = numbered(group, count)
            if by_number:
                candidates.append((score(loop), by_number))
    if count == 18:
        # Two named nines played as 18, in the order the course's name gives them.
        nines = [(loop, numbered(group, 9)) for loop, group in loops.items() if loop and score(loop)]
        nines = [(loop, n) for loop, n in nines if n]
        for i, (loop_a, a) in enumerate(nines):
            for loop_b, b in nines[i + 1:]:
                first = min(words.index(w) for w in loop_a.split("-") if w in words)
                second = min(words.index(w) for w in loop_b.split("-") if w in words)
                front, back = (a, b) if first < second else (b, a)
                candidates.append((score(loop_a) + score(loop_b), {**front, **{n + 9: h for n, h in back.items()}}))
    if not candidates:
        return None
    candidates.sort(key=lambda c: -c[0])
    if len(candidates) > 1 and candidates[0][0] == candidates[1][0]:
        return None
    return candidates[0][1]


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
    """Same holes and drawings. The location only feeds the library's map (index.json),
    not the phone's copy, so it doesn't count as a new version."""
    strip = dict(a)
    other = dict(b)
    for key in ("version", "location"):
        strip.pop(key, None)
        other.pop(key, None)
    return strip == other


# A few listings give only "FL" and a zip code where the town should be.
# These are the towns the clubs go by; any other zip-only one falls back to
# "Florida" and shows up in the report so it can be added here.
TOWN_FIXES = {
    "0277aa69-b446-42ee-8560-917246a25747": "Weston",          # Weston Hills, FL 33332
    "152943d4-ccc3-495f-9e85-023013b07e2b": "Vero Beach",      # John's Island West, FL 32958
    "1e998cad-3978-4a2c-a0d9-11bf661767bd": "Palm Harbor",     # Innisbrook, FL 34683
    "4511bcac-4335-4ce3-9d91-1a6db5df862f": "Wildwood",        # Southern Oaks, FL 34785
}


def town(record, report=None):
    """The course's town as "City, FL", never a zip code."""
    city = TOWN_FIXES.get(record.get("id")) or (record.get("city") or "").strip()
    if re.fullmatch(r"(FL\s*)?\d{5}(-\d{4})?", city, re.IGNORECASE):
        if report is not None:
            report["skipped"].setdefault("town was only a zip code (shown as Florida)", []).append(
                tidy_name(record.get("course_name") or record.get("dataset_name")))
        city = ""
    return f"{city}, FL" if city else "Florida"


def location(record):
    """Where the course is, from the course data, for the map in Find Courses. None if unknown."""
    lat, lng = record.get("lat"), record.get("lng")
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
        return None
    if not (-90 <= lat <= 90 and -180 <= lng <= 180) or (lat == 0 and lng == 0):
        return None
    return {"lat": round(lat, 6), "lng": round(lng, 6)}


def build(args):
    library = args.library
    courses_folder = os.path.join(library, "courses")
    ids = json.load(open(IDS_FILE)) if os.path.exists(IDS_FILE) else {}
    used = set(ids.values()) | set(SKIP.values())
    osm = OSM(args.osm) if args.osm else None
    report = {"fetched": 0, "added": 0, "with_drawings": 0, "with_yardages": 0, "with_location": 0, "skipped": {}}
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
        course = {"id": cid, "name": name, "town": town(record, report)}
        place = location(record)
        if place:
            course["location"] = place
        course["tees"] = card["tees"]
        course["holes"] = card["holes"]
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
        report["with_location"] += bool(place)
    # Courses this import made before but no longer can are left alone; only its own ids are touched.
    with open(IDS_FILE, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(ids.items())), f, indent=1)
        f.write("\n")
    report["skipped_counts"] = {k: len(v) for k, v in sorted(report["skipped"].items())}
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    print(f"Fetched {report['fetched']}; built {report['added']} courses, {report['with_yardages']} with yardages, "
          f"{report['with_drawings']} with hole drawings, {report['with_location']} on the map. Skipped: {report['skipped_counts']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("fetch-api")
    p.add_argument("--dataset", required=True, help="opengolfapi-us.ndjson from github.com/opengolfapi/data")
    p.add_argument("--limit", type=int, default=490, help="most API calls this run")
    p.add_argument("--pause", type=float, default=0.5, help="seconds between calls")
    p = sub.add_parser("fetch-osm")
    p.add_argument("geojson", help="golf features from osmium export, one GeoJSON feature a line")
    p.add_argument("out", help="where to keep what the drawings need (.json.gz)")
    p = sub.add_parser("build")
    p.add_argument("library", help="the course-library folder")
    p.add_argument("--osm", required=True, help="what fetch-osm kept; the hole drawings come from it")
    args = parser.parse_args()
    {"fetch-api": fetch_api, "fetch-osm": fetch_osm, "build": build}[args.command](args)


if __name__ == "__main__":
    main()
