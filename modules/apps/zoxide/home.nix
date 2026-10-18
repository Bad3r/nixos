/*
  Package: zoxide
  Description: Smarter cd command with learning capabilities.
  Homepage: https://github.com/ajeetdsouza/zoxide
*/

_: {
  flake.homeManagerModules.apps.zoxide =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "zoxide" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.zoxide = {
          enable = true;
          package = lib.attrByPath [ "programs" "zoxide" "extended" "package" ] pkgs.zoxide osConfig;
          # `j` and `ji` instead of `z` and `zi`.
          options = [
            "--cmd"
            "j"
          ];
        };

        programs.zsh.shellAliases = {
          ja = "zoxide add";
          jr = "zoxide remove";
          jri = "zoxide remove -i";
        };
      };
    };
}
