# kagi-search

`kagi-search` searches Kagi as the signed-in account of LibreWolf's default profile ([module](../../../modules/apps/kagi-search.nix), [package](../../../packages/kagi-search/default.nix)).
It reads the `kagi_session` cookie from a private copy of the profile's cookie database, since LibreWolf holds the live one locked.
The Gecko policy keeps `kagi.com` cookies through the shutdown wipe ([policy](../../../modules/browsers/_gecko-policies.nix)).

## Sign in

Precondition: LibreWolf runs its default profile.

1. Open `https://kagi.com` in LibreWolf and sign in.

2. Search from a shell:

   ```sh
   kagi-search nixos flakes
   ```

Verify that the output lists numbered hits with URLs.

## Claude Code WebSearch

The `kagi-websearch` plugin of the `nixos-local` marketplace answers every `WebSearch` call with `kagi-search` ([plugin](../../../modules/agents/claude-code/marketplace/kagi-websearch/hooks/register.ts)).
Its record matches the built-in tool's: one link list of titles and URLs, then a summary the session's model writes from the hits.
It runs `/run/current-system/sw/bin/kagi-search`, so each switch moves it to the current build.
Allowed domains narrow the Kagi query to `site:` (an `OR` group for several) and blocked ones add `-site:`; the hits are filtered by domain again afterwards.
A `standard` search returns the plugin's `maxResults` hits (10 by default); an `extended` one returns every hit on Kagi's first page, about 25 to 35.
A failed search answers with the built-in tool's own error record (`Web search error: unavailable`) and shows the reason in the status line; it never falls back to the built-in search.
`kagi-search` appends the reason behind every failed search, with a traceback for unexpected errors, to `~/.local/state/kagi-search/kagi-search.log`.
Each Home Manager activation checks that the installed Claude Code still carries the strings the plugin copies from the built-in search and passes the plugin's tests ([check](../../../modules/agents/claude-code/_websearch-check.nix)).
A mismatch prints a warning, writes `~/.local/state/kagi-search/claude-code-check.txt`, and keeps a notice in the status line until a later activation passes.

## Codex search

Codex runs its own `web.run` tool with the `standalone_web_search` feature, and `kagi-search-webrun` answers it in place of OpenAI's search service ([settings](../../../modules/agents/codex/_settings.nix)).
The llm-agents Codex package carries the patch that sends each call to the program named by `CODEX_WEB_RUN_COMMAND`.
Search uses Kagi; `open`, `click`, and `find` fetch pages locally and refuse loopback and private addresses.
Codex sees only the service's own wording, failures included; the real reasons go to `~/.local/state/kagi-search/web-run.log`.
Reference ids such as `turn0search0` persist per Codex session under `~/.local/state/kagi-search/web-run/`.
The `codex/web-run-contract` flake check fails a Codex update that drops the patch, renames the feature, or changes the tool's description or search schema ([checks](../../../modules/agents/codex/checks.nix)).

## Kagi rejected LibreWolf's session

The session expired or LibreWolf signed out.
Sign in to `kagi.com` in LibreWolf again, then rerun the search.

## Kagi answered with a bot challenge

Kagi sends requests without a valid session to its Cloudflare challenge.
Sign in to `kagi.com` in LibreWolf again; a session cookie skips the challenge.

## No search results kagi-search recognizes

Kagi changed the markup of `kagi.com/html/search`.
The parser lives in [page.py](../../../packages/kagi-search/kagi_search/page.py), and its fixtures in [test_page.py](../../../packages/kagi-search/tests/test_page.py).
