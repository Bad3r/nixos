{
  # Define Home Manager roles as simple data: lists of app keys.
  # These are resolved to actual modules at the NixOS→HM glue layer.
  flake.lib.homeManager.roles = {
    cli = [
      "bat"
      "eza"
      "fzf"
    ];
    terminals = [
      "kitty"
      "alacritty"
      "wezterm"
    ];
  };
}
