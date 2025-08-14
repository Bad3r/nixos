{
  flake.modules = {
    # This should be in base namespace since all systems need locale
    nixos.base =
      { pkgs, ... }:
      {
        time.timeZone = "Asia/Riyadh";
        i18n = {
          supportedLocales = [ "en_US.UTF-8/UTF-8" ];
          extraLocaleSettings = {
            LC_ADDRESS = "en_US.UTF-8";
            LC_IDENTIFICATION = "en_US.UTF-8";
            LC_MEASUREMENT = "en_US.UTF-8";
            LC_MONETARY = "en_US.UTF-8";
            LC_NAME = "en_US.UTF-8";
            LC_NUMERIC = "en_US.UTF-8";
            LC_PAPER = "en_US.UTF-8";
            LC_TELEPHONE = "en_US.UTF-8";
            LC_TIME = "en_US.UTF-8";
          };
          glibcLocales = pkgs.glibcLocales;
        };
        services.timesyncd.enable = true;
      };
    homeManager.base.home.sessionVariables.TZ = "Asia/Riyadh";
  };
}
