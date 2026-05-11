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

_: {
  flake.homeManagerModules.apps.floorp =
    {
      osConfig,
      lib,
      pkgs,
      config,
      inputs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "floorp" "extended" "enable" ] false osConfig;
      cfg = config.home.floorp;
      # Extend pkgs (which already carries allowUnfreePredicate from
      # modules/meta/nixpkgs-allowed-unfree.nix) with the NUR overlay so
      # unfree firefox-addons (languagetool, wappalyzer, etc.) evaluate.
      firefox-addons = (pkgs.extend inputs.dedupe_nur.overlays.default).nur.repos.rycee.firefox-addons;
      geckoPrefs = import ./_gecko-prefs.nix {
        inherit lib;
        fonts = if config.stylix.enable then config.stylix.fonts else null;
      };
      geckoSearch = import ./_gecko-search.nix { };
      geckoContainers = import ./_gecko-containers.nix { };
      geckoExtensions = import ./_gecko-extensions.nix { inherit firefox-addons; };

      mediaSettings = {
        "media.peerconnection.enabled" = cfg.enableWebRTC;
        "media.eme.enabled" = cfg.enableDRM;
        "media.gmp-widevinecdm.enabled" = cfg.enableDRM;
      };

      # Declarative workspaces (experimental).
      # Data format: Map serialized as array of [id, workspace] tuples.
      workspacesStore = builtins.toJSON {
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
              userContextId = 1; # Links to "work" container.
            }
          ]
        ];
        order = [
          "00000000-0000-0000-0000-000000000001"
          "00000000-0000-0000-0000-000000000002"
        ];
        defaultID = "00000000-0000-0000-0000-000000000001";
      };

      mkProfile =
        {
          id,
          packages,
          extraSettings ? { },
        }:
        {
          inherit id;
          settings = geckoPrefs.commonSettings // mediaSettings // extraSettings;
          inherit (geckoSearch) search;
          inherit (geckoContainers) containers containersForce;
          extensions = {
            force = true;
            inherit packages;
            settings = geckoExtensions.extensionStorage;
          };
        };
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

      config = lib.mkIf nixosEnabled {
        # Tridactyl native messaging host. The manifest installs under
        # $out/lib/mozilla/native-messaging-hosts/, which Floorp picks up via
        # the standard Mozilla discovery path.
        home.packages = [ pkgs.tridactyl-native ];

        programs.floorp = {
          enable = true;
          inherit (osConfig.programs.floorp.extended) package;

          policies = {
            DisableTelemetry = true;
            DisableFirefoxStudies = true;
            DisablePocket = true;
          }
          // geckoExtensions.extensionPolicies;

          languagePacks = [ "en-US" ];

          profiles = {
            primary = mkProfile {
              id = 0;
              packages = geckoExtensions.primaryPackages;
              extraSettings = {
                "floorp.workspaces.enabled" = true;
                "floorp.workspaces.v4.store" = workspacesStore;
              };
            };

            work = mkProfile {
              id = 1;
              packages = geckoExtensions.workPackages;
            };

            ephemeral = mkProfile {
              id = 2;
              packages = geckoExtensions.ephemeralPackages;
            };
          };
        };
      };
    };
}
