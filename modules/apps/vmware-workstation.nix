/*
  Package: vmware-workstation
  Description: VMware Workstation Pro hypervisor and tooling.
  Homepage: https://www.vmware.com/products/workstation-pro.html
  Documentation: https://docs.vmware.com/en/VMware-Workstation-Pro/

  Summary:
    * Installs VMware Workstation binaries for building and running local VMs.
    * Provides utilities like `vmware`, `vmrun`, and networking helpers required by the NixOS vmware host module.
    * Optionally enables VMware Workstation host services.

  Example Usage:
    * `vmware` — Launch the VMware Workstation UI.
    * `vmrun start <vmx>` — Automate headless VM lifecycle operations.
*/
_:
let
  VmwareWorkstationModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."vmware-workstation".extended;
    in
    {
      options.programs.vmware-workstation.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable vmware-workstation.";
        };

        enableHost = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable VMware Workstation host services.";
        };

        package = lib.mkPackageOption pkgs "vmware-workstation" { };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          nixpkgs.allowedUnfreePackages = [ "vmware-workstation" ];

          environment.systemPackages = [ cfg.package ];
        })
        (lib.mkIf cfg.enableHost {
          virtualisation.vmware.host = {
            enable = true;
            package = pkgs.vmware-workstation;
          };
        })
      ];
    };
in
{
  flake.nixosModules.apps.vmware-workstation = VmwareWorkstationModule;
}
