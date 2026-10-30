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
    print(f"{len(courses)} Florida courses; {len(courses) - len(todo)} already fetched, {len(todo)} to go")
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

OVERPASS_QUERY = """
[out:json][timeout:900][maxsize:2000000000];
area["ISO3166-2"="US-FL"]["admin_level"="4"]->.fl;
(way["leisure"="golf_course"](area.fl); relation["leisure"="golf_course"](area.fl);)->.gc;
.gc out tags geom;
.gc map_to_area->.gca;
(
  way["golf"](area.gca);
  relation["golf"](area.gca);
  way["natural"="water"](area.gca);
  relation["natural"="water"]["type"="multipolygon"](area.gca);
);
out tags geom;
"""

FEATURE_TAGS = ("golf", "natural", "leisure", "ref", "par", "handicap", "golf:par", "golf:handicap",
                "name", "golf:course:name", "course:name", "course", "type")


def rounded(geometry):
    return [[round(p["lat"], 6), round(p["lon"], 6)] for p in geometry or [] if p]


def fetch_osm(args):
    body = urllib.parse.urlencode({"data": OVERPASS_QUERY}).encode()
    answer = None
    for url in OVERPASS:
        try:
            print(f"Asking {url} for Florida's golf courses (takes a few minutes)")
            answer = get_json(url, data=body, timeout=1200)
            break
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            print(f"{url}: {error}")
    if answer is None:
        sys.exit("Couldn't reach Overpass; kept the old OpenStreetMap copy")
    elements = []
    for e in answer.get("elements", []):
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


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] in ("fetch-api", "fetch-osm"):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("fetch-api")
    p.add_argument("--dataset", required=True, help="opengolfapi-us.ndjson from github.com/opengolfapi/data")
    p.add_argument("--limit", type=int, default=900, help="most API calls this run")
    p.add_argument("--pause", type=float, default=0.5, help="seconds between calls")
    sub.add_parser("fetch-osm")
    args = parser.parse_args()
    {"fetch-api": fetch_api, "fetch-osm": fetch_osm}[args.command](args)
