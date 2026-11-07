# browser-fetch

`browser-fetch` fetches a web page the way Firefox does and prints it as Markdown ([module](../../../modules/apps/browser-fetch.nix), [package](../../../packages/browser-fetch/default.nix)).
It requests the page through curl-impersonate's Firefox profile, which sets the TLS handshake, the HTTP/2 settings and the headers.
The User-Agent and Accept-Language are those of its Camoufox fingerprint instead, so cookies Camoufox earned hold for curl too.
Each request carries the cookies LibreWolf's default profile would send to that URL, read from a private copy of the profile's cookie database, plus Camoufox's own.

## Fetch a page

Precondition: LibreWolf runs its default profile, so its cookies are current.

1. Fetch from a shell:

   ```sh
   browser-fetch https://nixos.org/
   ```

2. Fetch the record the Claude Code plugin reads:

   ```sh
   browser-fetch --json https://nixos.org/
   ```

Verify that the record's `via` is `curl` and its `status` is `200`.

## Which cookies go out

- LibreWolf's unpartitioned jar, and its CHIPS cookies partitioned to the page's own site.
- Camoufox's jar; on the same name, host and path, Camoufox's cookie wins.
- Cookies the site set on an earlier redirect of the same fetch, which win over both.
- A host on this machine or a private network, such as `127.0.0.1`, `10.0.0.1` or `localhost.`, gets none of the stored cookies.

`--no-cookies` leaves LibreWolf out; Camoufox's jar still goes along.

## When Camoufox takes over

A bot challenge or a page its scripts have yet to build goes to [Camoufox](../../../packages/camoufox/default.nix), driven by Playwright.
The markers for Cloudflare, DataDome, PerimeterX and Akamai, and the threshold for a script-built page, live in [challenge.py](../../../packages/browser-fetch/browser_fetch/challenge.py).
Camoufox runs headed on a private Xvfb display, in a user, mount and PID namespace that dies with `browser-fetch`, with its own `/tmp`.
It waits for the load and for a challenge to clear, within the bounds in [session.py](../../../packages/browser-fetch/browser_fetch/session.py).
A challenge that does not clear in time comes back as the page the browser shows, with the status its document got.
A main-document request that leaves the page's host, scheme or port is cancelled before it is sent and reported as a redirect.
Hosts on this machine or a private network never reach the browser.

Force or skip the browser:

```sh
browser-fetch --browser always https://example.org/
browser-fetch --browser never https://example.org/
```

## Camoufox's state

Camoufox keeps one profile and one fingerprint under `$XDG_STATE_HOME/browser-fetch/`, mode 0700, so a challenge it passed stays passed.
The fingerprint is drawn once per Camoufox release by Camoufox's own launcher, as Linux in `en-US`.
One fetch at a time uses the profile; another waits a bounded time, then fails.
LibreWolf's cookies for the page's host are added to the profile for the fetch and removed afterwards, unless the site set a new value meanwhile.
A fetch killed before that removal leaves a journal of hashes, and the next fetch removes them first.
The profile keeps no disk cache.

Start over with a new fingerprint and an empty profile:

```sh
rm -r "${XDG_STATE_HOME:-$HOME/.local/state}/browser-fetch"
```

## Content types

HTML, from curl or the browser, is converted with markitdown's HTML converter after `noscript`, `iframe` and `template` elements are removed.
PDF, Word, PowerPoint, Excel and EPUB documents go through markitdown's document converters, from the fetched bytes only.
Other text, such as JSON, XML, CSV and Markdown, passes through as it came.
Every binary body is also saved under `~/.cache/browser-fetch/` with mode 0600.
Each conversion runs in a child process that is killed at the fetch's deadline.

## Claude Code WebFetch

The `browser-webfetch` plugin of the `nixos-local` marketplace answers every `WebFetch` call with `browser-fetch` ([plugin](../../../modules/agents/claude-code/marketplace/browser-webfetch/hooks/register.ts)).
It runs `/run/current-system/sw/bin/browser-fetch`, so each switch moves it to the current build.
It follows Claude Code's own WebFetch: the haiku prompt, the 100,000-character cap, `offset` paging, and the redirect, HTTP error and binary notes.
It makes no domain safety check against `api.anthropic.com`.
It answers the call before Claude Code's permission check, so WebFetch permission rules, the auto-mode classifier and PreToolUse hooks do not apply to it.
A failed fetch puts its reason in the status line and refuses the call with the built-in tool's failure text, never falling back to it.

## LibreWolf's cookies are unreadable

`browser-fetch` exits 3 when LibreWolf has no default profile or its `cookies.sqlite` cannot be copied.
Start LibreWolf once so it creates the profile, then fetch again.
`--no-cookies` fetches without them.

## A site still answers with a challenge

The site rejects curl-impersonate's Firefox profile, and Camoufox did not clear its challenge within the wait either.
Challenges that want a click are not answered.
Sign in to the site in LibreWolf, then fetch again: the fallback starts with the cookies that grants.
LibreWolf's shutdown wipe keeps cookies only for the sites in its [policy](../../../modules/browsers/_gecko-policies.nix).

## The browser fails

`browser-fetch` exits 5 with the reason, such as another fetch holding the profile past the wait.
A page curl fetched whole is returned as curl got it when only its script-built look sent it to the browser.
Set `BROWSER_FETCH_DEBUG=1` to print the stack of an unexpected error, which exits 7.
