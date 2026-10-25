# Reader — engineering notes

An iPhone reader (iOS 26, Swift 6, SwiftUI) for your own book library: it browses an OPDS catalog
(such as Calibre-Web's), opens EPUB and PDF with the Readium Swift toolkit, and keeps your place
with a KOReader sync (kosync) server. The engine is borrowed; the reading UI is the product. This
file is the map and the rules.

## Map

- `Package.swift`: `ReaderCore` and `ReaderCoreTests`. The Xcode project builds ReaderCore from
  this package (local reference `..`); its iOS 26 / macOS 15 platforms are a floor.
- `Sources/ReaderCore`: the portable logic (builds on Linux too; Foundation only). `BookFormat`
  (the formats the app opens, by media type).
- `Tests/ReaderCoreTests` (Swift Testing) and `Tests/Fixtures` (below).
- `App/`: `Reader.xcodeproj` (synchronized folders: adding files needs no project edit), `Reader/`
  (`App/` the app, its root view, `Log` and `DemoMode`; `Resources/` the catalogs, privacy
  manifest and assets), `ReaderTests` (Swift Testing), `ReaderUITests` (XCTest),
  `Config/Info.plist` (export compliance, the scene manifest; the rest is the target's
  `INFOPLIST_KEY_*` settings).
- `ci/` and `.github/workflows/ci.yml`: jobs `core` (Linux: ReaderCore tests, warnings, string
  catalog, fixtures), `apple` (`iphone` on every push: Debug build, screenshots, unit and UI tests,
  Release check; or `compile`), `report` (`ci/report.py` writes `STATUS.md`). The scripts came
  from `pbordjadze/pigeon`'s `ci/` (and `pbordjadze/paint-by-number`'s before it) and keep their
  shape.
- `tools/`: `swift.sh` (SwiftPM in Docker), `strings_check.py`, `make_fixtures.py` (their
  docstrings are the manuals).
- `PRIVACY.md`: the privacy policy, word for word what the app does (below).
- Plans, briefs and the backlog are not committed here: they live in the private
  `painting-company` repository (the reader is its row 127). A commit message says what changed
  and why, and cites a row by number; it quotes no one and names no one.
- The app is a general OPDS + kosync reader. No real server's address, account, library or
  titles in the repository, its fixtures, screenshots, commits or issues, and nothing about where
  a library's books come from.

## Fixtures (tests never need a real server)

`Tests/Fixtures` is a reader's server in files, made by `tools/make_fixtures.py` from
public-domain text: an OPDS catalog in Calibre-Web's shape (navigation, two pages of new books,
OpenSearch, a search result), the books it offers (an EPUB 3, a PDF with a text layer, a scanned
PDF of page images under an invisible OCR layer, and one book offered only as MOBI), covers, and
kosync's requests and replies. Change the script, run it, commit both; CI fails when they differ.
Tests and demo scenarios read these, never a live server.

## Privacy (hard rules)

