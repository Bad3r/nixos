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
      gecko = import ./_gecko-mk-profile.nix {
        inherit
          pkgs
          inputs
          lib
          config
          ;
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        assertions = [
          {
            assertion = config.programs.firefox.profilesPath == ".mozilla/firefox";
            message = "Firefox Home Manager profiles must stay under ~/.mozilla/firefox; XDG profile roots are unsupported.";
          }
        ];

        home.file = gecko.mkCustomKeysFiles config.programs.firefox;

        programs.firefox = {
          enable = true;
          # This repo intentionally keeps Firefox on the legacy profile root.
          # The XDG path would split policy-applied browser state from
          # Home Manager's declarative user.js, customKeys.json, extension
          # storage, and profile-scoped packages.
          configPath = ".mozilla/firefox";
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
