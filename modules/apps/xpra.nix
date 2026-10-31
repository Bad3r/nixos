/*
  Package: xpra
  Description: Persistent remote display server and client for X11 applications.
  Homepage: https://xpra.org/
  Documentation: https://github.com/Xpra-org/xpra/tree/master/docs
  Repository: https://github.com/Xpra-org/xpra

  Summary:
    * Runs X11 applications in a virtual display on another host and shows their windows locally, like `ssh -X` with compressed encodings and sessions that survive disconnects.
    * Syncs the clipboard and forwards audio over its own connection.

  Options:
    seamless ssh://<host>/ "<command>": Start <command> on <host>, show its windows here, and end the session when it exits.
    attach ssh://<host>/: Reattach to a running session after a disconnect.
    stop ssh://<host>/: Stop the remote session.
    list: List the sessions on this host.
*/
_:
let
  XpraModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xpra.extended;
    in
    {
      options.programs.xpra.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xpra.";
        };

        package = lib.mkPackageOption pkgs "xpra" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # OpenSSH instead of the auto-selected paramiko backend; -x since the Mesh host entries set ForwardX11.
        environment.etc."xpra/xpra.conf".text = ''
          ssh = ssh -x
        '';
      };
    };
in
{
  flake.nixosModules.apps.xpra = XpraModule;
}
