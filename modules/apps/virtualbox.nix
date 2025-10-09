/*
  Package: virtualbox
  Description: Type-2 hypervisor for running hardware-virtualized guests.
  Homepage: https://www.virtualbox.org/
  Documentation: https://www.virtualbox.org/wiki/Documentation

  Summary:
    * Ships the VirtualBox Manager UI, headless tools, and VBoxManage CLI.
    * Provides kernel module tooling via dkms-style helpers packaged in nixpkgs.

  Example Usage:
    * `VirtualBox` — Launch the Qt management UI for creating and managing VMs.
    * `vboxmanage list vms` — Enumerate registered guests from the CLI.
*/

{
  flake.nixosModules.apps.virtualbox =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.virtualbox ];
    };
}
