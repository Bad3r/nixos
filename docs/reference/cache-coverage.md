# Cache Coverage Report

`scripts/cache-coverage.sh` reports, per host, the closure derivations that would build locally on a fresh machine although the raw nixpkgs input publishes a substitutable equivalent.
It catches changes that silently break binary-cache coverage: overlay edits, `overrideAttrs` on a widely consumed library, or a stylix target that patches a base package.
It only evaluates and probes narinfo over HTTP, and never builds anything.
The publisher in [Binary Cache Coverage](binary-cache-coverage.md) is the other half: a derivation reported here as a local build is a candidate for it to cover.

## Manual Use

Report every host, fail on any unexpected divergence:

```sh
scripts/cache-coverage.sh
```

One host, through the flake wrapper (use `path:.` in linked worktrees):

```sh
nix run path:.#cache-coverage -- --host songbird
```

Gate a deploy on the report:

```sh
./build.sh --cache-coverage
```

Every form resolves its reference the way `build.sh` does, through `scripts/lib/flake-ref.sh`, so the report measures the tree the build would build.
That reference is `path:` in a linked worktree or under `--allow-dirty`, and the bare reference everywhere else.
A `path:` reference copies every untracked path into the world-readable store, plus the whole `.git` directory in a primary checkout.
The script says so on stderr, naming the condition that selected the reference.
Before evaluating such a reference, the script runs the [secrets guard](secrets-guard.md) and exits 2 when the guard flags a path or cannot run.

## Method

1. The host toplevel derivation is instantiated with `nix path-info --derivation`, evaluation only.
2. The derivation graph is walked top down, and every output path of each visited derivation is probed over HTTP against the host probe bases.
   The bases are the host's `nix.settings.substituters` and `nix.settings.extra-substituters`, plus `https://cache.nixos.org`.
3. A derivation whose outputs are all served ends its branch, since binary caches are closed under references.
   An unserved one would build locally on a fresh machine, so the walk descends into its `inputDrvs`.
4. For every would-build derivation, the raw nixpkgs input from `flake.lock` is evaluated once, batched, to find the stock outPath of the matching attribute.
   That input carries no overlays and sets `config.allowUnfree = true`, matching how hydra and nixpkgs-unfree populate their caches.
5. A candidate attribute matches only when its stock version or stock derivation name equals the local one; name prefixes of unrelated packages never count.
6. Each stock outPath is probed against the same bases.
   Unfree stock paths are published only to `nixpkgs-unfree.cachix.org`, so probing the whole set is what catches unfree divergences.
7. A derivation that diverged from a served stock path is unexpected-local: the divergence, not cache lag, causes the local build.

The walk ignores local store validity, unlike `nix build --dry-run`, so leftover store paths from earlier generations cannot mask a regression.
Probes go straight to the caches over HTTP, so the daemon's narinfo negative cache cannot serve stale answers.

## Classes

| Class             | Meaning                                     |
| ----------------- | ------------------------------------------- |
| unexpected-local  | Diverged from a served stock path, FAIL     |
| allowlisted       | Unexpected-local, in the allowlist          |
| diverged-uncached | Diverged, stock path unserved as well       |
| inconclusive      | Stock probe not decisive, FAIL              |
| uncached-stock    | Identical to stock, unpublished (hydra lag) |
| fetch             | Fixed-output source download                |
| local-only        | No stock counterpart                        |

Only unexpected-local entries count against the thresholds.
Each entry names the actual path, the stock path and attribute, the stock nar size, and the repo files that mention the package.
Local-only covers config texts, units, wrappers, custom packages, and foreign-system builds.

## Thresholds And Allowlist

The run exits nonzero when unexpected-local entries exceed `--max-count` or their total stock nar size exceeds `--max-size`; both default to failing on any entry.
Accepted divergences go in `scripts/cache-coverage-allowlist.txt`, one glob per line with a comment recording the reason, matched against the derivation name and pname.
A glob there declares a permanent local build, for a package that cannot be cached or costs more CI time to publish than it saves.
[Extending Binary Cache Coverage](binary-cache-coverage-extension.md) covers the packages that belong in `modules/meta/cache-roots.nix` instead, and the `cache-roots-allowlist-disjoint` check that keeps the two lists apart.

## Caveats

- The stock comparison resolves attributes by pname, by name minus version, and by pname plus version major (`gtksourceview4`).
  An override that also changes the version surfaces as local-only, since the rebuild is then inherent to the pin.
- The root `nixpkgs` input must be a locked `github` flake input; other input types abort with an error.
- Derivations whose `system` differs from the host toplevel, such as the i686 libraries nvidia and steam pull in, surface as local-only.
  The stock baseline is evaluated for the host system only, so those rebuilds follow from hydra's thin i686 coverage.
- A derivation counts as substitutable only when every output is served by some probe base, so a partly published multi-output cache root reports as a local build.
- Only `200` and `404` are decisive probe results, and anything else reads as unserved.
  That covers `000` from an unreachable cache and `429`, `403`, or `503` from a rate-limiting or overloaded one.
- A non-decisive result for an output path is a warning, since it can only over-report a build, so one flaky cache does not disable the gate.
- A non-decisive result that leaves a matched stock path's status open is fatal, since it could hide an unexpected-local.
  The run exits 2 with no verdict, under the `inconclusive` class; re-run once the caches are healthy.
- Runtime is mostly evaluation plus one narinfo probe per output path of the unserved subgraph and its served frontier.
  Probe results are shared across hosts within a run.
