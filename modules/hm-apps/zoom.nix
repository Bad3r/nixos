/*
  Package: zoom
  Description: Video conferencing and collaboration client.
  Homepage: https://zoom.us/
  Documentation: https://support.zoom.com/hc/en
  Repository: https://github.com/logicalshift/zoom

  Summary:
    * Provides HD video/voice meetings, breakout rooms, screen sharing, and webinar features for distributed teams.
    * Integrates with calendars, virtual backgrounds, recording to cloud/local storage, and enterprise security controls.

  Options:
    --url="zoommtg://<meeting>": Join a meeting directly from a deep link.
    --atiomode=1: Start minimized in the system tray.
    --disable-gpu: Run with software rendering to work around GPU issues.
    --enable-features=WaylandWindowDecorations: Improve window handling on Wayland compositors.

  Example Usage:
    * `zoom` — Open the client to schedule or join meetings.
    * `zoom --url="zoommtg://zoom.us/join?action=join&confno=123456789"` — Join a meeting straight from the command line.
    * `zoom --disable-gpu` — Resolve rendering problems on thin clients or remote desktops.
*/

{
  flake.homeManagerModules.apps.zoom =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zoom.extended;
    in
    {
      options.programs.zoom.extended = {
        enable = lib.mkEnableOption "Video conferencing and collaboration client.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.zoom ];
      };
    };
}
