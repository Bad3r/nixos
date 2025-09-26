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

{
  nixpkgs.allowedUnfreePackages = [ "brave" ];

  flake.nixosModules.apps.brave =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.brave ];
    };

}
