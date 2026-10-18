# Repository Instructions

A personal NixOS configuration built with the Dendritic Pattern: every `.nix`
file under `modules/` is a flake-parts module that is imported automatically,
so files move freely and nothing imports a module by literal path. A `_`
prefix opts a file out, which is how private helpers and experiments stay
unloaded. Architecture docs live under `docs/architecture/`.

Nothing outside this repository consumes it, so backward compatibility is
never a goal: remove legacy support instead of carrying both paths.

## Modules

- Modules register under `flake.nixosModules` and `flake.homeManagerModules`,
  and hosts compose them from those namespaces. Use `lib.hasAttrByPath` with
  `lib.getAttrFromPath` for optional modules to avoid ordering issues.
- Cross-host logic lives in `modules/hosts/common/` and feeds the
  `hosts-common` aggregate, which `modules/configurations/nixos.nix` imports
  ahead of each registered host's own module (registry:
  `modules/hosts/common/registry.nix`), so per-host overrides win. Host
  iteration belongs to that file alone: iterating `flake.lib.nixos.hosts` from
  a common module can recurse infinitely.
- Device policy shared by several apps belongs in the common aggregate; app
  modules own their packages and wrappers.
- `modules/hosts/common/apps-enable.nix` sets app defaults at
  `lib.mkOverride 1100` and per-host files override at 1000; a flake check
  fails on a host override that repeats the baseline value.
- A program reaches PATH only through its own app module, built from that
  module's `package` option. A module that needs another app turns the app's
  row on with `lib.mkOverride 1050 true` rather than installing it, and
  `host-<host>-apps-match-registry` fails when a row evaluates to anything
  else or another module installs the package of an app whose row is off.
- Everything runs Lix from the nixpkgs pin (`modules/base/nix-package.nix`).
  `flake.nix#nixConfig` carries only what Lix needs before the module graph
  loads; `modules/base/nix-settings.nix` owns the rest, and cache topology sits
  in `modules/hosts/common/nix-substituters.nix` and
  `modules/meta/cache-roots.nix`. Adding a cache is a policy decision for the
  user.
- Unfree packages are allowlisted with `nixpkgs.allowedUnfreePackages` next to
  the module that installs them.
- Generated files (`README.md`, `.gitignore`, the gitleaks and sops configs,
  and the rest declared in `modules/files.nix`) are compared byte for byte by
  a check: edit the Nix source, then run
  `nix develop path:. --accept-flake-config -c write-files --offline`.
- Local mirrors are listed in `modules/hosts/common/mirrors.nix` by GitHub
  `owner/repo` shorthand (`tridactyl/tridactyl` lands at
  `/data/git/tridactyl-tridactyl`); `docs/reference/local-mirrors.md` covers
  adding one and the sync that maintains them.
- Secrets use sops-nix: encrypt with `sops secrets/<name>.yaml`, declare under
  `sops.secrets."<namespace>/<name>"`, and consume the entry's `.path`.
- Identifiers are lowercase and hyphenated.

## Workflow

- Work in a linked worktree on a `<type>/<name>` branch
  (`git worktree add "$HOME/trees/nixos/<type>-<name>" -b "<type>/<name>"`,
  with Conventional Commits types) and open a PR whose body has `## Summary`
  and `## Test plan`. Commits land on `main` directly only when the user says
  so in the session for that commit or push.
- In a linked worktree, flake commands take an explicit `path:.` installable
  (`nix develop path:.`, `nix flake check path:.`, `nix eval "path:.#..."`),
  since Lix cannot fetch a linked worktree as a `git+file` flake. Two commands
  cannot take it: `nix fmt` (use `nix run path:.#treefmt -- .`) and anything
  that writes `flake.lock` (use `nix flake update --flake "path:$PWD"`). A
  dirty tree hides the problem, because Lix then copies the tree instead of
  fetching it.
- `path:.` copies the working tree unfiltered: an untracked module evaluates
  locally but not in CI, and a decrypted secret would land in the store.
  `build.sh` and `scripts/cache-coverage.sh` run the shared secrets guard
  first; keep decrypted secrets out of the worktree.
- Hooks run through
  `nix develop path:. -c pre-commit run --all-files --hook-stage manual`.
  Hand-written Markdown follows `docs/technical-writing/style-guide.md`,
  enforced by the `docs-style` hook.
- Remove a finished worktree with `scripts/git-worktree-remove-safe.sh <path>`,
  because the `secrets/` submodule makes plain `git worktree remove` refuse;
  `scripts/prune-stale-worktrees.sh` and a timer sweep the leftovers
  (`docs/reference/worktree-prune.md`).

## Validation

- Value edits: `nix run path:.#treefmt -- .` plus a targeted `nix eval`.
- Structural changes (new modules, options, imports, argument shapes):
  `nix flake check path:. --accept-flake-config --no-build --offline`.
- Host closures:
  `nix build "path:.#nixosConfigurations.$HOSTNAME.config.system.build.toplevel"`.
- Overlay or override changes that can affect cache coverage:
  `scripts/cache-coverage.sh --host $HOSTNAME`
  (`docs/reference/cache-coverage.md`).
- Workflows: `nix develop path:. -c gh-actions-list`, then `gh-actions-run`
  (`-n` for a dry run) through `act`; static checks come first, and the full
  run is for workflow-path changes or an explicit request.
- Credential sweep over the full history: `nix run path:.#hook-gitleaks` on a
  complete clone.
