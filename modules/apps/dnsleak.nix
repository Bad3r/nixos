/*
  Package: dnsleak
  Description: Simple shell utility that checks outward-facing IP and resolvers to detect DNS leaks.
  Homepage: https://support.opendns.com/hc/en-us/articles/227987727-How-to-Test-If-OpenDNS-Is-Working
  Documentation: https://support.opendns.com/hc/en-us/articles/227987727-How-to-Test-If-OpenDNS-Is-Working
  Repository: https://github.com/vx/nixos

  Summary:
    * Queries OpenDNS (`myip.opendns.com`) to display your current public IP and ensure resolvers route through the expected service.
    * Prints the nameservers configured in `/etc/resolv.conf` so you can confirm VPN or DNS overrides are active.

  Options:
    dnsleak: Run the check; no additional flags are required.

  Example Usage:
    * `dnsleak` — Display the detected public IP and the DNS servers listed in `/etc/resolv.conf`.
    * `dnsleak | tee /tmp/dnsleak.log` — Capture the output for auditing or support tickets.
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
          description = lib.mdDoc "Whether to enable dnsleak.";
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
