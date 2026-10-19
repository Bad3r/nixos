_: {
  configurations.nixos.tpnix.module = {
    # Enable LVFS firmware updates
    services.fwupd.enable = true;
  };
}
