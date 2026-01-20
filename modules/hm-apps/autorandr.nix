/*
  Package: autorandr
  Description: Automatic display configuration based on connected devices.
  Homepage: https://github.com/phillipberndt/autorandr
*/

_: {
  flake.homeManagerModules.apps.autorandr =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "services" "autorandr" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.autorandr = {
          enable = true;
        };
      };
    };
}
