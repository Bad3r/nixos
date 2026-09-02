/*
  Package: brave-origin
  Description: Experimental standalone Brave browser distributed via the -nightly pre-release track.
  Homepage: https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin
  Documentation: https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin
  Repository: https://github.com/brave/brave-browser

  Summary:
    * Installs Brave Origin, a separate Brave product currently shipped only through the brave-origin-nightly channel.
    * Writes the Brave-family DNS-over-HTTPS policy file, shared with the brave module.

  Options:
    --incognito: Launch Brave Origin directly in a private browsing session.
    brave://policy: Inspect the active managed policy set after rebuild.
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder: Enable VA-API hardware acceleration on supported GPUs.
    --disable-features=OutdatedBuildDetector: Suppress the bundled updater notice.
    --ozone-platform-hint=auto: Allow Brave Origin to negotiate Wayland or X11 automatically.

  Notes:
    * Local copy of https://github.com/NixOS/nixpkgs/pull/511131 until the PR merges upstream.
    * Package is defined under packages/brave-origin/ and wired through modules/custom-overlays/brave-origin.nix.
    * Changelog: https://github.com/brave/brave-browser/blob/master/CHANGELOG_DESKTOP_ORIGIN.md (currently empty upstream).
    * The nightly binary compiles in /etc/brave/policies like every Brave channel; there is no channel-scoped
      directory. Brave stable reads the same directory, so the two modules write one identical
      dns-over-https.json and Brave's extended.json never restates its keys.
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

      inherit (import ../_chromium-policies.nix) braveDnsOverHttpsEtc;
    in
    {
      options.programs."brave-origin".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable brave-origin.";
        };

        package = lib.mkPackageOption pkgs "brave-origin" { };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ cfg.package ];
          etc = braveDnsOverHttpsEtc pkgs;
        };
      };
    };
in
{
  flake.nixosModules.browsers."brave-origin" = BraveOriginModule;
}
