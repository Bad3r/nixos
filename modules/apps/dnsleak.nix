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

{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {

        dnsleak = pkgs.writeShellApplication {
          name = "dnsleak";
          runtimeInputs = with pkgs; [
            curl
            jq
            dnsutils
          ];
          text = ''
            set -euo pipefail

            echo "Testing DNS leak..."
            dig +short myip.opendns.com @resolver1.opendns.com

            echo "DNS servers in use:"
            grep nameserver /etc/resolv.conf
          '';
        };
      };
    };

  flake.nixosModules.apps.dnsleak =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        config.flake.packages.${pkgs.system}.dnsleak
      ];
    };

}
