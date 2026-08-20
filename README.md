# QuotaBar

A tiny macOS menu bar utility that shows remaining quota for two providers —
Codex (OpenAI) and Claude (Anthropic) — as two compact indicators in the menu
bar, with a small popover on click. No windows, no Dock icon, no settings
beyond a Launch at Login toggle.

## Reading the indicators

Each provider shows two numbers, stacked: the short (5-hour) window on top,
the weekly window below. Both are **remaining** percentages, not used ones.

| Colour | Remaining |
|--------|-----------|
| green  | 50% or more |
| yellow | 20–49% |
| red    | under 20% |

The provider icon stays neutral (it follows the menu bar's own light/dark
appearance) so only the numbers carry meaning. Three other states:

- `—` instead of a number: that window has no data. This is normal — the
  Codex API does not always report both windows.
- `!` next to the icon: the last refresh attempt failed, or the data on
  screen is older than 20 minutes. The last known-good numbers stay visible;
  open the popover to see what went wrong.
- **No icon at all**: that provider isn't set up on this machine, so it drops
  out of the menu bar and the popover entirely instead of sitting there
  permanently marked `!` over nothing.

A provider is only hidden when it has never returned valid data *and* the
reason is unambiguous: the `codex` CLI isn't installed (the login shell exits
127), or Claude Code has no credentials in `~/.claude/.credentials.json` nor in
the Keychain. Anything that might be temporary keeps the provider visible with
its `!` — a locked Keychain, an expired token, a network failure, a timeout, or
`codex` installed but signed out. Install the missing CLI or sign in and the
icon returns on the next refresh; nothing needs restarting.

If neither provider is set up, the menu bar shows a single gauge glyph rather
than collapsing to an empty item, so the popover — and `Quit` — stays reachable.

Providers are independent: if one is unreachable, blocked, or slow, the other
still updates and displays normally.

## Build and run

1. Open `QuotaBar.xcodeproj` in Xcode.
2. Select the `QuotaBar` scheme.
3. Press `⌘R`.

## Standalone install (no Xcode needed afterwards)

Either:

- `Product → Archive` in Xcode, then export/install from the Organizer, or
- Build once (`⌘B`), then copy the built `.app` — found under
  `~/Library/Developer/Xcode/DerivedData/QuotaBar-*/Build/Products/Debug/QuotaBar.app` —
  into `/Applications`.

Once copied to `/Applications` and launched from there, Xcode is no longer
needed to run it.

## Keychain access, and why it asks again

QuotaBar reads Claude Code's own OAuth credentials from the macOS Keychain
(item "Claude Code-credentials"), which needs your permission the first time:
*"QuotaBar wants to access key 'Claude Code-credentials'"*. Choose
**Always Allow**.

That grant does not last forever, and not because of a bug here. Claude Code
rewrites the Keychain item every time it refreshes its own OAuth token, and a
rewritten item comes back with a fresh list of trusted applications — so
QuotaBar's permission is dropped every few hours.

**Background refreshes are therefore never allowed to show that prompt.**
Only two paths may: the first refresh after launch, and pressing `Refresh`
yourself. Everything else (the timer, waking from sleep) fails quietly
instead, showing `!` in the menu bar and *"Keychain access needed — click
Refresh"* in the popover. One click restores it. Without this rule the app
would stack up system dialogs overnight.

Rebuilding also drops the grant: the project is ad-hoc signed
(`CODE_SIGN_IDENTITY = "-"`), so the code signature changes with every build.
For a stable signature, open **Signing & Capabilities** in Xcode, enable
**Automatically manage signing**, and select your own Development Team.

## Refresh interval

`Refresh every` in the popover: 1, 5, 15, 30 or 60 minutes, default 5. The
choice persists across launches. Changing it restarts the timer immediately
and does not itself trigger a refresh.

## Why App Sandbox is disabled

App Sandbox is intentionally off, and there is no entitlements file. QuotaBar
needs to:

- Read a Keychain item created by a different application (Claude Code),
  which sandboxed apps cannot do without a shared keychain-access-group
  entitlement Claude Code doesn't provide.
- Launch an external process (`codex app-server`) via a login shell, which
  the sandbox blocks.

## Read-only, by design

QuotaBar never writes credentials anywhere, never logs tokens or credential
file contents, and never performs a login or token-refresh flow of its own.
If Claude's access token has expired, QuotaBar reports that and waits — only
Claude Code itself is allowed to refresh it.

## Manual verification

To sanity-check the two data sources outside the app (without ever printing
a token):

```sh
# Codex: exercises the same app-server JSON-RPC path QuotaBar uses.
codex app-server
# then paste, one line at a time:
# {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"test","version":"1.0.0"}}}
# {"jsonrpc":"2.0","method":"initialized"}
# {"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":null}

# Claude: confirms the account has a reachable usage endpoint (status code only).
# The token flows entirely through pipes (Keychain -> python3 -> curl's stdin via
# `-H @-`) and never appears as a command-line argument, so it never shows up in
# `ps` or shell history.
security find-generic-password -s 'Claude Code-credentials' -w \
  | python3 -c 'import json, sys; tok = json.load(sys.stdin)["claudeAiOauth"]["accessToken"]; print(f"Authorization: Bearer {tok}")' \
  | curl -s -o /dev/null -w "%{http_code}\n" -H @- -H "anthropic-beta: oauth-2025-04-20" \
    https://api.anthropic.com/api/oauth/usage
```
