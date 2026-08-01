# Binary Cache Coverage

Operator surface for serving custom derivations from a binary cache instead
of rebuilding them on every host switch (issue
https://github.com/Bad3r/nixos/issues/382). Cache topology and substituter
wiring live in `modules/hosts/common/nix-substituters.nix`; the build surface
lives in `modules/meta/cache-roots.nix`; the CI publisher is
`.github/workflows/cache-push.yml`.

This file documents the publisher. The detector that reports which closure
paths still build locally is `scripts/cache-coverage.sh`, documented in
`docs/reference/cache-coverage.md`. The two are halves of one mechanism:
the detector names what is uncovered, the publisher covers it.

## Garnix (retired)

Garnix shut down on 2026-07-15, deleted every stored build artifact, and open
sourced its CI with no public successor instance, leaving `cache.garnix.io` to
answer HTTP 502. It never covered this repository in any case: the GitHub app
was never installed, and `self.submodules = true` in `flake.nix` makes any
git-based fetch of the flake pull the private `secrets/` submodule that
external CI cannot read. The substituter and its trusted key are gone from
`modules/hosts/common/nix-substituters.nix` and the `build.sh` bootstrap
lists. Do not re-add them, and do not stand up a self-hosted instance: what it
would have contributed here is output enumeration, not hosting, and the
"Coverage gaps" section below tracks that.

## Mechanism

CI in this repository builds `packages.<system>.cache-roots` and pushes the
closure to the public Cachix cache `bad3r-nixos`, which hosts trust as a
substituter. The `nix-logseq-git-flake` input already used this shape, so the
trust and wiring pattern was proven in this configuration before being
generalized.

`cache-push.yml` triggers on `workflow_dispatch` and on pushes to `main`
touching `flake.lock`, `modules/**`, or `packages/**`. Lock freshness rides on
`update-flake.yml`, which opens a daily `automated/flake-update` pull request;
merging it touches `flake.lock` and fires a push. A cache hit requires the
exact derivation a consumer evaluates, so tracking the merged lock is what
makes the cache usable: it holds derivations for the revision hosts evaluate
against.

Alternatives were considered and rejected. Attic and Harmonia reintroduce a
server to operate, which is the dependency this design removed. FlakeHub Cache
is paid and pairs with Determinate Nix while hosts here run Lix. Cachix is
already trusted, already wired, and already publishing, so the remaining work
is coverage, not a change of service.

## Audit findings (2026-07-17)

Build-log profiling under `~/.local/state/nixos-build/` after PR
https://github.com/Bad3r/nixos/pull/380 still showed on the order of 170
derivations built locally per full system build. Three groups remain:

- custom flake packages and overlay-modified packages (pnpm and npm
  dependency trees, patched browser runtimes, pentest tooling)
- unfree binary repacks (vscode, webex, kiro, veracrypt, ventoy, and
  others)
- host-specific config and text derivations (cheap, acceptable)

## Build surface

`packages.<system>.cache-roots` is a `linkFarm` over an explicit allowlist
of free, redistribution-safe packages:

- Host-sourced entries come from the primary host's package set so custom
  overlays (firefoxpwa policy injection, john patches) and nixpkgs config
  produce exactly the derivations a host switch evaluates. Every entry's
  app must be enabled on that host: overlays are gated on
  `programs.<name>.extended.enable`, and a disabled app resolves to the
  stock nixpkgs attr that no host consumes (which is why wfuzz is not
  listed).
  `nix build --dry-run "path:.#cache-roots"` on a host that has switched
  recently should report no unexpected package rebuilds; that is the
  derivation-parity check.
- Option-sourced entries (`hostFinalPackagePaths`) read the owning module's
  read-only resolved-package option on the primary host, for modules that
  install a configured variant the bare package-set attribute never produces
  (nemo-with-extensions, via `programs.nemo.extended.finalPackage`). The
  enable invariant holds here through the option's shape: `finalPackage` is
  declared with no default and assigned inside `config = lib.mkIf cfg.enable`,
  so a disabled module leaves it undefined rather than resolving to a closure
  no host installs. `cache-roots.nix` reads the sibling `enable` as well, so
  the failure names the entry, the option path, and the host instead of
  surfacing a bare "was accessed but has no value defined".
- perSystem-sourced entries (codeburn, restringer) are consumed through
  the devshell surface and build from the perSystem nixpkgs instance.
- Input-sourced entries (context7-mcp, codex) come from the flake input the
  consuming module resolves them from, because the host package set can
  carry a same-named but different derivation.

The allowlist is explicit because `cachix push` publishes the full runtime
closure to a public cache. Every entry's closure must be redistributable. An
`assertFree` guard aborts evaluation for any entry whose `meta.license` is
missing or is neither free nor redistributable, so a license-violating addition
fails `nix flake check` (the check `modules/package-checks.nix` mirrors from
this output) instead of reaching the cache. The guard reads the entry's own
`meta.license` only; it does not walk the closure, so a wrapper that pulls in
separately licensed packages still needs the manual check under
"Extending the allowlist".

## Classification (2026-07-17 build logs)

License fields read from each package's `meta.license` on the surface that
entry is sourced from, per the rule under "Extending the allowlist": the
primary host's package set for host-sourced entries,
`programs.nemo.extended.finalPackage` for nemo-with-extensions, the owning
flake input for context7-mcp and codex, and `self'.packages` for codeburn
and restringer.

Cached via cache-roots (free, redistributable):

| Package              | License            |
| -------------------- | ------------------ |
| codeburn             | MIT                |
| codex                | Apache-2.0         |
| context7-mcp         | MIT                |
| electron-mail        | GPL-3.0            |
| firefoxpwa           | MPL-2.0            |
| john                 | GPL-2.0-or-later   |
| nemo-with-extensions | GPL-2.0 + LGPL-2.0 |
| planify              | GPL-3.0-or-later   |
| proton-vpn           | GPL-3.0-only       |
| restringer           | MIT                |
| tweakcc              | MIT                |
| upscayl              | AGPL-3.0-or-later  |
| wappalyzer-next      | GPL-3.0-only       |

context7-mcp is sourced from the `mcp-servers-nix` input, matching the
consumer in `modules/agents/mcp.nix`; the host package set carries a
same-named but different derivation no consumer runs. nemo-with-extensions
is sourced from `programs.nemo.extended.finalPackage` for the same reason:
`modules/apps/nemo.nix` re-wraps nemo with an explicit extension list, so
the bare `pkgs.nemo-with-extensions` attribute is a derivation no host
installs, and its closure omits nemo-preview and nemo-seahorse. For entries built
through `buildFHSEnv` or wrapper derivations (electron-mail, upscayl,
nemo-with-extensions), the outer wrapper sets `allowSubstitutes = false`
and always rebuilds locally; that is trivial assembly work, and the heavy
dependency closure underneath substitutes normally.

Intentionally local, unfree with redistribution not permitted or unclear
(publishing these to a public cache would violate their licenses):

| Package       | License note                       |
| ------------- | ---------------------------------- |
| charles       | unfree                             |
| discord       | unfree                             |
| dropbox       | unfree                             |
| google-chrome | unfree                             |
| kiro          | Amazon Software License            |
| veracrypt     | TrueCrypt-derived, unfree          |
| ventoy        | unfree (vendored blobs)            |
| vscode        | unfree (Microsoft product license) |
| webex         | unfree                             |

Unfree but marked redistributable in nixpkgs; candidates for a later
operator decision, kept local until then:

| Package     | License note                               |
| ----------- | ------------------------------------------ |
| firefox-bin | Firefox trademark license, redistributable |
| nvidia-x11  | unfreeRedistributable                      |
| steam       | unfreeRedistributable                      |

Residual local builds accepted with reasons:

- tor-browser and mullvad-browser: free and redistributable, but nixpkgs
  sets `allowSubstitutes = false` on the main derivation, so hosts build
  them locally regardless of cache contents; caching them would only
  spend CI time.
- logseq family: served by `nix-logseq-git-flake.cachix.org`. Local builds
  happen when that input repository's CI has not yet built the pinned
  nightly; the fix belongs in that repository's build schedule, not in a
  backfill here.
- pentest wrappers (`pentest-*`): the wrapper derivations embed the flake
  self path and change on every commit; their heavy runtime payloads are
  either Hydra-built (metasploit, nmap, sqlmap, ...), covered by
  cache-roots entries (john, wappalyzer-next), or unfree (burpsuite,
  charles) and excluded by license.
- nix-index-with-full-db: fetch-dominated assembly of a prebuilt database,
  negligible build cost.
- host config and systemd unit text derivations: cheap by design.
- nixpkgs packages missing from `cache.nixos.org` right after a fresh
  nixpkgs pin (Hydra lag): transient; planify is pinned into cache-roots for
  that reason. nemo is not pinned. It reaches the cache only through the
  nemo-with-extensions closure, which carries its `out` and not its `dev`, so
  it reports local under coverage gap 4 instead of clearing on the next Hydra
  run.

## Operator setup

Completed 2026-07-17:

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
   fresh machine that has nothing in its store. Keep both lists in step with
   the module.

Confirmed operating as of 2026-07-31: `cache-push.yml` reaches the "Push
closure to Cachix" step with a `success` conclusion on merges to `main`, and
`https://bad3r-nixos.cachix.org/nix-cache-info` serves `Priority: 41`.

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
   system76-power, nixos-icons, nixos-option). The two sets are disjoint by
   hand, not by construction: one file accepts rebuilding a package forever
   and the other decides what to publish, with nothing reconciling them. So a
   new custom package stays uncached until somebody reads a build log, and a
   name added to the publisher leaves behind a dead glob that absorbs the next
   regression on it. The allowlist's other entries are permanent dispositions
   `docs/reference/cache-coverage.md` accepts rather than reconciliation debt:
   the RAR-enabled p7zip is unfree while the cache is public, and the
   configuration wrappers are too cheap to be worth the CI time.
