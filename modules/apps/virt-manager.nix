/*
  Package Group: virt-manager
  Description: Virtual Machine Manager UI for libvirt along with SPICE viewers.
  Homepage: https://virt-manager.org/
  Documentation: https://virt-manager.org/documentation/

  Summary:
    * Provides virt-manager desktop client for administering libvirt hosts.
    * Bundles virt-viewer for SPICE/RDP console access to VMs.

  Example Usage:
    * `virt-manager` — Launch the graphical manager and connect to qemu:///system.
    * `virt-viewer --connect qemu+ssh://host/system <vm>` — Attach to a guest console via SPICE.
*/

{
  flake.nixosModules.apps."virt-manager" =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        virt-manager
        virt-viewer
      ];
    };
}
