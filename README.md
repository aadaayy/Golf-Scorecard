# Golf Scorecard

A paper-style golf scorecard for iPhone Duo and regular iPhones. Open the Duo and the card sits on the left with the hole map on the right; close it and you switch between them with tabs. No tracking, no accounts, no internet: everything stays on the phone.

## Run it on your iPhone Duo (free Apple account)

You need a Mac with Xcode 27.1 or later (macOS Tahoe 26.6 or later). No simulator is needed.

### First time

1. In Xcode, choose Integrate > Clone, paste `https://github.com/aadaayy/golf-scorecard`, and pick a folder.
2. Open `GolfScorecard.xcodeproj` if it doesn't open by itself.
3. Xcode Settings > Accounts: sign in with your Apple account. A free account works; Xcode calls it a Personal Team.
4. Click the blue GolfScorecard project at the top of the file list, select the GolfScorecard target, open Signing & Capabilities, and pick your Personal Team.
5. If Xcode says the bundle identifier is taken, change `com.albertoaday.golfscorecard` to something unique to you.
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

1. Logic tests (Linux): every course file loads and passes its checks, and the scoring math adds up.
2. App build and walk-through (Mac): builds the app and runs the same walk-through on an iPhone Pro Max simulator and the iPhone Duo simulator. It starts a round, scores a hole, opens the map, turns the phone sideways, and saves screenshots. After a push to main, the newest screenshots are on the `screenshots` branch, named after the device and the step.

If a check fails, GitHub marks the commit with a red X.

## Add a course

1. Copy `GolfScorecard/Courses/sample-links.json` to a new file named after the course id, for example `palm-links.json`.
2. Fill in the id, name, town, tees and every hole's par, handicap and yardage.
3. Add hole drawings to `Assets.xcassets`, named like `palm-links-01`, and put that name in each hole's `map`.
4. Push. The logic tests check the new file for typos such as a missing yardage or a repeated handicap.

## Layout

- `GolfScorecard/Core`: course format and scoring math (plain Swift, also tested on Linux)
- `GolfScorecard/Models`: saved rounds (SwiftData, on the phone only) and the course list
- `GolfScorecard/Views`: the screens
- `GolfScorecard/Courses`: one JSON file per course
- `GolfScorecardUITests`: the walk-through used by the automatic checks
- `Tests/ScorecardCoreTests`: logic tests
