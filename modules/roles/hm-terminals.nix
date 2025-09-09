{ config, ... }:
{
  flake.homeManagerModules.roles.terminals.imports = with config.flake.homeManagerModules.apps; [
    kitty
    alacritty
    wezterm
  ];
}
