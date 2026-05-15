# Home Manager Modules

This document covers the Home Manager aggregator namespace and app loading mechanism.

## The `flake.homeManagerModules` Namespace

Home Manager modules feed into `flake.homeManagerModules` for user-level configuration:

| Key                                                                    | Type             | Description                                                           |
| ---------------------------------------------------------------------- | ---------------- | --------------------------------------------------------------------- |
| `base`                                                                 | Deferred module  | Bootstrap configuration (shell, git, shared defaults)                 |
| `gui`                                                                  | Deferred module  | Reserved GUI aggregation point (currently mostly an empty merge root) |
| `apps.<name>`                                                          | Deferred module  | Individual app modules loaded by key                                  |
| `context7Secrets`, `greptileSecrets`, `r2Secrets`, `virustotalSecrets` | Deferred modules | Optional SOPS-managed secret modules                                  |

## Contributing to Namespaces

Multiple files can extend shared namespaces. Common patterns in this repo:

```nix
# modules/files/fzf.nix
_: {
  flake.homeManagerModules.base = _: {
    programs.fzf.enable = true;
  };
}

# modules/stylix/stylix.nix
_: {
  flake.homeManagerModules.apps.stylix-gui = { ... }: {
    stylix.targets.gtk.enable = true;
  };
}
```

## Per-App Modules

Most app modules live under `modules/hm-apps/<name>.nix`, but any auto-imported module can export `flake.homeManagerModules.apps.<name>` (for example, `modules/apps/i3wm/*.nix` exporting `apps.i3-config`).

The loader first resolves by key from aggregated flake exports, then falls back to `modules/hm-apps/<name>.nix`.

## App Loading Mechanism

The glue layer in `modules/home-manager/nixos.nix` resolves app modules in this order:

```nix
loadAppModule = name:
  let
    filePath = ../hm-apps + "/${name}.nix";
    moduleFromConfig = lib.attrByPath [ "apps" name ] null hmModules;
  in
  if moduleFromConfig != null then
    moduleFromConfig
  else if builtins.pathExists filePath then
    loadHomeModule filePath [ "flake" "homeManagerModules" "apps" name ]
  else
    throw "Home Manager app module not found: ${name}";
```

`hmModules` is merged from `config.flake.homeManagerModules`, `moduleArgs.inputs.self.homeManagerModules`, and `inputs.self.homeManagerModules`.

### Default App Imports

The following apps are loaded by default for `vx` on each NixOS host (defined in `modules/home-manager/nixos.nix`):

```nix
defaultAppImports = [
  "codex"
  "bat"
  "eza"
  "fzf"
  "git-mirror"
  "kitty"
];
```

### Adding Extra Apps

Each host appends to `home-manager.extraAppImports` and mirrors matching app modules into `home-manager.sharedModules` from its own `modules/<host>/home-manager-apps.nix`.

### Per-Host Divergences

The shared HM base is identical across hosts; per-host overrides live in each host's `imports.nix`. As a current snapshot:

| HM toggle           | system76 default       | tpnix default                          | Notes                                                                                                                                  |
| ------------------- | ---------------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `context7Secrets`   | `mkDefault true`       | `mkForce false`                        | Context7 API key rendering.                                                                                                            |
| `greptileSecrets`   | `mkForce false`        | `mkForce false`                        | Disabled with the Greptile Claude Code plugin/MCP integration; re-enable only when that plugin is explicitly enabled.                  |
| `virustotalSecrets` | `mkDefault true`       | `mkForce false`                        | VirusTotal API key rendering.                                                                                                          |
| `r2Secrets`         | `mkForce false`        | `mkForce false`                        | NixOS-side `r2CloudSecrets` is also off in the current configuration.                                                                  |
| `repoGpg`           | `mkDefault true`       | (not enabled, no shared module pulled) | system76 pulls `inputs.self.homeManagerModules.repoGpg` into `home-manager.sharedModules`; tpnix does not pull this shared module.     |
| `services.espanso`  | (inherits HM upstream) | `x11Support = mkForce true`            | system76 leaves espanso's session-backend defaults alone; tpnix forces X11 via `home-manager.sharedModules` because it runs i3 on X11. |

Authoritative source for any host: that host's `imports.nix` (`modules/<host>/imports.nix`). When adding a new secret module, set both NixOS- and HM-side defaults explicitly per host so behavior is obvious from `imports.nix` rather than implicit through `mkDefault` chains.

## Authoring Rules

1. **Always export under `flake.homeManagerModules.*`**
2. **Guard host-dependent config** -- use `osConfig` checks when an HM app depends on NixOS-side enablement
3. **Keep app keys stable** -- `apps.<name>` is the stable import contract (filename matching is recommended for `modules/hm-apps/` fallback, but not required globally)
4. **Guard secrets** -- wrap secret declarations with `builtins.pathExists` checks

## Secrets Integration

Home-level secrets helpers guard SOPS declarations behind `builtins.pathExists`:

```nix
# modules/home/context7-secrets.nix
{ lib, metaOwner, secretsRoot, ... }:
let
  ctxFile = "${secretsRoot}/context7.yaml";
in
{
  config = lib.mkIf (builtins.pathExists ctxFile) {
    sops.secrets."context7/api-key" = {
      sopsFile = ctxFile;
      # ...
    };
  };
}
```

This ensures evaluation succeeds even when secret files are absent.

## HM Diagnostics

Home Manager runs as a NixOS module per host (no standalone HM configuration). To inspect or build a host's HM tree, substitute the host name:

```bash
# Evaluate a host's HM users tree
nix eval .#nixosConfigurations.<host>.config.home-manager.users.vx.home.packages --apply builtins.length

# Build the host closure (HM activation runs on switch)
nix build .#nixosConfigurations.<host>.config.system.build.toplevel

# List the hosts available in the current checkout
nix eval --accept-flake-config --json .#nixosConfigurations --apply builtins.attrNames
```

For NixOS-managed Home Manager, inspect the active generation through
`~/.local/state/home-manager/gcroots/current-home/home-files`. The standalone
`~/.local/state/nix/profiles/home-manager` profile can be stale and should not
be used as the source of truth for NixOS module activation.

If a Home Manager-managed file or directory is removed but the system
generation does not change, `nh os switch` / `switch-to-configuration` may not
rerun `home-manager-<user>.service`. Restart the system service directly to
relink the active generation:

```bash
sudo systemctl restart home-manager-vx.service
```

Gecko browser profiles are intentionally managed only at `~/.mozilla/firefox`
and `~/.librewolf`. Runtime-generated XDG profiles under `~/.config/mozilla` or
`~/.config/librewolf` are unmanaged drift; remove them recoverably with `rip`
before relinking the Home Manager generation.

Add `home-manager` to `modules/devshell.nix` if a standalone CLI is needed for ad-hoc diagnostics.

## Next Steps

- [Host Composition](05-host-composition.md) -- how hosts assemble these modules
- [Module Authoring](02-module-authoring.md) -- general authoring patterns
- [SOPS Usage](../sops/README.md) -- secrets management
