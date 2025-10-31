/*
  Package: lshw
  Description: Hardware lister that reports detailed system component information.
  Homepage: https://ezix.org/project/wiki/HardwareLiSter
  Documentation: https://ezix.org/project/wiki/HardwareLiSter
  Repository: https://github.com/lyonel/lshw

  Summary:
    * Collects hardware details from sysfs, DMI, and device databases to produce hierarchical inventories.
    * Outputs text, HTML, XML, or JSON formats for diagnostics and asset tracking.

  Options:
    -short: Print a summarized hardware list.
    -json: Emit machine-readable JSON output.
    -class network: Restrict the report to a particular device class.
*/
_:
let
  LshwModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lshw.extended;
    in
    {
      options.programs.lshw.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable lshw.";
        };

        package = lib.mkPackageOption pkgs "lshw" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lshw = LshwModule;
}
