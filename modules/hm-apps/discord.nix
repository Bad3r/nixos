/*
  Package: discord
  Description: All-in-one cross-platform voice and text chat for gamers.
  Homepage: https://discord.com/
  Documentation: https://support.discord.com/hc/en-us

  Summary:
    * Provides persistent voice/video channels, screen sharing, and community chat with roles, threads, and automation.
    * Integrates with rich presence APIs, access controls, and notification settings across desktop and mobile clients.

  Options:
    --version: Print the installed Discord client version and exit.
    --enable-features=WaylandWindowDecorations: Enable native decorations when using Wayland.
    --disable-gpu: Fall back to software rendering on unsupported GPUs.
    --proxy-server=<host:port>: Route network traffic through a proxy (Chromium flag).

  Example Usage:
    * `discord` — Open the Electron-based client for chat and voice calls.
    * `discord --disable-gpu` — Work around rendering glitches on older hardware.
    * `discord --proxy-server=127.0.0.1:8080` — Force the client to respect a corporate proxy requirement.
*/

{
  flake.homeManagerModules.apps.discord =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.discord ];
    };
}
