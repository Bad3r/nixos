/*
  Package: dust
  Description: du alternative that visualizes disk usage with tree-based bar charts.
  Homepage: https://github.com/bootandy/dust
  Documentation: https://github.com/bootandy/dust#readme
  Repository: https://github.com/bootandy/dust

  Summary:
    * Shows directory trees ordered by size with colored bar charts, so large paths stand out.
    * Supports depth limits, ignore patterns, and file counts.

  Options:
    -d <depth>: Limit traversal to the specified directory depth.
    -n <count>: Show only the top N biggest entries.
    -x: Stay on the current filesystem (do not cross mount points).
    --filecount: Display the number of files in each directory.
    --ignore-directory <pattern>: Skip directories matching the given pattern.
*/
_:
let
  DustModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dust.extended;
    in
    {
      options.programs.dust.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dust.";
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
