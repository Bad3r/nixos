/*
  Package: dust
  Description: du alternative that visualizes disk usage with interactive, tree-based bar charts.
  Homepage: https://github.com/bootandy/dust
  Documentation: https://github.com/bootandy/dust#readme
  Repository: https://github.com/bootandy/dust

  Summary:
    * Displays directory trees ordered by size using colored Unicode bar charts for quick identification of large paths.
    * Offers interactive navigation, JSON output, and ignore patterns for scripting or exploratory cleanup.

  Options:
    -d <depth>: Limit traversal to the specified directory depth.
    -n <count>: Show only the top N biggest entries.
    -x: Stay on the current filesystem (do not cross mount points).
    --filecount: Display the number of files in each directory.
    --ignore-directory <pattern>: Skip directories matching the given pattern.

  Example Usage:
    * `dust` — Render an interactive overview of disk usage under the current directory.
    * `dust -d 2 /var` — Inspect the largest directories within `/var` up to depth 2.
    * `dust -n 10 --ignore-directory node_modules project/` — Show the top ten space consumers while ignoring `node_modules`.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.dust.extended;
  DustModule = {
    options.programs.dust.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable dust.";
      };

      package = lib.mkPackageOption pkgs "dust" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.dust = DustModule;
}
