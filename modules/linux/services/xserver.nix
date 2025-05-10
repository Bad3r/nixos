# modules/linux/services/xserver.nix

{
  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;
    # Configure keymap in X11
    xkb = {
      layout = "us";
      variant = "";
    };
  };
  # Configure console keymap
  console.keyMap = "us";
}
