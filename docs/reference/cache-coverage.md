# Cache Coverage Report

`scripts/cache-coverage.sh` reports, per host, which derivations of the
system closure would compile locally on a fresh machine even though the
raw nixpkgs input publishes a substitutable equivalent. It catches
configuration changes that silently break binary-cache coverage: overlay
edits, `overrideAttrs` on a widely consumed library, or a stylix target
that patches a base package (issue
`https://github.com/Bad3r/nixos/issues/381`; the motivating regression was
the stylix gtksourceview overlay removed in PR 380). Evaluation and HTTP
narinfo probes only: the script never builds anything.

## Manual Use

Report every host, fail on any unexpected divergence:

```sh
scripts/cache-coverage.sh
```

One host, through the flake wrapper (use `path:.` in linked worktrees):

```sh
nix run path:.#cache-coverage -- --host system76
```

Gate a deploy on the report:

```sh
./build.sh --cache-coverage
```

## Method

1. The host toplevel derivation is instantiated
   (`nix path-info --derivation`, evaluation only).
2. The derivation graph is walked top down. Every output path of every
   visited derivation is probed over HTTP against the host probe bases:
   its `nix.settings.substituters` and `nix.settings.extra-substituters`
   (app modules such as doom-emacs and logseq append caches through
   `extra-substituters`) plus `https://cache.nixos.org`. A derivation
   whose outputs are all served terminates its branch: binary caches are
   closed under references, so everything below it substitutes too. An
   unserved derivation would build locally on a fresh machine; the walk
   descends into its `inputDrvs`.
3. For every would-build derivation, the raw nixpkgs input from
   `flake.lock` (no overlays, `config.allowUnfree = true`, matching the
   hydra and nixpkgs-unfree cache population) is evaluated once, batched,
   to find the stock outPath of the matching attribute. A candidate
   attribute matches only when its stock version equals the local version
   or its stock derivation name equals the local one; name prefixes of
   unrelated packages never count.
4. Each stock outPath is probed against the same host probe bases
   (substituters, extra-substituters, and `cache.nixos.org`). Unfree stock
   paths are published only to `nixpkgs-unfree.cachix.org`, so probing that
   whole set, not `cache.nixos.org` alone, is what catches unfree
   divergences. A derivation that diverged from a served stock path is
   unexpected-local: the divergence, not cache lag, causes the local build.

Unlike `nix build --dry-run`, the walk ignores local store validity, so
leftover store paths from earlier generations cannot mask a regression.
Probes go straight to the caches over HTTP, so the daemon narinfo negative
cache (`narinfo-cache-negative-ttl`) cannot serve stale answers.

## Classes

| Class             | Meaning                                                                                     |
| ----------------- | ------------------------------------------------------------------------------------------- |
| unexpected-local  | Diverged from a stock path that a host probe base serves (FAIL)                             |
| allowlisted       | unexpected-local, accepted in the allowlist                                                 |
| diverged-uncached | Diverged, but the stock path is not served either                                           |
| inconclusive      | Stock probe not decisive (not 200 or 404), so the served status is unknown (FAIL)           |
| uncached-stock    | Identical to stock, not yet published (hydra lag)                                           |
| fetch             | Fixed-output derivation, a source download                                                  |
| local-only        | No stock counterpart: config texts, units, wrappers, custom packages, foreign-system builds |

Only unexpected-local entries count against the thresholds. Each entry
names the actual path, the stock path and attribute, the stock nar size,
and repo files mentioning the package as a provenance hint.

## Thresholds And Allowlist

The check exits nonzero when unexpected-local entries exceed `--max-count`
(default 0) or their total stock nar size exceeds `--max-size` (default
0). Accepted divergences belong in `scripts/cache-coverage-allowlist.txt`:
one glob per line, matched against the derivation name and pname, with a
comment recording the reason. Both files are repo-tracked so changes go
through review.

## Caveats

- The stock comparison resolves attributes by pname, by name minus
  version, and by pname plus version major (`gtksourceview4`). An override
  that also changes the version escapes the unexpected-local class; the
  rebuild is then inherent to the pin, and the entry surfaces as
  local-only instead.
- The root `nixpkgs` input must be a locked `github` flake input; other
  input types abort with an error.
- Derivations whose `system` differs from the host toplevel (the i686
  support libraries pulled in by nvidia and steam 32-bit userspace) are
  never stock-matched: the stock baseline is evaluated for the host system
  only, and those rebuilds are inherent to hydra's thin i686 coverage, not
  divergences. They surface under local-only.
- All-outputs probing: a derivation counts as substitutable only when
  every output is served by some probe base.
- Only `200` (served) and `404` (absent) are decisive probe results;
  anything else (`000` from an unreachable cache, or `429`/`403`/`503` from
  a rate-limiting or overloaded cachix/S3 base) is non-definitive and read
  as unserved. For an output path this is only a non-fatal warning: the path
  is usually already served by a definitive `200` from another base, and
  even a genuinely local path fails closed (it can only over-report a build,
  never hide one), so a single flaky cache does not disable the gate. A
  non-decisive result that leaves a matched stock path's served status
  undecided is fatal: that divergence could be a hidden unexpected-local, so
  the run exits 2 with no OK/FAIL verdict (surfaced as the `inconclusive`
  class). Re-run once the caches are healthy.
- Runtime is dominated by evaluation (about one minute per host on a warm
  eval cache) plus one narinfo probe per output path of the unserved
  subgraph and its served frontier. Probe results are shared across
  hosts within a run.
