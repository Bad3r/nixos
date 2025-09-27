# Dendritic Pattern Reference

The Dendritic Pattern treats every file under `modules/` as a flake-parts module, composing them organically through shared aggregators. This repository follows the canonical implementation from [`mightyiam/infra`](https://github.com/mightyiam/infra) and keeps the pattern intentionally lightweight: add a module, export it under a namespace, and the flake wires it up automatically.

## Automatic Module Discovery

- `import-tree ./modules` (see `flake.nix`) walks the entire tree and imports every `.nix` file that does **not** start with an underscore. Prefix experimental or parked files with `_` to exclude them without deleting history.
- Because modules are auto-imported, never use literal `./path/to/module.nix` imports. Move files freely—references stay stable because consumers import by name (e.g. `config.flake.nixosModules.base`).
- Put unfinished work under `_scratch/` or `_archive/` directories when you need to stash ideas without activating them.

## Aggregator Namespaces

This flake exposes two merge-friendly aggregators:

| Namespace                  | Purpose                    | Typical Exports                                                                 |
| -------------------------- | -------------------------- | ------------------------------------------------------------------------------- |
| `flake.nixosModules`       | System-level configuration | `base`, `pc`, `workstation`, `apps.<name>`, `roles.<name>`, `roles.dev` aliases |
| `flake.homeManagerModules` | Home Manager configuration | `base`, `gui`, `apps.<name>`, secrets helpers                                   |

Modules register themselves under these namespaces. Example (`modules/files/fzf.nix`):

```nix
_: {
  flake.homeManagerModules.base = { pkgs, ... }: {
    programs.fzf.enable = true;
  };
}
```

Home Manager glue lives in `modules/home-manager/nixos.nix`: it imports the base HM module, wires secrets, and resolves the default app list via guarded lookups. See `docs/home-manager-aggregator.md` for the exact rules.

### Host Definitions

Complete hosts live under `configurations.nixos.<name>.module`. The helper in `modules/configurations/nixos.nix` turns those definitions into `nixosConfigurations.<name>` outputs. Example (`modules/system76/imports.nix`):

```nix
configurations.nixos.system76.module = {
  imports = with config.flake.nixosModules; [
    base
    pc
    workstation
    roles.dev
  ];
};
```

Use `config.flake.nixosModules.roles.dev` (and the other role modules) so host composition stays stable even if role internals change.

## Authoring Modules

Follow these rules when writing new modules:

1. If you need `pkgs`, export a _function_:
   ```nix
   flake.nixosModules.dev-shell = { pkgs, ... }: { environment.systemPackages = with pkgs; [ jq yq ]; };
   ```
2. If you do not need `pkgs`, export an attribute set directly.
3. Keep one concern per file; compose larger features via `imports`.
4. Prefer `lib.mkIf` + predicates over ad-hoc `if` statements at the top level.
5. Cross-reference other modules via the aggregator (`config.flake.nixosModules.<name>`), never via path literals.

For detailed patterns (multi-namespace modules, extending existing namespaces, common pitfalls) reference `docs/MODULE_STRUCTURE_GUIDE.md`.

## Apps, Roles, and Lookups

- Per-app modules live under `flake.nixosModules.apps.<name>` and `flake.homeManagerModules.apps.<name>`.
- Helper surface: `modules/meta/nixos-app-helpers.nix` exposes `config.flake.lib.nixos.{hasApp,getApp,getApps,getAppOr}`. Consume apps through this namespace instead of re-implementing `lib.hasAttrByPath`/`lib.getAttrFromPath` in each role.
- Role modules (e.g. `modules/roles/dev.nix`) compose their imports with
  ```nix
  let getApps = config.flake.lib.nixos.getApps; in getApps [ "neovim" "httpie" ]
  ```
  Optional imports (such as shared VPN defaults) remain explicit with short comments.
- Core roles under `flake.nixosModules.roles` (`dev`, `media`, `net`) mirror their import lists for host composition; reference them directly instead of duplicating the lists.
- Home Manager defaults import a guarded app list defined in `modules/home-manager/nixos.nix`; edit that file when the baseline set changes.

## Tooling and Required Commands

The dev shell (`nix develop`) provides all tooling. The repository already enables `pipe-operators` globally via `nixConfig.extra-experimental-features`, so you **do not** need to append `--extra-experimental-features` to commands.

Run the following before every push:

```bash
nix fmt
nix develop -c pre-commit run --all-files
generation-manager score  # target 90/90
nix flake check --accept-flake-config
```

Additional helpers:

- `nix develop -c update-input-branches` – rebase and push vendored inputs under `inputs/*`.
- `nix develop -c gh-actions-run -n` – dry-run GitHub Actions locally with `act`.
- `write-files` – refresh generated files (managed by `modules/meta/docs.nix`).

## Secrets and SOPS

Secrets are managed with `sops-nix`. See `docs/sops-nixos.md` for the house style and `docs/SECRETS_ACT.md` for the `act` helper secret. Secret templates expose stable paths (e.g. `/etc/act/secrets.env`) and only render when the encrypted file exists.

## Migration Checklist

When adopting an existing configuration into the Dendritic Pattern:

1. Split host configuration into feature-focused modules under `modules/<domain>/`.
2. Export each feature under `flake.nixosModules.<logical-name>` (and/or Home Manager equivalents).
3. Replace literal `imports = [ ./module.nix ];` with aggregator references.
4. Define the host under `configurations.nixos.<host>.module`.
5. Run the validation commands above and ensure `generation-manager score` stays ≥ 90.

## Further Reading

- `docs/MODULE_STRUCTURE_GUIDE.md` – concrete module authoring patterns.
- `docs/home-manager-aggregator.md` – how Home Manager app aggregation works.
- `docs/INPUT-BRANCHES-PLAN.md` – managing vendored flake inputs.
- `docs/NIXOS_CONFIGURATION_REVIEW_CHECKLIST.md` – review procedure for the current host.
