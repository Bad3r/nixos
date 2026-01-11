/*
  Package: upscayl
  Description: Free and open source AI image upscaler.
  Homepage: https://upscayl.github.io/
  Documentation: https://github.com/upscayl/upscayl/wiki
  Repository: https://github.com/upscayl/upscayl

  Summary:
    * Cross-platform desktop application that uses AI models to upscale and enhance images without quality loss.
    * Supports batch processing and multiple AI models including Real-ESRGAN for various upscaling scenarios.
*/
_:
let
  UpscaylModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.upscayl.extended;
    in
    {
      options.programs.upscayl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable upscayl.";
        };

        package = lib.mkPackageOption pkgs "upscayl" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.upscayl = UpscaylModule;
}
