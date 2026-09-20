/*
  Package: atuin
  Description: Encrypted, synchronized shell history manager with powerful search.
  Homepage: https://atuin.sh/
*/

_: {
  flake.homeManagerModules.apps.atuin =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "atuin" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.atuin = {
          enable = true;
          # The arrows stay on zsh's prefix history search (modules/shell/zsh/keybindings.nix).
          flags = [ "--disable-up-arrow" ];
          # Only atuin's first-run config file sets this, and Home Manager replaces that file.
          settings.enter_accept = true;
        };
      };
    };
}
