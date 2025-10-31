/*
  Package: signal-desktop
  Description: Private, simple, and secure messenger (nixpkgs build).
  Homepage: https://signal.org/
  Documentation: https://support.signal.org/hc/en-us/articles/360007318871
  Repository: https://github.com/signalapp/Signal-Desktop

  Summary:
    * End-to-end encrypted messaging and calling client synced with Signal mobile apps, offering disappearing messages, reactions, and media sharing.
    * Provides safety number verification, multi-device support, and cross-platform encrypted voice/video calls.

  Options:
    --start-in-tray: Start minimized to the system tray.
    --enable-features=WaylandWindowDecorations: Improve Wayland integration on compatible compositors.
    --proxy-server=<host:port>: Connect via proxy when required.
    --disable-gpu: Use software rendering for compatibility or remote sessions.

  Example Usage:
    * `signal-desktop` — Pair with the Signal mobile app to sync encrypted conversations on desktop.
    * `signal-desktop --start-in-tray` — Keep the client running silently while receiving notifications.
    * `signal-desktop --proxy-server=socks5://127.0.0.1:9050` — Route traffic through Tor or corporate proxies.
*/

{
  flake.homeManagerModules.apps.signal-desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.signal-desktop.extended;
    in
    {
      options.programs.signal-desktop.extended = {
        enable = lib.mkEnableOption "Private, simple, and secure messenger (nixpkgs build).";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.signal-desktop ];
      };
    };
}
