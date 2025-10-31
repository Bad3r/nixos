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
  config,
  lib,
  pkgs,
  ...
}:
let
  QemuModule = { config, lib, pkgs, ... }:
  let
    cfg = config.programs.qemu.extended;
  in
  {
    options.programs.qemu.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable QEMU virtualization tools.";
      };

      package = lib.mkPackageOption pkgs "qemu" { };

      extraTools = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [
          qemu_kvm
          quickemu
        ];
        description = lib.mdDoc ''
          Additional QEMU tools and helpers.

          Included by default:
          - qemu_kvm: QEMU with KVM acceleration support
          - quickemu: Quickly create and run optimized VMs
        '';
        example = lib.literalExpression "with pkgs; [ qemu_kvm quickemu ]";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ] ++ cfg.extraTools;
    };
  };
in
{
  flake.nixosModules.apps.qemu = QemuModule;
}
