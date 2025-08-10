# Module: locale.nix
# Purpose: Timezone and locale configuration
# Namespace: flake.modules.nixos.base (should be in base, not separate)
# Pattern: Uses metadata for configuration values

{ config, ... }:
let
  timeZone = config.flake.meta.system.timezone;
  locale = config.flake.meta.system.locale;
in
{
  flake.modules = {
    # This should be in base namespace since all systems need locale
    nixos.base = { pkgs, ... }: {
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
      services.timesyncd.enable = true;
    };
    homeManager.base.home.sessionVariables.TZ = timeZone;
  };
}
