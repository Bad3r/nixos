# Extending Binary Cache Coverage

## Extending the list

Add a package to `modules/meta/cache-roots.nix` when it shows up in build logs
and a host actually installs it. License does not determine inclusion; see the
[license posture](binary-cache-coverage-policy.md).

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
  builds; a package served by the cache does not belong in that accepted-local
  build set, and leaving the glob behind hides the next regression on that
  name. The `cache-roots-allowlist-disjoint` check enforces this: it matches
  every published entry against the file's globs, on the entry name and on the
  derivation `name` and `pname`, and aborts evaluation naming the offender. So
  forgetting the deletion fails `nix flake check` rather than surfacing as a
  silently dead glob later.

- Confirm derivation parity with
  `nix build --dry-run "path:.#cache-roots"` on a recently switched host:
  the new entry must not introduce rebuilds of paths the host already has.
