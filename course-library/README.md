# Course library

The courses players find and download in Find Courses. The app reads these files straight from GitHub (`https://raw.githubusercontent.com/aadaayy/Golf-Scorecard/main/course-library/`), so there's no server and nothing to pay for. This only works while the repository is public; see "Before the repository goes private" in the main README.

- `index.json`: the list Find Courses shows. Written by `Tools/CourseLibrary/build_index.py`, never by hand.
- `courses/<id>/course.json`: one course, in the app's course format, with a `"version"`.
- `courses/<id>/<map>.svg`: one drawing per hole, named after that hole's `map` (for example `pompano-pines-01.svg`).

## Florida courses from open data

Every Florida course except Pompano Beach Pines comes from open data, put in by `Tools/CourseImport/florida.py` and the **Course import** workflow (`.github/workflows/course-import.yml`), which runs once a day:

- Par, stroke index and tee yardages: the OpenGolfAPI course API (opengolfapi.org). The free API allows 1,000 calls a day, so the first import takes a few days; after that the courses are rebuilt every Monday so new OpenStreetMap drawings come in.
- Hole drawings: OpenStreetMap, for the courses whose holes are mapped there. Courses without mapped holes have no drawings.
- Yardages that aren't known are left out rather than guessed. A course with none lists no tees.

The map data is fetched fresh each time and not kept in the repository. `Tools/CourseImport/florida-report.json` says how many went in and which courses were left out and why. To fix one of these courses by hand, edit its files as below; the import only rewrites a course when its source data changes, so put a lasting fix into OpenStreetMap or OpenGolfAPI too.

## Licence

The course data is © OpenStreetMap contributors and OpenGolfAPI, under the Open Database License 1.0 (https://opendatacommons.org/licenses/odbl/1-0/). That's why this library has to stay public, and why the app shows "Course data © OpenStreetMap contributors (ODbL 1.0) via OpenGolfAPI. Contains data from OpenGolfAPI (opengolfapi.org)." in Find Courses and Profile → About. Keep that credit wherever the courses show.

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
