# AGENTS.md

Notes for AI agents working in this repo. Read this before changing code — most of it is hard-won behavior of macOS menu bar apps and the Workamajig API that isn't obvious from the source.

## What this is

**Wmj Quick Timer** — a macOS menu bar (status bar) app that logs time to Workamajig. Two jobs: **Quick Log** (pick project/task/service, enter hours, post to today's timesheet) and a **Timer** (start/stop, submit rounded time). Distributed as a Developer ID-signed, notarized zip from GitHub Releases; no App Store, no third-party dependencies.

## Layout

```
Package.swift                  SPM manifest — no .xcodeproj exists, don't add one
Sources/WmjQuickTimerCore/     Testable library: no SwiftUI, no AppKit
  Models.swift                 Codable models, API envelopes, APIError
  APIClient.swift              async URLSession client, auth headers, 6 endpoints
  Keychain.swift               SecItem wrapper — both tokens in ONE item
  TimeMath.swift               quarter-hour rounding + Quick Log validation
  TimerState.swift             pure timer state machine (idle/running/stopped)
  UpdateCheck.swift            GitHub release model + version compare + fetch
Sources/WmjQuickTimer/         SwiftUI app
  QuickTimerApp.swift          @main: MenuBarExtra + Window scenes + Settings scene
  MenuView.swift               the dropdown menu (menu items only)
  Panels.swift                 TimerPanel, QuickLogPanel, panelChrome/regularWhileOpen
  LogTimeForm.swift            ProjectField (type-ahead) + shared project/task/service form
  SettingsView.swift           preferences window
  AppModel.swift               @Observable @MainActor hub: settings, data, timer, submit
  Updater.swift                download → verify signature → swap bundle → relaunch
Tests/WmjQuickTimerCoreTests/  XCTest over Core only
Support/Info.plist             bundle plist (LSUIElement, CFBundleIconFile…)
Support/Resources/             AppIcon.icns, MenuBarIcon.png/@2x — copied into the bundle
scripts/package.sh             universal build → .app → Developer ID sign (ad-hoc fallback) → zip; NOTARIZE=1 notarizes + staples
scripts/release.sh             guards → package → tag → push → gh release
scripts/smoke.sh               live API smoke test from .env
docs/                          end-user documentation (installation/usage/troubleshooting)
```

Rule of thumb: **anything testable goes in Core** (no SwiftUI/AppKit imports there), UI stays in the app target.

## Commands

```sh
swift build                      # compile
swift test                       # unit tests (must stay green)
swift run                        # run from source — see caveats below
bash scripts/package.sh 0.1.0    # build dist/WmjQuickTimer.app + zip (Developer ID-signed if cert present)
NOTARIZE=1 bash scripts/package.sh 0.1.0   # …plus Apple notarization + stapling (needs .env keys)
WMJ_DEMO=1 dist/WmjQuickTimer.app/Contents/MacOS/WmjQuickTimer   # demo mode: canned data, for screenshots
open dist/WmjQuickTimer.app      # run the real bundle
killall WmjQuickTimer            # stop it before repackaging
bash scripts/smoke.sh            # live API check (needs .env)
bash scripts/release.sh 0.2.0    # full release (see Releasing)
```

`swift run` limitations — several features **only work from the assembled `.app`**: bundle Resources (menu bar icon falls back to an SF Symbol), `SMAppService` launch-at-login, and the Dock/app icon. When testing anything in those areas, package and `open` the bundle instead.

After a rename or a target change, stale objects can produce bogus link errors — `swift package clean` before assuming the code is broken.

## macOS menu bar app rules

These are the things that break if you forget them:

- **Activation policy.** The app runs as `.accessory` (set in `AppDelegate`, plus `LSUIElement` in Info.plist) so there's no Dock icon. Accessory apps are excluded from ⌘-Tab **and their windows hide when another app takes focus** — which made the Settings window vanish mid-copy-paste. Fix in place: `regularWhileOpen()` in `Panels.swift` flips to `.regular` + `hidesOnDeactivate = false` while any titled window is open, and back to `.accessory` when the last one closes. Any new window scene must use `panelChrome()` or `regularWhileOpen()`.
- **Opening a window from an accessory app** needs `NSApp.activate(ignoringOtherApps: true)` first or it opens behind everything.
- **MenuBarExtra style.** Default (`.menu`) renders real menu items and auto-dismisses on click — that's what `MenuView` relies on. `.menuBarExtraStyle(.window)` gives a popover that **closes on click-away and discards `@State`**; don't put forms in it (that bug is why the panels exist).
- **Panel positioning.** SwiftUI has no API for "under the status item", so `StatusItemAnchor` in `Panels.swift` finds the `NSStatusBarWindow` in `NSApp.windows` and sets the frame from it, clamped to the visible screen.
- **Menu bar icons** must be **template images** (`isTemplate = true`, black + alpha only) so macOS tints them for light/dark and inverts them on click. Provide `@1x` (18pt) and `@2x`; `NSImage(named:)` picks the scale.
- **Icon generation** — imagemagick is installed. From an SVG: render at high density, `-trim +repage`, then `-resize`. For a colored app icon, `-fill white -colorize 100` recolors the glyph (`-evaluate set 255` silently does nothing on grayscale+alpha), composite over a rounded rect, build an `.iconset`, then `iconutil -c icns`.
- **Keychain prompts.** macOS prompts once **per keychain item per code signature**. Both tokens live in one JSON item for that reason — don't split them back out. Released builds share the stable Developer ID signature, so users see the prompt once ever; ad-hoc fallback builds (no cert on the machine) are each a new identity, so a prompt after every such rebuild is expected, not a bug.
- **Dock icon caching** — macOS may show a stale app icon until the bundle is moved or you log out.

## SwiftUI/Swift conventions here

- `@Observable @MainActor final class AppModel` is the single hub; views get it via `.environment(model)` and `@Environment(AppModel.self)`.
- **Observation only tracks stored properties.** `isConfigured` used to be computed off the Keychain and the menu never updated when tokens were saved. It's now a stored property written by `saveCredentials(...)` — the single write path. Keep it that way: if state derives from something outside Observation (Keychain, filesystem, `SMAppService`), store it and update it explicitly.
- Async work started from `.task` gets **cancelled** when the view re-renders; swallow `CancellationError` / `URLError.cancelled` rather than showing them (see `AppModel.refresh()`), and guard against overlapping refreshes.
- Timer elapsed time is always derived from wall-clock `Date`s (`TimerState.elapsed(now:)`), never accumulated by ticking — that's what makes it survive sleep and relaunch. The 1s `Timer` exists only to nudge `now` while running.
- Persistence: non-secrets and the encoded `TimerState` in `UserDefaults` (via `didSet`), tokens in the Keychain. Nothing else.
- No third-party dependencies. URLSession, Security, ServiceManagement, SwiftUI, AppKit only. Don't add a package for something a few lines can do.
- Deliberate shortcuts are marked with a `// ponytail:` comment naming the ceiling. Follow that convention instead of silently taking a shortcut.
- **Demo mode**: `WMJ_DEMO=1` (checked via `AppModel.demo`) runs the whole UI on canned fake data — no API calls, no Keychain reads, no UserDefaults writes. Use it for screenshots or UI poking without real credentials; keep any new API/Keychain/persistence touchpoint behind the same flag. `WMJ_DEMO_OPEN=timer|quicklog|settings|update` opens that window at launch (screenshots need no UI scripting); `WMJ_DEMO_IDLE=1` skips the pre-seeded running timer so the start-form shows; `WMJ_DEMO_UPDATE=1` seeds a fake pending release so the update panel has something to show.

## Self-update

The app polls `GET /repos/Moosylvania/wmj-timer/releases/latest` (unauthenticated, 60 req/hr is plenty) and installs the zip itself — `Updater.swift`. Things that bite:

- **`codesign -R` needs a leading `=` on the requirement string.** Without it codesign reads the argument as a *path to a requirement file*, fails with "No such file or directory / invalid requirement specification", and rejects the genuine release exactly like a forged one — a bug that looks like working security. The requirement pins team `RTNF9A97B6` + identifier `com.moosylvania.QuickTimer`; verify before trusting a downloaded bundle, always.
- **Zips fetched with URLSession carry no `com.apple.quarantine`** (LaunchServices applies that, not the network layer), so an installed update doesn't trip Gatekeeper the way a browser download would. `spctl -a -vv` on the swapped bundle should still say `source=Notarized Developer ID`; `ditto`/`mv` preserve the stapled ticket.
- **A running bundle can't replace itself in place.** The swap is handed to a detached `/bin/sh` that waits for the PID to exit, then `rm -rf` + `mv` + `open`. Copy the new app out of the temp dir *before* returning — the `defer` deletes it.
- **Version only exists in the packaged bundle.** `AppModel.currentVersion` falls back to `0.0.0` under `swift run`, which suppresses update checks entirely. `package.sh` patches both `CFBundleShortVersionString` and `CFBundleVersion`.
- Checks are throttled to twice a day via a `lastUpdateCheck` UserDefaults date, polled hourly so sleep/wake can't skip a day. The banner fires once per version (`notifiedVersion`). Delete both keys from `com.moosylvania.QuickTimer` to re-test.

## Workamajig API facts

Base `{wmjURL}/api/beta1`, headers `APIAccessToken` (company) + `UserToken` (user) on every request.

| Endpoint | Notes |
|---|---|
| `GET /projects` | **PascalCase** JSON (`ProjectKey`, `ProjectNumber`, `ProjectName`, `ClientName`, also `ProjectStatus`/`ProjectStatusID`). Accepts ONLY `searchFor`+`searchField` — any other query param is a 400. There is **no membership filter**: admins get every project, and `POST /time` is the only thing that knows whether the user can actually log to one |
| `GET /tasks?projectKey=&includeTaskUser=true` | **camelCase**; `taskID` is usually a number but can be any string ("2.1.1" on outline-numbered jobs) — decoded to and posted as a string. Also returns `percComp`, `completedByDate` ("1/1/1900 …" = never), and `taskUser` (assignments with `userKey`/`userName`/`serviceCode`). `taskStatus` (1/2/3) is a **schedule** indicator (3 = late), NOT open/closed — filter completion on `percComp`/`completedByDate` |
| `GET /services` | PascalCase (`ServiceCode`, `Description`) |
| `POST /time` | Body is a JSON **array** of entries; success is `{"success":[…]}`; `workDate` is `M/d/yyyy` with `en_US_POSIX` |
| `GET /time?startDate=&endDate=&includeTime=1` | Timesheets (UserToken-scoped) with `TimeEntries` inside; entry `taskID` is a **string** here and `serviceCode` comes back lowercased |
| `PUT /time` | Update an entry: array body `[{"timeKey":…,"hours":…}]` suffices; same success envelope. Used by merge-on-submit (`AppModel.submitTime`) |

Field casing is inconsistent per module — every model spells out `CodingKeys`. Verify against `scripts/smoke.sh` output before trusting a new model.

More hard-won API facts:

- **Rate limiting is real**: ~55 rapid sequential requests returned HTTP 429. Never loop over projects calling `/tasks` per project.
- **The user's own `userKey`** comes from their timesheet entries (`GET /time` is UserToken-scoped; each entry has `userKey`), and it matches `taskUser[].userKey` on assignments. That's how `AppModel.userKey` is bootstrapped — `/users`, `/todos`, and `/employees/search` are permission-gated dead ends.
- **Error bodies have two shapes**: `{"status":…,"description":…}` and `{"logid":…,"errors":[{"error":[{"message":…,"status":…}]}]}` (occasionally `{"errors":["-3"]}`). `APIErrorBody` decodes all of them; surface `message`, log the raw body.

Pre-start validation (`AppModel.validateCanLog`) is a deliberate real write: a 0-hour `POST /time` (skipped when today already has a matching row). There is no dry-run or DELETE endpoint — the 0-hour row staying on the timesheet is the accepted cost, and merge-on-submit later folds real hours into it.

Two error cases users hit: `403` with "not enabled" (admin must enable API access — mapped to `APIError.accessNotEnabled`), and `401` (the token's user lacks the security rights).

Time posting: `userID` is always the lowercased settings email (`AppModel.submitTime`). Don't reach for `GET /employees/search` — it needs permissions many users lack, which is why it was removed.

## Security

- **`.env` is gitignored and must never be committed, echoed, or pasted into a message.** It holds real `WMJ_COMPANY_TOKEN` / `WMJ_USER_TOKEN` / `WMJ_URL` / `WMJ_EMAIL`, plus notarization credentials: `APPSTORECONNECT_APIKEY` (path to the App Store Connect `.p8`, kept in the gitignored `secrets/`) and `APPSTORECONNECT_ISSUERID`. The `.p8` is downloadable from Apple only once — don't delete or move it.
- Tokens belong in the Keychain, never in `UserDefaults`, logs, or source.
- Don't POST time to the live timesheet as a casual test — a real entry lands on a real person's timesheet. `scripts/smoke.sh` has a commented block for a deliberate one.

## Releasing

Every change gets an entry under `## [Unreleased]` in `CHANGELOG.md` as it's made. To ship: move those items into a dated `## [X.Y.Z]` section, commit, then `bash scripts/release.sh X.Y.Z` — it refuses to run on a dirty tree, off `main`, with an existing tag, or without a changelog entry, then builds, tags, pushes, and creates the GitHub Release with the zip attached. Details and the semver convention are in `README.md`.

## Definition of done

1. `swift build` clean and `swift test` green (add a test to Core for any non-trivial logic).
2. If the change touches UI or bundle behavior: `bash scripts/package.sh <version>` and `open dist/WmjQuickTimer.app`, then actually exercise the path.
3. User-visible change → update `docs/` and add a `CHANGELOG.md` entry under `## [Unreleased]`.
4. Don't commit or push unless asked.
