/*
  Package: qrencode
  Description: C library and command line tool for encoding data in a QR Code symbol.
  Homepage: https://fukuchi.org/works/qrencode/
  Documentation: https://fukuchi.org/works/qrencode/
  Repository: https://github.com/fukuchi/libqrencode

  Summary:
    * Encodes text or binary data into QR Code symbols and outputs PNG, SVG, or terminal-renderable formats.
    * Supports configurable error correction levels (L/M/Q/H) and Micro QR Code generation.

  Options:
    -o FILENAME: write image to FILENAME; use `-` for stdout.
    -t TYPE: output format — PNG, SVG, EPS, UTF8, ANSIUTF8, ASCII (default=PNG).
    -s NUMBER: module size in pixels (default=3).
    -l {LMQH}: error correction level from L (lowest) to H (highest) (default=L).
    -m NUMBER: margin width in modules (default=4).
    -M: encode as Micro QR Code.
*/
_:
let
  QrencodeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.qrencode.extended;
    in
    {
      options.programs.qrencode.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable qrencode.";
        };

        package = lib.mkPackageOption pkgs "qrencode" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.qrencode = QrencodeModule;
}
