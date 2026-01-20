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

_: {
  flake.homeManagerModules.apps.signal-desktop =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "signal-desktop" "extended" "enable" ] false osConfig;
    in
    {
      # Package installed by NixOS module; HM provides user-level config if needed
      config = lib.mkIf nixosEnabled {
        # signal-desktop doesn't have HM programs module - config managed by app itself
      };
    };
}
