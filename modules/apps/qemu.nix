/*
  Package Group: qemu
  Description: QEMU and helper tooling for accelerating virtualization workloads.
  Homepage: https://www.qemu.org/
  Documentation: https://www.qemu.org/docs/

  Summary:
    * Installs qemu binaries with KVM acceleration, virtio tools, and quickemu helpers.
    * Enables workflows for creating, running, and debugging libvirt-based guests.

  Example Usage:
    * `qemu-system-x86_64` — Launch a QEMU virtual machine directly.
    * `quickemu --vm ubuntu-24.04.conf` — Start a Quickemu-managed desktop guest with sensible defaults.
*/

{
  flake.nixosModules.apps.qemu =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        qemu
        qemu_kvm
        quickemu
      ];
    };
}
