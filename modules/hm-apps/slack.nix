/*
  Package: slack
  Description: Desktop client for Slack.
  Homepage: https://slack.com/
  Documentation: https://slack.com/help

  Summary:
    * Team communication client offering channels, threads, huddles, screen sharing, and integration with thousands of apps.
    * Provides offline sync, enterprise key management, workflow automation, and compliance exports for organizations.

  Options:
    --enable-features=WaylandWindowDecorations: Improve window behavior on Wayland compositors.
    --proxy-server=<host:port>: Route traffic through an explicit proxy.
    --disable-gpu: Run using software rendering to avoid GPU driver issues.
    --version: Display the current Slack client version.

  Example Usage:
    * `slack` — Open the desktop client to collaborate in channels and direct messages.
    * `slack --disable-gpu` — Bypass hardware acceleration in remote or virtualized environments.
    * `slack --proxy-server=http://proxy.internal:8080` — Comply with corporate network policies requiring a proxy.
*/

{
  flake.homeManagerModules.apps.slack =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.slack ];
    };
}
