{ lib, ... }:
{
  flake.modules.nixos.pc = _: {
    # Enable necessary services for VPN functionality
    services.resolved.enable = lib.mkDefault true;
    # Prefer loose reverse path filtering unless a later module overrides it
    networking.firewall.checkReversePath = lib.mkAfter "loose";
  };
}
