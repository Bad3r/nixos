{ inputs, ... }:
{
  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      programs.firefox = {
        enable = true;
        package = pkgs.firefox;
        profiles = {
          primary = {
            id = 0;
            settings = {
              "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
              "browser.ctrlTab.sortByRecentlyUsed" = true;
              "browser.tabs.closeWindowWithLastTab" = false;
              # Ensure extensions are enabled
              "extensions.autoDisableScopes" = 0;
              # Enable Firefox vertical tabs sidebar (when supported)
              "sidebar.verticalTabs" = true;
            };
            extensions.packages =
              let
                inherit (inputs.dedupe_nur.legacyPackages.${pkgs.system}.repos.rycee) firefox-addons;
              in
              with firefox-addons;
              [
                bitwarden
                ublock-origin
              ];
            userChrome = '''';
            userContent = '''';
          };
        };
      };
    };
}
