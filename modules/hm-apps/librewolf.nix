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
      inputs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "librewolf" "extended" "enable" ] false osConfig;
      firefox-addons = (pkgs.extend inputs.dedupe_nur.overlays.default).nur.repos.rycee.firefox-addons;
      geckoBrowser = import ./_gecko-browser-common.nix { inherit firefox-addons; };
    in
    {
      config = lib.mkIf nixosEnabled {
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

          # Core enterprise policies via the wrapped LibreWolf. DisableTelemetry
          # and friends are already enforced by LibreWolf's built-in prefs; they
          # are repeated here so the policy surface stays identical to
          # firefox/floorp and the shared extension wiring composes cleanly.
          policies = {
            DisableTelemetry = true;
            DisableFirefoxStudies = true;
            DisablePocket = true;
          }
          // geckoBrowser.extensionPolicies;

          profiles.primary = {
            id = 0;

            settings = {
              # Auto-enable packaged extensions (e.g. Stylix's FirefoxColor add-on)
              # on first profile load; without this, scope-masked XPIs land
              # installed-but-disabled and the Stylix theme never applies.
              "extensions.autoDisableScopes" = 0;
            };

            extensions = {
              # Acknowledge that declarative settings override existing ones.
              force = true;

              # LibreWolf ships uBO bundled; installing it again from NUR pins
              # the version declaratively and dedupes against the bundle by ID.
              packages = geckoBrowser.extensionPackages;

              settings = geckoBrowser.extensionStorage;
            };
          };
        };
      };
    };
}
