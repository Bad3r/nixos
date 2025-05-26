# modules/locale.nix
{ pkgs, ... }:

let
  timeZone = "Asia/Riyadh";
  locale = "en_US.UTF-8";
in
{
  flake.modules = {
    nixos = {
      time.timeZone = timeZone;
      i18n = {
        supportedLocales = [ "${locale}/UTF-8" ];
        extraLocaleSettings = {
          LC_ADDRESS = locale;
          LC_IDENTIFICATION = locale;
          LC_MEASUREMENT = locale;
          LC_MONETARY = locale;
          LC_NAME = locale;
          LC_NUMERIC = locale;
          LC_PAPER = locale;
          LC_TELEPHONE = locale;
          LC_TIME = locale;
        };
        glibcLocales = pkgs.glibcLocales;
      };
      pc.services.timesyncd.enable = true;
    };
    homeManager.base.home.sessionVariables.TZ = timeZone;
  };
}
