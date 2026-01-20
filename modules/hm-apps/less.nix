/*
  Package: less
  Description: Terminal pager program for viewing text files.
  Homepage: https://www.greenwoodsoftware.com/less/
*/

_: {
  flake.homeManagerModules.apps.less =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "less" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.less = {
          enable = true;
          package = null; # Package installed by NixOS module
        };
      };
    };
}
