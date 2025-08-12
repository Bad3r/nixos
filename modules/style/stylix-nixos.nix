{ inputs, lib, ... }:
{
  flake.modules.nixos.base = {
    imports = [ inputs.stylix.nixosModules.stylix ];
    stylix = {
      enable = lib.mkDefault true;
      # Disable automatic Home-Manager import to avoid conflicts
      # Home-Manager stylix is handled separately in stylix-home.nix
      homeManagerIntegration.autoImport = false;
    };
  };
}