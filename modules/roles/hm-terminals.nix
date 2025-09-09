{ config, ... }:
{
  flake.modules.homeManager.roles.terminals.imports = with config.flake.modules.homeManager.apps; [
    kitty
    alacritty
    wezterm
  ];
}
