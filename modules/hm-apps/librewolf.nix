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

{
  flake.homeManagerModules.apps.librewolf =
    { pkgs, ... }:
    {
      programs.librewolf = {
        enable = false;
        package = pkgs.librewolf-bin-unwrapped;
      };
    };
}
