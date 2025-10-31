/*
  Package: mattermost-desktop
  Description: Electron-based desktop client for Mattermost secure team messaging.
  Homepage: https://mattermost.com/
  Documentation: https://docs.mattermost.com/install/desktop-app-install.html
  Repository: https://github.com/mattermost/desktop

  Summary:
    * Provides a native desktop experience for Mattermost servers with multi-tab support, desktop notifications, and custom server profiles.
    * Supports secure context menus, proxy configuration, spell check, and deep links to channels or threads.

  Options:
    mattermost-desktop: Launch the application and sign into one or more Mattermost servers.
    CLI flags (Electron): `--disable-gpu`, `--safe-mode`, etc., for troubleshooting; most features configured via GUI preferences.

  Example Usage:
    * `mattermost-desktop` — Open the client and log into a Mattermost workspace.
    * Configure multiple servers via “Add Server” to switch between environments easily.
    * Use Settings → Notifications to customize notification sounds and behavior.
*/
_:
let
  MattermostDesktopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mattermost.extended;
    in
    {
      options.programs.mattermost.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Mattermost desktop.";
        };

        package = lib.mkPackageOption pkgs "mattermost-desktop" { };
      };

      config = lib.mkIf cfg.enable {
        nixpkgs.config.allowedUnfreePackages = [ "mattermost-desktop" ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mattermost = MattermostDesktopModule;
}
