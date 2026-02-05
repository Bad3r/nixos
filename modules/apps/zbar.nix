/*
  Package: zbar
  Description: Bar code reader suite supporting QR codes and various 1D formats.
  Homepage: https://github.com/mchehab/zbar
  Documentation: https://github.com/mchehab/zbar
  Repository: https://github.com/mchehab/zbar

  Summary:
    * Decodes EAN-13/UPC-A, UPC-E, EAN-8, Code 128, Code 93, Code 39, QR Code, and more from images or video streams.
    * Provides zbarimg for scanning saved images and zbarcam for live video capture via V4L2.

  Options:
    -q, --quiet: Minimal output, only print decoded symbol data.
    --raw: Output decoded symbol data without converting charsets.
    -v, --verbose: Increase debug output level.
    --xml: Enable XML output format.
    -1, --oneshot: Exit after scanning one bar code.
    -d, --display: Enable display of images to screen during scanning.
*/
_:
let
  ZbarModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zbar.extended;
    in
    {
      options.programs.zbar.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable zbar.";
        };

        package = lib.mkPackageOption pkgs "zbar" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.zbar = ZbarModule;
}
