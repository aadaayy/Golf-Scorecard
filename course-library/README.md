# Course library

The courses players find and download in Find Courses. The app reads these files straight from GitHub (`https://raw.githubusercontent.com/aadaayy/Golf-Scorecard/main/course-library/`), so there's no server and nothing to pay for. This only works while the repository is public; see "Before the repository goes private" in the main README.

- `index.json`: the list Find Courses shows. Written by `Tools/CourseLibrary/build_index.py`, never by hand.
- `courses/<id>/course.json`: one course, in the app's course format, with a `"version"`.
- `courses/<id>/<map>.svg`: one drawing per hole, named after that hole's `map` (for example `pompano-pines-01.svg`).

## Add a course

1. Make the course file and hole drawings (see "Add a built-in course" in the main README; the drawings come from `Tools/HoleDrawings/trace_holes.py`).
2. Make a folder `courses/<id>/`, named after the course's id, and put `course.json` and the drawings in it. Start with `"version": 1`.
3. From the repository's top folder, run `python3 Tools/CourseLibrary/build_index.py course-library`. It checks the course and rewrites index.json.
4. Push. Players see the course in Find Courses within a few minutes.

## Fix a course

Change its files, raise `"version"` in its course.json by one, rebuild index.json as above and push. Phones that have the course download the new copy the next time Play opens with a signal.

## Remove a course

Delete its folder, rebuild index.json and push. Phones that already downloaded it keep their copy.

Each push that changes the library runs `.github/workflows/course-library.yml`. A red X means a course file has a problem or index.json wasn't rebuilt.
