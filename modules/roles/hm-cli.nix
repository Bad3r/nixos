{ config, ... }:
{
  flake.homeManagerModules.roles.cli.imports = with config.flake.homeManagerModules.apps; [
    bat
    eza
    fzf
  ];
}
