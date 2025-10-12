{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (virtualization:virtualbox)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  virtualboxApp = getApp "virtualbox";
in
{
  flake.nixosModules.virtualization.virtualbox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.virt.virtualbox.enable or false;
      owner = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] null config;
    in
    {
      imports = lib.optional cfg virtualboxApp;

      config = lib.mkIf cfg (
        lib.mkMerge [
          {
            virtualisation.virtualbox.host = {
              enable = true;
              package = pkgs.virtualbox;
            };

            nixpkgs.allowedUnfreePackages = lib.mkAfter [
              "virtualbox"
              "virtualbox-extpack"
            ];
          }
          (lib.mkIf (owner != null) {
            users.users.${owner}.extraGroups = lib.mkAfter [ "vboxusers" ];
          })
        ]
      );
    };
}
