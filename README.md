# Yardage Book

The app shows as **Yardage Book** on the Home Screen (the project and bundle id keep the Golf Scorecard name). It looks like a caddie's yardage book: ink on cream paper, typewriter titles, red marks, and each hole drawn with red arcs every 50 yards to the middle of the green, a close-up of the green, and trees around the edge (the trees are decoration, not surveyed).

A paper-style golf scorecard for iPhone Duo and regular iPhones. Open the Duo, or turn any iPhone sideways, and the card sits on the left with the hole you're on at the right; hold a phone upright (or close the Duo) and you switch between them with tabs. No tracking, and no account unless you play with friends. Courses come from a free online course library and, once downloaded, work with no signal.

## What's in it

1. Welcome pages the first time: your name, an optional handicap, and whether the open Duo and a sideways phone each start on the Hole or Nine view.
2. Three tabs: Play, Past Rounds and Profile. On the iPhone Duo they sit in the strip at the side of the screen, under Back. Play resumes an unfinished round or picks a course; open or sideways, the picked course shows on the right, and Past Rounds and Profile use both halves too.
3. Find Courses (on Play): search the course library by name or town, or switch to Map to see every course as a dot (zoom into a town, tap a dot, download), and download a course. Downloaded courses show on Play, work offline, update themselves when the library has a newer copy, and can be removed with a swipe. Pompano Beach Pines is also built in, so the app works on first launch with no signal.
4. Start a round: tee, and up to four players (you're first; people you've played with are a tap away).
5. The round: card and map (see below), then Finish for a summary with Out, In, Total, to par and net. Delete (in red) throws away a round you have to leave part way through, after asking first.
6. The Lock Screen card (a Live Activity) during a round: the hole you're on and your score. Tap it to go straight back to that hole. It can be turned off in Profile.
7. Past rounds: every round, newest first. Finished cards stay locked until Edit.
8. Group rounds (Play with Friends): start a round with Start Group Round, and friends join from their own phones with a six-letter code (or the Invite link). Everyone keeps their own score, and everyone's card fills in live as scores come in. Sign in with Google is the only way in; Sign in with Apple is built and switched off until there's a paid Apple Developer account. Up to four players, like a paper card. Each phone keeps its own copy, so a round carries on with no signal and scores go out when it's back. Needs the setup below before it works.
9. Profile & Settings, laid out like the iPhone's Settings: My Profile (name, handicap, and the group rounds account with Sign Out and Delete Account), Playing (usual tee, and Hole or Nine for Duo open and for Sideways, each kept on its own), During a Round (show the round on the Lock Screen), History, and About (version, Erase Everything). Open or sideways, the sections are on the left and the picked one on the right.

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

## Group rounds setup

