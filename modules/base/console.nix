{ lib, ... }:
{
  flake.nixosModules.base = {
    # Enable Stylix theming for console
    stylix.targets.console.enable = lib.mkDefault true;

    console.keyMap = "us";
  };
}
