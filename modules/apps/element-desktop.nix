/*
  Package: element-desktop
  Description: Matrix.org secure collaboration client with end-to-end encryption.
  Homepage: https://element.io/
  Documentation: https://element.io/help
  Repository: https://github.com/vector-im/element-desktop

  Summary:
    * Connects to Matrix homeservers for encrypted chats, VoIP calls, and collaborative spaces.
    * Offers cross-signing, sticker packs, bridging support, and theme customization across workspaces.

  Options:
    element-desktop --profile <name>: Launch with a specific profile directory.
    element-desktop --proxy-server=<url>: Send traffic through an HTTP/SOCKS proxy.
    element-desktop --enable-features=UseOzonePlatform: Enable Wayland-friendly rendering.

  Example Usage:
    * `element-desktop` — Sign into a Matrix account for personal or team collaboration.
    * `element-desktop --profile work` — Maintain separated home and work profiles.
    * `element-desktop --proxy-server="socks5://127.0.0.1:9150"` — Route Matrix traffic over Tor or corporate proxies.
*/

{
  flake.nixosModules.apps."element-desktop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."element-desktop" ];
    };

}
