# Troubleshooting

## "Your Workamajig admin must enable API access for your user account"

Workamajig blocks API calls per-user until an admin enables access. Ask your admin to enable API access for your account in Workamajig's admin settings, then generate/retrieve your User API Token (click your name → API User Token) and re-verify in the app's Settings. This is separate from simply *having* a token — the token can exist while access is still disabled.

## Time entry submit fails

- The email in Settings must exactly match your Workamajig login email — it's used as your user ID when posting time. Check for typos and confirm with your admin which email is on your employee record.
- Some Workamajig setups require a **Service code** on every entry — make sure one is selected.
- The task must allow time to be charged to it (and to you). The task picker already hides completed tasks and tasks assigned only to other people, but it can't see project **team membership** — on a project you're not a member of, submitting fails with "The project is valid, but the user doesn't have access to it." Ask to be added to the project team, or use **Change Project…** in the Timer window to move the tracked time to a job you can log to. Try the same entry in the Workamajig web UI; if it fails there too, it's a project setup issue.

## macOS won't open the app ("damaged" / "unidentified developer")

This shouldn't happen anymore: releases from 0.2.0 on are signed and notarized by Apple and open normally. If you see this warning, you're probably running the old unsigned 0.1.0 — download the current version from the [Releases page](../../../releases). For the legacy 0.1.0 only, the workaround was right-click → **Open**, or:

```sh
xattr -d com.apple.quarantine "/Applications/WmjQuickTimer.app"
```

## macOS keeps asking for Keychain access

Your two API tokens are stored in one encrypted macOS Keychain item, and macOS asks permission the first time the app reads them. Click **Always Allow** and the prompt stops — releases share the same Developer ID signature, so updates don't re-trigger it. If it *keeps* coming back, you likely clicked **Allow** (one-time) instead of **Always Allow**. Upgrading from the unsigned 0.1.0 triggers the prompt one final time. See [About the Keychain prompt](installation.md#about-the-keychain-prompt) for what's stored and how to inspect or delete it.

If the app instead reports missing credentials after an update, re-enter both tokens in Settings and click **Save & Verify**.

## "401 unauthorized" from Workamajig

Workamajig is rejecting the credentials. Two common causes:

- **The User API Token is no longer valid.** Tokens can be invalidated server-side — notably, an admin generating *system-wide* user tokens overwrites every previously issued one. Generate a fresh token (click your name → **API User Token**), paste it into Settings, and **Save & Verify**.
- **The account lacks security rights.** The app can only do what the token's user is allowed to do — ask your admin to check the account's API access and permissions.

## Seeing the full error message

The Settings window and panels truncate long errors. The complete response from every failed API call is appended to:

```
~/Library/Logs/WmjQuickTimer.log
```

Open it with Console.app or any text editor (in Finder: **Go → Go to Folder…** and paste the path). Your tokens are never written to this file.

## The menu bar icon is missing

macOS hides menu bar items when the bar is full (especially on notched MacBooks), and offers apps no way to pin their icon or claim priority. The app stays reachable anyway:

- **⌃⌥T** opens the Timer window and **⌃⌥L** opens Quick Log, from anywhere.
- Launch the app again (Spotlight → "Wmj Quick Timer" → Return, or double-click it in Finder) — the running copy opens the Timer window if a timer is going, otherwise Quick Log.

To get the icon back, remove or rearrange other menu bar items (⌘-drag), or use an app like Bartender/Ice. Also confirm the app is actually running: it has no Dock icon by design.
