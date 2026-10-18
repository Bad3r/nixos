# Espanso Text Expander Module

The espanso module configures the cross-platform text expander declaratively, through Home Manager's `services.espanso` module with repo defaults and common match patterns.

- [Matches](espanso-matches.md): custom matches, variables, and regex triggers.
- [Configuration](espanso-configuration.md): app-specific configs, display-server support, and the package.

## Enabling espanso

Two modules cooperate behind a single system-level toggle:

- `flake.nixosModules.apps.espanso`, from `modules/apps/espanso/nixos.nix`, declares the row's option `services.espanso.extended.enable`, default `false`.
- `flake.homeManagerModules.apps.espanso`, from `modules/apps/espanso/home.nix`, reads that toggle from `osConfig` and configures `services.espanso` only when it is `true`.

Importing the Home Manager module alone does nothing, because the toggle must be on at the system level.

### Common-baseline hosts

Hosts whose registry entry has `shareCommon = true` receive espanso through the common host modules:

- `modules/hosts/common/home-manager-apps.nix` adds `flake.homeManagerModules.apps.espanso`, with every other Home Manager app module, to `home-manager.sharedModules`.
- `modules/hosts/common/apps-enable.nix` turns the `espanso` row on in its `services` block at `lib.mkOverride 1100`.

Those hosts need no separate Home Manager import.
They customize `services.espanso.matches` in Home Manager configuration, and a host opts out with `espanso = false` in its app rows, as [App registry](../guides/apps-module-registry.md) describes.

### Hosts outside the common baseline

A host that does not use `hosts-common` needs a flake-parts module that pushes both the NixOS option module and the Home Manager app module into the host module:

```nix
{ config, ... }:
let
  espansoModule = config.flake.nixosModules.apps.espanso;
in
{
  configurations.nixos.<hostName>.module = _: {
    imports = [ espansoModule ];

    services.espanso.extended.enable = true;
    home-manager.sharedModules = [ config.flake.homeManagerModules.apps.espanso ];
  };
}
```

## Default Triggers

When enabled, espanso starts with notifications off and these triggers, where `:test` is a smoke test:

<!-- dprint-ignore-start -->

| Trigger       | Output            | Example                                             |
| ------------- | ----------------- | --------------------------------------------------- |
| `:test`       | Smoke-test string | `test 1.2.3`                                        |
| `:date`       | Current date      | `2025-10-08`                                        |
| `:time`       | Current time      | `14:30`                                             |
| `:now`        | Date and time     | `2025-10-08 14:30`                                  |
| `:isodate`    | ISO 8601 format   | `2025-10-08T14:30:00+0000`                          |
| `:shebang`    | Bash shebang      | `#!/usr/bin/env bash`                               |
| `:shebangnix` | Nix-shell shebang | `#!/usr/bin/env nix-shell`<br>`#!nix-shell -i bash` |
| `:todo`       | `TODO` comment    | `# TODO: `                                          |
| `:fixme`      | `FIXME` comment   | `# FIXME: `                                         |

<!-- dprint-ignore-end -->

## Service Management

Home Manager runs espanso as a systemd user service:

```bash
systemctl --user status espanso
systemctl --user restart espanso
journalctl --user -u espanso -f
```

The generated YAML lands in `~/.config/espanso/config/*.yml` (configuration) and `~/.config/espanso/match/*.yml` (matches).
Nix manages both declaratively, so Home Manager activation overwrites manual edits.

## Troubleshooting

### Espanso Not Triggering

1. Check that the service runs: `systemctl --user status espanso`.
2. Read its logs: `journalctl --user -u espanso`.
3. Type the `:test` trigger, which expands to `test 1.2.3`.
4. Try another backend for the application, such as `backend = "Clipboard"` in an [app-specific config](espanso-configuration.md#app-specific-configurations).

### Wayland Clipboard Issues

On a multi-user Wayland setup, grant access to the Wayland runtime directory; `username` stands for the user, and `usermod` needs root:

```bash
echo $XDG_RUNTIME_DIR
sudo usermod -a -G username espanso
chmod g+rwx $XDG_RUNTIME_DIR
chmod g+w $XDG_RUNTIME_DIR/wayland-0
```

### Application Compatibility

Some applications need the clipboard backend:

```nix
{
  services.espanso.configs.incompatible-app = {
    filter_title = "AppName$";
    backend = "Clipboard";
  };
}
```

## References

- Official documentation: <https://espanso.org/docs/>
- Variables reference: <https://espanso.org/docs/matches/extensions/>
- nixpkgs package: `pkgs/by-name/es/espanso/package.nix`
- Home Manager module: `/data/git/nix-community-home-manager/modules/services/espanso.nix`
