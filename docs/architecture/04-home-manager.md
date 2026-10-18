# Home Manager Modules

Home Manager modules use an aggregator namespace and a shared app-loading mechanism.

## The `flake.homeManagerModules` Namespace

Home Manager modules feed into `flake.homeManagerModules` for user-level configuration:

| Key                                                                 | Type             | Description                                                                  |
| ------------------------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------- |
| `base`                                                              | Deferred module  | Bootstrap configuration (shell, git, shared defaults)                        |
| `gui`                                                               | Deferred module  | Reserved GUI aggregation point                                               |
| `apps.<name>`                                                       | Deferred module  | Individual app modules, all loaded on every host                             |
| `browsers.<name>`                                                   | Deferred module  | Per-browser modules from `modules/browsers/<name>/home.nix`                  |
| `sopsRuntime`                                                       | Deferred module  | HM-side SOPS runtime bootstrap (loaded for every host)                       |
| `context7Secrets`, `geckoSecrets`, `r2Secrets`, `virustotalSecrets` | Deferred modules | Optional SOPS-managed secret modules (each guarded by `builtins.pathExists`) |

## Contributing to Namespaces

Multiple files can extend shared namespaces. Common patterns in this repo:

```nix
# modules/files/eza.nix
{
  flake.homeManagerModules.base = _: {
    programs.eza.enable = true;
  };
}

# modules/stylix/stylix.nix (excerpt)
{ inputs, lib, ... }:
{
  flake.homeManagerModules.apps.stylix-gui = { ... }: {
    stylix.targets.gtk.enable = true;
  };
}
```

## Per-App Modules

An app's Home Manager module lives in its app folder as `modules/apps/<name>/home.nix`, but any auto-imported module can export `flake.homeManagerModules.apps.<name>` (for example, `modules/apps/i3wm/*.nix` exporting `apps.i3-config`).

## App Loading

`modules/hosts/common/home-manager-apps.nix` adds every `flake.homeManagerModules.apps` and `flake.homeManagerModules.browsers` module to `home-manager.sharedModules` on every host.
Each module gates on its NixOS app row through `osConfig`, on its own enable option, or on the NixOS setting it configures, so the app registry decides where an app runs.
`sharedModules` matches the scope of a row: a row is host-wide, so its Home Manager half reaches every Home Manager user on the host.
A standalone Home Manager configuration passes `osConfig = null`, which every gate reads as off.

### Browser Modules

Browsers register under `flake.homeManagerModules.browsers.<name>` from `modules/browsers/<name>/home.nix` and load the same way.
A sibling file can extend the same `browsers.<name>` key, merged the same way `apps.stylix-gui` is above: `modules/browsers/firefoxpwa/home.nix` pins the userdata directory for every firefoxpwa site, and `modules/browsers/firefoxpwa/dmail.nix` layers the DMail-specific install onto the same `browsers.firefoxpwa` key.

### Per-Host Divergences

The shared HM base and secret defaults live in
`modules/hosts/common/imports.nix`; host-owned modules add only the overrides
that diverge. As a current snapshot:

| HM toggle           | songbird default                       | tpnix default                          | Notes                                                                                                                                                |
| ------------------- | -------------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `context7Secrets`   | `mkDefault true`                       | `mkDefault true`                       | Context7 API key rendering.                                                                                                                          |
| `geckoSecrets`      | `mkDefault true`                       | `mkDefault true`                       | The common baseline enables Gecko bookmark secret rendering for every host; rendering still requires the secret file.                                |
| `virustotalSecrets` | `mkDefault true`                       | `mkDefault true`                       | VirusTotal API key rendering.                                                                                                                        |
| `r2Secrets`         | `mkDefault true`                       | `mkDefault true`                       | Renders `~/.config/cloudflare/r2/env` when the secret file exists; the common baseline also defaults NixOS-side `security.r2CloudSecrets.enable` on. |
| `repoGpg`           | `mkDefault true` (when module present) | `mkDefault true` (when module present) | The common baseline conditionally imports `inputs.self.homeManagerModules.repoGpg` and gates `repoGpg.enable` on the same module-existence check.    |
| `services.espanso`  | (inherits HM upstream)                 | `x11Support = mkForce true`            | tpnix forces X11 via `home-manager.sharedModules` because it runs i3 on X11.                                                                         |

On the NixOS side, every host defaults `security.repoSecrets.enable` and
`security.r2CloudSecrets.enable` to `mkDefault true`, so the repo-managed SOPS
payloads decrypt once the shared age key is installed.

The common defaults in `modules/hosts/common/imports.nix` are authoritative;
host-owned modules such as `modules/hosts/tpnix/services.nix` carry explicit
divergences. When adding a shared secret module, set both NixOS- and HM-side
defaults in the common baseline and add only host-specific overrides locally.

## Authoring Rules

1. **Always export under `flake.homeManagerModules.*`**
2. **Gate every app module** -- every `apps.<name>` and `browsers.<name>` module loads on every host, so its config waits for its NixOS row, its own enable option, or the NixOS setting it configures
3. **Keep app keys stable** -- checks reference `apps.<name>` by key
4. **Guard secrets** -- wrap secret declarations with `builtins.pathExists` checks

## Secrets Integration

[SOPS usage](../sops/README.md) covers guarded Home Manager declarations and runtime behavior.

## HM Diagnostics

[Home Manager debugging](../guides/nix-debugging-manual.md#4-debugging-home-manager) covers activation, generated files, and module inspection.

## Next Steps

- [Host Composition](05-host-composition.md) -- how hosts assemble these modules
- [Module Authoring](02-module-authoring.md) -- general authoring patterns
- [SOPS Usage](../sops/README.md) -- secrets management
