/*
  Package: maim
  Description: Command-line screenshot utility for X11 with region selection via slop.
  Homepage: https://github.com/naelstrof/maim
  Documentation: https://github.com/naelstrof/maim#readme
  Repository: https://github.com/naelstrof/maim

  Summary:
    * Captures full-screen, window, or user-selected regions with optional cursor inclusion, alpha transparency, and image format control.
    * Integrates with `slop` to provide interactive selection boxes and outputs to standard streams or files.

  Options:
    -s: Use slop to interactively select a capture region.
    -u: Include the mouse cursor in the screenshot.
    -m <seconds>: Delay capture by the specified number of seconds.
    -f <format>: Set the output format (png, jpg, bmp, etc.).
    -i <window-id>: Capture a specific window by XID.
*/
_:
let
  MaimModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.maim.extended;
    in
    {
      options.programs.maim.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable maim.";
        };

        package = lib.mkPackageOption pkgs "maim" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.maim = MaimModule;
}
