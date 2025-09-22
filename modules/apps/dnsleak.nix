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

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        config.flake.packages.${pkgs.system}.dnsleak
      ];
    };
}
