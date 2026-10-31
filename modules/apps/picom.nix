/*
  Package: picom
  Description: Lightweight X11 compositor providing window transparency, shadows, and VSYNC.
  Homepage: https://github.com/yshui/picom
  Documentation: https://github.com/yshui/picom/wiki
  Repository: https://github.com/yshui/picom

  Summary:
    * Fork of compton offering advanced effects (blur, animations via forks), configurable backends (xrender, glx), and experimental Nvidia optimizations.
    * Useful for window managers lacking built-in compositing (i3, bspwm, Openbox) to enable transparency, shadows, and fade effects.

  Options:
    picom --config <file>: Use a specific configuration file.
    --backend <xrender|glx>: Select rendering backend.
    --vsync: Enable vertical sync to reduce tearing.
    --log-file <path>: Write logs for debugging.
*/
_:
let
  PicomModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.picom.extended;
    in
    {
      options.programs.picom.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable picom.";
        };

        package = lib.mkPackageOption pkgs "picom" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.picom = PicomModule;
}
