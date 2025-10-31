/*
  Package: yaak
  Description: Yet Another API Client - Desktop app for testing APIs
*/
_:
let
  YaakModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.yaak.extended;
    in
    {
      options.programs.yaak.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable yaak.";
        };

        package = lib.mkPackageOption pkgs "yaak" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.yaak = YaakModule;
}