2. Only the primary host sources entries
   (https://github.com/Bad3r/nixos/issues/423). `cache-roots.nix` hardcodes
   `primaryHost`, so apps a sibling host enables and the primary does not
   (`modules/tpnix/apps-enable.nix` turns on projectlibre and thinkfan) never
   reach the cache, and neither do that host's distinct wrapper closures.
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
   `man`) report as local builds on system76 although the output hosts install
   answers 200 from `bad3r-nixos.cachix.org` and the other answers 404
   everywhere. Neither name belongs in the allowlist: a glob there would
   restore coverage on paper and suppress the next real divergence on that
   package.

The unfree group remains the issue's phase 2 and stays out of scope while the
cache is public: serving it needs a private or authenticated cache with the
token provisioned to hosts through sops.

Before-and-after measurement of switch time belongs to the detector, not to a
manual log diff. Once gap 3 lands, the report's own class counts are the
metric.

## Extending the allowlist

Add a package to `modules/meta/cache-roots.nix` when it shows up in build
logs and its full runtime closure is redistributable:

- Source it from the surface that owns the derivation:
  - the host package set, when a custom overlay or host nixpkgs config
    shapes it;
  - `self'.packages`, when only the devshell surface consumes it;
  - the owning flake input, when a module consumes the input's package
    directly (context7-mcp);
  - the owning module's read-only resolved-package option, listed in
    `hostFinalPackagePaths`, when the module installs a configured variant
    rather than the bare package-set attribute (nemo-with-extensions).
    Declare that option with no default and assign it inside
    `config = lib.mkIf cfg.enable`, next to a sibling `enable` that
    `cache-roots.nix` reads; `modules/browsers/ungoogled-chromium/apps.nix`
    and `modules/apps/nemo.nix` are the reference shape.
