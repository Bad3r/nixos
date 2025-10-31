/*
  Package: brave
  Description: Privacy-focused Chromium-based browser with built-in tracking protection and Tor support.
  Homepage: https://brave.com/
  Documentation: https://github.com/brave/brave-browser/wiki
  Repository: https://github.com/brave/brave-browser

  Summary:
    * Blocks ads and trackers by default using Brave Shields and optional Brave Rewards support.
    * Provides private windows with Tor connectivity, including bridges for censored regions.

  Options:
    --incognito: Launch Brave directly in a private browsing session.
    --tor: Start Brave in a private window connected through the Tor network.
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder: Enable VA-API hardware acceleration on supported GPUs.
    --disable-features=OutdatedBuildDetector: Suppress Brave's self-update prompts when using the wrapped build.
    --ozone-platform-hint=auto: Allow Brave to negotiate Wayland or X11 automatically on Linux systems.
*/
_:
let
  BraveModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.brave.extended;
    in
    {
      options.programs.brave.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable brave.";
        };

        package = lib.mkPackageOption pkgs "brave" { };
      };

      config = lib.mkIf cfg.enable {
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "brave" ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.brave = BraveModule;
}
