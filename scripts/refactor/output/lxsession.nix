/*
  Package: lxsession
  Description: Lightweight session manager for LXDE providing autostart, authentication, and environment setup.
  Homepage: https://wiki.lxde.org/en/LXSession
  Documentation: https://wiki.lxde.org/en/LXSession
  Repository: https://github.com/lxde/lxsession

  Summary:
    * Manages X11 desktop sessions by launching components specified in `/etc/xdg/lxsession` or user autostart directories.
    * Provides utilities like `lxsession-default-apps` for configuring default browsers, terminals, and compositors in LXDE environments.

  Options:
    lxsession: Start an LXDE session using the default profile.
    lxsession -s <session>: Launch a specific session profile (e.g. `LXDE` or custom names).
    lxsession -e <ENVS>: Override environment variables supplied to the session.
    lxsession-default-apps: Configure preferred applications via a GUI.

  Example Usage:
    * `lxsession -s LXDE` — Start an LXDE session manually from a display manager or console.
    * `lxsession-default-apps` — Adjust default web browser, terminal, and file manager for the session.
    * Create `~/.config/lxsession/LXDE/autostart` to launch custom applications when the session starts.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lxsession.extended;
  LxsessionModule = {
    options.programs.lxsession.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable lxsession.";
      };

      package = lib.mkPackageOption pkgs "lxsession" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.lxsession = LxsessionModule;
}