No account, no analytics, no ads, no third-party services. Books and reading positions travel only
between the phone and the servers the reader adds, over HTTPS (no App Transport Security
exception). A server's password lives in the Keychain. No DRM: Readium's LCP module stays out. A
change to what leaves the phone changes `PRIVACY.md`, `Resources/PrivacyInfo.xcprivacy` and
`ShipHygieneTests` together. A required-reason API (UserDefaults, file timestamps, disk space,
boot time) adds its category and reason to the manifest, and to the list `ShipHygieneTests` pins
(Debug-only code, like `DemoMode`'s UserDefaults, doesn't ship and doesn't count). The app asks
for no permission; `ci/check_release.sh` fails on a usage description or a background mode.

## Working here (Linux, no Xcode)

| Task | Command |
| --- | --- |
| ReaderCore tests | `tools/swift.sh test` |
| String catalog check | `python3 tools/strings_check.py` |
| Fixtures | `python3 tools/make_fixtures.py` (`--check` to compare) |

- `App/` compiles only on CI: after editing an App Swift file, re-read it whole and check its
  imports (`MemberImportVisibility`), actor isolation at each boundary, API names and signatures
  against iOS 26 / Swift 6.2, and every call site of anything renamed.
- Compiler warnings fail CI (`ci/warnings.sh`, on the Linux and Xcode build logs; `main` has
  none): fix a new one, never silence it.
- Scratch output goes outside the repo. Keep a diff to what the task needs.

## App rules

- Deployment target iOS 26.0, iPhone only. Build with Xcode 26.6 (CI). Swift 6 with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency: app types are MainActor
  by default; mark pure helpers `nonisolated` and CPU-heavy async work `@concurrent`. ReaderCore
  is a separate module (nonisolated). The test targets have neither setting: suites that touch app
  types are `@MainActor`.
- `MemberImportVisibility` is enabled: every file that touches members of a type from another
  module imports that module itself (`import ReaderCore`, …); a file that logs through `Log`
  imports `os`.
- System controls stay system controls (Liquid Glass), SF Symbols, Dynamic Type, dark mode,
  VoiceOver labels and values, Reduce Motion.
- Identity: the display name is a working name, Reader. The product name, the icon and the App
  Store listing are the owner's to decide; never change them unasked.
- Localization: every user-facing string of the app target lives in
  `Resources/Localizable.xcstrings` (English first), the Info.plist texts in
  `Resources/InfoPlist.xcstrings` (keyed by the plist key); ReaderCore stays English and returns
  values, not sentences. Three code forms, and nothing else: a SwiftUI literal with no
  interpolation (`Text("Done")`: the literal is the key); `String(localized: "key", defaultValue:
  "…\(x)…", comment: "…")` for an interpolation, a count or a non-SwiftUI destination (dotted keys;
  the comment says where it shows and what the arguments are); `String(localized: "literal")` for
  a plain string. `Text(someString)` is verbatim, so build such strings with the second or third
  form first. Counts are catalog plurals; numbers, sizes and dates go through `.formatted(...)`,
  never concatenation. A new string needs its catalog entry written by hand (`"comment"`,
  `"extractionState": "manual"`; an explicit key also `localizations.en`): Xcode extracts nothing.
  `tools/strings_check.py` (CI) fails on drift.
- Demo scenarios: `-demo <name>` (`DemoMode`; scenarios listed on the views that render them). A
  screenshotted scenario is one `name@seconds` line of `ci/scenarios.txt` and calls
  `DemoMode.markReady()` once its content is on screen; `-dark` and `-long-text` in a name pick dark
  appearance and doubled strings. Demo content comes from the fixtures. Demo code is `#if DEBUG`,
  and `ci/check_release.sh` fails if it shows up in the Release binary.
- Done means: a test for each new behaviour in the right target, a demo scenario for any new
  screen, catalog entries for its strings, VoiceOver, Dynamic Type and dark mode for every new
  control, and this file's pointers kept current. No stubs or flags hiding unfinished work.

## CI feedback loop (no Xcode locally)

1. Before a push, look at the Actions runs of this repository, `pbordjadze/paint-by-number` and
   `pbordjadze/pigeon`: the 5 macOS runners are shared. One branch at a time while
   paint-by-number's `main` runs.
2. Commit, push to a branch (`git push -u origin HEAD:<branch>`; CI runs on every branch). Compile
   first: `[compile]` in a branch commit's message runs only the Debug and Release builds, the
   Release check and the warnings gate on one runner, no simulator.
3. Run `CI_BRANCH=<branch> ci/fetch.sh <sha> <outdir>` in the background; it waits for the report
   CI publishes to the ref `refs/ci-shots/<branch>` (not fetched by a clone) and unpacks it:
   `STATUS.md` (job results, failed steps, test counts, failed tests with their first message,
   scenarios that never signalled readiness, crashes), logs, `core/`, and per job `errors.txt`,
   `shots/*.png`, `*-app.log`, `test-app.log`, test results and `attachments/`.
4. Read errors and screenshots, fix, repeat. Batch fixes: a newer push to the same branch cancels
   the older run.

**Branches.** `main` is the default branch. Work on `claude/<topic>` branches and merge into
`main` once CI is green and a reviewer that didn't write the change has read
`git diff origin/main...HEAD`; the merge commit lists what the review found and what was fixed.
Docs-only commits carry `[skip ci]`; a commit message holds CI's tags (`[skip ci]`,
`[compile]`) only to mean them.

## Conventions

- Swift 6 language mode, strict concurrency. Core types are `Sendable` value types.
- Comments explain *why*, sparingly. No dead code, no TODO litter.
