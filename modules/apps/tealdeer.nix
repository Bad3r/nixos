/*
  Package: tealdeer
  Description: Fast Rust reimplementation of tldr-pages for simplified command-line help.
  Homepage: https://github.com/dbrgn/tealdeer
  Documentation: https://github.com/dbrgn/tealdeer#usage
  Repository: https://github.com/dbrgn/tealdeer

  Summary:
    * Fetches and caches community-maintained TL;DR pages, providing concise examples for Unix commands.
    * Supports automatic updates, color themes, search, and offline usage with minimal startup time compared to Python-based clients.

  Options:
    tldr <command>: Display TL;DR page for a command.
    tldr --update: Refresh cached pages.
    tldr --list: List available pages and categories.
    tldr --platform <common|linux|osx|windows>: Select platform-specific examples.
    tldr --language <lang>: Show localized pages.

  Example Usage:
    * `tldr tar` — View quick reference examples for the `tar` command.
    * `tldr --update` — Download the latest TL;DR pages.
    * `tldr --platform linux find` — Show Linux-specific usage examples.
*/
_:
let
  TealdeerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tealdeer.extended;
    in
    {
      options.programs.tealdeer.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tealdeer.";
        };

        package = lib.mkPackageOption pkgs "tealdeer" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tealdeer = TealdeerModule;
}
