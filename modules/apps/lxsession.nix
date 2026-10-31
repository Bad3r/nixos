/*
  Package: lxsession
  Description: Lightweight session manager for LXDE providing autostart, authentication, and environment setup.
  Homepage: https://wiki.lxde.org/en/LXSession
  Documentation: https://wiki.lxde.org/en/LXSession
  Repository: https://github.com/lxde/lxsession

  Summary:
    * Manages X11 desktop sessions by launching components from `/etc/xdg/lxsession` or user autostart directories.
    * Provides `lxsession-default-apps` for configuring default browsers, terminals, and compositors.

  Options:
    lxsession -s <session>: Launch a specific session profile (e.g. `LXDE` or custom names).
    lxsession -e <ENVS>: Override environment variables supplied to the session.
*/
_:
let
  LxsessionModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lxsession.extended;
    in
    {
      options.programs.lxsession.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lxsession.";
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
