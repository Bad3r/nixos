_: {
  configurations.nixos.tpnix.module = {
    host.virtualization.windowsGuest.enable = true;
    host.virtualization.windowsGuest.installIso = "/var/lib/libvirt/winapps/en-us_windows_11_enterprise_ltsc_2024_x64_dvd_965cfb00.iso";
  };
}
