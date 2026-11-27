/*
  Package: atuin
  Description: Encrypted, synchronized shell history manager with powerful search.
  Homepage: https://atuin.sh/
*/

_: {
  flake.homeManagerModules.apps.atuin =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "atuin" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.atuin = {
          enable = true;
          package = lib.attrByPath [ "programs" "atuin" "extended" "package" ] pkgs.atuin osConfig;
          # The arrows stay on zsh's prefix history search (modules/shell/zsh/keybindings.nix).
          flags = [ "--disable-up-arrow" ];
          settings = {
            # Only atuin's first-run config file sets this, and Home Manager replaces that file.
            enter_accept = true;
            # Unbinds `?` and turns off the Atuin Hub chat.
            ai.enabled = false;
          };
        };
      };
    };
}
