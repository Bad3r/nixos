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
The `mode` argument has no Kagi counterpart and changes nothing.
A failed search refuses the call with the reason; it never falls back to the built-in search.

## Kagi rejected LibreWolf's session

The session expired or LibreWolf signed out.
Sign in to `kagi.com` in LibreWolf again, then rerun the search.

## Kagi answered with a bot challenge

Kagi sends requests without a valid session to its Cloudflare challenge.
Sign in to `kagi.com` in LibreWolf again; a session cookie skips the challenge.

## No search results kagi-search recognizes

Kagi changed the markup of `kagi.com/html/search`.
The parser lives in [page.py](../../../packages/kagi-search/kagi_search/page.py), and its fixtures in [test_page.py](../../../packages/kagi-search/tests/test_page.py).
