/*
  Package: kdiskmark
  Description: Qt-based disk benchmark inspired by CrystalDiskMark for Linux.
  Homepage: https://github.com/JonMagon/KDiskMark
  Documentation: https://github.com/JonMagon/KDiskMark#features
  Repository: https://github.com/JonMagon/KDiskMark

  Summary:
    * Measures sequential and random read/write performance using configurable test profiles and queue depths.
    * Saves HTML/PDF reports, displays graphs, and supports multiple languages with an intuitive GUI.

  Options:
    kdiskmark: Launch the graphical benchmark tool.
    Profiles menu: Select standard (SEQ1M Q8T1, RND4K Q32T16) or custom presets.
    Settings: Adjust block sizes, passes, and data sets for benchmarking.

  Example Usage:
    * `kdiskmark` — Start the GUI and run default sequential/random tests.
    * Choose “All” and click “Start” to benchmark both read and write performance.
    * Export results via “Save Report…” to archive benchmark outcomes.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.kdiskmark.extended;
  KdiskmarkModule = {
    options.programs.kdiskmark.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable kdiskmark.";
      };

      package = lib.mkPackageOption pkgs "kdiskmark" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.kdiskmark = KdiskmarkModule;
}
