{
  configurations.nixos.system76.module = {
    xdg = {
      menus.enable = true;
      mime.enable = true;
      # Browser defaults are set by HM browser modules (floorp.nix, etc.)
      # User-level ~/.config/mimeapps.list always overrides system-level
    };
  };
}
