# Binary Cache Coverage

Operator surface for serving custom derivations from a binary cache instead
of rebuilding them on every host switch (issue
https://github.com/Bad3r/nixos/issues/382). Cache topology and substituter
wiring live in `modules/hosts/common/nix-substituters.nix`; the build surface
lives in `modules/meta/cache-roots.nix`; the CI publisher is
`.github/workflows/cache-push.yml`.

## Audit findings (2026-07-17)

Build-log profiling under `~/.local/state/nixos-build/` after PR
https://github.com/Bad3r/nixos/pull/380 still showed on the order of 170
derivations built locally per full system build. Three groups remain:

- custom flake packages and overlay-modified packages (pnpm and npm
  dependency trees, patched browser runtimes, pentest tooling)
- unfree binary repacks (vscode, webex, kiro, veracrypt, ventoy, and
  others)
- host-specific config and text derivations (cheap, acceptable)

The garnix question from the issue resolves as follows:

- The garnix GitHub app is not installed for this repository. Recent
  commits carry no garnix check suites, and the garnix badge API returns
  an empty badge. The few `cache.garnix.io` hits observed during builds
  come from garnix's shared public cache, populated by other projects'
  builds, not from CI coverage of this repository.
- garnix cannot build this flake in its current shape even if installed:
  `flake.nix` sets `self.submodules = true`, so any git-based fetch of the
  flake pulls the private `secrets/` submodule, which external CI cannot
  read. The repository's own GitHub Actions work around this with `path:.`
  checkouts and secretless evaluation (see `.github/workflows/check.yml`),
  a mechanism garnix does not document an equivalent for. Revisit garnix
  only if it documents submodule-free fetching or the submodule leaves the
  fetch path.

Coverage therefore comes from this repository's own CI pushing to Cachix,
the mechanism already proven by the `nix-logseq-git-flake` input, whose CI
builds logseq and pushes to its own Cachix cache trusted in
`modules/hosts/common/nix-substituters.nix`.

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
- perSystem-sourced entries (codeburn, restringer) are consumed through
  the devshell surface and build from the perSystem nixpkgs instance.

The allowlist is explicit because `cachix push` publishes the full runtime
closure to a public cache. Every entry's closure must be redistributable, and
`cache-roots` enforces it: an `assertFree` guard aborts evaluation for any entry
whose `meta.license` is missing or is neither free nor redistributable, so a
license-violating addition fails `nix flake check` (the check
`modules/package-checks.nix` mirrors from this output) instead of reaching the
cache.

## Classification (2026-07-17 build logs)

License fields read from each package's `meta.license` on the primary
host's package set.

Cached via cache-roots (free, redistributable):

| Package              | License            |
| -------------------- | ------------------ |
| codeburn             | MIT                |
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
same-named but different derivation no consumer runs. For entries built
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
  nixpkgs pin (Hydra lag): transient; the heaviest recurring cases (nemo,
  planify) are pinned into cache-roots.

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

Remaining:

1. First populated run: the workflow triggers on pushes to `main` that
   change `flake.lock`, the cache-roots module, custom overlays, or
   `packages/` (the merge introducing the module qualifies), or run it via
   `workflow_dispatch`; confirm the push step succeeds.
2. After the next nixpkgs bump and merge, compare a host switch build log
   against a pre-cache log: the cache-roots packages should appear as
   downloads, not builds.

## Extending the allowlist

Add a package to `modules/meta/cache-roots.nix` when it shows up in build
logs and its full runtime closure is redistributable:

- Source it from the host package set when a custom overlay or host
  nixpkgs config shapes it; source it from `self'.packages` when only the
  devshell surface consumes it; source it from the owning flake input
  when a module consumes the input's package directly (context7-mcp).
- Verify the license before adding:
  `nix eval "path:.#nixosConfigurations.<host>.pkgs.<name>.meta.license"`.
- Verify the heavy derivation substitutes: entries whose main derivation
  sets `allowSubstitutes = false` (check `drvAttrs.allowSubstitutes`)
  never hit the cache and do not belong in the list.
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
