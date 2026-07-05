/*
  Package: firefoxpwa
  Description: Progressive Web Apps for Firefox (PWAsForFirefox). Installs and
    runs websites as standalone apps in a dedicated, patched Firefox runtime,
    managed from the browser through a companion extension and native connector.
  Homepage: https://pwasforfirefox.filips.si/
  Repository: https://github.com/filips123/PWAsForFirefox

  Notes:
    * The companion extension and native-messaging connector are wired into the
      gecko browsers in modules/browsers/{firefox,librewolf}/home.nix.
    * Extensions for the isolated PWA runtime profiles are installed (per-add-on
      force_installed or user-removable normal_installed) through a policy file
      injected by modules/custom-overlays/firefoxpwa.nix.
*/
_:
let
  FirefoxpwaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.firefoxpwa.extended;
    in
    {
      options.programs.firefoxpwa.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Progressive Web Apps for Firefox.";
        };

        package = lib.mkPackageOption pkgs "firefoxpwa" { };
      };

      config = lib.mkIf cfg.enable {
        # The connector is launched via the native-messaging manifest's absolute
        # path, but the `firefoxpwa` CLI must also be on PATH so the management
        # extension can detect it and so sites install/launch from a shell.
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.browsers.firefoxpwa = FirefoxpwaModule;
}
