{
  flake.modules.nixos = {
    base = {
      # Base visual settings for ALL systems
      stylix.targets.grub.enable = false;
      boot.kernelParams = [
        "quiet"
        "systemd.show_status=error"
      ];
    };
    pc = {
      # Plymouth only for desktop/laptop systems (servers don't need it)
      boot.plymouth.enable = true;
    };
  };
}