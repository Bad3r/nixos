/*
  Package: vmware-workstation
  Description: VMware Workstation Pro hypervisor and tooling.
  Homepage: https://www.vmware.com/products/workstation-pro.html
  Documentation: https://docs.vmware.com/en/VMware-Workstation-Pro/

  Summary:
    * Installs VMware Workstation binaries for building and running local VMs.
    * Provides utilities like `vmware`, `vmrun`, and networking helpers required by the NixOS vmware host module.

  Example Usage:
    * `vmware` — Launch the VMware Workstation UI.
    * `vmrun start <vmx>` — Automate headless VM lifecycle operations.
*/

{
  nixpkgs.allowedUnfreePackages = [ "vmware-workstation" ];

  flake.nixosModules.apps."vmware-workstation" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."vmware-workstation" ];
    };
}
