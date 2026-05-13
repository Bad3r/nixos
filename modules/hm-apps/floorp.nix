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
  # Unfree extensions bundled by the shared gecko extension list in
  # `_gecko-extensions.nix`. Names match `lib.getName` on each addon
  # derivation.
  nixpkgs.allowedUnfreePackages = [
    "languagetool"
    "onepassword-password-manager"
    "wappalyzer"
  ];

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
      cfg = config.home.floorpPrivacy;
      gecko = import ./_gecko-mk-profile.nix {
        inherit
          pkgs
          inputs
          lib
          config
          cfg
          ;
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
    in
    {
      options.home.floorpPrivacy = {
        enableWebRTC = lib.mkEnableOption "Allow WebRTC (media.peerconnection)" // {
          default = false;
        };
      };

      config = lib.mkIf nixosEnabled {
        programs.floorp = {
          enable = true;
          # Bake the Tridactyl native messaging host into the Floorp
          # wrapper. See modules/hm-apps/firefox.nix for the why; the
          # short version is that HM's `home.packages` directory is not
          # on Firefox's native-messaging discovery path.
          package = osConfig.programs.floorp.extended.package.override {
            nativeMessagingHosts = [ pkgs.tridactyl-native ];
          };

          policies = {
            DisableTelemetry = true;
            DisableFirefoxStudies = true;
            DisablePocket = true;
          }
          // gecko.extensionPolicies;

          languagePacks = [ "en-US" ];

          profiles = {
            # Floorp rewrites containers.json at runtime, so let HM
            # overwrite the file unconditionally; Firefox and LibreWolf
            # leave containersForce at its mkProfile default of false.
            primary = gecko.mkProfile {
              id = 0;
              packages = gecko.primaryPackages;
              containersForce = true;
              extraSettings = {
                "floorp.workspaces.enabled" = true;
                "floorp.workspaces.v4.store" = workspacesStore;
              };
            };

            work = gecko.mkProfile {
              id = 1;
              packages = gecko.workPackages;
              containersForce = true;
            };

            ephemeral = gecko.mkProfile {
              id = 2;
              packages = gecko.ephemeralPackages;
              containersForce = true;
            };
          };
        };
      };
    };
}
