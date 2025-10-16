{ config, lib, ... }:
let
  fallbackRole =
    if lib.hasAttrByPath [ "roles" "system" "display" "x11" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "roles" "system" "display" "x11" ] config.flake.nixosModules
    else
      throw "roles.xserver: roles.system.display.x11 missing";
in
{
  flake.nixosModules.roles.xserver = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ fallbackRole ];
  };
}
