# Troubleshooting

## "Your Workamajig admin must enable API access for your user account"

Workamajig blocks API calls per-user until an admin enables access. Ask your admin to enable API access for your account in Workamajig's admin settings, then generate/retrieve your User API Token (click your name → API User Token) and re-verify in the app's Settings. This is separate from simply *having* a token — the token can exist while access is still disabled.

## "No employee found for [email]"

The email in Settings must exactly match your Workamajig login email. Check for typos and confirm with your admin which email is on your employee record.

## Time entry submit fails

- Some Workamajig setups require a **Service code** on every entry — make sure one is selected.
- The task must allow time to be charged to it (and to you). Try the same entry in the Workamajig web UI; if it fails there too, it's a project setup issue.
- The app first tries your email address as your user ID, then automatically retries with the user ID from your employee record. If both fail, the error shown comes straight from Workamajig.

## macOS won't open the app ("damaged" / "unidentified developer")

The app is not notarized. See [Installation](installation.md) — right-click → Open, or remove the quarantine flag:

```sh
xattr -d com.apple.quarantine "/Applications/WmjQuickTimer.app"
```

## macOS keeps asking for Keychain access

Your two API tokens are stored in one encrypted macOS Keychain item, so macOS asks permission the first time each *copy* of the app reads them. Since releases are unsigned, every update looks like a new app and the prompt returns once — click **Always Allow** and it stops for that version. See [About the Keychain prompt](installation.md#about-the-keychain-prompt) for what's stored and how to inspect or delete it.

If the app instead reports missing credentials after an update, re-enter both tokens in Settings and click **Save & Verify**.

## "401 unauthorized" from Workamajig

The user token identifies a specific Workamajig user, and the app can only do what that user is allowed to do. A 401 means that account lacks the security rights for the request — ask your admin to check the user's permissions, or use a token belonging to an account that has them.

## The menu bar icon is missing

macOS hides menu bar items when the bar is full (especially on notched MacBooks). Remove or rearrange other menu bar items (⌘-drag), or use an app like Bartender/Ice. Also confirm the app is actually running: it has no Dock icon by design.
