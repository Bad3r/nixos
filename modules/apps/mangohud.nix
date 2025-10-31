/*
  Package: mangohud
  Description: Vulkan/OpenGL overlay for monitoring FPS, frame times, GPU/CPU metrics, and more.
  Homepage: https://github.com/flightlessmango/MangoHud
  Documentation: https://github.com/flightlessmango/MangoHud#configuration
  Repository: https://github.com/flightlessmango/MangoHud

  Summary:
    * Displays real-time performance metrics as an overlay for games and applications using Vulkan, OpenGL, or DXVK/Proton.
    * Highly configurable via `MANGOHUD_CONFIG` or config files, supporting logging, benchmarking, fan sensors, and wine/proton integration.

  Options:
    mangohud <command>: Launch a program with MangoHud overlay enabled (e.g. `mangohud glxgears`).
    MANGOHUD=1: Prefix environment variable to enable the overlay for Proton/Steam games.
    MANGOHUD_CONFIG=<options>: Specify overlay settings such as `cpu_temp,gpu_temp,fps_limit=60`.
    /etc/xdg/MangoHud/MangoHud.conf: System-wide configuration file.

  Example Usage:
    * `MANGOHUD=1 %command%` — Steam launch option to enable MangoHud for a game.
    * `mangohud --dlsym /path/to/game` — Inject the overlay for native Linux games.
    * `MANGOHUD_CONFIG="fps,frame_timing,temperature" mangohud glxgears` — Show specific metrics while running a test application.
*/

let
  nixosModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mangohud.extended;
    in
    {
      options.programs.mangohud.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true; # Backward compatibility
          description = lib.mdDoc "Whether to enable MangoHud performance overlay for games.";
        };

        package = lib.mkPackageOption pkgs "mangohud" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };

  homeModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.mangohud.extended;
    in
    {
      options.programs.mangohud.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true; # Backward compatibility
          description = lib.mdDoc "Whether to enable MangoHud performance overlay integration.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.mangohud.enable = true;
      };
    };
in
{
  flake = {
    nixosModules.apps.mangohud = nixosModule;
    nixosModules.workstation = nixosModule;
    homeManagerModules.gui = homeModule;
  };
}
