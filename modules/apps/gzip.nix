/*
  Package: gzip
  Description: GNU gzip utility for compressing and decompressing files using the DEFLATE algorithm.
  Homepage: https://www.gnu.org/software/gzip/
  Documentation: https://www.gnu.org/software/gzip/manual/gzip.html
  Repository: https://git.savannah.gnu.org/git/gzip.git

  Summary:
    * Provides the `gzip`, `gunzip`, and `zcat` commands along with compatible library routines for .gz archives.
    * Supports transparent decompression via shell pipelines and retains file metadata during compression when requested.

  Options:
    -k, --keep: Retain original files after compression or decompression.
    -d, --decompress: Force decompression when invoking `gzip`.
    -1 .. -9: Select compression level (fast to best).
    -r, --recursive: Operate on files within directories recursively.
    -l, --list: Display compression ratios and statistics for .gz files.
*/
_:
let
  GzipModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gzip.extended;
    in
    {
      options.programs.gzip.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gzip.";
        };

        package = lib.mkPackageOption pkgs "gzip" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gzip = GzipModule;
}
