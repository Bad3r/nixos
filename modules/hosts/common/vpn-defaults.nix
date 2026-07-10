# DNS and firewall defaults for the VPN clients shipped on shared hosts.
{ lib, ... }:
let
  body = {
    services.resolved.enable = lib.mkDefault true;
    # VPN clients route asymmetrically; strict rpfilter would drop return traffic.
    networking.firewall.checkReversePath = lib.mkDefault "loose";
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
