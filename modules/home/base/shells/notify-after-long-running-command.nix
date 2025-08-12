# Module: home/base/shells/notify-after-long-running-command.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.gui
# Pattern: Home Manager GUI - Graphical application configuration

{ inputs, ... }:
{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.libnotify ];
      programs.zsh.plugins = [
        {
          name = "auto-notify";
          src = inputs.zsh-auto-notify;
        }
      ];
    };
}
