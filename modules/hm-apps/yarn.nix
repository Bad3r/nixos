/*
  Package: yarn
  Description: Fast, reliable, and secure dependency management for JavaScript.
  Homepage: https://yarnpkg.com/
*/

_: {
  flake.homeManagerModules.apps.yarn =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "yarn" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.yarn = {
          enable = true;
          # No package option - HM yarn module only manages config file
        };
      };
    };
}
