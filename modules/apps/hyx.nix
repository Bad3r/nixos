/*
  Package: hyx
  Description: Minimalistic console hex editor.
  Homepage: https://yx7.cc/code/
  Documentation: https://yx7.cc/code/hyx/
  Repository: https://yx7.cc/code/hyx/

  Summary:
    * Edits binary files in the terminal with a hex and ASCII view, insert and overwrite modes, and undo.
    * Streams large files without loading them whole.
*/
_:
let
  HyxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hyx.extended;
    in
    {
      options.programs.hyx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hyx.";
        };

        package = lib.mkPackageOption pkgs "hyx" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.hyx = HyxModule;
}
