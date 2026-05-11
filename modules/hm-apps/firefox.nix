_: {
  flake.homeManagerModules.apps.firefox =
    {
      osConfig,
      lib,
      pkgs,
      config,
      inputs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "firefox" "extended" "enable" ] false osConfig;
      cfg = config.home.firefoxPrivacy;
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

      mkProfile =
        {
          id,
          packages,
        }:
        {
          inherit id;
          settings = geckoPrefs.commonSettings // mediaSettings;
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
      options.home.firefoxPrivacy = {
        enableWebRTC = lib.mkEnableOption "Allow WebRTC (media.peerconnection)" // {
          default = false;
        };
        enableDRM = lib.mkEnableOption "Allow DRM/Widevine (EME) playback" // {
          default = true;
        };
      };

      config = lib.mkIf nixosEnabled {
        # Tridactyl native messaging host. The manifest installs under
        # $out/lib/mozilla/native-messaging-hosts/, which Firefox picks up via
        # the standard Mozilla discovery path.
        home.packages = [ pkgs.tridactyl-native ];

        programs.firefox = {
          enable = true;
          # nixpkgs wraps Firefox with MOZ_LEGACY_PROFILES=1, which forces
          # reads from ~/.mozilla/firefox. Home Manager stateVersion 26.05
          # switched this default to $XDG_CONFIG_HOME/mozilla/firefox, which
          # Firefox ignores. Pin to the legacy path so HM writes where
          # Firefox reads.
          configPath = ".mozilla/firefox";
          inherit (osConfig.programs.firefox.extended) package;

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
