/*
  Package: codex-desktop
  Description: Unofficial ChatGPT desktop application for Linux built from the upstream macOS application.
  Homepage: https://chatgpt.com/
  Documentation: https://github.com/ilysenko/codex-desktop-linux/blob/main/docs/nix.md
  Repository: https://github.com/ilysenko/codex-desktop-linux

  Summary:
    * Provides the ChatGPT desktop interface on Linux with Wayland and X11 support.
    * Runs Codex through a separately installed Codex CLI, including the repository's existing `codex` package.

  Options:
    codex-desktop: Launch the ChatGPT desktop application.

  Notes:
    * Package sourced from codex-desktop-linux flake (github:ilysenko/codex-desktop-linux).
*/
{ inputs, ... }:
{
  nixpkgs.allowedUnfreePackages = [ "codex-desktop" ];

  flake.nixosModules.apps.codex-desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.codex-desktop.extended;
    in
    {
      options.programs.codex-desktop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable codex-desktop.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.codex-desktop-linux.packages.${pkgs.stdenv.hostPlatform.system}.codex-desktop;
          defaultText = lib.literalExpression "inputs.codex-desktop-linux.packages.\${system}.codex-desktop";
          description = "The codex-desktop package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
