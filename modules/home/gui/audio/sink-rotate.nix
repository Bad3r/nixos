# Module: home/gui/audio/sink-rotate.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{ lib, withSystem, ... }:
{
  flake.modules.homeManager.base =
    {
      pkgs,
      config,
      ...
    }:
    let
      sink-rotate = withSystem pkgs.system ({ inputs', ... }: inputs'.sink-rotate.packages.default);
      mod = config.wayland.windowManager.sway.config.modifier;
    in
    {
      home.packages = [ sink-rotate ];
      wayland.windowManager = {
        sway.config.keybindings = {
          "--no-repeat ${mod}+c" = "exec ${lib.getExe sink-rotate}";
        };
        hyprland.settings.bind = [
          "SUPER, c, exec, ${lib.getExe sink-rotate}"
        ];
      };
    };
}
