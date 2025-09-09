{
  flake.modules.homeManager.gui = _: {
    programs.kitty = {
      enable = true;
      # Ensure kitty is set as default terminal in user session
      settings = {
        # Add any kitty-specific settings here if needed
      };
    };
  };
}
