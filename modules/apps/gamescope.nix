/*
  Package: gamescope
  Description: Micro-compositor optimized for running games with explicit resolution and fullscreen control.
  Homepage: https://github.com/ValveSoftware/gamescope
  Documentation: https://github.com/ValveSoftware/gamescope#readme
  Repository: https://github.com/ValveSoftware/gamescope

  Summary:
    * Wraps game execution in a compositor designed for low-latency scaling, fullscreen handling, and resolution conversion.
    * Improves compatibility for launchers that need deterministic output and game surface sizing behavior.

  Options:
    -f: Force fullscreen mode for the launched application.
    -W <pixels> -H <pixels>: Set output (display) width and height for compositor presentation.
    -w <pixels> -h <pixels>: Set internal game render width and height before upscale/downscale.
*/
_:
let
  GamescopeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gamescope.extended;
    in
    {
      options.programs.gamescope.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gamescope.";
        };

        package = lib.mkPackageOption pkgs "gamescope" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gamescope = GamescopeModule;
}
