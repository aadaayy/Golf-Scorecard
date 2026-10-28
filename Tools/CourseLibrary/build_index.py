#!/usr/bin/env python3
"""Checks every course in a course library folder and writes its index.json.

The library is a folder (course-library in the app repository) laid out like this:

  index.json                      written by this script; the app reads it first
  courses/<id>/course.json        the course, in the app's course format
  courses/<id>/<map>.svg          one drawing per hole, named after the hole's "map"

Run it after adding or changing a course, then push:

  python3 Tools/CourseLibrary/build_index.py course-library          writes course-library/index.json
  python3 Tools/CourseLibrary/build_index.py course-library --check  fails if index.json is out of date

When you change a course that's already in the library, raise its "version" in
course.json by one, so phones that have it download the new copy.

Only uses the Python standard library.
"""
import argparse
import json
import os
import re
import sys

FORMAT = 1
COURSE_FILE = "course.json"
ID_PATTERN = re.compile(r"^[a-z0-9-]+$")
FILE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def course_problems(course, folder_name, files):
    problems = []
    cid = course.get("id", "")
    if not ID_PATTERN.match(cid):
        problems.append("id must use only lowercase letters, numbers and hyphens")
    if cid != folder_name:
        problems.append(f"the folder should be named after the id, {cid}")
    if not str(course.get("name", "")).strip():
        problems.append("name is empty")
    tees = course.get("tees") or []
    if not tees:
        problems.append("no tees listed")
    version = course.get("version", 1)
    if not isinstance(version, int) or version < 1:
        problems.append("version must be a whole number, 1 or more")
    holes = course.get("holes") or []
    if len(holes) not in (9, 18):
        problems.append(f"has {len(holes)} holes; expected 9 or 18")
    if [h.get("number") for h in holes] != list(range(1, len(holes) + 1)):
        problems.append("hole numbers must run 1 to the last hole in order")
    maps = []
    for hole in holes:
        n = hole.get("number")
        if not 3 <= hole.get("par", 0) <= 6:
            problems.append(f"hole {n}: par looks wrong")
        yards = hole.get("yards") or {}
        for tee in tees:
            if not 50 <= yards.get(tee, 0) <= 750:
                problems.append(f"hole {n}: yardage for the {tee} tee is missing or looks wrong")
        if hole.get("map"):
            maps.append(hole["map"])
            if f"{hole['map']}.svg" not in files:
                problems.append(f"hole {n}: drawing {hole['map']}.svg is missing")
    if len(set(maps)) != len(maps):
        problems.append("two holes use the same drawing")
    handicaps = [h["handicap"] for h in holes if h.get("handicap") is not None]
    if handicaps and sorted(handicaps) != list(range(1, len(holes) + 1)):
        problems.append("handicaps must use each number from 1 to the hole count once")
    for name in files:
        if not FILE_PATTERN.match(name):
            problems.append(f"{name}: file names may only use letters, numbers, dots, dashes and underscores")
    return problems


def svg_problems(path):
    text = open(path, encoding="utf-8").read()
    problems = []
    if "<svg" not in text or not re.search(r'viewBox="[-0-9. ]+"', text):
        problems.append(f"{os.path.basename(path)}: needs an <svg> with a viewBox")
    for d in re.findall(r'\sd="([^"]*)"', text):
        bad = set(re.findall(r"[A-Za-z]", d)) - set("MmLlHhVvCcZze")
        if bad:
            problems.append(f"{os.path.basename(path)}: uses path commands {''.join(sorted(bad))}, which the app doesn't draw")
    tags = set(re.findall(r"<([a-zA-Z]+)", text)) - {"svg", "path", "polyline", "polygon", "line", "circle"}
    if tags:
        problems.append(f"{os.path.basename(path)}: has {', '.join(sorted(tags))}, which the app doesn't draw")
    return problems


def build(library):
    courses_folder = os.path.join(library, "courses")
    entries, problems = [], []
    for folder_name in sorted(os.listdir(courses_folder)) if os.path.isdir(courses_folder) else []:
        folder = os.path.join(courses_folder, folder_name)
        if not os.path.isdir(folder) or folder_name.startswith("."):
            continue
        files = sorted(f for f in os.listdir(folder) if not f.startswith("."))
        if COURSE_FILE not in files:
            problems.append(f"{folder_name}: no {COURSE_FILE}")
            continue
        try:
            course = json.load(open(os.path.join(folder, COURSE_FILE), encoding="utf-8"))
        except ValueError as error:
            problems.append(f"{folder_name}/{COURSE_FILE}: not valid JSON ({error})")
            continue
        found = course_problems(course, folder_name, files)
        for name in files:
            if name.endswith(".svg"):
                found += svg_problems(os.path.join(folder, name))
        problems += [f"{folder_name}: {p}" for p in found]
        holes = course.get("holes") or []
        tees = course.get("tees") or []
        entries.append({
            "id": course.get("id", folder_name),
            "name": course.get("name", ""),
            "town": course.get("town", ""),
            "holes": len(holes),
            "par": sum(h.get("par", 0) for h in holes),
            "tees": tees,
            "yards": {tee: sum((h.get("yards") or {}).get(tee, 0) for h in holes) for tee in tees},
            "version": course.get("version", 1),
            "folder": f"courses/{folder_name}",
            "files": files,
            "bytes": sum(os.path.getsize(os.path.join(folder, f)) for f in files),
        })
    entries.sort(key=lambda e: e["name"].lower())
    return {"format": FORMAT, "courses": entries}, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("library", help="the library folder (the one with courses/ in it)")
    parser.add_argument("--check", action="store_true", help="fail if index.json is missing or out of date")
    args = parser.parse_args()

    index, problems = build(args.library)
    for problem in problems:
        print(f"Problem: {problem}", file=sys.stderr)
    if problems:
        sys.exit(1)
    text = json.dumps(index, indent=2, ensure_ascii=False) + "\n"
    path = os.path.join(args.library, "index.json")
    if args.check:
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
        if current != text:
            print("index.json is out of date: run Tools/CourseLibrary/build_index.py course-library and push the new index.json", file=sys.stderr)
            sys.exit(1)
        print(f"index.json is up to date: {len(index['courses'])} courses")
    else:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"Wrote index.json: {len(index['courses'])} courses")


if __name__ == "__main__":
    main()
