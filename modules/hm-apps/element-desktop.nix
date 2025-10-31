/*
  Package: element-desktop
  Description: Feature-rich client for Matrix.org.
  Homepage: https://element.io/
  Documentation: https://element.io/help/desktop
  Repository: https://github.com/element-hq/element-desktop

  Summary:
    * Secure Matrix client with end-to-end encrypted chats, voice/video calls, threads, spaces, and extensive moderation tools.
    * Supports custom homeservers, bridging, offline message queueing, and cross-signing for verifying devices.

  Options:
    --profile <name>: Use a specific profile directory (Electron `--profile`).
    --enable-features=WaylandWindowDecorations: Enable Wayland window decorations on compatible compositors.
    --proxy-server=<host:port>: Route network traffic through an explicit proxy.
    --disable-gpu: Run without GPU acceleration if drivers misbehave.

  Example Usage:
    * `element-desktop` — Start the Matrix client and sign into personal or enterprise homeservers.
    * `element-desktop --profile work` — Maintain an isolated profile for workplace accounts.
    * `element-desktop --disable-gpu` — Resolve rendering glitches inside remote desktop sessions.
*/

{
  flake.homeManagerModules.apps.element-desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.element-desktop.extended;
    in
    {
      options.programs.element-desktop.extended = {
        enable = lib.mkEnableOption "Feature-rich client for Matrix.org.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.element-desktop ];
      };
    };
}
