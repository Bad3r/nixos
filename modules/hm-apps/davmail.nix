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
        services.davmail = {
          enable = false;
          settings = {
            "davmail.server" = true;
            "davmail.mode" = "ExchangeEWS";
            "davmail.userAgent" = "Microsoft Office/16.0 (Windows NT 10.0; MAPI 16.0.4266; Pro)";
            "davmail.bindAddress" = "127.0.0.1";
            "davmail.allowRemote" = false;
            "davmail.disableUpdateCheck" = true;
            "davmail.showStartupBanner" = false;
            "davmail.imapPort" = 1143;
            "davmail.smtpPort" = 1025;
            "davmail.popPort" = 1110;
            "davmail.caldavPort" = 1080;
            "davmail.ldapPort" = 1389;
            "davmail.logFilePath" = "/dev/null";
            "log4j.rootLogger" = "WARN";
            "log4j.logger.davmail" = "WARN";
            "log4j.logger.httpclient" = "WARN";
            "log4j.logger.httpclient.wire" = "WARN";
          };
        };
      };
    };
}
