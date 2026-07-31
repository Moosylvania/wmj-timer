# Changelog

Every released version of Wmj Quick Timer and what changed in it. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org). Downloads are on the
[Releases page](https://github.com/Moosylvania/wmj-timer/releases).

## [0.2.0] - 2026-07-31

### Added

- Date field on Quick Log, defaulting to today — log time to a different day when needed.
- Merge-on-submit: if the day already has a row for the same project, task, and service, submitted hours are added to that row instead of creating a duplicate. Existing time is never overwritten.
- Failed API calls are logged in full to `~/Library/Logs/WmjQuickTimer.log` (the UI truncates long errors; tokens are never written).
- `AGENTS.md` — repo guide for AI agents: layout, commands, macOS menu bar gotchas, API facts, and the release flow.
- Demo mode (`WMJ_DEMO=1`): runs the UI on canned fake data with no API calls, Keychain reads, or settings writes — used for documentation screenshots.
- Screenshots in the user documentation (menu, Timer, Quick Log, Settings).

### Changed

- Quick Log and Start a Timer forms now use an aligned label column with uniform control widths.
- Releases are now signed with a Developer ID certificate and notarized by Apple: no more right-click-to-open or `xattr` on first launch, and the Keychain permission prompt happens once ever instead of after every update. Upgrading from 0.1.0 triggers the prompt one last time.

### Fixed

- Reopening a panel with a project already selected now shows the project in the search field instead of a blank placeholder.

## [0.1.0] - 2026-07-31

### Added

- macOS menu bar app for logging time to Workamajig — no Dock icon, no App Store, no third-party dependencies.
- Menu with **Add Timer** and **Quick Log**, each opening its own panel window under the menu bar icon. Panels stay visible (and ⌘-Tab-able) while you work in another app.
- **Timer**: start against a project/task/service, live `h:mm:ss` in the menu bar, Stop → Resume / Submit Time / Discard. Elapsed time is wall-clock based, so it survives sleep, quit, and restart. Submitted time rounds **up** to the next quarter hour, minimum 0.25.
- **Quick Log**: log 0.25–8 hours in quarter-hour steps to today's timesheet, usable while a timer is running.
- Type-ahead project search — click for the full list, type to filter by number, name, or client, Return takes the top match.
- Preferences window for Workamajig URL, email, and both API tokens, with eye buttons to reveal a token and **Save & Verify** to confirm the connection.
- API tokens stored in the macOS Keychain as a single encrypted item; everything else in UserDefaults. Nothing leaves the machine except requests to your Workamajig server.
- User ID resolution: posts time as your lowercased email, falling back to an employee lookup and remembering the resolved ID.
- **Start at login** toggle (`SMAppService`).
- Chess-clock menu bar (template) and app icons.
- Universal (Apple silicon + Intel) unsigned zip distribution via `scripts/package.sh`.
- User documentation: [installation](docs/installation.md) (including how to get API tokens and why macOS asks for Keychain access), [usage](docs/usage.md), [troubleshooting](docs/troubleshooting.md).

[0.2.0]: https://github.com/Moosylvania/wmj-timer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Moosylvania/wmj-timer/releases/tag/v0.1.0
