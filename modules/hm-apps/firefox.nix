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
      gecko = import ./_gecko-mk-profile.nix {
        inherit
          pkgs
          inputs
          lib
          config
          cfg
          ;
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
          // gecko.extensionPolicies;

          languagePacks = [ "en-US" ];

          profiles = {
            primary = gecko.mkProfile {
              id = 0;
              packages = gecko.primaryPackages;
            };

            work = gecko.mkProfile {
              id = 1;
              packages = gecko.workPackages;
            };

            ephemeral = gecko.mkProfile {
              id = 2;
              packages = gecko.ephemeralPackages;
            };
          };
        };
      };
    };
}
