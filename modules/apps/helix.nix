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
*/
_:
let
  HelixModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.helix.extended;
    in
    {
      options.programs.helix.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable helix.";
        };

        package = lib.mkPackageOption pkgs "helix" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.helix = HelixModule;
}
