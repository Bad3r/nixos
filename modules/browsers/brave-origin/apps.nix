/*
  Package: brave-origin
  Description: Standalone Brave Origin browser, Brave's privacy-stripped product variant.
  Homepage: https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin
  Documentation: https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin
  Repository: https://github.com/brave/brave-browser

  Summary:
    * Installs Brave Origin, a separate Brave product with rewards, wallet, and AI features removed.
    * Writes the DNS-over-HTTPS managed policy file.

  Options:
    --incognito: Launch Brave Origin directly in a private browsing session.
    brave://policy: Inspect the active managed policy set after rebuild.
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder: Enable VA-API hardware acceleration on supported GPUs.
    --disable-features=OutdatedBuildDetector: Suppress the bundled updater notice.
    --ozone-platform-hint=auto: Allow Brave Origin to negotiate Wayland or X11 automatically.

  Notes:
    * Package comes from packages/brave-origin, carried after nixpkgs dropped brave-origin (NixOS/nixpkgs 73120ec5921e).
    * Changelog: https://github.com/brave/brave-browser/blob/master/CHANGELOG_DESKTOP_ORIGIN.md (currently empty upstream).
    * Brave Origin compiles in /etc/brave/policies like every Brave channel; there is no channel-scoped directory.
*/
_:
let
  BraveOriginModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."brave-origin".extended;

      inherit (import ../_chromium-policies.nix) managedDnsOverHttps;
    in
    {
      options.programs."brave-origin".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable brave-origin.";
        };

        package = lib.mkPackageOption pkgs "brave-origin" { };

        enableManagedPolicies = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to install the DNS-over-HTTPS managed policy.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ cfg.package ];
          etc = lib.mkIf cfg.enableManagedPolicies {
            "brave/policies/managed/dns-over-https.json".text = builtins.toJSON managedDnsOverHttps;
          };
        };
      };
    };
in
{
  flake.nixosModules.browsers."brave-origin" = BraveOriginModule;
}
