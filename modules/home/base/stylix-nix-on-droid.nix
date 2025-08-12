{ inputs, lib, ... }:
{
  flake.modules.nixOnDroid.base = {
    imports = [ inputs.stylix.nixOnDroidModules.stylix ];
    stylix.enable = lib.mkDefault true;
  };
}