/*
  Package: foremost
  Description: Recover files based on their contents.
  Homepage: https://foremost.sourceforge.net/
  Documentation: https://foremost.sourceforge.net/

  Summary:
    * Carves deleted or damaged files from raw disk images and block devices using file signatures.
    * Supports targeted recovery by type, configurable carving rules, and audit-friendly output directories.

  Options:
    -i: Read input from the specified image file or block device.
    -o: Write recovered artifacts and audit logs into the given output directory.
    -t: Restrict carving to the listed file types instead of scanning every supported signature.
    -c: Load a custom configuration file with signature and carving rules.
*/
_:
let
  ForemostModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.foremost.extended;
    in
    {
      options.programs.foremost.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable foremost.";
        };

        package = lib.mkPackageOption pkgs "foremost" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.foremost = ForemostModule;
}
