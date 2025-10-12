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
      cfg = config.virt.libvirt.enable or false;
      owner = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] null config;
    in
    {
      imports = lib.optionals cfg appImports;

      config = lib.mkIf cfg (
        lib.mkMerge [
          {
            virtualisation.libvirtd = {
              enable = true;
              qemu = {
                package = pkgs.qemu_kvm;
                runAsRoot = false;
              };
            };
            home-manager.extraAppImports = lib.mkAfter [ "virt-manager" ];
          }
          (lib.mkIf (owner != null) {
            users.users.${owner}.extraGroups = lib.mkAfter [
              "kvm"
              "libvirtd"
              "qemu-libvirtd"
            ];
          })
        ]
      );
    };
}
