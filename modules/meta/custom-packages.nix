{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        hello-custom = pkgs.writeShellApplication {
          name = "hello-custom";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            echo "Hello from custom package!"
          '';
        };

        dnsleak-cli = pkgs.writeShellApplication {
          name = "dnsleak-cli";
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

  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        config.flake.packages.${pkgs.system}.hello-custom
        config.flake.packages.${pkgs.system}.dnsleak-cli
      ];
    };
}
