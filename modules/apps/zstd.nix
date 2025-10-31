/*
  Package: zstd
  Description: Zstandard command-line tool and library for fast, real-time compression.
  Homepage: https://facebook.github.io/zstd/
  Documentation: https://facebook.github.io/zstd/zstd_manual.html
  Repository: https://github.com/facebook/zstd

  Summary:
    * Provides zstd, zstdcat, zstdmt, and ancillary tools built around the LZMA2-inspired Zstandard algorithm with tunable speed/ratio trade-offs.
    * Supports dictionary-based compression, streaming APIs, and transparent integration with tar, grep, and other Unix workflows.

  Options:
    -d: Decompress input streams, auto-detecting .zst and .tzst containers.
    -# (0–19): Choose compression level; higher values improve ratio at the cost of CPU time.
    -T# : Compress or decompress using the specified number of worker threads.
    --long=WINDOW: Enable large window sizes for high-compression scenarios and long-distance matching.
    --adapt: Dynamically adjust compression parameters for mixed workloads.

  Example Usage:
    * `zstd -19 dataset.csv` — Compress large datasets with maximum ratio.
    * `zstd -d -c logs.zst | jq '.message'` — Stream-decompress into another command without creating intermediate files.
    * `zstd --adapt -T0 < input.bin > output.zst` — Compress mixed workloads using all available cores with adaptive tuning.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ZstdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zstd.extended;
    in
    {
      options.programs.zstd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable zstd.";
        };

        package = lib.mkPackageOption pkgs "zstd" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.zstd = ZstdModule;
}
