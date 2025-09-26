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
  flake.nixosModules.apps.xz =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.xz ];
    };

}
