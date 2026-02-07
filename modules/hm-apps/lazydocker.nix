/*
  Package: lazydocker
  Description: Simple terminal UI for both Docker and Docker Compose.
  Homepage: https://github.com/jesseduffield/lazydocker
  Documentation: https://github.com/jesseduffield/lazydocker/blob/master/README.md
  Repository: https://github.com/jesseduffield/lazydocker

  Summary:
    * Enables Home Manager configuration management for lazydocker.
    * Delegates package installation to the NixOS module (package = null).

  Notes:
    * Theme uses ANSI color names which Stylix remaps to base16 values via the terminal palette.
    * Upstream defaults to macOS `open` command; overridden to `xdg-open` for NixOS.
*/
_: {
  flake.homeManagerModules.apps.lazydocker =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "lazydocker" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.lazydocker = {
          enable = true;
          package = null;
          settings = {
            gui.theme = {
              activeBorderColor = [
                "blue"
                "bold"
              ];
              inactiveBorderColor = [ "default" ];
              selectedLineBgColor = [ "blue" ];
              optionsTextColor = [ "blue" ];
            };
            oS = {
              openCommand = "xdg-open {{filename}}";
              openLinkCommand = "xdg-open {{link}}";
            };
          };
        };
      };
    };
}
