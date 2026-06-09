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
      ...
    }:
    let
      legacyProfilesPath = ".librewolf";
      xdgProfilesPath = ".config/librewolf/librewolf";
      nixosEnabled = lib.attrByPath [ "programs" "librewolf" "extended" "enable" ] false osConfig;
      # The NVIDIA proprietary X driver's EGL/DMABUF path corrupts images; detect
      # it from the host so the gecko prefs disable widget.dmabuf on that host only.
      nvidiaProprietary = lib.elem "nvidia" (
        lib.attrByPath [ "services" "xserver" "videoDrivers" ] [ ] osConfig
      );
      gecko = import ./_gecko-mk-profile.nix {
        inherit
          pkgs
          lib
          config
          nvidiaProprietary
          ;
      };
      xdgProfileRoot = gecko.mkXdgProfileRoot {
        browserName = "LibreWolf";
        inherit legacyProfilesPath xdgProfilesPath;
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        assertions = [
          {
            assertion = config.programs.librewolf.profilesPath == legacyProfilesPath;
            message = "LibreWolf Home Manager profiles must stay under ~/.librewolf; the XDG profile root is only a compatibility symlink.";
          }
        ];

        home.activation.checkLibreWolfXdgProfileRoot = xdgProfileRoot.activation;

        home.file = gecko.mkCustomKeysFiles config.programs.librewolf // xdgProfileRoot.file;

        programs.librewolf = {
          enable = true;
          # This repo intentionally keeps LibreWolf on the legacy profile root.
          # A real XDG profile root would split policy-applied browser state from
          # Home Manager's declarative user.js, customKeys.json, extension
          # storage, and profile-scoped packages, so the XDG leaf is a symlink.
          configPath = legacyProfilesPath;
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
