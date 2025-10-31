/*
  Package: ncdu
  Description: Disk usage analyzer with an ncurses interface.
  Homepage: https://dev.yorhel.nl/ncdu
  Documentation: https://dev.yorhel.nl/ncdu/man
  Repository: https://code.blicky.net/yorhel/ncdu

  Summary:
    * Provides an interactive terminal interface for exploring directory sizes and deleting files safely.
    * Efficiently scans large filesystems with configurable depth and supports exporting/importing scan data.

  Options:
    -o <file>: Export scan results to a file for later inspection.
    --exclude <pattern>: Skip directories matching a pattern.
    --prune: Remove entries that match the current filter from the disk.
    -x: Stay on a single filesystem and avoid crossing mount points.

  Example Usage:
    * `ncdu /var` — Investigate disk usage in `/var` and delete logs or caches interactively.
    * `ncdu -o scan.json /srv` — Capture usage data on a server for offline analysis.
    * `ncdu -x --exclude '/var/lib/docker/*' /var` — Audit a filesystem without crossing into container layers.
*/

{
  flake.homeManagerModules.apps.ncdu =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ncdu.extended;
    in
    {
      options.programs.ncdu.extended = {
        enable = lib.mkEnableOption "Disk usage analyzer with an ncurses interface.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.ncdu ];
      };
    };
}
