{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      programs.kitty = {
        enable = true;
        # Ensure kitty is set as default terminal in user session
        settings = {
          # Add any kitty-specific settings here if needed
        };
      };
    };
}
