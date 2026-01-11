/*
  Package: gnused
  Description: GNU stream editor for non-interactive text transformations.
  Homepage: https://www.gnu.org/software/sed/
  Documentation: https://www.gnu.org/software/sed/manual/sed.html
  Repository: https://git.savannah.gnu.org/cgit/sed.git

  Summary:
    * Applies scripted substitutions, insertions, and deletions to text streams and files.
    * Supports in-place editing, extended regular expressions, and multi-line pattern spaces.

  Options:
    -e 's/old/new/': Perform one-off substitutions on stdin or files.
    -n '1,10p': Print only selected line ranges without default output.
    -i.bak 's/foo/bar/': Edit files in place while writing backups with the specified suffix.
*/
_:
let
  GnusedModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gnused.extended;
    in
    {
      options.programs.gnused.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gnused.";
        };

        package = lib.mkPackageOption pkgs "gnused" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gnused = GnusedModule;
}