Group rounds run on [Supabase](https://supabase.com)'s free plan: accounts (Google sign-in), the database, and live updates. Until steps 1 to 5 are done, Start Group Round and Join a Group Round just say group rounds aren't set up yet, and the rest of the app works as before.

1. **Create the Supabase project.** Sign up at supabase.com, then New project. Pick a name (for example `yardage-book`), a strong database password you keep somewhere safe, and the region closest to you (East US). The free plan is enough.
2. **Make the tables.** In the project, open SQL Editor > New query, paste all of `supabase/migrations/20261031000000_group_rounds.sql`, and press Run. It makes the tables, the rules for who can see and change what, and turns on live updates for scores.
3. **Turn off email sign-in.** Authentication > Sign In / Providers > Email: turn it off, so the only way in is Google (and later Apple). Then Authentication > URL Configuration > Redirect URLs: add `golfscorecard://login-callback`.
4. **Set up Google sign-in.**
   1. In Supabase, open Authentication > Sign In / Providers > Google and copy the Callback URL it shows (it looks like `https://<your-project>.supabase.co/auth/v1/callback`). Leave the page open.
   2. Go to [console.cloud.google.com](https://console.cloud.google.com) and create a project (for example `Yardage Book`).
   3. Open Google Auth Platform (APIs & Services > OAuth consent screen). Fill in Branding with the app name Yardage Book and your email, and pick External under Audience.
   4. Clients > Create client. Type: Web application. Under Authorized redirect URIs, paste the Callback URL from step 4.1. Create, then copy the Client ID and Client secret.
   5. Back in Supabase's Google page: turn Google on, paste the Client ID and Client secret, and save.
   6. While Google's Audience says Testing, only the test users you list there (up to 100) can sign in. To open it to everyone, press Publish app. The app only asks for name and email, which normally doesn't need Google's review.
5. **Connect the app.** In Supabase, Project Settings > API Keys: copy the Project URL and the publishable key (or the legacy `anon` key). Paste them into `GolfScorecard/GroupScoring.plist` as `SupabaseURL` and `SupabaseAnonKey`, then push (or send them to Claude to push). Both are safe in the app and on GitHub: the database's rules decide what each player can do. Never paste the `service_role` or secret key.
6. **Later, Sign in with Apple** (needs the paid Apple Developer Program):
   1. In Xcode, GolfScorecard target > Signing & Capabilities > + Capability > Sign in with Apple.
   2. In Supabase, Authentication > Sign In / Providers > Apple: turn it on and add `com.albertoaday.golfscorecard` (your bundle id) under Client IDs. Sign in on the phone itself doesn't need a secret key.
   3. In `GroupScoring.plist`, set `AppleSignIn` to true. The Apple button then shows next to Continue with Google.

How it works:

- Each phone keeps its own copy of the round, saved like any other round (Past Rounds, the Lock Screen card), and only sends its own player's scores. The database only lets players in a round see it, and only lets each player write their own row.
- Codes use letters and digits that can't be mixed up (no I, L, O, 0 or 1), work for a day, and stop working when the starter taps Finish. A round takes up to four players.
- The Invite button shares the code and a `golfscorecard://join?code=…` link, which opens Join a Group Round on phones that have the app. A web link that installs the app first would need a website and the paid developer account.
- Delete Account (Profile > My Profile) removes the account and the scores it sent; rounds saved on the phone stay. Apple requires this for apps with accounts.
- Free plan room: 500 MB of database, 50,000 monthly users and 200 phones connected live at once. A round of four is about 72 small score rows, roughly 15 KB, so 1,000 testers playing a few rounds a week use well under 100 MB a month. A free project pauses after a week with no use; open the dashboard to wake it.
- The automatic checks never reach Supabase: they use a pretend server on the phone (`-mockGroup`, `GolfScorecard/Group/MockGroupService.swift`).

## Automatic checks

Every push runs the checks in `.github/workflows/checks.yml`:

1. Logic tests (Linux): every course file and hole drawing loads and passes its checks, the course library's index and search work, and the scoring math adds up.
2. App build and walk-through (Mac): builds the app and runs the same walk-through on iPhone Pro Max, iPhone Pro and iPhone Duo simulators. It finds, downloads, plays and removes a course in Find Courses, starts a round, scores a hole, opens the map, turns the phone sideways (checking the whole nine fits next to the hole), and saves screenshots. After a push to main, the newest screenshots are on the `screenshots` branch, named after the device and the step.

If a check fails, GitHub marks the commit with a red X.

## The course library

The courses in Find Courses live in the `course-library` folder of this repository, so they cost nothing to host. The app reads plain files from it on GitHub (no server, no account):

- `course-library/index.json`: every course's name, town, holes, par, tees, version, files and, when known, its location (`lat`, `lng`). Find Courses shows and searches this list, and puts courses with a location on its map.
- `course-library/courses/<id>/course.json` and one `<map>.svg` drawing per hole.

The app downloads every file of a course, checks them, and only then saves the course on the phone (Application Support/Downloaded Courses). On Play it quietly updates any course on the phone whose `version` in the library is higher. To add, fix or remove a library course, see `course-library/README.md`.

`Tools/CourseLibrary/make_library.py` lays out the built-in courses as a library folder. The automatic checks use it to make a copy of the library on the test Mac, so most of the Find Courses walk-through doesn't depend on the internet; one check on the iPhone Pro downloads from the real library on GitHub.

### Before the repository goes private

Phones can only download from a public repository. Before making this one private:

1. Create an empty public repository for the library, for example `golf-course-library`.
2. Move the contents of `course-library/` to it, plus `Tools/CourseLibrary/build_index.py`, the check in `.github/workflows/course-library.yml`, and the Florida import (`Tools/CourseImport/` and `.github/workflows/course-import.yml`). The Florida courses are open data under ODbL, which requires the library to stay public.
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
- `GolfScorecard/Group`: group rounds: sign-in, start and join, the live card (`GroupRoundSync`), the Supabase connection and the pretend server for the checks
- `GolfScorecard/GroupScoring.plist`: the Supabase project URL and key (placeholders until set up)
- `supabase/migrations`: the group-round database: tables, who can see and change what, and live updates
- `Config`: Info.plist settings that can't be build settings (Live Activities, the `golfscorecard://` link the card opens)
- `GolfScorecard/Courses`: one JSON file per course (Pompano Beach Pines so far)
- `Shared/Book.swift`: the yardage book colors, fonts and paper, used by the app and the Lock Screen card
- `Tools/HoleDrawings`: redraws a card's hole diagrams as vector drawings
- `Tools/AppIcon`: draws the app icon and the small copy on the welcome page (`python3 Tools/AppIcon/make_icon.py`, needs Pillow)
- `Tools/CourseLibrary`: checks a course library folder and writes its index
- `GolfScorecardUITests`: the walk-through used by the automatic checks
- `Tests/ScorecardCoreTests`: logic tests
