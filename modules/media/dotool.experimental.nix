# modules/dotool.nix (experimental)
# Example: echo type "hello, Friend" | dotool
# Must add user to input group to use /dev/uinput

{ lib, ... }:
{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    let
      package = pkgs.dotool;
    in
    {
      options.dotoolc = lib.mkOption {
        type = lib.types.pathInStore;
        default = lib.getExe' package "dotoolc";
      };
      config = {
        home.packages = [ package ];
        xsession.windowManager.i3.config.startup = [
          { command = "${lib.getExe' pkgs.dotool "dotoold"}"; }
        ]; # https://mynixos.com/home-manager/option/xsession.windowManager.i3.config.startup
      };
    };

  flake.nixosModules.roles.system.base.imports = lib.mkAfter [
    (
      { config, lib, ... }:
      {
        users.users.${config.flake.lib.meta.owner.username}.extraGroups = lib.mkAfter [ "input" ];
      }
    )
  ];
}
