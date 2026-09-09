# Binary Cache Coverage Policy and Inventory

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
`modules/meta/cache-roots.nix`. Host membership comes from evaluated
`nixosConfigurations`; the inventory is not duplicated here.
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

perSystem-sourced (restringer) and input-sourced (context7-mcp,
codex) entries are published once, not per host, because no host package set
shapes them.

context7-mcp is sourced from the `mcp-servers-nix` input, matching the
consumer in `modules/agents/mcp.nix`, which resolves every server's package
through `inputs.mcp-servers-nix.packages.<system>`; host package sets carry a
same-named but different derivation no consumer runs. nemo-with-extensions
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
  happen when that input repository's CI has not built the pinned
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
