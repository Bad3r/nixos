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

        # AirPods Max 2 (model A3454) outputs left-channel-only audio when the
        # WirePlumber/BlueZ stack picks the non-standard SBC-XQ codec, which is
        # selected by default on Linux when both peers advertise it. Reported
        # at https://github.com/kavishdevar/librepods/pull/519#issuecomment by
        # the PR author after testing on Arch with the same WirePlumber build
        # NixOS ships. `bluez5.enable-sbc-xq` is a daemon-wide property in
        # WirePlumber's BlueZ monitor, so this disables SBC-XQ for every
        # bluetooth sink rather than just the Max 2; it is the same scope the
        # upstream workaround uses. Other sinks negotiate plain SBC (or AAC if
        # both ends support it), which is the codec all non-Max AirPods and
        # most generic bluetooth speakers default to anyway. Drop this block
        # if upstream librepods/WirePlumber gain a per-device opt-out, or if
        # the Max 2 firmware ships a fix for the SBC-XQ stereo handling.
        services.pipewire.wireplumber.extraConfig."51-disable-sbc-xq" = {
          "monitor.bluez.properties" = {
            "bluez5.enable-sbc-xq" = false;
          };
        };
      };
    };
in
{
  flake.nixosModules.apps.librepods = LibrepodsModule;
}
