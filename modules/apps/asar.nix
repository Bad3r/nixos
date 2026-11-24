/*
  Package: asar
  Description: Electron archive format tool.
  Homepage: https://github.com/electron/asar
  Documentation: https://github.com/electron/asar#readme
  Repository: https://github.com/electron/asar

  Summary:
    * Lists, extracts, and packs Electron `app.asar` archives.
*/
_:
let
  AsarModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.asar.extended;
    in
    {
      options.programs.asar.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable asar.";
        };

        package = lib.mkPackageOption pkgs "asar" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.asar = AsarModule;
}
