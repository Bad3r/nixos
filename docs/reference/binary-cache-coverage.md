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

Garnix is retired, has deleted every stored build artifact, and open
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

## Audit findings

Build-log profiling under `~/.local/state/nixos-build/` after PR
https://github.com/Bad3r/nixos/pull/380 still showed on the order of 170
derivations built locally per full system build. Three groups remain:

- custom flake packages and overlay-modified packages (pnpm and npm
  dependency trees, patched browser runtimes, pentest tooling)
- unfree binary repacks (vscode, webex, kiro, veracrypt, ventoy, and
  others)
- host-specific config and text derivations (cheap, acceptable)

## Build surface

`packages.<system>.cache-roots` is a `linkFarm` over an explicit list of the
packages hosts would otherwise build locally. Every output of each entry is
linked, not just the default one: `cache-push.yml` pushes the closure of the
built `result`, and a multi-output derivation's `outPath` does not reach its
siblings, so those outputs would be built on CI and then dropped. `nvidia-x11`
alone splits into `out`, `lib32`, `bin`, `modsrc`, and `firmware`. Links are
keyed `<host>/<package>/<output>`.

- Host-sourced entries read `programs.<name>.extended.package` on each host,
  which is the value those modules install, so custom overlays (firefoxpwa
  policy injection, john patches), nixpkgs config, and any per-host override
  of that option produce exactly the derivations a host switch evaluates.
  Reading the bare package-set attribute instead would desync silently: an
  override keeps `extended.enable = true`, so the gate stays green while the
  published derivation is one nobody builds, and the symptom is a cache miss
  rather than an error. Every registered
  host that builds for the current system contributes its own entries, so an
  app only a sibling host enables still reaches the cache and each host's
  distinct closure is published separately for each host that enables it.
  Entries are gated per host on `programs.<name>.extended.enable`, so a host
  that turns an app off contributes nothing for it and the cache never carries
  a closure that host will not install (which is why wfuzz is not listed).
  `nix build --dry-run "path:.#cache-roots"` on a host that has switched
  recently should report no unexpected package rebuilds; that is the
  derivation-parity check.
- Option-sourced entries (`hostOptionPackages`) resolve the package from the
  host config, for packages the bare package-set attribute never produces or
  that never reach `environment.systemPackages` at all. Resolution is a
  function rather than an option path, because it can mean reaching past the
  option into the value it holds, or choosing between derivations by another
  option's value: `hardware.nvidia.package.mod` is the kernel module built
  against `boot.kernelPackages` and installed through
  `boot.extraModulePackages`, `hardware.nvidia.package.settings` is
  nvidia-settings, and neither is an output, so linking every output does not
  reach them. Each entry carries
  its own `installed` predicate rather than deriving a sibling `enable` from
  the option path, because these options do not share one shape:
  `programs.nemo.extended.finalPackage` is assigned inside
  `config = lib.mkIf cfg.enable` and is undefined when the module is off, so
  its sibling `enable` is the real signal, while `hardware.nvidia.package` and
  `programs.steam.package` carry upstream defaults and stay defined on hosts
  that never install them, so `services.xserver.videoDrivers` and the upstream
  `programs.steam.enable` are what actually install them.
- perSystem-sourced entries (codeburn, restringer) are consumed through
  the devshell surface and build from the perSystem nixpkgs instance.
- Input-sourced entries (context7-mcp, mcp-server-sequential-thinking, codex)
  come from the flake input the consuming module resolves them from, because
  host package sets can carry a same-named but different derivation.

The list names the module hosts enable, which is not always the attribute that
shares the app's common name: `vscode-fhs` and `ventoy-full` are what
`modules/apps/` enables, while the bare `vscode` and `ventoy` attributes are
different derivations no host consumes. `vscode` still reaches the cache as a
dependency of the `vscode-fhs` closure.

A name listed but enabled on no host aborts evaluation instead of quietly
publishing nothing, so renaming an app or disabling it on the last host that
had it fails `nix flake check` rather than leaving a dead entry behind. The
one exemption is `nvidia-kernel-modules`: while some host loads the NVIDIA
driver, every NVIDIA host setting `cacheRoots.nvidiaKernelModules = false` is
a policy opt-out that leaves the name in place unpublished, and the abort only
returns once no host loads the driver at all.

There is no license gate. `cachix push` publishes the full runtime closure,
and the cache is operator-private in use, so unfree packages are published
alongside free ones and redistribution is not evaluated at build time. See
"License posture" below for what that assumes.

## License posture

The cache carries unfree packages. This rests on the cache being consumed by
its operator alone, not on any redistribution grant: most entries below
(vscode, google-chrome, webex, charles, obsidian, veracrypt, ventoy-full,
discord, dropbox, burpsuite) are `unfree` with
`redistributable = false` in nixpkgs, so publishing them to an audience would
violate their licenses. `nvidia-x11`, `firefox-bin`, and `steam` are the only
unfree entries nixpkgs marks redistributable.

