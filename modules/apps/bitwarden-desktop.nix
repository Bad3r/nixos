/*
  Package: bitwarden-desktop
  Description: Secure and free password manager for all of your devices.
  Homepage: https://bitwarden.com
  Documentation: https://bitwarden.com/help/desktop-app/
  Repository: https://github.com/bitwarden/clients

  Summary:
    * Launches the Bitwarden desktop vault for browsing, editing, and autofill-adjacent credential workflows.
    * Syncs encrypted items from Bitwarden-hosted or self-hosted services and integrates with biometric or desktop unlock features.

  Options:
    bitwarden: Launch the desktop application and open the vault UI.
    Account settings: Configure the server endpoint, sign-in method, and vault timeout behavior from the in-app settings.
*/
_:
let
  BitwardenDesktopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."bitwarden-desktop".extended;
    in
    {
      options.programs.bitwarden-desktop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bitwarden-desktop.";
        };

        package = lib.mkPackageOption pkgs "bitwarden-desktop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bitwarden-desktop = BitwardenDesktopModule;
}
