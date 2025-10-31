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
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.virtualbox.extended;
  VirtualboxModule = {
    options.programs.virtualbox.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable virtualbox.";
      };

      package = lib.mkPackageOption pkgs "virtualbox" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.virtualbox = VirtualboxModule;
}
