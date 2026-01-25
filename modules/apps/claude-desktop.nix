/*
  Package: claude-desktop
  Description: Official Claude AI desktop application for Linux with MCP support.
  Homepage: https://claude.ai/
  Documentation: https://docs.anthropic.com/en/docs
  Repository: https://github.com/k3d3/claude-desktop-linux-flake

  Summary:
    * Provides native Claude AI desktop interface with conversation history and file attachments.
    * Supports MCP (Model Context Protocol) servers for extensible tool integrations.

  Options:
    claude-desktop: Launch Claude Desktop with the default UI.
    claude-desktop %u: Open with a custom URI handler.

  Notes:
    * Uses FHS wrapper (claude-desktop-with-fhs) to support MCP tools via npx, uvx, or docker.
    * Package is unfree; the build script is MIT/Apache-2.0 licensed.
*/
{ inputs, ... }:
let
  packageFor = system: inputs."claude-desktop-linux-flake".packages.${system}.claude-desktop-with-fhs;

  ClaudeDesktopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.claude-desktop.extended;
    in
    {
      options.programs.claude-desktop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Claude Desktop.";
        };

        package = lib.mkPackageOption pkgs "claude-desktop-with-fhs" { };
      };

      config = {
        # Add overlay to make claude-desktop-with-fhs available in pkgs
        # Must be unconditional so the package option can resolve
        nixpkgs.overlays = [
          (_final: prev: {
            claude-desktop-with-fhs = packageFor prev.stdenv.hostPlatform.system;
          })
        ];

        environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "claude-desktop" ];
  flake.nixosModules.apps.claude-desktop = ClaudeDesktopModule;
}
