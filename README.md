# Wmj Quick Timer

A macOS menu bar app for logging time to [Workamajig](https://www.workamajig.com): quick-log hours against a project/task, or run a live timer that submits quarter-hour-rounded time to your timesheet.

![The menu bar icon with its menu open](docs/images/menu.png)

**User documentation:** [Installation](docs/installation.md) · [Usage](docs/usage.md) · [Troubleshooting](docs/troubleshooting.md) · [Changelog](CHANGELOG.md)

## Requirements

- macOS 14 (Sonoma) or later
- A Workamajig account with **API access enabled** (ask your admin), plus your Company API Token and User API Token

## Development

The app is a plain Swift Package — no Xcode project file, no dependencies.

```sh
swift build          # compile
swift test           # run unit tests (time math + timer state machine)
swift run            # run the app (menu bar icon appears; no Dock icon)
open Package.swift   # develop in Xcode
```

Layout:

- `Sources/QuickTimerCore` — models, API client, Keychain helper, time math, timer state machine (unit-tested)
- `Sources/QuickTimer` — SwiftUI menu bar app (`MenuBarExtra`)
- `Support/Info.plist` — bundle plist (`LSUIElement` = no Dock icon)
- `scripts/` — API smoke test and release packaging

### API smoke test

With a `.env` file in the repo root (never committed) containing `WMJ_URL`, `WMJ_COMPANY_TOKEN`, `WMJ_USER_TOKEN`, and `WMJ_EMAIL`:

```sh
bash scripts/smoke.sh
```

Hits `/services`, `/projects`, and `/employees/search` and prints pass/fail. A commented block at the bottom shows how to post a first live time entry deliberately.

## Release

Releases are Developer ID-signed and notarized by Apple; `release.sh` refuses to run until the pieces below are in place.

One-time setup:

1. `brew install gh && gh auth login`
2. A **Developer ID Application** certificate in your login Keychain (Xcode → Settings → Accounts → your team → Manage Certificates → **+** → Developer ID Application — Account Holder role required). Verify with `security find-identity -v -p codesigning`.
3. An **App Store Connect API key** for notarization (App Store Connect → Users and Access → Integrations → Team Keys; the `.p8` downloads only once — keep it in the gitignored `secrets/`). In `.env`, set:
   ```sh
   APPSTORECONNECT_APIKEY=./secrets/AuthKey_XXXXXXXXXX.p8
   APPSTORECONNECT_ISSUERID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

Every change goes under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) as you make it. To ship:

1. Move the `Unreleased` items into a new `## [X.Y.Z] - YYYY-MM-DD` section and add the link refs at the bottom of the file.
2. Commit it (`git commit -am "Release X.Y.Z"`).
3. `bash scripts/release.sh X.Y.Z`

That verifies you're on a clean `main` with a real changelog entry and the signing/notarization pieces in place, builds the universal (Apple silicon + Intel) zip via `scripts/package.sh` — signed, notarized, and stapled — tags `vX.Y.Z`, pushes, and creates the GitHub Release with `dist/Wmj-Quick-Timer-X.Y.Z.zip` attached and the changelog section as the notes. It aborts before tagging if any check fails.

Versioning:

| Bump | When |
|---|---|
| **Patch** (0.1.**1**) | Bug fixes, docs, anything invisible to how the app is used |
| **Minor** (0.**2**.0) | New features or UI changes |
| **Major** (**1**.0.0) | Anything forcing users to reconfigure — settings reset, tokens re-entered, macOS requirement raised |

To build a zip without releasing it (testing the bundle locally): `bash scripts/package.sh X.Y.Z` — signs with the Developer ID cert if present (ad-hoc fallback otherwise) and skips notarization; add `NOTARIZE=1` to test the full notarization path.

For documentation screenshots, run the app with fake data — no credentials or API calls involved: `WMJ_DEMO=1 dist/WmjQuickTimer.app/Contents/MacOS/WmjQuickTimer`.
