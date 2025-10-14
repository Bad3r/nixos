/*
  Package: avahi
  Description: Multicast DNS/DNS-SD service discovery for local networks.
  Homepage: https://www.avahi.org/
  Documentation: https://www.avahi.org/wiki/Avahi-Documentation

  Summary:
    * Installs the Avahi daemon and utilities for mDNS service discovery.
    * Required when enabling `services.avahi.*` or when browsing local Bonjour devices.
*/

{
  flake.nixosModules.apps.avahi =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.avahi ];
    };
}