- Verify the license on the surface the entry is sourced from, not on the
  host package set by default, because the bare `pkgs.<name>` attribute can
  be a different derivation than the one that gets published:
  - host-sourced:
    `nix eval "path:.#nixosConfigurations.<host>.pkgs.<name>.meta.license"`
  - option-sourced:
    `nix eval "path:.#nixosConfigurations.<host>.config.<option-path>.meta.license"`
  - perSystem- and input-sourced: the matching `self'.packages.<name>` or
    flake-input attribute.
- For a wrapper-style entry, check the packages it wraps as well. `meta.license`
  on the wrapper describes the wrapper alone, and `assertFree` reads that same
  field, so neither covers what the wrapper pulls into the published closure:
  `nemo-with-extensions` reports GPL-2.0 and LGPL-2.0 while carrying
  nemo-preview, nemo-seahorse, nemo-python, nemo-fileroller (GPL-2.0-or-later),
  nemo-emblems, and folder-color-switcher (GPL-3.0-only).
- Verify the heavy derivation substitutes: a derivation that sets
  `allowSubstitutes = false` (check `drvAttrs.allowSubstitutes`) never hits
  the cache itself, so what matters is whether that derivation is the
  expensive one. An entry belongs in the list when the non-substitutable
  derivation is thin assembly over a substitutable dependency closure
  (electron-mail, upscayl, nemo-with-extensions all set it on the outer
  wrapper). It does not belong when the non-substitutable derivation is
  itself the expensive build (tor-browser, mullvad-browser).
- Drop the matching glob from `scripts/cache-coverage-allowlist.txt` in the
  same change. That file records divergences accepted as permanent local
  builds; a package the cache now serves is no longer one, and leaving the
  glob behind hides the next regression on that name. The
  `cache-roots-allowlist-disjoint` check enforces this: it matches every
  published entry name against the file's globs and aborts evaluation naming
  the offender, so forgetting the deletion fails `nix flake check` rather than
  surfacing as a silently dead glob later.
- Confirm derivation parity with
  `nix build --dry-run "path:.#cache-roots"` on a recently switched host:
  the new entry must not introduce rebuilds of paths the host already has.

Unfree packages must never enter the allowlist while the cache is public.
Serving them requires the issue's phase 2: a private or authenticated
cache with the token provisioned to hosts via sops. The `assertFree` guard
in `cache-roots.nix` backstops this: a package whose license is missing or
non-redistributable aborts evaluation. Unfree-but-redistributable packages
(firefox-bin, nvidia-x11, steam) pass the guard's legal check but stay out of
the allowlist until that phase-2 operator decision.
