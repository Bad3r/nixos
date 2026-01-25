# Home Manager Modules

This document covers the Home Manager aggregator namespace and app loading mechanism.

## The `flake.homeManagerModules` Namespace

Home Manager modules feed into `flake.homeManagerModules` for user-level configuration:

| Key                            | Type             | Description                                  |
| ------------------------------ | ---------------- | -------------------------------------------- |
| `base`                         | Deferred module  | Bootstrap configuration (shell, git, etc.)   |
| `gui`                          | Deferred module  | GUI-specific helpers (Stylix desktop tweaks) |
| `apps.<name>`                  | Deferred module  | Individual app modules                       |
| `r2Secrets`, `context7Secrets` | Deferred modules | Optional SOPS-managed secrets                |

## Contributing to Namespaces

Multiple files can extend `base` or `gui` -- the loader merges them after evaluation:

```nix
# modules/files/fzf.nix
_: {
  flake.homeManagerModules.base = { pkgs, ... }: {
    programs.fzf.enable = true;
  };
}

# modules/terminal/alacritty.nix
_: {
  flake.homeManagerModules.gui = _: {
    programs.alacritty.enable = true;
  };
}
```

## Per-App Modules

App modules live under `modules/hm-apps/<name>.nix` and **must** export functions:

```nix
# modules/hm-apps/kitty.nix
_: {
  flake.homeManagerModules.apps.kitty = _: {
    programs.kitty.enable = true;
  };
}
```

**Key requirement:** The filename must match the export key (`kitty.nix` exports `apps.kitty`).

## App Loading Mechanism

The glue layer in `modules/home-manager/nixos.nix` loads apps by resolving file paths:

```nix
loadAppModule = name:
  let
    filePath = ../hm-apps + "/${name}.nix";
  in
  if builtins.pathExists filePath then
    loadHomeModule filePath [ "flake" "homeManagerModules" "apps" name ]
  else
    throw ("Home Manager app module file not found: " + toString filePath);
```

### Default App Imports

The following apps are loaded by default for `vx@system76`:

```nix
defaultAppImports = [
  "codex"
  "bat"
  "eza"
  "fzf"
  "ghq-mirror"
  "kitty"
  "alacritty"
  "wezterm"
];
```

### Adding Extra Apps

Hosts can append to `home-manager.extraAppImports`:

```nix
# modules/system76/home-manager-apps.nix
{
  home-manager.extraAppImports = [
    "espanso"
    "direnv"
  ];
}
```

## Authoring Rules

1. **Always export a module value** -- export under `flake.homeManagerModules.*`
2. **Guard optional modules** -- check for secret/package availability in the module body
3. **Keep names stable** -- the key under `apps.<name>` must match the filename
4. **Document secrets** -- reference `docs/sops/README.md` when credentials are needed

## Secrets Integration

Home-level secrets helpers guard SOPS declarations behind `builtins.pathExists`:

```nix
# modules/home/context7-secrets.nix
{ config, lib, ... }:
let
  secretPath = ../../secrets/context7.yaml;
in
lib.mkIf (builtins.pathExists secretPath) {
  sops.secrets."context7/api-key" = {
    sopsFile = secretPath;
    # ...
  };
}
```

This ensures evaluation succeeds even when secret files don't exist.

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
