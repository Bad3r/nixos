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
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs."virt-manager".extended;
  VirtManagerModule = {
    options.programs."virt-manager".extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility
        description = lib.mdDoc "Whether to enable Virtual Machine Manager.";
      };

      package = lib.mkPackageOption pkgs "virt-manager" { };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [ virt-viewer ]; # Default extras
        description = lib.mdDoc ''
          Additional packages to install alongside virt-manager.
          Includes virt-viewer for SPICE/RDP console access.
        '';
        example = lib.literalExpression "with pkgs; [ virt-viewer ]";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ] ++ cfg.extraPackages;
    };
  };
in
{
  flake.nixosModules.apps."virt-manager" = VirtManagerModule;
}
