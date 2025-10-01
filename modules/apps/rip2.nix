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
    * `rip src/old_module` — Safely remove a directory while keeping the ability to restore it.
    * `rip ls` — Inspect recently removed files stored in the trash.
    * `rip undo` — Restore the most recently removed item to its original location.
*/

let
  ripModule =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rip2 ];

      environment.sessionVariables.RIP_GRAVEYARD = "/tmp/rip-graveyard";

      systemd.tmpfiles.rules = [
        # Ensure the rip graveyard exists on every boot with sticky permissions
        "d /tmp/rip-graveyard 1777 root root -"
      ];
    };
in
{
  flake.nixosModules.apps.rip2 = ripModule;

  flake.nixosModules.base = ripModule;
}
