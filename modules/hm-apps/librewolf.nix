/*
  Package: librewolf
  Description: Fork of Firefox focused on privacy, security, and freedom.
  Homepage: https://librewolf.net/
  Documentation: https://librewolf.net/docs/settings/
  Repository: https://codeberg.org/librewolf/librewolf

  Summary:
    * Provides hardened Firefox with privacy-focused defaults, removing telemetry and fingerprinting vectors.
    * Supports user overrides via librewolf.overrides.cfg for customizing default privacy settings.

  Options:
    --private-window <url>: Open a URL directly in a new private browsing window.
    --ProfileManager: Launch the profile manager to create or select profiles.
    --new-window <url>: Open a new window with the provided URL.
    --headless: Run LibreWolf without a visible UI for automated testing or printing.
    --safe-mode: Start LibreWolf with extensions disabled for troubleshooting.
*/

_: {
  flake.homeManagerModules.apps.librewolf =
    {
      osConfig,
      lib,
      pkgs,
      config,
      inputs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "librewolf" "extended" "enable" ] false osConfig;
      cfg = config.home.librewolfPrivacy;
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
      options.home.librewolfPrivacy = {
        enableWebRTC = lib.mkEnableOption "Allow WebRTC (media.peerconnection)" // {
          default = false;
        };
        # LibreWolf upstream ships `media.eme.enabled` and
        # `media.gmp-widevinecdm.enabled` off by default as part of its
        # privacy posture; defaulting `enableDRM` to false preserves that
        # stance and leaves the opt-in to users who explicitly need
        # Widevine/EME playback.
        enableDRM = lib.mkEnableOption "Allow DRM/Widevine (EME) playback" // {
          default = false;
        };
      };

      config = lib.mkIf nixosEnabled {
        # Tridactyl native messaging host. The manifest installs under
        # $out/lib/mozilla/native-messaging-hosts/, which LibreWolf picks up
        # via the standard Mozilla discovery path.
        home.packages = [ pkgs.tridactyl-native ];

        programs.librewolf = {
          enable = true;
          # LibreWolf builds use the XDG-compliant profile root
          # ~/.config/librewolf/librewolf regardless of MOZ_LEGACY_PROFILES,
          # but Home Manager's LibreWolf module still defaults to ~/.librewolf.
          # Point HM at the path LibreWolf actually reads so declarative
          # profile seeding reaches the running browser.
          # Keep prefs under profiles.*.settings: HM still writes top-level
          # settings to ~/.librewolf/librewolf.overrides.cfg regardless of
          # configPath.
          configPath = ".config/librewolf/librewolf";
          inherit (osConfig.programs.librewolf.extended) package;

          # DisableTelemetry / DisableFirefoxStudies / DisablePocket are already
          # enforced by LibreWolf's built-in prefs; repeated here so the policy
          # surface stays identical to firefox/floorp and the shared extension
          # wiring composes cleanly.
          policies = {
            DisableTelemetry = true;
            DisableFirefoxStudies = true;
            DisablePocket = true;
          }
          // geckoExtensions.extensionPolicies;

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
