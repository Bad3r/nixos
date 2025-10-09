{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (virtualization:libvirt)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  appImports = map getApp [
    "qemu"
    "virt-manager"
  ];
in
{
  flake.nixosModules.virtualization.libvirt =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      owner = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] null config;
    in
    {
      imports = appImports;

      config = lib.mkMerge [
        {
          virtualisation.libvirtd = {
            enable = true;
            qemu = {
              package = pkgs.qemu_kvm;
              ovmf = {
                enable = true;
                packages = [ pkgs.OVMFFull.fd ];
              };
              runAsRoot = false;
            };
          };

          programs.virt-manager.enable = true;
        }
        (lib.mkIf (owner != null) {
          users.users.${owner}.extraGroups = lib.mkAfter [
            "kvm"
            "libvirtd"
            "qemu-libvirtd"
          ];
        })
      ];
    };
}
