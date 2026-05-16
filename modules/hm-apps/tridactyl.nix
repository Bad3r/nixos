_: {
  flake.homeManagerModules.apps.tridactyl =
    { osConfig, lib, ... }:
    let
      firefoxEnabled = lib.attrByPath [ "programs" "firefox" "extended" "enable" ] false osConfig;
      librewolfEnabled = lib.attrByPath [ "programs" "librewolf" "extended" "enable" ] false osConfig;
      geckoTridactyl = import ./_gecko-tridactyl.nix { inherit lib; };
    in
    {
      config = lib.mkIf (firefoxEnabled || librewolfEnabled) {
        xdg.configFile = geckoTridactyl.configFile;
      };
    };
}
