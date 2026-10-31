/*
  Package: krita
  Description: Free and open source painting application.
  Homepage: https://krita.org/
  Documentation: https://docs.krita.org/
  Repository: https://invent.kde.org/graphics/krita

  Summary:
    * Digital painting and illustration with brushes, layers, and advanced color management.
*/
_:
let
  KritaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.krita.extended;
    in
    {
      options.programs.krita.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable krita.";
        };

        package = lib.mkPackageOption pkgs "krita" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.krita = KritaModule;
}
