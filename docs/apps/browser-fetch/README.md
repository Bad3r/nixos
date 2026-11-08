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
- Expired rows of either jar count for nothing.
  A cookie a redirect deletes stays deleted for the rest of the fetch, and a fetch that falls back to Camoufox deletes it from Camoufox's profile too.

`--no-cookies` leaves LibreWolf out; Camoufox's jar still goes along.

## Private networks

A host is resolved before each request, including every redirect hop.
One that resolves to this machine or a private, shared, link-local, ULA or documentation range is refused with exit 4, before any cookie is read or sent.
curl connects only to the addresses that were checked, so a second DNS answer cannot move the request.
Behind a proxy, the proxy resolves the name instead.
curl takes it from `https_proxy`, `HTTPS_PROXY`, `all_proxy` or `ALL_PROXY`, the first one set, and Camoufox uses the same one.

## When Camoufox takes over

A bot challenge or a page its scripts have yet to build goes to [Camoufox](../../../packages/camoufox/default.nix), driven by Playwright.
The markers for Cloudflare, DataDome, PerimeterX and Akamai, and the threshold for a script-built page, live in [challenge.py](../../../packages/browser-fetch/browser_fetch/challenge.py).
Camoufox runs headed on a private Xvfb display, in a user, mount, network and PID namespace that dies with `browser-fetch`, with its own `/tmp`.
[pasta](https://passt.top/) gives that namespace internet access, with no mapping of the host's loopback or gateway and no port forwarding.
Routing rules in the namespace refuse the ranges above, so no page or redirect reaches this machine or a private network, whatever a name resolves to.
A proxy on this machine is out of the browser's reach.
It waits for the load and for a challenge to clear, within the bounds in [session.py](../../../packages/browser-fetch/browser_fetch/session.py).
A page the browser ends on comes back with the status its document got.
Outside 2xx that is an HTTP error, as from curl, so a challenge that does not clear in time on a 403 reads as that 403.
A main-document request that leaves the page's host, scheme or port is cancelled before it is sent and reported as a redirect.
The browser navigates only once the guard addon that cancels it reports its listeners in place, and the document's redirect chain is checked again afterwards.
A navigation that never commits a document is a browser failure, not an empty page.

Force or skip the browser:

```sh
browser-fetch --browser always https://example.org/
browser-fetch --browser never https://example.org/
```

## Camoufox's state

Camoufox keeps one profile and one fingerprint under `$XDG_STATE_HOME/browser-fetch/`, mode 0700, so a challenge it passed stays passed.
The fingerprint is drawn once per Camoufox release by Camoufox's own launcher, as Linux in `en-US`.
Drawing it starts Camoufox, so only a fetch that may use the browser draws it.
Until one exists, or when it cannot be drawn, curl sends its Firefox profile's own User-Agent and Accept-Language; `BROWSER_FETCH_DEBUG=1` prints why.
One fetch at a time uses the profile; another waits a bounded time, then fails.
LibreWolf's cookies for the page's host are added to the profile for the fetch and removed afterwards, unless the site set a new value meanwhile.
A fetch killed before that removal leaves a journal of hashes.
Every fetch, curl-only ones included, removes them under the profile lock before it reads the profile's cookies.
A fetch that cannot take the lock within the short `JAR_LOCK_SECONDS` bound of [browser.py](../../../packages/browser-fetch/browser_fetch/browser.py) goes on without Camoufox's cookies, so another fetch's render never stalls it.
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
