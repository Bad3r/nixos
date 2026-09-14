/*
  Package: davmail
  Description: Java application which presents a Microsoft Exchange server as local CALDAV, IMAP and SMTP servers.
  Homepage: https://davmail.sourceforge.net/
*/
_: {
  flake.homeManagerModules.apps.davmail =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "davmail" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        services.davmail.enable = false;
      };
    };
}
