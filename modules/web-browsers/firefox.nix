_: {
  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      programs.firefox = {
        enable = true;
        package = pkgs.firefox;

        # Core enterprise policies via the wrapped Firefox
        policies = {
          DisableTelemetry = true;
          DisableFirefoxStudies = true;
          DisablePocket = true;
          ExtensionSettings = {
            "uBlock0@raymondhill.net" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            };
            "bitwarden@bitwarden.com" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
            };
          };
        };

        # Language packs
        languagePacks = [ "en-US" ];

        profiles = {
          primary = {
            id = 0;
            settings = {
              "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
              "browser.ctrlTab.sortByRecentlyUsed" = true;
              "browser.tabs.closeWindowWithLastTab" = false;
              # Ensure extensions are enabled from Nix/HM sources
              "extensions.autoDisableScopes" = 0;
              # Enable Firefox vertical tabs sidebar (when supported)
              "sidebar.verticalTabs" = true;
              # Open Tabs sidebar by default on the left
              "sidebar.open" = true;
              "sidebar.position_start" = true;
              "sidebar.command" = "viewTabsSidebar";
              # Enable VA-API hardware decoding (Wayland wrapper already set)
              "media.ffmpeg.vaapi.enabled" = true;

              # Prefer portals for file picker and integration
              "widget.use-xdg-desktop-portal.file-picker" = 1;
              "widget.use-xdg-desktop-portal" = 1;

              # Reduce sponsored/newtab noise
              "browser.newtabpage.activity-stream.showSponsored" = false;
              "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
              "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;

              # Privacy-friendly defaults
              "privacy.globalprivacycontrol.enabled" = true;
              # Disable Firefox Suggest (quicksuggest), keep engine suggestions working
              "browser.urlbar.quicksuggest.enabled" = false;
              "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
              "browser.urlbar.suggest.quicksuggest.sponsored" = false;
              # Reduce prefetching/speculative connections
              "network.prefetch-next" = false;
              "network.dns.disablePrefetch" = true;
              "network.predictor.enabled" = false;
              "network.predictor.enable-prefetch" = false;
              "network.http.speculative-parallel-limit" = 0;
              "browser.urlbar.speculativeConnect.enabled" = false;
              # Disable Beacon API pings
              "beacon.enabled" = false;
              # Ensure stripping of known tracking parameters
              "privacy.query_stripping.enabled" = true;

              # HTTPS-Only Mode and stronger isolation/fingerprinting defenses
              "dom.security.https_only_mode" = true;
              "dom.security.https_only_mode_pbm" = true;
              "privacy.firstparty.isolate" = true;
              "privacy.resistFingerprinting" = true;

              # Disable WebRTC peer connections (prevents local IP leaks; breaks WebRTC apps)
              "media.peerconnection.enabled" = false;

              # Disable DRM / Widevine (blocks EME playback like Netflix)
              "media.eme.enabled" = false;
              "media.gmp-widevinecdm.enabled" = false;

              # Cookie banner handling: attempt to auto-reject
              "cookiebanners.service.mode" = 1;
              "cookiebanners.service.mode.privateBrowsing" = 1;
              "cookiebanners.ui.desktop.enabled" = true;
            };

            # Declarative search configuration
            search = {
              enable = true;
              default = "Kagi";
              force = true;
              engines = {
                Kagi = {
                  icon = "https://kagi.com/favicon-32x32.png";
                  urls = [
                    { template = "https://kagi.com/search?q={searchTerms}"; }
                    {
                      template = "https://kagi.com/api/autosuggest?q={searchTerms}";
                      type = "application/x-suggestions+json";
                    }
                  ];
                  definedAliases = [ "@k" ];
                };

                "Nix Packages" = {
                  urls = [
                    { template = "https://search.nixos.org/packages?query={searchTerms}"; }
                  ];
                };
              };
            };

            # Declarative bookmarks
            bookmarks = {
              force = true;
              settings = [
                {
                  name = "Extensions";
                  toolbar = true;
                  bookmarks = [
                    {
                      name = "Bitwarden";
                      url = "https://vault.bitwarden.com/";
                    }
                    {
                      name = "uBlock Origin";
                      url = "https://ublockorigin.com/";
                    }
                  ];
                }
              ];
            };

            # Multi-Account Container(s)
            containers = {
              work = {
                id = 1;
                color = "blue";
                icon = "briefcase";
              };
            };

            # Extensions and per-extension settings
            extensions = {
              # Acknowledge that declarative settings override existing ones
              force = true;

              settings."uBlock0@raymondhill.net".settings = {
                selectedFilterLists = [
                  "ublock-filters"
                  "ublock-privacy"
                  "ublock-unbreak"
                  "ublock-quick-fixes"
                  # Extra lists to suppress cookie banners/annoyances
                  "ublock-annoyances"
                  "adguard-cookies"
                  "ublock-cookies-adguard"
                  "fanboy-cookiemonster"
                  "ublock-cookies-easylist"
                ];
              };
            };
          };
        };
      };
    };
}
