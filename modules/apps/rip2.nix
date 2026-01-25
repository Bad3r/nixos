/*
  Package: rip2
  Description: Safe alternative to `rm` that uses a trash bin with undo support.
  Homepage: https://github.com/MilesCranmer/rip2
  Documentation: https://github.com/MilesCranmer/rip2#usage
  Repository: https://github.com/MilesCranmer/rip2

  Summary:
    * Moves files to a trash directory instead of deleting them outright, storing metadata to allow restoration.
    * Provides commands to list trash contents, restore items, and purge older entries according to retention policy.

  Options:
    rip <paths>: Move files/directories to the trash.
    rip ls: List trashed items with deletion times.
    rip undo [index]: Restore the last (or specified) deleted item.
    rip purge [--days N]: Permanently remove trashed items, optionally older than N days.

  Example Usage:
    * `rip src/old_module` -- Safely remove a directory while keeping the ability to restore it.
    * `rip ls` -- Inspect recently removed files stored in the trash.
    * `rip undo` -- Restore the most recently removed item to its original location.
*/

let
  ripModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rip2.extended;
    in
    {
      options.programs.rip2.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable rip2 safe rm alternative with trash support.";
        };

        package = lib.mkPackageOption pkgs "rip2" { };

        graveyardPath = lib.mkOption {
          type = lib.types.str;
          default = "/tmp/rip-graveyard";
          description = ''
            Directory where deleted files are moved to.

            Defaults to `/tmp/rip-graveyard` which is cleared on reboot.
            For persistent trash, use a path like `/var/cache/rip-graveyard`.
          '';
          example = "/var/cache/rip-graveyard";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        environment.sessionVariables.RIP_GRAVEYARD = cfg.graveyardPath;

        systemd.tmpfiles.rules = [
          # Ensure the rip graveyard exists with sticky permissions
          # Files older than 10 days are automatically cleaned
          "d ${cfg.graveyardPath} 1777 root root 10d"
        ];
      };
    };
in
{
  flake.nixosModules.apps.rip2 = ripModule;
}
