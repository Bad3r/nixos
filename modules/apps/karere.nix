/*
  Package: karere
  Description: Gtk4 Whatsapp client.
  Homepage: https://github.com/tobagin/karere
  Documentation: https://github.com/tobagin/karere/blob/main/README.md
  Repository: https://github.com/tobagin/karere

  Summary:
    * Native GTK4 WhatsApp client with system tray integration.
    * Custom notification sounds, image and text pasting, persistent sessions, and spell checking.

  Notes:
    * Video attachments are unsupported.
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
