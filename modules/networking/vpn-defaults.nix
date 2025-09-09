{
  flake.modules.nixos.pc = _: {
    # Enable necessary services for VPN functionality
    services.resolved.enable = true;
    networking.firewall.checkReversePath = "loose";
  };
}
