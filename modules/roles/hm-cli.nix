{ config, ... }:
{
  flake.modules.homeManager.roles.cli.imports = with config.flake.modules.homeManager.apps; [
    bat
    eza
    fzf
  ];
}
