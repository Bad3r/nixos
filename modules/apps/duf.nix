/*
  Package: duf
  Description: Disk usage/free viewer that presents mount information with colored, column-aligned output.
  Homepage: https://github.com/muesli/duf
  Documentation: https://github.com/muesli/duf#readme
  Repository: https://github.com/muesli/duf

  Summary:
    * Lists mounted devices and network shares with human-readable sizes, sorting, and filtering.
    * Emits JSON for scripts.

  Options:
    --all: Include pseudo, duplicate, and inaccessible file systems in the listing.
    --only <type,...>: Restrict results to specific mount types (e.g. `--only local,network`).
    --sort <field>: Sort by size, usage, mount point, or other columns.
    --json: Emit machine-readable JSON instead of a table.
    --output <columns>: Choose which columns to display (e.g. `--output mount,size,usage`).
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
          description = "Whether to enable duf.";
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
