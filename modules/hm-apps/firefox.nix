_: {
  flake.homeManagerModules.apps.firefox =
    {
      osConfig,
      lib,
      pkgs,
      config,
      ...
    }:
    let
      legacyProfilesPath = ".mozilla/firefox";
      xdgProfilesPath = ".config/mozilla/firefox";
      nixosEnabled = lib.attrByPath [ "programs" "firefox" "extended" "enable" ] false osConfig;
      gecko = import ./_gecko-mk-profile.nix {
        inherit
          pkgs
          lib
          config
          osConfig
          ;
      };
      xdgProfileRoot = gecko.mkXdgProfileRoot {
        browserName = "Firefox";
        inherit legacyProfilesPath xdgProfilesPath;
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        assertions = [
          {
            assertion = config.programs.firefox.profilesPath == legacyProfilesPath;
            message = "Firefox Home Manager profiles must stay under ~/.mozilla/firefox; the XDG profile root is only a compatibility symlink.";
          }
        ];

        home = {
          activation.checkFirefoxXdgProfileRoot = xdgProfileRoot.activation;

          # Seed Dark Reader storage once as a writable file so the extension's
          # runtime changes survive home-manager switches.
          activation.seedDarkreaderFirefox = gecko.mkDarkreaderSeed {
            profilesPath = legacyProfilesPath;
            # Mirrors programs.firefox.profiles below.
            profiles = [
              "primary"
              "pentesting"
              "work"
            ];
          };

          file = gecko.mkCustomKeysFiles config.programs.firefox // xdgProfileRoot.file;
        };

        programs.firefox = {
          enable = true;
          # This repo intentionally keeps Firefox on the legacy profile root.
          # A real XDG profile root would split policy-applied browser state from
          # Home Manager's declarative user.js, customKeys.json, extension
          # storage, and profile-scoped packages, so the XDG leaf is a symlink.
          configPath = legacyProfilesPath;
          package = osConfig.programs.firefox.extended.package;
          # `home.packages` is not on Firefox's native-messaging discovery
          # path. Use HM's browser-native option so manifests land in
          # ~/.mozilla/native-messaging-hosts.
          nativeMessagingHosts = [ pkgs.tridactyl-native ] ++ gecko.nativeMessagingHosts;

          inherit (gecko) policies;

          languagePacks = [ "en-US" ];

          profiles = {
            primary = gecko.mkProfile {
              id = 0;
              packages = gecko.primaryPackages;
            };

            pentesting = gecko.mkProfile {
              id = 1;
              packages = gecko.pentestingPackages;
            };

            work = gecko.mkProfile {
              id = 2;
              packages = gecko.workPackages;
            };
          };
        };
      };
    };
}
