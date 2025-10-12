{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (virtualization:docker)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  dockerApp = getApp "docker";
in
{
  flake.nixosModules.virtualization.docker =
    { config, lib, ... }:
    let
      cfg = config.virt.docker.enable or false;
      owner = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] null config;
    in
    {
      imports = lib.optional cfg dockerApp;

      config = lib.mkIf cfg (
        lib.mkMerge [
          {
            virtualisation.docker = {
              enable = true;
              enableOnBoot = true;
            };

            home-manager.extraAppImports = lib.mkAfter [ "lazydocker" ];
          }
          (lib.mkIf (owner != null) {
            users.users.${owner}.extraGroups = lib.mkAfter [ "docker" ];
          })
        ]
      );
    };
}
