# Tracing a course from aerial photos

For Florida courses OpenStreetMap has no holes for. The photos are USGS NAIP
(public domain). Never use Google, Apple or any other imagery, never edit
OpenStreetMap, and don't open accounts anywhere.

You mark each hole's tee and green (and any bend) on the photos in a small plan
file. `trace.py build` then finds the green's shape, the fairway, bunkers, water
and trees around your marks by color, and writes `Tools/CourseImport/traced/<course>.json`,
which the course import draws the holes from.

Set these first (the paths are given in your brief):

    export PHOTOS=... WORK=... LIBRARY=...
    cd Tools/CourseImport/tracing

## 1. Look at the course

    python3 trace.py overview <course>

This prints the card (par and yardage range of every hole) and writes, in
`$WORK/<course>/`:

- `overview.png`, the whole course box with a 100 m grid;
- `zoom-X-Y.png`, the course in pieces at 0.5 m a pixel with a 25 m grid.
  These are the ones to plan from. Grid numbers are meters east (x) and south (y)
  of the top left of the course box, the same in every picture.

Magenta is the course outline from the map. Red lines, cyan rings and blue
rings are holes, greens and tees the map already has (often for a neighbouring
course, sometimes misnumbered); use them as hints.

If the club is bigger than the course box (fairways run off its edges, or one
small outline covers several courses), write `{"whole": true}` to
`$WORK/<course>/box.json` and run overview again: the box is then the whole
photo. Do this before you plan, since it moves the grid.

For a closer look: `python3 trace.py zoom <course> X0 Y0 X1 Y1 0.3`
(add `cir` at the end for the infrared picture, where live grass is red and
greens often show as smooth, even patches).

## 1b. Check the course's own scorecard

Search the web for the course's own scorecard: its own website first, then a
well-known scorecard listing. If one shows the holes with pars (and yardages or
handicaps), and it differs from the card overview printed (pars in another order,
missing yardages, different holes), write it to `$WORK/<course>/card.json`:

    {"source": "https://... (the page you read it on)",
     "tees": ["Blue", "White", "Red"],
     "holes": [{"number": 1, "par": 4, "handicap": 7, "yards": {"Blue": 402, "White": 380, "Red": 310}}, ...]}

Copy the numbers exactly; leave out anything the page doesn't give (no
guessing). trace.py then uses it in place of the library's card. A hole map on
the course's site may help you tell which hole is which, but draw only from the
aerial photos.

## 2. Find the holes

- Greens: smooth, evenly mown ovals 20 to 35 m across, usually darker or
  brighter than the grass round them, with a collar ring, and bunkers (pale
  sand) hugging them. A flag stick sometimes shows as a dot with a shadow.
- Tees: small, flat, often rectangular pads, several in a row, behind the
  start of a fairway, often next to a cart path.
- Fairways: the long mown strips (mowing stripes) between the rough and trees.
- The clubhouse and car park: holes 1 and 10 usually start near it, and 9 and
  18 usually finish near it.
- Each hole's tee is usually a short walk (under about 150 m) from the green
  before it.
- Use the card: hole lengths (yards; 1 yd = 0.9144 m) and pars tell you which
  green goes with which corridor. A par 3 is a short hole with no fairway.
- Where a club has several courses, only plan the holes of the course you were
  given (the card says how many and how long). The others share the photos.

## 3. Write the plan

`$WORK/<course>/plan.json`, in grid meters:

    {"holes": {
       "1": {"tee": [585, 125], "green": [385, 517]},
       "2": {"tee": [400, 555], "via": [[250, 560]], "green": [95, 570]},
       "3": {"toward": [95, 570], "green": [127, 442]}
     },
     "unsure": {"3": "tee not visible under the trees; placed from the card's length"}}

- `tee`: the back of the longest tees. `green`: the middle of the green.
- `via`: bends, for doglegs, in order from the tee. A straight hole has none.
- `toward`: use instead of `tee` only when you can't see the tee; the tee is
  then put at the card's longest yardage from the green, in that direction.
- `par`: only when the card lists its pars in sorted order (overview says so):
  give every hole its par from the photo (3 short with no fairway, 4, or 5 long).
  Keep the card's total par where you can; say in `unsure` where you can't.
- `unsure`: a hole number (or "all") and why, for anything you had to guess:
  the hole order, a green you couldn't find, a tee placed by `toward`.
  Be honest here; these are listed to Alberto. Don't guess silently.

Then:

    python3 trace.py check <course>

It prints each hole's traced length against the card (SHORT or LONG when it's
well outside the card's range) and any long walk from a green to the next tee,
and draws `routing.png`. Fix and re-run until the lengths fit and the routing
looks like a golf course (holes side by side, not crossing each other).

## 4. Build and look

    python3 trace.py build <course>

Then open `traced-front.png` (and `traced-back.png`): greens (dark green),
fairways (light green), bunkers, water and trees over the photo. Check every
hole: the green sits on the green, the line runs down its fairway, nothing
crosses another hole. If a green came out as a plain oval in the wrong spot,
move its point; if a line cuts through trees, add a `via`. Re-run build after
any change. Two or three rounds is normal.

## 5. Report

For each course: done, the number of holes traced, and every unsure hole with
its reason, in one line each. Don't commit anything and don't touch anything
outside `$WORK` and `Tools/CourseImport/traced/`.
