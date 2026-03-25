/*
  Package: onlyoffice-desktopeditors
  Description: Home Manager integration for ONLYOFFICE Desktop Editors preferences.
  Homepage: https://www.onlyoffice.com/desktop.aspx
  Documentation: https://nix-community.github.io/home-manager/options.xhtml#opt-programs.onlyoffice.enable
  Repository: https://github.com/nix-community/home-manager

  Notes:
    * Enabled only when `programs.onlyoffice-desktopeditors.extended.enable` is true in the NixOS configuration.
    * `programs.onlyoffice.package` is nullable in Home Manager, so `package = null` delegates installation to NixOS.
*/
_: {
  flake.homeManagerModules.apps.onlyoffice-desktopeditors =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [
        "programs"
        "onlyoffice-desktopeditors"
        "extended"
        "enable"
      ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.onlyoffice = {
          enable = true;
          package = null;
        };
      };
    };
}
