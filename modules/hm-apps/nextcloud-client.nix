/*
  Package: nextcloud-client
  Description: Desktop sync client for Nextcloud.
  Homepage: https://nextcloud.com
  Documentation: https://docs.nextcloud.com/server/latest/user_manual/en/desktop/index.html
  Repository: https://github.com/nextcloud/desktop

  Summary:
    * Binds the upstream Home Manager services.nextcloud-client user unit to graphical-session.target.
    * Starts the client with --background so a login lands in the tray rather than the account wizard window.

  Notes:
    * The package comes from services."nextcloud-client".extended.package so the unit's ExecStart and the system profile resolve to one store path.
    * Sync folders and the account itself are set up interactively on first launch and live in ~/.config/Nextcloud, which this module does not manage.
*/

_: {
  flake.homeManagerModules.apps."nextcloud-client" =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [
        "services"
        "nextcloud-client"
        "extended"
        "enable"
      ] false osConfig;
      inherit (osConfig.services."nextcloud-client".extended) package;
    in
    {
      config = lib.mkIf nixosEnabled {
        services.nextcloud-client = {
          enable = true;
          startInBackground = true;
          inherit package;
        };
      };
    };
}
