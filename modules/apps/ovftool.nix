/*
  Package: ovftool
  Description: VMware OVF Tool for converting and deploying virtual machines.
  Homepage: https://developer.vmware.com/
  Documentation: https://developer.vmware.com/web/tool/ovf

  Summary:
    * Command-line utility for importing and exporting OVF/OVA packages.
    * Supports conversion between different virtual machine formats.

  Example Usage:
    * `ovftool --help` -- Show available commands and options.
    * `ovftool vm.vmx vm.ova` -- Convert a VMX file to OVA format.
*/

_:
let
  OvftoolModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ovftool.extended;
      ovftoolPkg = pkgs.ovftool.override { acceptBroadcomEula = true; };
    in
    {
      options.programs.ovftool.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable VMware OVF Tool.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = ovftoolPkg;
          description = "The ovftool package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "ovftool" ];
  flake.nixosModules.apps.ovftool = OvftoolModule;
}
