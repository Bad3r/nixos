/*
  Package: davmail
  Description: Java application which presents a Microsoft Exchange server as local CALDAV, IMAP and SMTP servers.
  Homepage: https://davmail.sourceforge.net/

  Notes:
    * Enables Home Manager's services.davmail as a systemd user unit. The upstream package option is not
      nullable, so it is omitted here; NixOS and Home Manager each resolve pkgs.davmail independently to
      the same store path.
    * The mailbox URL and credentials are per-user and not set here. Add them in the user's own Home
      Manager configuration, e.g.:
        services.davmail.settings."davmail.url" = "https://outlook.office365.com/EWS/Exchange.asmx";
*/
_: {
  flake.homeManagerModules.apps.davmail =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "davmail" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        services.davmail.enable = true;
      };
    };
}
