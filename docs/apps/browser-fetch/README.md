# browser-fetch

`browser-fetch` fetches a web page the way Firefox does and prints it as Markdown ([module](../../../modules/apps/browser-fetch.nix), [package](../../../packages/browser-fetch/default.nix)).
It requests the page through curl-impersonate's Firefox profile, which sets the TLS handshake, the HTTP/2 settings and the headers.
The User-Agent and Accept-Language are those of its Camoufox fingerprint instead, so cookies Camoufox earned hold for curl too.
curl, Camoufox and [kagi-search](../kagi-search/README.md) share one cookie jar under the profile lock, the `cookies.sqlite` of Camoufox's profile, so what one earns, the others send.

The standalone `camoufox` command, built with `nix build path:.#camoufox`, is enabled only on Songbird through `programs.camoufox.extended.enable` ([module](../../../modules/browsers/camoufox/apps.nix)).
The [package](../../../packages/camoufox/default.nix) applies its bundled uninstall policy at build time and checks removal and saved profile data across restarts.

## Fetch a page

1. Fetch from a shell:

   ```sh
   browser-fetch https://nixos.org/
   ```

2. Fetch the record the Claude Code plugin reads:

   ```sh
   browser-fetch --json https://nixos.org/
   ```

Verify that the record's `via` is `curl` and its `status` is `200`.

## Sign in to a site

Precondition: a local X display in `DISPLAY`.
Open an http or https page in Camoufox, sign in in the window, then close every window:

```sh
browser-fetch login https://kagi.com
```

Verify that the last line counts the site's cookies in `cookies.sqlite`.

The window runs Camoufox on the profile and fingerprint fetches use, in the same namespaces but without the guard addon, so it navigates anywhere.
The namespace gets the display's socket and an Xauthority file with only that display's entries.
The login holds the profile lock until every window is closed, or until `LOGIN_SECONDS` of [browser.py](../../../packages/browser-fetch/browser_fetch/browser.py) pass.
It then closes Camoufox, which writes the cookies to the jar; session cookies are lost, as when Firefox closes.

## The cookie jar

Each fetch that runs curl reads the jar under the profile lock, and each request carries what Firefox would send to its URL.
That is the unpartitioned jar plus the CHIPS cookies partitioned to the page's own site, with expired rows counting for nothing.
A cookie the site set on an earlier hop of the same fetch wins over the jar's.

Every `Set-Cookie` curl receives, deletions and expiries included, is written to the jar as its response arrives, so the writes of overlapping fetches follow arrival order.
That holds for a response whose transfer then fails, such as a body over the size limit or a timeout.
Parsing, validation and the rows follow the cookie code of the Firefox release Camoufox is built on, so Camoufox loads curl's cookies as its own.
Rows go in only while no browser runs, under the profile lock, and every connection is closed before Camoufox starts.
A database at another schema version than Firefox's 17 is never touched, since Firefox drops a table it cannot read.

Session cookies are never written, as Firefox never stores them.
They still go on curl's later hops, and a fallback adds them to the browser through Playwright before it navigates.
Playwright adds to the unpartitioned jar only, so a partitioned session cookie stays out of the browser.
It also stores `SameSite=None` as unset, which Firefox treats the same while `network.cookie.sameSite.laxByDefault` is off.

`--no-cookies` neither reads nor writes the jar.
curl still sends a cookie the site set on an earlier hop, and a fallback renders in a throwaway profile given those cookies.

## Proxies

