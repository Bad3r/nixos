/*
  Package: thunderbird
  Description: Home Manager integration for Thunderbird profile and account settings.
  Homepage: https://thunderbird.net/
  Documentation: https://nix-community.github.io/home-manager/options.xhtml#opt-programs.thunderbird.enable
  Repository: https://github.com/nix-community/home-manager

  Notes:
    * Enabled only when `programs.thunderbird.extended.enable` is true in the NixOS configuration.
    * `programs.thunderbird.package` is non-nullable in Home Manager, so package delegation uses defaults.
    * Declares a default `main` profile to support declarative Thunderbird state.
*/
_: {
  flake.homeManagerModules.apps.thunderbird =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "thunderbird" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.thunderbird = {
          enable = true;
          profiles.main = {
            isDefault = true;
            withExternalGnupg = true;
            settings = {
              "mailnews.start_page.enabled" = false;
            };
          };
        };
      };
    };
}