That assumption is not enforced by anything in this repo. `bad3r-nixos.cachix.org`
is a public cache: `modules/hosts/common/nix-substituters.nix` reads it with no
token and `nix-cache-info` answers anonymously, so the store paths are reachable
by anyone who knows the cache name. Making the Cachix cache private is what would
make the posture match the mechanism.

An earlier `assertFree` guard aborted evaluation for any entry that was neither
free nor redistributable. It was removed with this policy; nothing now checks a
license at build time, so adding an entry is purely an operator decision.

## Inventory

The authoritative lists are `hostPackageNames` and `hostOptionPackages` in
`modules/meta/cache-roots.nix`. Host membership is evaluated from the current
`nixosConfigurations` and is intentionally not duplicated in this document.
Query the current inventory with:

```sh
nix eval --accept-flake-config --offline --json --impure \
  --expr 'let flake = builtins.getFlake (toString ./.); in flake.lib.nixos._cacheRootsInventory flake.nixosConfigurations'
```

In a linked worktree this resolves through the unfiltered `path:` fetcher
(`.git` is a file there, so Lix cannot fetch it as `git+file`), which copies
every untracked path into the world-readable store, secrets included; this
hand-typed `nix eval` does not run through the guard in
`scripts/lib/secrets-guard.sh`. Sweep first with
`git status --porcelain --ignored=matching`, or run this from a primary
checkout instead.

The result contains `hostPackages` and `optionPackages` for each configured
host. It reports names only, so package versions and derivation paths continue
to follow the evaluated flake without requiring a documentation update.

For hosts whose cache policy publishes `nvidia-kernel-modules`, the entry
selects the module flavor each enabled host installs, mirroring upstream's
`boot.extraModulePackages = if useOpenModules then [ nvidia_x11.open ] else [ nvidia_x11.mod ]`
with `useOpenModules = cfg.open == true`. Gating on one flavor would drop
coverage silently on a host that flips `hardware.nvidia.open`, which
`modules/hardware/nvidia-gpu.nix` documents as required on Blackwell and newer.

Every NVIDIA-enabled host must declare the Boolean
`cacheRoots.nvidiaKernelModules`. `true` keeps the installed module in the
published cache roots, while `false` records an intentional exclusion. Missing,
empty, non-Boolean, and unknown policy values fail evaluation before the cache
publisher can fall back to its ordinary inclusion behavior.

Songbird intentionally declares `cacheRoots.nvidiaKernelModules = false`: its
CachyOS kernel is built from source and no CachyOS substituter is configured.
The module remains installed on songbird, but it is omitted from the published
cache roots. `nvidia-x11` and `nvidia-settings` remain cache roots because their
current derivations do not require the CachyOS kernel build. The evaluated
`cache-roots-nvidia-cache-policy` check exercises valid, missing, empty,
misspelled, unknown-key, and non-Boolean policy cases, then reads the
publisher's actual host-qualified entries for each exclusion. It fails if the
module is published again, `nvidia-x11` is absent, or `nvidia-settings` is
absent while the evaluated host configuration enables it. A host that instead
sets `hardware.nvidia.nvidiaSettings = false` is not required to publish
`nvidia-settings`: the check reads that option's evaluated value rather than
assuming every host enables it.

The full closure detector classifies the source-built CachyOS kernel and its
modules as `local-only`, not `unexpected-local`, because stock nixpkgs has no
corresponding `linux-cachyos` derivation. Do not add a `linux-cachyos*` glob to
the allowlist: allowlist entries are reserved for served stock derivations
that diverge through an accepted overlay or wrapper.

`steam` is option-sourced because `modules/apps/steam.nix` installs nothing
itself: it sets `programs.steam.enable` with `extraCompatPackages` and
`extraPackages`, and upstream's `programs.steam.package` carries an `apply`
that re-`override`s the FHS env with both lists. The applied value is what
upstream puts in `environment.systemPackages`, and proton-ge-bin, dwarfs,
fuse-overlayfs, and protonup-rs live inside it. It can differ from `pkgs.steam`,
so publishing only the bare attribute can leave the installed closure
unsubstituted.

perSystem-sourced (codeburn, restringer) and input-sourced (context7-mcp,
mcp-server-sequential-thinking, codex) entries are published once, not per
host, because no host package set shapes them.

