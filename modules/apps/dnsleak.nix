/*
  Package: dnsleak
  Description: Simple shell utility that checks outward-facing IP and resolvers to detect DNS leaks.
  Homepage: https://support.opendns.com/hc/en-us/articles/227987727-How-to-Test-If-OpenDNS-Is-Working
  Documentation: https://support.opendns.com/hc/en-us/articles/227987727-How-to-Test-If-OpenDNS-Is-Working
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Shows the current public IP as seen by OpenDNS (`myip.opendns.com`).
    * Lists the nameservers in `/etc/resolv.conf` to confirm VPN or DNS overrides.
*/
_:
let
  DnsleakModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dnsleak.extended;
    in
    {
      options.programs.dnsleak.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dnsleak.";
        };

        package = lib.mkPackageOption pkgs "dnsleak" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dnsleak = DnsleakModule;
}
