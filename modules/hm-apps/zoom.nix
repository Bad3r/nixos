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

_: {
  flake.homeManagerModules.apps.zoom =
    { osConfig, lib, ... }:
    let
      # NixOS module is named zoom-us, not zoom
      nixosEnabled = lib.attrByPath [ "programs" "zoom-us" "extended" "enable" ] false osConfig;
    in
    {
      # Package installed by NixOS module; HM provides user-level config if needed
      config = lib.mkIf nixosEnabled {
        # zoom doesn't have HM programs module - config managed by app itself
      };
    };
}
