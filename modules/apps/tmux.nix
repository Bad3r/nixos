/*
  Package: tmux
  Description: Terminal multiplexer for persistent sessions, windows, and panes.
  Homepage: https://github.com/tmux/tmux/wiki
  Documentation: https://github.com/tmux/tmux/wiki/Getting-Started
  Repository: https://github.com/tmux/tmux

  Summary:
    * Keeps terminal sessions running after detaching or disconnecting.
    * Organizes terminals into windows and split panes.
*/
_:
let
  TmuxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tmux.extended;
    in
    {
      options.programs.tmux.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tmux.";
        };

        package = lib.mkPackageOption pkgs "tmux" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tmux = TmuxModule;
}
