/*
  Package: duf
  Description: Disk usage/free viewer that presents mount information with colored, column-aligned output.
  Homepage: https://github.com/muesli/duf
  Documentation: https://github.com/muesli/duf#readme
  Repository: https://github.com/muesli/duf

  Summary:
    * Lists mounted devices, snap volumes, and remote shares with human-readable sizes, sorting, and filtering controls.
    * Supports JSON output for automation and theming options for desktop or terminal integration.

  Options:
    --all: Include pseudo, duplicate, and inaccessible file systems in the listing.
    --only <type,...>: Restrict results to specific mount types (e.g. `--only local,network`).
    --sort <field>: Sort by size, usage, mount point, or other columns.
    --json: Emit machine-readable JSON instead of a table.
    --output <columns>: Choose which columns to display (e.g. `--output mount,size,usage`).

  Example Usage:
    * `duf` — Display disk usage for local filesystems with a colored summary.
    * `duf --only local --sort usage` — Focus on local mounts and sort by utilization.
    * `duf --json | jq '.[] | {mount, usage}'` — Feed JSON output into other tools for scripting.
*/
_:
let
  DufModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.duf.extended;
    in
    {
      options.programs.duf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable duf.";
        };

        package = lib.mkPackageOption pkgs "duf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.duf = DufModule;
}
