_: {
  configurations.nixos.songbird.module = {
    # Install-time constant for this host: disk A was installed from a NixOS
    # 26.11pre image, so the value the plan assumed (26.05) does not apply.
    # Never bump on upgrades.
    system.stateVersion = "26.11";
  };
}
