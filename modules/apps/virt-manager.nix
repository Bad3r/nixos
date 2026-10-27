/*
  Package: virt-manager
  Description: Desktop client for creating and managing libvirt guests.
  Homepage: https://virt-manager.org/
  Documentation: https://virt-manager.org/
  Repository: https://github.com/virt-manager/virt-manager

  Summary:
    * Creates, configures, and opens consoles of guests on qemu:///system and qemu:///session.
    * Seeds qemu:///system as its autoconnected connection through dconf.

  Example Usage:
    * `virt-manager` -- Open the manager; wheel members connect to qemu:///system without a password.
    * `virt-manager --connect qemu:///session` -- Manage the owner's unprivileged guests.

  Notes:
    * Guests created here carry no workloads ownership marker, so the declarative engine never
      touches them.
*/
_:
let
  VirtManagerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."virt-manager".extended;
    in
    {
      options.programs."virt-manager".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Virtual Machine Manager.";
        };

        package = lib.mkPackageOption pkgs "virt-manager" { };
      };

      config = lib.mkIf cfg.enable {
        programs."virt-manager" = {
          enable = true;
          inherit (cfg) package;
        };
      };
    };
in
{
  flake.nixosModules.apps."virt-manager" = VirtManagerModule;
}
