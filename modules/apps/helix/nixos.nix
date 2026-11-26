/*
  Package: evil-helix
  Description: Post-modern modal text editor with Vim keybindings.
  Homepage: https://github.com/usagi-flow/evil-helix
  Documentation: https://github.com/usagi-flow/evil-helix#readme
  Repository: https://github.com/usagi-flow/evil-helix

  Summary:
    * Helix fork with Vim-style normal, insert, and visual editing, enabled by `editor.evil`.
    * Keeps multiple selections and built-in language server support.

  Options:
    -h: Print help.
    -c: Specify a config file.
*/
_:
let
  HelixModule =
    { lib, pkgs, ... }:
    {
      options.programs.helix.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable helix.";
        };

        package = lib.mkPackageOption pkgs "evil-helix" { };
      };
    };
in
{
  flake.nixosModules.apps.helix = HelixModule;
}
