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
    --backend <xrender|glx|xr_glx_hybrid>: Select rendering backend.
    --experimental-backends: Enable new GLX features (blur, dual-kawase).
    --vsync: Enable vertical sync to reduce tearing.
    --log-file <path>: Write logs for debugging.

  Example Usage:
    * `picom --config ~/.config/picom/picom.conf --daemon` — Start compositing with a custom config.
    * `picom --experimental-backends --backend glx` — Use GLX backend with blur effects.
    * `pkill picom {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} picom --vsync` — Restart picom with VSYNC enabled to mitigate tearing.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
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
          description = lib.mdDoc "Whether to enable picom.";
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
