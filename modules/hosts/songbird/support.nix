_: {
  configurations.nixos.songbird.module = {
    # No vendor daemon on this board: fan control is BIOS Q-Fan, and the
    # sensors the kernel binds on its own (coretemp, the asus WMI hwmon,
    # spd5118 DIMM thermals, NVMe) are monitoring only. LVFS firmware updates
    # cover the NVMe drives and USB peripherals; build.sh runs fwupdmgr after
    # a successful switch.
    services.fwupd.enable = true;
  };
}
