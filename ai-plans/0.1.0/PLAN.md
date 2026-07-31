# Workamajig Quick Timer — Implementation Plan

## Context
Greenfield macOS menu bar app for the agency to log time to Workamajig: a Quick Log form (project → task → service → hours) and a start/stop timer that submits quarter-hour-rounded time to the user's timesheet via the Workamajig REST API. Distributed as an **unsigned zip** from GitHub Releases. Repo currently contains only `.gitignore` (already Xcode/Swift-aware), `.env` (tokens, gitignored), and `InitialPrompt.md`.

**API facts (verified from the official docs via the logged-in browser):**
- Base `{WMJ_URL}/api/beta1/`; headers `APIAccessToken` + `UserToken` on every request; JSON everywhere.
- `GET /projects?searchFor=&searchField=projectname` — projects visible to the user
- `GET /tasks?projectKey=K&includeTaskUser=true` — tasks (`taskID`, `taskKey`, `taskName`)
- `GET /services` — service codes (`ServiceCode`, `Description`) — note PascalCase; use explicit `CodingKeys` per model
- `GET /employees/search?email=X` — **verified live**: returns `data.employee[]` with `userID` (**this is the ID for time posting** — in practice the user's email, lowercase; `systemID` is empty in our instance), `email`, `defaultServiceCode`, `employeeKey`, `firstName`/`lastName`, `active`
- `POST /time` — body is a **JSON array**: `[{userID, hours, projectNumber, taskID, serviceCode, workDate ("M/d/yyyy"), comments, overtime}]` → `{success:[{timeKey, timeSheetKey, ...}]}`

**API access status:** enabled and verified live (2026-07-30) — `GET /employees/search?email=` returns real data. The app should still map 403 `"access denied - API/MCP access is not enabled for this user"` to a friendly "ask your Workamajig admin to enable API access" message, since each new user hits this on first setup.

**User decisions:** unsigned zip distribution; service-code picker pre-selected to the user's default; settings collects **email**. For time posting, **use the email (lowercased) directly as `userID`**; only if `POST /time` rejects it, fall back to `GET /employees/search?email=` and retry with the returned `userID`.

## Approach
Swift Package Manager executable (NOT a hand-rolled `.pbxproj` — fragile to generate non-interactively; SPM gives `swift test`, universal binaries, and `open Package.swift` Xcode dev for free). Two targets: **QuickTimerCore** library (models, API client, keychain, time math, timer state — testable) + **QuickTimer** executable (SwiftUI). A script assembles the `.app` bundle with `Info.plist` (`LSUIElement=true`). Min macOS 14 (`MenuBarExtra` + `@Observable`). Zero dependencies: URLSession, Security framework, UserDefaults.

- **UI**: one `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Label = timer SF Symbol + `h:mm` text while running. Panel: timer section (phase-dependent) above an always-available Quick Log; gear → inline settings; explicit Quit button. `NSApp.setActivationPolicy(.accessory)` in code so `swift run` also hides the Dock icon.
- **Timer**: `enum Phase { idle; running(startedAt: Date, accumulated: TimeInterval); stopped(accumulated) }` — elapsed always derived from wall clock, never tick-accumulated. 1 s `Timer` exists only while running. Whole state persisted to UserDefaults on every transition → survives restart. Submit rounds to nearest 0.25 h, clamped to min 0.25; failure keeps state for retry. One timer at a time (start only from `.idle`).
- **Quick Log**: hours field validated 0.25–8.0 in exact 0.25 steps; independent selection from the timer so it works while a timer runs.
- **Secrets**: tokens in Keychain (small SecItem helper); URL/email/defaultServiceCode in UserDefaults. Settings has "Verify Connection" → `GET /employees/search?email=` shows the resolved name and stores `defaultServiceCode` (and the returned `userID` as the posting fallback). Day-to-day posting just uses the lowercased email as `userID`.
- **Launch at login**: "Start at login" toggle in Settings using `SMAppService.mainApp.register()/.unregister()` (ServiceManagement framework, macOS 13+, no deps, no helper app). Caveat: only works from the assembled `.app` bundle (not `swift run`) and the app should live in `/Applications` — documented in installation.md. Toggle reflects `SMAppService.mainApp.status`.

## File Layout
```
Package.swift                          # SPM manifest, platforms [.macOS(.v14)]
Support/Info.plist                     # LSUIElement=true, bundle id, version
Sources/QuickTimerCore/
  Models.swift                         # Codable models + API envelopes + APIError (.accessNotEnabled etc.)
  APIClient.swift                      # async URLSession client, auth headers, 6 endpoints (~150 lines)
  Keychain.swift                       # ~50-line SecItem get/set/delete
  TimeMath.swift                       # roundToQuarterHour, validateQuickLogHours
  TimerState.swift                     # phase enum + pure transitions + Codable persistence
Sources/QuickTimer/
  QuickTimerApp.swift                  # @main MenuBarExtra(.window), restore state
  AppModel.swift                       # @Observable hub: settings, fetch/cache, timer driving, submit
  MenuView.swift                       # phase-driven timer section + Quick Log + footer
  LogTimeForm.swift                    # project search → task → service pickers (+ hours in Quick Log mode)
  SettingsView.swift                   # tokens (SecureField), URL, email, Verify Connection
Tests/QuickTimerCoreTests/
  TimeMathTests.swift                  # rounding/validation edges
  TimerStateTests.swift                # transitions + Codable round-trip
scripts/smoke.sh                       # curl smoke test from .env (detects the 403 case, prints remediation); commented POST /time block
scripts/package.sh                     # universal release build → assemble .app → ad-hoc codesign → ditto -c -k zip
README.md                              # build/dev/release instructions → links to docs/
docs/installation.md                   # zip install + right-click→Open / xattr quarantine workaround
docs/usage.md                          # settings, Quick Log, timer flows
docs/troubleshooting.md                # 403 admin-enable, keychain re-prompts after rebuild, token rotation
```

## Implementation Sequence
1. Scaffold: `Package.swift`, `Info.plist`, stub `MenuBarExtra` → `swift build` && `swift run` shows icon
2. `TimeMath` + `TimerState` + tests → `swift test` green
3. `Keychain` + `Models` + `APIClient` (incl. `.accessNotEnabled` mapping)
4. `scripts/smoke.sh` → run against live API (access confirmed working) to lock in response shapes for /projects, /tasks, /services
5. Settings + Verify Connection (`/employees/search?email=`)
6. Quick Log form + submit
7. Timer UI + menu-bar label + restart-persistence check (`killall` + relaunch)
8. `scripts/package.sh` → zip, install-test on a clean location
9. README + docs/

## Verification
- `swift build`, `swift test` at each step
- `swift run`: menu bar icon, no Dock icon, settings persist, timer survives kill/relaunch
- `bash scripts/smoke.sh`: real data from /projects, /tasks, /services, /employees/search
- First live `POST /time` via the commented smoke.sh block before trusting the app path (verify entry lands on the timesheet in WMJ UI, incl. that email-as-userID is accepted)
- `bash scripts/package.sh 0.1.0` → unzip elsewhere, right-click→Open works per docs

## Risks
- Email-as-`userID` for `POST /time` is inferred from the employee record, not yet proven by a live POST → first live submit via smoke.sh confirms; `/employees/search` fallback designed in
- WMJ field-name casing is inconsistent across modules → explicit `CodingKeys`, verify against smoke.sh output before finalizing models
