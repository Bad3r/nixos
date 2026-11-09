/*
  Package: camoufox
  Description: Firefox build that spoofs a consistent device fingerprint, driven through Playwright.
  Homepage: https://camoufox.com/
  Repository: https://github.com/daijro/camoufox

  Notes:
    * Uses the browser packaged in packages/camoufox.
    * Bundled Linux fonts include nonfree Adobe fonts.
*/
_:
let
  CamoufoxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.camoufox.extended;
    in
    {
      options.programs.camoufox.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Camoufox.";
        };

        package = lib.mkPackageOption pkgs "camoufox" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "camoufox" ];
  flake.nixosModules.browsers.camoufox = CamoufoxModule;
}
