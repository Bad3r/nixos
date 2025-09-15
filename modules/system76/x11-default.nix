_: {
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      # Make X11 the default; ignore Wayland for now
      services.displayManager.sddm.wayland.enable = lib.mkForce false;
      services.xserver.displayManager.defaultSession = lib.mkForce "plasma"; # X11 Plasma session
    };
}
