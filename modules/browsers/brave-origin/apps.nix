/*
  Package: brave-origin
  Description: Experimental standalone Brave browser distributed via the -nightly pre-release track.
  Homepage: https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin
  Documentation: https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin
  Repository: https://github.com/brave/brave-browser

  Summary:
    * Installs Brave Origin, a separate Brave product currently shipped only through the brave-origin-nightly channel.
    * Exposes the upstream binary as `brave-origin` without managed enterprise policies.

  Options:
    --incognito: Launch Brave Origin directly in a private browsing session.
    brave://policy: Inspect the active policy set after rebuild (empty by default).
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder: Enable VA-API hardware acceleration on supported GPUs.
    --disable-features=OutdatedBuildDetector: Suppress the bundled updater notice.
    --ozone-platform-hint=auto: Allow Brave Origin to negotiate Wayland or X11 automatically.

  Notes:
    * Local copy of https://github.com/NixOS/nixpkgs/pull/511131 until the PR merges upstream.
    * Package is defined under packages/brave-origin/ and wired through modules/custom-overlays/brave-origin.nix.
    * Changelog: https://github.com/brave/brave-browser/blob/master/CHANGELOG_DESKTOP_ORIGIN.md (currently empty upstream).
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
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.browsers."brave-origin" = BraveOriginModule;
}
