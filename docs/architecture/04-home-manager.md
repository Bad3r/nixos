# Home Manager Modules

This document covers the Home Manager aggregator namespace and app loading mechanism.

## The `flake.homeManagerModules` Namespace

Home Manager modules feed into `flake.homeManagerModules` for user-level configuration:

| Key                                                 | Type             | Description                                                           |
| --------------------------------------------------- | ---------------- | --------------------------------------------------------------------- |
| `base`                                              | Deferred module  | Bootstrap configuration (shell, git, shared defaults)                 |
| `gui`                                               | Deferred module  | Reserved GUI aggregation point (currently mostly an empty merge root) |
| `apps.<name>`                                       | Deferred module  | Individual app modules loaded by key                                  |
| `context7Secrets`, `r2Secrets`, `virustotalSecrets` | Deferred modules | Optional SOPS-managed secret modules                                  |

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

The following apps are loaded by default for `vx@system76`:

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

Hosts append to `home-manager.extraAppImports`. The System76 host also appends matching app modules to `home-manager.sharedModules` in `modules/system76/home-manager-apps.nix`.

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

Home Manager CLI is not bundled by default. Run via:

```bash
nix develop -c nix run nixpkgs#home-manager -- --flake .#vx switch --dry-run
```

Or add `home-manager` to `modules/devshell.nix` for a persistent binary.

## Next Steps

- [Host Composition](05-host-composition.md) -- how hosts assemble these modules
- [Module Authoring](02-module-authoring.md) -- general authoring patterns
- [SOPS Usage](../sops/README.md) -- secrets management
