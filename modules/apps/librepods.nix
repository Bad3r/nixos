/*
  Package: librepods
  Description: Reverse-engineered AirPods support for Linux. Reads battery,
    handles ear detection, noise control modes, and other Apple Accessory
    Protocol features over L2CAP, with a Continuity BLE advertisement
    decoder for out-of-session battery readings.
  Homepage: https://github.com/kavishdevar/librepods
  Documentation: https://github.com/kavishdevar/librepods/blob/main/linux/README.md
  Repository: https://github.com/kavishdevar/librepods

  Notes:
    * Requires the BlueZ daemon (`hardware.bluetooth.enable`).
    * Ships two binaries: `librepods` (Qt GUI) and `librepods-ctl` (CLI helper).
*/
_:
let
  LibrepodsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.librepods.extended;
    in
    {
      options.programs.librepods.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable librepods.";
        };

        package = lib.mkPackageOption pkgs "librepods" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.librepods = LibrepodsModule;
}
