# DNS and firewall defaults for the VPN clients shipped on shared hosts.
{ lib, ... }:
let
  body = _: {
    config = {
      services.resolved.enable = lib.mkDefault true;
      # Prefer loose reverse path filtering unless a later module overrides it
      networking.firewall.checkReversePath = lib.mkAfter "loose";
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