context7-mcp and mcp-server-sequential-thinking are sourced from the
`mcp-servers-nix` input, matching the consumer in `modules/agents/mcp.nix`,
which resolves every server's package through
`inputs.mcp-servers-nix.packages.<system>`; host package sets carry
same-named but different derivations no consumer runs. nemo-with-extensions
is sourced from `programs.nemo.extended.finalPackage` for the same reason:
`modules/apps/nemo.nix` re-wraps nemo with an explicit extension list, so
the bare `pkgs.nemo-with-extensions` attribute is a derivation no host
installs, and its closure omits nemo-preview and nemo-seahorse. For entries built
through `buildFHSEnv` or wrapper derivations (electron-mail, kiro-fhs, upscayl,
vscode-fhs, nemo-with-extensions), the outer wrapper sets
`allowSubstitutes = false` and always rebuilds locally; that is trivial
assembly work, and the heavy dependency closure underneath substitutes
normally.

Deliberately absent:

- firefox-bin: it is not a cache-roots entry. Source-built Firefox wrappers are
  dispositioned as accepted local builds by the `firefox-[0-9]*` glob in
  `scripts/cache-coverage-allowlist.txt`. The
  `firefox-bin` closure is pushed anyway, as a member of the dropbox FHS
  rootfs, so listing it would add an entry and no coverage.
- tor-browser and mullvad-browser: see the residual-local-builds list below.

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
  either Hydra-built (metasploit, nmap, sqlmap, ...) or covered by
  cache-roots entries (john, wappalyzer-next, burpsuite, charles).
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
   system76-power, nixos-icons, nixos-option). The two sets are disjoint by
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

## Extending the list

Add a package to `modules/meta/cache-roots.nix` when it shows up in build logs
and a host actually installs it. License is no longer a criterion; see
"License posture".

- Name the attribute a host installs, not the one that shares the app's common
  name. `pkgs.vscode` and `pkgs.ventoy` are derivations no host consumes; the
  installed attributes are `vscode-fhs` and `ventoy-full`. Confirm with
  `nix eval` that the attribute's `outPath` appears in the host's
  `environment.systemPackages` or Home Manager `home.packages`, or that it is a
  dependency of the wrapper that does.

- Source it from the surface that owns the derivation:

  - the host package set, when a custom overlay or host nixpkgs config
    shapes it. `hostPackageNames` entries are gated per host on
    `programs.<name>.extended.enable`, so the app must be wired through
    `modules/hosts/common/apps-enable.nix` or a per-host override;
  - `self'.packages`, when only the devshell surface consumes it;
  - the owning flake input, when a module consumes the input's package
    directly (context7-mcp);

- the host config, listed in `hostOptionPackages`, when the bare
  package-set attribute never produces it or it never reaches
  `environment.systemPackages` (nemo-with-extensions, nvidia-x11). Write
  `path` as a `hostConfig: package` function, not an option path: it may
  reach past the option into a derivation hanging off the package
  (`hardware.nvidia.package.settings`) or choose between derivations by
  another option's value (`hardware.nvidia.open`). Give the entry an
  `installed` predicate naming the condition under which the host installs
  it; do not assume a sibling `enable` exists, because upstream options such
  as `hardware.nvidia.package` carry a default and stay defined on hosts
  that never use them.

- A host may install an option-sourced package without publishing it when the
  build is host-specific and no configured substituter serves it. Keep that
  exception in the host registry's `cacheRoots` policy. Every NVIDIA-enabled
  host must set its `nvidiaKernelModules` Boolean explicitly; the focused check
  rejects missing, malformed, or unknown policy values and verifies retained
  and omitted entries.

- A name enabled on no host aborts evaluation rather than publishing nothing,
  so a rename or a last-host disable fails `nix flake check` instead of leaving
  a dead entry. `nvidia-kernel-modules` is exempt while any host loads the
  NVIDIA driver, because a fleet-wide `cacheRoots.nvidiaKernelModules = false`
  is a policy opt-out rather than a stale name.

- Verify the heavy derivation substitutes: a derivation that sets
  `allowSubstitutes = false` (check `drvAttrs.allowSubstitutes`) never hits
  the cache itself, so what matters is whether that derivation is the
  expensive one. An entry belongs in the list when the non-substitutable
  derivation is thin assembly over a substitutable dependency closure
  (electron-mail, upscayl, vscode-fhs, nemo-with-extensions all set it on the
  outer wrapper). It does not belong when the non-substitutable derivation is
  itself the expensive build (tor-browser, mullvad-browser).

- Drop the matching glob from `scripts/cache-coverage-allowlist.txt` in the
  same change. That file records divergences accepted as permanent local
  builds; a package the cache now serves is no longer one, and leaving the
  glob behind hides the next regression on that name. The
  `cache-roots-allowlist-disjoint` check enforces this: it matches every
  published entry against the file's globs, on the entry name and on the
  derivation `name` and `pname`, and aborts evaluation naming the offender. So
  forgetting the deletion fails `nix flake check` rather than surfacing as a
  silently dead glob later.

- Confirm derivation parity with
  `nix build --dry-run "path:.#cache-roots"` on a recently switched host:
  the new entry must not introduce rebuilds of paths the host already has.
