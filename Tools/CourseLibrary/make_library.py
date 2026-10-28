#!/usr/bin/env python3
"""Lays out the app's built-in courses as a course library folder.

Copies each course in GolfScorecard/Courses with its hole drawings from the asset
catalog into LIBRARY/courses/<id>/, then writes LIBRARY/index.json with
build_index.py. The automatic checks use it to make a library on the test Mac,
and it seeded the course-library folder.

Usage:
  python3 Tools/CourseLibrary/make_library.py LIBRARY_FOLDER
"""
import glob
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    library = sys.argv[1]
    drawings = {os.path.splitext(os.path.basename(p))[0]: p
                for p in glob.glob(os.path.join(REPO, "GolfScorecard", "Assets.xcassets", "**", "*.svg"), recursive=True)}
    for path in sorted(glob.glob(os.path.join(REPO, "GolfScorecard", "Courses", "*.json"))):
        course = json.load(open(path, encoding="utf-8"))
        folder = os.path.join(library, "courses", course["id"])
        os.makedirs(folder, exist_ok=True)
        shutil.copy(path, os.path.join(folder, "course.json"))
        for hole in course["holes"]:
            if hole.get("map"):
                shutil.copy(drawings[hole["map"]], os.path.join(folder, hole["map"] + ".svg"))
    subprocess.run([sys.executable, os.path.join(HERE, "build_index.py"), library], check=True)


if __name__ == "__main__":
    main()
