/*
  Package: dmidecode
  Description: SMBIOS table decoder for inspecting hardware inventory.
  Homepage: https://www.nongnu.org/dmidecode/
  Documentation: https://www.nongnu.org/dmidecode/manual.html
  Repository: https://git.savannah.gnu.org/cgit/dmidecode.git

  Summary:
    * Reads system firmware tables to report CPU, memory, chassis, and firmware details without rebooting.
    * Supports targeted queries by structure type for asset management and diagnostics.

  Options:
    --type <num>: Filter output to a specific SMBIOS structure type (e.g., `--type 17` for memory devices).
    --dump: Emit the raw SMBIOS table for archival or offline analysis.
    -q: Suppress keywords for compact output when scanning large inventories.
*/
_:
let
  DmidecodeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dmidecode.extended;
    in
    {
      options.programs.dmidecode.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable dmidecode.";
        };

        package = lib.mkPackageOption pkgs "dmidecode" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dmidecode = DmidecodeModule;
}
