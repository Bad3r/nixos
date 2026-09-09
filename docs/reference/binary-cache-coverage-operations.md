# Binary Cache Coverage Operations

## Operator setup

The operator setup is complete:

1. The public Cachix cache `bad3r-nixos` exists under the account that
   owns `nix-logseq-git-flake`.
2. A Cachix auth token with write access to the cache is stored as the
   `CACHIX_AUTH_TOKEN` repository secret
   (`gh secret set CACHIX_AUTH_TOKEN --repo Bad3r/nixos`; rotate the same
   way). Whenever the secret is absent, the workflow builds cache-roots
   and emits a warning instead of pushing.
3. Common hosts trust the cache: `modules/hosts/common/nix-substituters.nix`
   carries `https://bad3r-nixos.cachix.org` and its public key.
4. `build.sh` carries the same URL and key in `BOOTSTRAP_SUBSTITUTERS` and
   `BOOTSTRAP_TRUSTED_KEYS`. That path writes `substituters =`, replacing the
   list rather than extending it, so a cache missing there is unreachable for
   the bootstrap build that runs before the host module is active: exactly the
   fresh machine that has nothing in its store. The
   `bootstrap-substituter-parity` check keeps the two in step: it parses both
   arrays out of `build.sh` and aborts evaluation when a substituter or key any
   registered host trusts is missing from them. Every host is covered, not just
   the primary, because `build.sh` bootstraps whichever host it runs on.
   `extra-substituters` counts the
   same as `substituters`, because the bootstrap write replaces the whole list
   and a cache wired the way `modules/apps/doom-emacs.nix` and
   `modules/apps/logseq.nix` wire theirs is just as unreachable. The comparison
   is directional, so the region mirrors for other networks do not trip it, and
   an array that is missing, unclosed, or empty fails rather than comparing
   nothing.

Verify the publisher after a merge by checking that `cache-push.yml` reaches
the "Push closure to Cachix" step successfully and that
`https://bad3r-nixos.cachix.org/nix-cache-info` responds anonymously.

## Coverage gaps

The publisher works; its input list does not keep itself honest. A CI service
that enumerates flake outputs on its own needs no such list, so what the
retired one would have contributed is that enumeration, and reproducing it is
the remaining work. Four gaps carry it.

1. The detector and the publisher do not talk to each other
   (https://github.com/Bad3r/nixos/issues/422). `cache-roots.nix` publishes a
   hand-maintained name list, while `scripts/cache-coverage-allowlist.txt`
   suppresses diverged local builds that list never publishes
   (age-plugin-fido2prf, librepods, snixembed, subjack, cewl, normcap, zap,
   nixos-icons, nixos-option). The two sets are disjoint by
   hand, not by construction: one file accepts rebuilding a package forever
   and the other decides what to publish, with nothing reconciling them. So a
   new custom package stays uncached until somebody reads a build log, and a
   name added to the publisher leaves behind a dead glob that absorbs the next
   regression on it. The allowlist's other entries are permanent dispositions
   `docs/reference/cache-coverage.md` accepts rather than reconciliation debt:
   the configuration wrappers are too cheap to be worth the CI time. The
   RAR-enabled p7zip left the file for the opposite reason: `cache-roots.nix`
   publishes it as `p7zip-rar` now, so its glob was deleted in the same change.
2. ~~Only the primary host sources entries~~ (closed,
   https://github.com/Bad3r/nixos/issues/423). `cache-roots.nix` iterates every
   registered host that builds for the current system and keys links
   `<host>/<package>/<output>`, so a sibling host's apps and its distinct
   closures are published too. This pulls each registered host's selected
   nvidia-x11 closure into the cache; before the change, evaluating a sibling
   host fetched its driver and then published nothing for it.
3. Nothing gates coverage in CI
   (https://github.com/Bad3r/nixos/issues/424). `scripts/cache-coverage.sh`
   is reachable only through `build.sh --cache-coverage` and `nix run`, and
   `check.yml` never invokes it, so allowlist drift and new divergences
   surface during a host switch rather than during review.
4. Multi-output entries are published in part
   (https://github.com/Bad3r/nixos/issues/426). `cachix push` uploads the
   runtime closure of the `linkFarm`, so only an entry's default output reaches
   the cache, while the detector counts a derivation as substitutable only when
   every output is served. proton-vpn (`out`, `dist`) and nemo (`out`, `dev`,
   `man`) report as local builds although the output hosts install
   answers 200 from `bad3r-nixos.cachix.org` and the other answers 404
   everywhere. Neither name belongs in the allowlist: a glob there would
   restore coverage on paper and suppress the next real divergence on that
   package.

The issue's phase 2 is now partly inverted: the unfree group is served, but the
private or authenticated cache it was meant to be served from does not exist
yet. Provisioning a Cachix read token to hosts through sops is what would close
the gap between the posture under "License posture" and the mechanism.

Before-and-after measurement of switch time belongs to the detector, not to a
manual log diff. Once gap 3 lands, the report's own class counts are the
metric.
