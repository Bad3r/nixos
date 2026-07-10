{
  configurations.nixos.tpnix.module = {
    # Install-time constant for this host. Never bump on upgrades.
    system.stateVersion = "26.05";
  };
}
