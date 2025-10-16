/*
  Package: openresolv
  Description: Framework for managing `/etc/resolv.conf` from multiple providers.
  Homepage: https://roy.marples.name/projects/openresolv
  Documentation: https://roy.marples.name/projects/openresolv/documentation

  Summary:
    * Coordinates DNS configuration when multiple services (DHCP, VPNs) update resolvers.
    * Required by NetworkManager and other network stacks to prevent resolver conflicts.
*/

{
  flake.nixosModules.apps.openresolv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openresolv ];
    };
}
