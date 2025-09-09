_: {
  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      programs.firefox = {
        enable = true;
        package = pkgs.firefox.override {
          # Enable policies support
          extraPolicies = {
            ExtensionSettings = {
              # Bitwarden extension ID
              "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
                installation_mode = "force_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
                # Pin to toolbar
                default_area = "navbar";
              };
            };
            # Additional policies to ensure extension is enabled
            Extensions = {
              Install = [
                "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi"
              ];
            };
          };
        };
        profiles = {
          primary = {
            id = 0;
            settings = {
              "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
              "browser.ctrlTab.sortByRecentlyUsed" = true;
              "browser.tabs.closeWindowWithLastTab" = false;
              # Ensure extensions are enabled
              "extensions.autoDisableScopes" = 0;
            };
            userChrome = '''';
            userContent = '''';
          };
          vpn = {
            id = 1;
            settings = {
              # Ensure extensions are enabled
              "extensions.autoDisableScopes" = 0;
            };
          };
        };
      };
    };
}
