/*
  Package: telegram-desktop
  Description: Telegram Desktop messaging app.
  Homepage: https://desktop.telegram.org/
  Documentation: https://telegram.org/faq
  Repository: https://github.com/telegramdesktop/tdesktop

  Summary:
    * Secure cloud-synced messaging client offering chats, media sharing, voice/video calls, and multi-device support.
    * Provides secret chats, customizable themes, message scheduling, and file transfers up to 2 GB per item.

  Options:
    --startintray: Start minimized to the system tray while continuing to receive notifications.
    --proxy-server=<host:port>: Route network traffic through a proxy.
    --enable-features=WaylandWindowDecorations: Improve Wayland integration on compatible compositors.
    --debug: Emit verbose logs for troubleshooting.

  Example Usage:
    * `telegram-desktop` — Join chats, channels, and voice rooms from the desktop client.
    * `telegram-desktop --startintray` — Keep Telegram running quietly while still receiving notifications.
    * `telegram-desktop --proxy-server=socks5://127.0.0.1:9050` — Use a SOCKS5 proxy for privacy or corporate compliance.
*/

_: {
  flake.homeManagerModules.apps.telegram-desktop =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "telegram-desktop" "extended" "enable" ] false osConfig;
    in
    {
      # Package installed by NixOS module; HM provides user-level config if needed
      config = lib.mkIf nixosEnabled {
        # telegram-desktop doesn't have HM programs module - config managed by app itself
      };
    };
}
