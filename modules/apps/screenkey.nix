/*
  Package: screenkey
  Description: Keystroke and mouse-button visualizer for live demos and screencasts.
  Homepage: https://www.thregr.org/~wavexx/software/screenkey/
  Documentation: https://www.thregr.org/~wavexx/software/screenkey/
  Repository: https://gitlab.com/screenkey/screenkey

  Summary:
    * Displays pressed keys as an on-screen overlay for demonstrations, tutorials, and recordings.
    * Supports timeout, placement, and styling controls for consistent screencast output.

  Options:
    -t, --timeout TIMEOUT: Hide displayed keys after TIMEOUT seconds.
    -p, --position {top,center,bottom,fixed}: Set vertical overlay position.
    -g, --geometry GEOMETRY: Set fixed overlay geometry.
    -s, --font-size {large,medium,small}: Set overlay font size.
    -M, --mouse: Show mouse button presses.
*/
_:
let
  ScreenkeyModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.screenkey.extended;
    in
    {
      options.programs.screenkey.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable screenkey.";
        };

        package = lib.mkPackageOption pkgs "screenkey" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.screenkey = ScreenkeyModule;
}
