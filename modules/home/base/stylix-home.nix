{ inputs, lib, ... }:
{
  flake.modules.homeManager.base = {
    imports = [ inputs.stylix.homeModules.stylix ];
    stylix.enable = lib.mkDefault true;
  };
}