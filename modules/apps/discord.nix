/*
  Package: discord
  Description: Electron-based chat and voice platform for communities and teams.
  Homepage: https://discord.com/
  Documentation: https://support.discord.com/hc/en-us
  Repository: https://github.com/discord

  Summary:
    * Provides text, voice, and video chat with community servers, threads, and screen sharing.
    * Supports rich presence integrations, notification controls, and hardware-accelerated rendering tweaks via flags.

  Options:
    discord --disable-gpu: Force software rendering to mitigate GPU driver issues.
    discord --proxy-server=<url>: Route traffic through an HTTP/SOCKS proxy.
    discord --enable-features=UseOzonePlatform: Improve Wayland support in recent Chromium builds.

  Example Usage:
    * `discord` — Launch the desktop client and connect to servers or direct messages.
    * `discord --disable-gpu` — Work around rendering glitches on unsupported GPUs.
    * `discord --proxy-server="socks5://127.0.0.1:1080"` — Respect network egress policies in restricted environments.
*/

{
  nixpkgs.allowedUnfreePackages = [ "discord" ];

  flake.nixosModules.apps.discord =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.discord ];
    };

}
