/*
  Package: autorandr
  Description: Automatically select display configuration based on connected devices.
  Homepage: https://github.com/phillipberndt/autorandr
  Documentation: https://github.com/phillipberndt/autorandr#readme
  Repository: https://github.com/phillipberndt/autorandr

  Summary:
    * Detects connected monitors via EDID and automatically applies saved xrandr configurations.
    * Supports hook scripts (preswitch, postswitch, postsave) for integration with window managers.

  Options:
    --save <profile>: Save current display configuration as a named profile.
    --load <profile>: Load a saved profile (or use profile name directly).
    --change: Automatically detect and apply the matching profile.
    --default <profile>: Fallback profile when no match is detected.
    --force: Force reload even if configuration appears unchanged.
    --detected: List only detected profiles.
    --current: List only the current profile.
*/
_:
let
  AutorandrModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.autorandr.extended;
    in
    {
      options.services.autorandr.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable autorandr.";
        };

        package = lib.mkPackageOption pkgs "autorandr" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # Enable the autorandr service for automatic profile switching
        services.autorandr.enable = true;
      };
    };
in
{
  flake.nixosModules.apps.autorandr = AutorandrModule;
}
