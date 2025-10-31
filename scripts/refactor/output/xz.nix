/*
  Package: xz
  Description: XZ Utils command-line compressor and decompressor built around the LZMA2 algorithm.
  Homepage: https://tukaani.org/xz/
  Documentation: https://tukaani.org/xz/man/xz.1.html
  Repository: https://github.com/tukaani-project/xz

  Summary:
    * Compresses and decompresses data using .xz and .lzma formats with high compression ratios and multi-threaded support.
    * Provides supporting scripts and library tooling (liblzma) compatible with POSIX environments and other compression utilities.

  Options:
    -z: Compress input data to the .xz format (default action when no mode flags are set).
    -d: Decompress .xz or .lzma streams with automatic format detection.
    -k: Keep original input files when compressing or decompressing.
    -T NUM: Run compression or decompression with NUM parallel threads when supported.
    --format=FORMAT: Force processing of a specific container format such as xz, lzma, or raw.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.xz.extended;
  XzModule = {
    options.programs.xz.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable xz.";
      };

      package = lib.mkPackageOption pkgs "xz" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.xz = XzModule;
}
