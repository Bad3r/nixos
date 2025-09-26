/*
  Package: maim
  Description: Screenshot utility for X11/Wayland (via slop) offering region selection and advanced output features.
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

  Example Usage:
    * `maim screenshot.png` — Capture the entire screen to `screenshot.png`.
    * `maim -s -u -m 3 region.png` — After a 3-second delay, interactively select an area including the cursor.
    * `maim -s | xclip -selection clipboard -t image/png` — Copy a selected region directly to the clipboard.
*/

{
  flake.nixosModules.apps.maim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.maim ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.maim ];
    };
}
