/*
  Package: mosh
  Description: Mobile shell (ssh replacement).
  Homepage: https://mosh.org/
  Documentation: https://mosh.org/
  Repository: https://github.com/mobile-shell/mosh

  Summary:
    * Keeps interactive remote shells responsive across roaming, packet loss, and changing client IPs.
    * Uses SSH for initial authentication, then switches to a UDP-based stateful transport.

  Options:
    --ssh=COMMAND: Use a custom SSH client or argument set for the initial handshake.
    --family=all|inet|inet6|prefer-inet|prefer-inet6: Control IPv4 or IPv6 selection.
*/
_:
let
  MoshModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mosh.extended;
    in
    {
      options.programs.mosh.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mosh.";
        };

        package = lib.mkPackageOption pkgs "mosh" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mosh = MoshModule;
}
