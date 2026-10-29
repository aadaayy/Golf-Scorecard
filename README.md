# Yardage Book

The app shows as **Yardage Book** on the Home Screen (the project and bundle id keep the Golf Scorecard name). It looks like a caddie's yardage book: ink on cream paper, typewriter titles, red marks, and each hole drawn with red arcs every 50 yards to the middle of the green, a close-up of the green, and trees around the edge (the trees are decoration, not surveyed).

A paper-style golf scorecard for iPhone Duo and regular iPhones. Open the Duo, or turn any iPhone sideways, and the card sits on the left with the hole you're on at the right; hold a phone upright (or close the Duo) and you switch between them with tabs. No tracking and no accounts. Courses come from a free online course library and, once downloaded, work with no signal.

## What's in it

1. Welcome pages the first time: your name, an optional handicap, and whether the open Duo starts on the Hole or Nine view.
2. Three tabs: Play, Past Rounds and Profile. On the iPhone Duo they sit in the strip at the side of the screen, under Back. Play resumes an unfinished round or picks a course; open or sideways, the picked course shows on the right, and Past Rounds and Profile use both halves too.
3. Find Courses (on Play): search the course library by name or town and download a course. Downloaded courses show on Play, work offline, update themselves when the library has a newer copy, and can be removed with a swipe. Pompano Beach Pines is also built in, so the app works on first launch with no signal.
4. Start a round: tee, and up to four players (you're first; people you've played with are a tap away).
5. The round: card and map (see below), then Finish for a summary with Out, In, Total, to par and net. Delete (in red) throws away a round you have to leave part way through, after asking first.
6. The Lock Screen card (a Live Activity) during a round: the hole you're on and your score. Tap it to go straight back to that hole. It can be turned off in Profile.
7. Past rounds: every round, newest first. Finished cards stay locked until Edit.
8. Profile & Settings, laid out like the iPhone's Settings: My Profile (name, handicap), Playing (usual tee, Hole or Nine), During a Round (show the round on the Lock Screen), History, and About (version, Erase Everything). Open or sideways, the sections are on the left and the picked one on the right.

## Run it on your iPhone Duo (free Apple account)

You need a Mac with Xcode 27.1 or later (macOS Tahoe 26.6 or later). No simulator is needed.

### First time

1. In Xcode, choose Integrate > Clone, paste `https://github.com/aadaayy/golf-scorecard`, and pick a folder.
2. Open `GolfScorecard.xcodeproj` if it doesn't open by itself.
3. Xcode Settings > Accounts: sign in with your Apple account. A free account works; Xcode calls it a Personal Team.
4. Click the blue GolfScorecard project at the top of the file list, open Signing & Capabilities, and pick your Personal Team for both targets: GolfScorecard and RoundActivity (the Lock Screen card).
5. If Xcode says the bundle identifier is taken, change `com.albertoaday.golfscorecard` to something unique to you, and RoundActivity's to the same thing followed by `.RoundActivity`.
6. Plug the Duo into the Mac with a cable and tap Trust on the phone.
7. On the Duo: Settings > Privacy & Security > Developer Mode, turn it on and restart when asked.
8. In Xcode, pick your Duo from the device menu at the top and press Run (the play button).
9. The first time, the phone may block the app. On the Duo, open Settings > General > VPN & Device Management, trust your developer certificate, and open the app again.
10. Optional: Window > Devices and Simulators, select the Duo, tick Connect via network. Later runs then work over Wi-Fi.

### Each time there's a new version

1. Integrate > Pull.
2. Press Run.

With a free account, the app stops opening after 7 days. Press Run again to refresh it.

## Automatic checks

Every push runs the checks in `.github/workflows/checks.yml`:

