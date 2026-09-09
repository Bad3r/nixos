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
- perSystem-sourced entries (restringer) are consumed through
  the devshell surface and build from the perSystem nixpkgs instance.
- Input-sourced entries (context7-mcp, codex)
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
the [license posture](binary-cache-coverage-policy.md) page for what that
assumes.

## Reference pages

- [Policy and inventory](binary-cache-coverage-policy.md): license posture and
  the evaluated cache-root inventory.
- [Operations and coverage gaps](binary-cache-coverage-operations.md): cache
  setup, verification, and known coverage gaps.
- [Extending cache coverage](binary-cache-coverage-extension.md): rules for
  adding a derivation to the published cache roots.
