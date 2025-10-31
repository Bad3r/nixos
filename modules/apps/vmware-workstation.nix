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
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.vmware-workstation.extended;
  VmwareWorkstationModule = {
    options.programs.vmware-workstation.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable vmware-workstation.";
      };

      package = lib.mkPackageOption pkgs "vmware-workstation" { };
    };

    config = lib.mkIf cfg.enable {
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "vmware-workstation" ];

      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.vmware-workstation = VmwareWorkstationModule;
}