1. Logic tests (Linux): every course file and hole drawing loads and passes its checks, the course library's index and search work, and the scoring math adds up.
2. App build and walk-through (Mac): builds the app and runs the same walk-through on iPhone Pro Max, iPhone Pro and iPhone Duo simulators. It finds, downloads, plays and removes a course in Find Courses, starts a round, scores a hole, opens the map, turns the phone sideways (checking the whole nine fits next to the hole), and saves screenshots. After a push to main, the newest screenshots are on the `screenshots` branch, named after the device and the step.

If a check fails, GitHub marks the commit with a red X.

## The course library

The courses in Find Courses live in the `course-library` folder of this repository, so they cost nothing to host. The app reads plain files from it on GitHub (no server, no account):

- `course-library/index.json`: every course's name, town, holes, par, tees, version and files. Find Courses shows and searches this list.
- `course-library/courses/<id>/course.json` and one `<map>.svg` drawing per hole.

The app downloads every file of a course, checks them, and only then saves the course on the phone (Application Support/Downloaded Courses). On Play it quietly updates any course on the phone whose `version` in the library is higher. To add, fix or remove a library course, see `course-library/README.md`.

`Tools/CourseLibrary/make_library.py` lays out the built-in courses as a library folder. The automatic checks use it to make a copy of the library on the test Mac, so most of the Find Courses walk-through doesn't depend on the internet; one check on the iPhone Pro downloads from the real library on GitHub.

### Before the repository goes private

Phones can only download from a public repository. Before making this one private:

1. Create an empty public repository for the library, for example `golf-course-library`.
2. Move the contents of `course-library/` to it, plus `Tools/CourseLibrary/build_index.py` and the check in `.github/workflows/course-library.yml`.
3. Change `AppInfo.courseLibraryURL` to `https://raw.githubusercontent.com/aadaayy/<new repo>/main/`.
4. Ship that app update before going private. Copies of the app that still point here stop finding new courses once it's private, but courses already downloaded keep working.

## Add a built-in course

1. Copy `GolfScorecard/Courses/pompano-pines.json` to a new file named after the course id, for example `palm-links.json`.
2. Fill in the id, name, town, tees and every hole's par, handicap and yardage. If one tee has its own handicap row on the card (often the red tees), add it under `handicaps`, as hole 2 of Pompano Pines does.
3. Hole drawings: take a straight-on photo of the paper card and run `Tools/HoleDrawings/trace_holes.py` with a small spec file saying where the hole diagrams sit (see `Tools/HoleDrawings/pompano-pines.json`). It redraws each hole as a sharp vector drawing and adds them to `Assets.xcassets` as data sets, so the app can read the shapes and draw them in the yardage book style. Keep the colors the script uses: the map tells rough, fairway, water, sand, green and tee apart by them. Put each drawing's name, like `palm-links-01`, in that hole's `map`.
4. Push. The logic tests check the new file for typos such as a missing yardage or a repeated handicap.

## Layout

- `GolfScorecard/Core`: course format and scoring math (plain Swift, also tested on Linux)
- `GolfScorecard/Models`: saved rounds (SwiftData, on the phone only), the courses on the phone, and the course library
- `GolfScorecard/Views`: the screens
- `Shared`: the round's Lock Screen card, used by both the app and the RoundActivity extension
- `RoundActivity`: the widget extension that draws the Lock Screen card
- `Config`: Info.plist settings that can't be build settings (Live Activities, the `golfscorecard://` link the card opens)
- `GolfScorecard/Courses`: one JSON file per course (Pompano Beach Pines so far)
- `Shared/Book.swift`: the yardage book colors, fonts and paper, used by the app and the Lock Screen card
- `Tools/HoleDrawings`: redraws a card's hole diagrams as vector drawings
- `Tools/AppIcon`: draws the app icon and the small copy on the welcome page (`python3 Tools/AppIcon/make_icon.py`, needs Pillow)
- `Tools/CourseLibrary`: checks a course library folder and writes its index
- `GolfScorecardUITests`: the walk-through used by the automatic checks
- `Tests/ScorecardCoreTests`: logic tests
