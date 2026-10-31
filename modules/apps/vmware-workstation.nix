/*
  Package: vmware-workstation
  Description: VMware Workstation Pro hypervisor and tooling.
  Homepage: https://www.vmware.com/products/workstation-pro.html
  Documentation: https://docs.vmware.com/en/VMware-Workstation-Pro/
  Repository: nil

  Summary:
    * Builds and runs local VMs.
    * Ships the `vmware` UI and the `vmrun` CLI.
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
          description = "Whether to enable vmware-workstation.";
        };

        enableHost = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable VMware Workstation host services.";
        };

        package = lib.mkPackageOption pkgs "vmware-workstation" { };
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && !cfg.enableHost) {
          environment.systemPackages = [ cfg.package ];
        })
        (lib.mkIf cfg.enableHost {
          virtualisation.vmware.host = {
            enable = true;
            inherit (cfg) package;
          };
        })
      ];
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "vmware-workstation" ];
  flake.nixosModules.apps.vmware-workstation = VmwareWorkstationModule;
}
