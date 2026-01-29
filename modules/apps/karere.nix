/*
  Package: karere
  Description: Gtk4 Whatsapp client.
  Homepage: https://github.com/tobagin/karere
  Documentation: https://github.com/tobagin/karere/blob/main/README.md
  Repository: https://github.com/tobagin/karere

  Summary:
    * Native GTK4 WhatsApp client with LibAdwaita styling and system tray integration.
    * Features custom notification sounds, image/text pasting, persistent sessions, and multi-language spell checking.

  Options:
    * System tray icon with unread message status indicator.
    * Custom notification sounds (WhatsApp, Pop, Alert, Soft, Start).
    * Theme selection (Light, Dark, System) with LibAdwaita styling.
    * Custom download directory and spell checking dictionaries.

  Notes:
    * Video attachments unsupported due to WebKitGTK/WhatsApp Web compatibility limitations.
*/
_:
let
  KarereModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.karere.extended;
    in
    {
      options.programs.karere.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable karere.";
        };

        package = lib.mkPackageOption pkgs "karere" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.karere = KarereModule;
}
