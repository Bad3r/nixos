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

This file documents the detector. The publisher that puts custom derivations
on a cache is `modules/meta/cache-roots.nix` plus
`.github/workflows/cache-push.yml`, documented in
`docs/reference/binary-cache-coverage.md`. The two are halves of one
mechanism: what this report classifies as a local build is the candidate set
the publisher should cover.

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

Every form above resolves its reference the way `build.sh` does: `path:` in a
linked worktree, where Lix cannot fetch a clean checkout as a `git+file` flake,
or under `--allow-dirty`, which is what makes untracked files visible at all;
the bare ref everywhere else. That keeps the report on the tree the build would
build.

A `path:` ref dumps the tree unfiltered into the world-readable store rather
than fetching it through git, so those two cases run the secrets guard in
`scripts/lib/secrets-guard.sh` first and abort when an untracked file matching
the `.gitignore` secrets block would be copied, in the tree or in a submodule
working tree. The whole untracked set is scanned, ignored or not, because that
is what `path:` adds over the `git+file` fetcher, which carries only the tracked
tree. An untracked directory that is itself a git repository aborts on its name
alone: `ls-files` reports that boundary and never opens it, so nothing inside
reaches the block, while `path:` copies the directory whole. Pass
`--allow-secret-copy` (`ALLOW_SECRET_COPY=1`) to report
anyway. A primary checkout on the default path evaluates the bare ref, so it
copies nothing and has nothing to override.

A guard hit aborts, and so does a guard that cannot run: any of `git`, `grep`,
`awk`, `mktemp` and `rm` missing from `PATH`, a `mktemp` present that fails
anyway on a read-only `TMPDIR` or a full filesystem, a hit list the guard cannot
write or read back for the same reasons, a `.gitignore` tracked but absent or
present and unreadable, a secrets block that no longer yields its patterns, and
a directory carrying a `.git` marker git will not open as a repository. Both
exit 2, naming
which of the two they were. A missing `git` is in that list rather than in the
skip below it, because the reference is chosen without consulting git:
`--allow-dirty` selects `path:` from the flag alone, so a tree whose ignore set
could not be read is still copied. The unopenable `.git` is there for the same
reason, and it is what separates the two answers `git rev-parse` gives at exit
128: a linked worktree outliving the gitdir its `.git` file names still selects
`path:` off that file, so reading it as a foreign directory would skip the scan
on the one reference that makes the copy. Dubious ownership arrives the same way
on a tree git reads perfectly well, which is why the abort offers
`safe.directory` beside repairing the repository. Everything else the guard has
to say is a stderr notice that
aborts nothing: a
`path:` reference copies every untracked path whatever its ignore status, and in
a primary checkout under `--allow-dirty` the whole `.git` directory with it. The
notice names which of the two conditions selected the reference, since one is
asked for and the other comes with the worktree. `build.sh` says the same
through `announce_path_ref`, off the same predicate in
`scripts/lib/flake-ref.sh`: a report that resolved a different reference than
the build would measure a different tree.

The guard covers the reference this script evaluates, not the one that delivered
the script. `nix run path:.#cache-coverage` is therefore unguarded by
construction: Lix copies the tree unfiltered while resolving that installable,
before the wrapper's first statement, and in a primary checkout the script then
keeps the bare ref and does not scan at all. Reproduced with a probe `.env` in a
worktree whose `git status --short` was empty: `nix flake metadata path:.`
reports a store source containing it at `-r--r--r-- root root`. Reach for
`scripts/cache-coverage.sh` from the checkout, or `./build.sh --cache-coverage`,
whenever the sweeps above report anything.

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

Allowlisting and caching are mutually exclusive dispositions, not a
preference. A glob here declares that the divergence is a permanent local
build; a name in `cache-roots.nix` declares that CI publishes it. Choose the
allowlist only when the package cannot be cached: `allowSubstitutes = false`
on the expensive derivation (tor-browser, mullvad-browser), or a wrapper cheap
enough that publishing it costs more CI time than it saves. A license is not a
reason; `cache-roots.nix` publishes unfree packages too, so the RAR-enabled
p7zip belongs there, and its glob left this file in the same change.
Everything else belongs in `cache-roots.nix`, and adding it there
means deleting the glob here in the same change. That is enforced rather than
left to memory: the `cache-roots-allowlist-disjoint` flake check in
`modules/meta/cache-roots.nix` reads this file and aborts evaluation naming the
offender. It matches each published entry on the derivation `name` and `pname`,
which are the strings this report matches globs against, so a version-anchored
glob such as `proton-vpn-[0-9]*` is caught the same as `proton-vpn*`. The
entry's package name is checked as well: a glob spelled that way suppresses
nothing here, since that name never reaches this report, but it declares the
same disposition the rule forbids. The host-qualified `linkFarm` key
(`<host>/<package>/<output>`) is not checked, because no glob is written that
way. Its
domain is the published entries, not the closure
members the push also serves, because that closure does not exist at evaluation
time; extending the check to them is
https://github.com/Bad3r/nixos/issues/428. It throws
during evaluation, so `nix flake check --no-build` catches it without building
anything. `check.yml` runs on `pull_request` so that this fires at review time:
the guard is a throw inside `perSystem.checks`, which enforces nothing unless
something forces `checks.<system>`, and that workflow's "Check flake" step is
what does. Entries currently allowlisted that fail the disposition test, rather
than the overlap test, are tracked in
https://github.com/Bad3r/nixos/issues/422.

Nothing runs this script in CI yet, so drift surfaces during a host switch
rather than during review; `check.yml` coverage is tracked in
https://github.com/Bad3r/nixos/issues/424.

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
  every output is served by some probe base. `cache-roots.nix` publishes only
  each entry's default output, so a multi-output entry reports as a local build
  even when the output hosts install is served
  (https://github.com/Bad3r/nixos/issues/426).
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
