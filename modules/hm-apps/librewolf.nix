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
        home.file = gecko.mkCustomKeysFiles config.programs.librewolf;

        programs.librewolf = {
          enable = true;
          # Point HM at the path LibreWolf reads so declarative profile
          # seeding reaches the running browser.
          # configPath = ".config/librewolf/librewolf";
          package = osConfig.programs.librewolf.extended.package;
          # See modules/hm-apps/firefox.nix for why this uses the browser
          # native-messaging option instead of `home.packages`.
          nativeMessagingHosts = [ pkgs.tridactyl-native ] ++ gecko.nativeMessagingHosts;

          inherit (gecko) policies;

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
