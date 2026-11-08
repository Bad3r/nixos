# kagi-search

`kagi-search` searches Kagi as the account signed in to [browser-fetch](../browser-fetch/README.md)'s Camoufox profile ([module](../../../modules/apps/kagi-search.nix), [package](../../../packages/kagi-search/default.nix)).
It runs on browser-fetch's own Python modules, taken from browser-fetch's package.
It reads the `kagi_session` cookie from browser-fetch's [cookie jar](../browser-fetch/README.md#the-cookie-jar), the `cookies.sqlite` of the profile under `$XDG_STATE_HOME/browser-fetch/`.

## Sign in

Precondition: a local X display in `DISPLAY`.

1. Open Kagi in browser-fetch's Camoufox:

   ```sh
   browser-fetch login https://kagi.com
   ```

2. Sign in to Kagi in the window, then close every window.

3. Search from a shell:

   ```sh
   kagi-search nixos flakes
   ```

Verify that the output lists numbered hits with URLs.

## Searches

Each search is one request through browser-fetch's curl-impersonate, with the Camoufox fingerprint's headers and browser-fetch's [proxy rules](../browser-fetch/README.md#proxies); Camoufox never starts.
The jar is read and written under browser-fetch's profile lock, and every cookie change in Kagi's response is written back to it as a fetch's is.
No redirect is followed: one to Kagi's sign-in page means the session is gone, one to its challenge is a bot challenge, and any other fails the search with its target.
While a [login](../browser-fetch/README.md#sign-in-to-a-site) holds the profile, the jar read gives up after browser-fetch's short wait, so the search finds no session.

## Claude Code WebSearch

The `kagi-websearch` plugin of the `nixos-local` marketplace answers every `WebSearch` call with `kagi-search` ([plugin](../../../modules/agents/claude-code/marketplace/kagi-websearch/hooks/register.ts)).
Its record matches the built-in tool's: one link list of titles and URLs, then a summary the session's model writes from the hits.
It runs `/run/current-system/sw/bin/kagi-search`, so each switch moves it to the current build.
Allowed domains narrow the Kagi query to `site:` (an `OR` group for several) and blocked ones add `-site:`; the hits are filtered by domain again afterwards.
A `standard` search returns the plugin's `maxResults` hits (10 by default); an `extended` one returns every hit on Kagi's first page, about 25 to 35.
A failed search answers with the built-in tool's own error record (`Web search error: unavailable`) and shows the reason in the status line; it never falls back to the built-in search.
`kagi-search` appends the reason behind every failed search, with a traceback for unexpected errors, to `~/.local/state/kagi-search/kagi-search.log`.
browser-fetch's warnings for a search, such as a cookie change the jar did not take, go to the same log.
Each Home Manager activation checks that the installed Claude Code still carries the strings the plugin copies from the built-in search and passes the plugin's tests ([check](../../../modules/agents/claude-code/_websearch-check.nix)).
A mismatch prints a warning, writes `~/.local/state/kagi-search/claude-code-check.txt`, and keeps a notice in the status line until a later activation passes.

## Codex search

Codex runs its own `web.run` tool with the `standalone_web_search` feature, and `kagi-search-webrun` answers it in place of OpenAI's search service ([feature flags](../../../modules/agents/codex/_features.nix)).
The llm-agents Codex package carries the patch that sends each call to the program named by `CODEX_WEB_RUN_COMMAND`, `/run/current-system/sw/bin/kagi-search-webrun`.
Search uses Kagi; `open`, `click`, and `find` fetch pages directly, loopback and private addresses included.
Codex sees only the service's own wording, failures included; the real reasons go to `~/.local/state/kagi-search/web-run.log`.
Reference ids such as `turn0search0` persist per Codex session under `~/.local/state/kagi-search/web-run/`.
The `codex/web-run-contract` flake check fails a Codex update that drops the patch, renames the feature, or changes the tool's description or search schema ([checks](../../../modules/agents/codex/checks.nix)).

## No Kagi session in browser-fetch's profile

`kagi-search` exits 3 when the jar holds no `kagi_session` for `kagi.com`, cannot be read, or stays locked by a login past the wait.
Close any open login window, then sign in as [Sign in](#sign-in) shows.

## Kagi rejected the session

The session expired or was signed out, and Kagi redirected to its sign-in page; `kagi-search` exits 4.
Sign in as [Sign in](#sign-in) shows, then rerun the search.

## Kagi answered with a bot challenge

Kagi sends requests without a valid session to its Cloudflare challenge; `kagi-search` exits 5.
Sign in as [Sign in](#sign-in) shows; a session cookie skips the challenge.

## No search results kagi-search recognizes

Kagi changed the markup of `kagi.com/html/search`.
The parser lives in [page.py](../../../packages/kagi-search/kagi_search/page.py), and its fixtures in [test_page.py](../../../packages/kagi-search/tests/test_page.py).
