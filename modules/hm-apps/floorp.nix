/*
  Package: floorp
  Description: Fork of Firefox that seeks balance between versatility, privacy and web openness.
  Homepage: https://floorp.app/
  Documentation: https://docs.floorp.app/
  Repository: https://github.com/Floorp-Projects/Floorp

  Summary:
    * Provides a privacy-focused Firefox fork with workspaces, vertical tabs, and customizable interface features.
    * Supports enterprise policies, profile management, and headless automation inherited from Firefox.

  Options:
    --private-window <url>: Open a URL directly in a new private browsing window.
    --ProfileManager: Launch the profile manager to create or select profiles.
    --new-window <url>: Open a new window with the provided URL.
    --headless: Run Floorp without a visible UI for automated testing or printing.
    --safe-mode: Start Floorp with extensions disabled for troubleshooting.
*/

{
  flake.homeManagerModules.apps.floorp =
    {
      lib,
      pkgs,
      config,
      inputs,
      ...
    }:
    let
      cfg = config.home.floorp;
      inherit (pkgs.stdenv.hostPlatform) system;
      inherit (inputs.dedupe_nur.legacyPackages.${system}.repos.rycee) firefox-addons;
    in
    {
      options.home.floorp = {
        enableWebRTC = lib.mkEnableOption "Allow WebRTC (media.peerconnection)" // {
          default = false;
        };
        enableDRM = lib.mkEnableOption "Allow DRM/Widevine (EME) playback" // {
          default = true;
        };
      };

      config = {
        programs.floorp = {
          enable = true;

          # Core enterprise policies via the wrapped Floorp
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
                # Default fonts (Stylix will override these via targets.floorp)
                "font.name.serif.x-western" = "MonoLisa";
                "font.name.sans-serif.x-western" = "MonoLisa";
                "font.name.monospace.x-western" = "MonoLisa";

                "browser.aboutConfig.showWarning" = false;
                "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
                "browser.ctrlTab.sortByRecentlyUsed" = true;
                "browser.tabs.closeWindowWithLastTab" = false;
                # Ensure extensions are enabled from Nix/HM sources
                "extensions.autoDisableScopes" = 0;
                # Enable Firefox vertical tabs sidebar (Floorp 12+ uses Firefox's implementation)
                # See: https://docs.floorp.app/docs/features/about-vertical-tab-bar/
                "sidebar.verticalTabs" = true;
                # Open Tabs sidebar by default on the left
                "sidebar.open" = true;
                "sidebar.position_start" = true;
                "sidebar.command" = "viewTabsSidebar";
                # Enable VA-API hardware decoding
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

                # HTTPS-Only Mode and fingerprinting defenses
                "dom.security.https_only_mode" = true;
                "dom.security.https_only_mode_pbm" = true;
                # FPI (privacy.firstparty.isolate) is deprecated, replaced by dFPI/TCP.
                # Network partitioning (Firefox 85+) + dFPI provide modern isolation.
                # Explicitly enabled for clarity. See: github.com/arkenfox/user.js/issues/1051
                "privacy.partition.network_state" = true;
                "network.cookie.cookieBehavior" = 5; # dFPI/TCP (Total Cookie Protection)
                "privacy.resistFingerprinting" = true;
                # Disable timer jitter to fix Claude AI infinite loop freeze
                # https://codeberg.org/librewolf/issues/issues/1934
                "privacy.resistFingerprinting.reduceTimerPrecision.jitter" = false;

                # WebRTC/DRM toggles (optional via HM options)
                "media.peerconnection.enabled" = cfg.enableWebRTC;
                "media.eme.enabled" = cfg.enableDRM;
                "media.gmp-widevinecdm.enabled" = cfg.enableDRM;

                # Cookie banner handling: attempt to auto-reject
                "cookiebanners.service.mode" = 1;
                "cookiebanners.service.mode.privateBrowsing" = 1;
                "cookiebanners.ui.desktop.enabled" = true;

                # Declarative workspaces (experimental)
                # Data format: Map serialized as array of [id, workspace] tuples
                "floorp.workspaces.enabled" = true;
                "floorp.workspaces.v4.store" = builtins.toJSON {
                  data = [
                    [
                      "00000000-0000-0000-0000-000000000001"
                      {
                        name = "Default";
                        icon = "fingerprint";
                        userContextId = 0;
                      }
                    ]
                    [
                      "00000000-0000-0000-0000-000000000002"
                      {
                        name = "Work";
                        icon = "briefcase";
                        userContextId = 1; # Links to "work" container
                      }
                    ]
                  ];
                  order = [
                    "00000000-0000-0000-0000-000000000001"
                    "00000000-0000-0000-0000-000000000002"
                  ];
                  defaultID = "00000000-0000-0000-0000-000000000001";
                };
              };

              # Declarative search configuration (same as Firefox)
              search = {
                force = true;
                default = "Google Custom";
                engines = {
                  "Google Custom" = {
                    name = "Google Custom";
                    urls = [
                      {
                        template = "https://www.google.com/search";
                        params = [
                          {
                            name = "q";
                            value = "{searchTerms}";
                          }
                          {
                            name = "hl";
                            value = "en";
                          }
                          {
                            name = "gl";
                            value = "US";
                          }
                          {
                            name = "pws";
                            value = "0";
                          }
                          {
                            name = "safe";
                            value = "off";
                          }
                        ];
                      }
                    ];
                    icon = "https://www.google.com/favicon.ico";
                    definedAliases = [ "@g" ];
                  };

                  Kagi = {
                    name = "Kagi";
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
                    name = "Nix Packages";
                    urls = [
                      { template = "https://search.nixos.org/packages?query={searchTerms}"; }
                    ];
                    definedAliases = [ "@nix" ];
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

                # Install extensions from NUR
                packages = with firefox-addons; [
                  ublock-origin
                  bitwarden
                ];

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
    };
}
