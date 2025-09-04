_: {
  flake.modules.nixos.pc = {
    # Enable native Wayland support for Chromium and Electron applications
    # This prevents GPU process crashes and WebGL failures on Wayland
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };
}
