/*
  Package: davmail
  Description: Java application which presents a Microsoft Exchange server as local CALDAV, IMAP and SMTP servers.
  Homepage: https://davmail.sourceforge.net/
  Documentation: https://davmail.sourceforge.net/serversetup.html
  Repository: https://github.com/mguessan/davmail

  Summary:
    * Bridges an Exchange or Office 365 mailbox (EWS/WebDAV) to local POP, IMAP, SMTP, CalDAV, CardDAV, and LDAP servers for any mail client.
    * Ships both a Swing GUI (tray icon and settings frame) and a headless server mode driven by a davmail.properties file.

  Options:
    -server: Run headless using the settings file instead of showing the Swing GUI.
    -notray: Disable the system tray icon, overriding the davmail.enableTray setting.
    -tray: Force-enable the system tray icon, overriding the davmail.enableTray setting.
    -token: Print an OAuth refresh token after an interactive Microsoft sign-in, then exit.
    -kerberos: Check Kerberos authentication and exit.

  Notes:
    * modules/hm-apps/davmail.nix enables Home Manager's per-user services.davmail (a systemd user unit)
      once this module is enabled, since each gateway instance holds one user's Exchange credentials and
      mailbox URL.
    * That unit is gated on graphical-session.target, so it only starts once a desktop session is active;
      on a headless host it sits idle.
*/
_:
let
  DavmailModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.davmail.extended;
    in
    {
      options.programs.davmail.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable davmail.";
        };

        package = lib.mkPackageOption pkgs "davmail" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.davmail = DavmailModule;
}
