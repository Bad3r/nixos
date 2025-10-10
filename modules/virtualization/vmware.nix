{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (virtualization:vmware)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  vmwareApp = getApp "vmware-workstation";
in
{
  flake.nixosModules.virtualization.vmware =
    { lib, pkgs, ... }:
    {
      imports = [ vmwareApp ];

      config = {
        virtualisation.vmware.host = {
          enable = true;
          package = pkgs.vmware-workstation;
        };

        nixpkgs.allowedUnfreePackages = lib.mkAfter [
          "vmware-workstation"
        ];
      };
    };
}
