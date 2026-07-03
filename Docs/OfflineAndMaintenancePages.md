# Offline / maintenance pages in a Hotwire Native app

Every page loaded into a Hotwire Native `WKWebView` gets `turbo.js` (this
repo's `Source/Turbo/WebView/turbo.js`) injected as a `WKUserScript`. It
expects real Turbo Drive on the page: it waits for `window.Turbo` (or
`window.Turbolinks`) plus a `turbo:load` event, then calls
`Turbo.registerAdapter(this)` and posts `pageLoaded` back to native. A plain
static HTML page — e.g. a maintenance/offline page served by an edge worker
while the real backend is down — has no Turbo Drive on it at all, so it never
satisfies that contract. Observed in production twice in the same afternoon
(birthdaze, 2026-07-03) before landing on the right fix:

1. **Do nothing.** After `TURBO_LOAD_TIMEOUT` (30s) with no `window.Turbo`,
   `turbo.js` calls `pageLoadFailed()` — the native side shows "Error loading
   page: configuration error" instead of the page.
2. **Naively stub `window.Turbo = {}`.** This satisfies the truthiness check
   and avoids #1, but `setup()` then calls `Turbo.registerAdapter(this)`
   unconditionally, which throws on a bare object (no such method) — the
   throw aborts `setup()` before `pageLoaded()` ever runs, so native never
   gets a success message either. Result: an infinite native loading spinner,
   silently, which is worse than #1.

## Recommended: opt out of the handshake entirely

As of this commit, a page can declare it has no Turbo Drive at all:

```html
<meta name="hotwire-native-bridge" content="none">
```

`turbo.js` checks for this before doing anything else and calls
`window.turboNative.pageLoaded()` immediately — no timeout, no fake `Turbo`
object to keep in sync with this file's internal contract.

**Compatibility note:** `turbo.js` ships bundled inside the app binary, not
fetched at runtime — so this only works for app builds compiled against this
commit (or later) of the fork. An app already installed on a device won't
understand the meta tag until it's rebuilt and the user updates. For a page
that must render correctly in *already-shipped* app versions too, use the
manual stub below (safe to include unconditionally alongside the meta tag —
it's read only if the meta tag isn't understood).

## Fallback: manual stub (works on any app version)

```html
<script>
  window.Turbo = window.Turbo || {
    registerAdapter: function () {},
    navigator: { restorationIdentifier: "" }
  };
  document.dispatchEvent(new Event("turbo:load"));
</script>
```

This matches the exact shape `setup()`/`pageLoaded()` read
(`registerAdapter()` that doesn't throw, `navigator.restorationIdentifier`
that doesn't throw) without depending on this fork's meta tag. It's a no-op
in a plain browser tab, where `turbo.js` was never injected in the first
place — safe to ship on a page that's sometimes viewed outside the app too.

Both approaches were verified against this file's actual `setup()` /
`pageLoaded()` / `registerAdapter()` logic with a standalone Node harness
(not just read by inspection) before shipping to production.

## Where this shipped

`homeserver-infra`'s Cloudflare Worker maintenance pages (`birthdaze`,
`gigq` — `terraform/cloudflare/workers/maintenance.js`) use the manual stub,
since the already-installed App Store builds predate the meta tag. New
static/offline pages built against this version of the fork should prefer
the meta tag.
