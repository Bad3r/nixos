/*
  Package: wpa_supplicant
  Description: Wireless Protected Access supplicant for managing Wi-Fi connections.
  Homepage: https://w1.fi/wpa_supplicant/
  Documentation: https://w1.fi/cgit/wpa_supplicant/tree/wpa_supplicant/README

  Summary:
    * Supplies the userspace daemon and CLI tools required by NetworkManager and iwd fallbacks.
    * Ensures workstation roles ship the standard Wi-Fi stack even when alternative backends are used.
*/

{
  flake.nixosModules.apps."wpa_supplicant" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wpa_supplicant ];
    };
}
