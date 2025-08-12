# Module: pc/editor.nix
# Purpose: Editor configuration
# Namespace: flake.modules.nixos.pc
# Pattern: Personal computer configuration - Extends base for desktop systems

# modules/editor.nix

{
  flake.modules.nixos.pc.programs = {
    neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };
    nano.enable = false;
  };
}
