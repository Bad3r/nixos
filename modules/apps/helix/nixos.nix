/*
  Package: helix
  Description: Post-modern modal text editor.
  Homepage: https://helix-editor.com
  Documentation: https://docs.helix-editor.com
  Repository: https://github.com/helix-editor/helix

  Summary:
    * Modal editing with multiple selections as a core feature.
    * Built-in language server support.

  Options:
    -h: Print help.
    -c: Specify a config file.

  Notes:
    * Home Manager installs `package` wrapped with its language servers and formatters (modules/apps/helix/home.nix).
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

        package = lib.mkPackageOption pkgs "helix" { };
      };
    };
in
{
  flake.nixosModules.apps.helix = HelixModule;
}
