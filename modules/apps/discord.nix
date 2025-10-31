/*
  Package: discord
  Description: Electron-based chat and voice platform for communities and teams.
  Homepage: https://discord.com/
  Documentation: https://support.discord.com/hc/en-us
  Repository: https://github.com/discord

  Summary:
    * Provides text, voice, and video chat with community servers, threads, and screen sharing.
    * Supports rich presence integrations, notification controls, and hardware-accelerated rendering tweaks via flags.

  Options:
    discord --disable-gpu: Force software rendering to mitigate GPU driver issues.
    discord --proxy-server=<url>: Route traffic through an HTTP/SOCKS proxy.
    discord --enable-features=UseOzonePlatform: Improve Wayland support in recent Chromium builds.

  Example Usage:
    * `discord` — Launch the desktop client and connect to servers or direct messages.
    * `discord --disable-gpu` — Work around rendering glitches on unsupported GPUs.
    * `discord --proxy-server="socks5://127.0.0.1:1080"` — Respect network egress policies in restricted environments.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.discord.extended;
  DiscordModule = {
    options.programs.discord.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable discord.";
      };

      package = lib.mkPackageOption pkgs "discord" { };
    };

    config = lib.mkIf cfg.enable {
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "discord" ];

      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.discord = DiscordModule;
}