curl takes an https URL's proxy from the first of `https_proxy`, `HTTPS_PROXY`, `all_proxy` and `ALL_PROXY` that is set and not empty, and an http URL's from `http_proxy`, `all_proxy` and `ALL_PROXY`, never `HTTP_PROXY`.
It reaches a host directly when `no_proxy`, or `NO_PROXY` if `no_proxy` is unset or empty, names it by [curl's rules](https://curl.se/libcurl/c/CURLOPT_NOPROXY.html).
An HTTP, HTTPS, `socks5h` or `socks4a` proxy resolves the name itself; to a `socks5` or `socks4` proxy, curl sends the address it resolved.
Camoufox goes through the proxy curl uses for the page it takes over, or directly when curl does, and has a SOCKS proxy resolve names.
A redirect in Camoufox to the host's `www.` twin is reported, not followed, when curl would route the twin differently.
A proxy at an IPv6 address, or a SOCKS proxy with credentials, fails the browser, since Playwright cannot give either to Firefox.

## When Camoufox takes over

A bot challenge or a page its scripts have yet to build goes to [Camoufox](../../../packages/camoufox/default.nix), driven by Playwright.
The markers for Cloudflare, DataDome, PerimeterX and Akamai, and the threshold for a script-built page, live in [challenge.py](../../../packages/browser-fetch/browser_fetch/challenge.py).
Camoufox runs headed on a private Xvfb display, in a user, mount, network and PID namespace that dies with `browser-fetch`, with its own `/tmp`.
[pasta](https://passt.top/) gives that namespace the host's network, with an address of `192.0.0.0/29` of its own, so the host's addresses and gateway are the real ones.
A loopback port the host listens on is forwarded to the host's, so loopback, LAN and other private addresses, and proxies on them, are reached as curl reaches them; nothing connects into the namespace.
It waits for the load and for a challenge to clear, within the bounds in [session.py](../../../packages/browser-fetch/browser_fetch/session.py).
A page the browser ends on comes back with the status its document got.
Outside 2xx that is an HTTP error, as from curl, so a challenge that does not clear in time on a 403 reads as that 403.
A main-document request that leaves the page's host or port, or its scheme other than from http to https, is cancelled before it is sent and reported as a redirect.
The browser navigates only once the guard addon that cancels it reports its listeners in place, and the document's redirect chain is checked again afterwards.
A navigation that never commits a document is a browser failure, not an empty page.
Firefox shows its own error page for an empty 4xx or 5xx document, which comes back at once with that status; any other Firefox error page, such as an unreachable proxy's, is a browser failure.

Force or skip the browser:

```sh
browser-fetch --browser always https://example.org/
browser-fetch --browser never https://example.org/
```

## Camoufox's state

Camoufox keeps one profile and one fingerprint under `$XDG_STATE_HOME/browser-fetch/`, mode 0700, so a challenge it passed stays passed.
The fingerprint is drawn once per Camoufox release by Camoufox's own launcher, as Linux in `en-US`.
Drawing it starts Camoufox, so only a login or a render draws it, and a page curl answers never waits on it.
Until one exists, or when it cannot be read, curl sends its Firefox profile's own User-Agent and Accept-Language; `BROWSER_FETCH_DEBUG=1` prints why.
One render or login at a time uses the profile; another waits a bounded time, then fails.
The render closes the browser before its deadline, which writes the cookies Firefox holds in memory to the jar for the next fetch.
A jar read or write waits only `JAR_LOCK_SECONDS` of [browser.py](../../../packages/browser-fetch/browser_fetch/browser.py) for a render or login.
Past that the fetch goes on without the jar; a write that missed is tried again with the next response and by a render, and what none took is reported.
Each warning is a `browser-fetch: warning:` line on stderr and an entry of the record's `warnings`.
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
It preapproves no site, so every page, Markdown included, goes to haiku with the quote rules the built-in gives sites it does not preapprove.
A same-host redirect is followed even out of a documentation path the built-in preapproves.
It makes no domain safety check against `api.anthropic.com`.
It fetches `localhost` and other hostnames without a dot, which the built-in refuses, and every address like any other.
An http URL is requested over http, where the built-in upgrades every URL to https, and a same-host redirect from http to https is followed.
It answers the call before Claude Code's permission check, so WebFetch permission rules, the auto-mode classifier and PreToolUse hooks do not apply to it.
A failed fetch puts its reason in the status line and refuses the call with the built-in tool's failure text, never falling back to it.
Each of `browser-fetch`'s warnings follows the result, or that refusal, as a `[WebFetch warning: …]` note for the model.

## The cookie jar is unusable

`browser-fetch` exits 3 when Camoufox's `cookies.sqlite` has another schema version than 17, or cannot be read or written.
A Camoufox release on a newer Firefox can move the version; the package check pins it against the packaged Camoufox.
Start over with an empty profile as [Camoufox's state](#camoufoxs-state) shows, then fetch again.

## A site still answers with a challenge

The site rejects curl-impersonate's Firefox profile, and Camoufox did not clear its challenge within the wait either.
Challenges that want a click are not answered.

## The browser fails

`browser-fetch` exits 5 with the reason, such as another fetch or a login holding the profile past the wait, or a login without a local X display.
A page curl fetched whole is returned as curl got it when only its script-built look sent it to the browser, with a warning that names the browser's failure.
Set `BROWSER_FETCH_DEBUG=1` to print the stack of an unexpected error, which exits 7.
