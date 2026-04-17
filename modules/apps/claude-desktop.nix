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
  upstreamSrc = inputs."claude-desktop-linux-flake";

  packageFor =
    pkgs:
    let
      patchy-cnb = pkgs.callPackage "${upstreamSrc}/pkgs/patchy-cnb.nix" { };

      claude-desktop = pkgs.callPackage "${upstreamSrc}/pkgs/claude-desktop.nix" {
        inherit patchy-cnb;
        # TODO: Remove this compatibility shim once upstream stops referencing
        # nodePackages.asar and uses pkgs.asar directly.
        # Upstream still expects nodePackages.asar, but nixpkgs moved asar top-level.
        nodePackages = {
          inherit (pkgs) asar;
        };
      };
    in
    {
      inherit claude-desktop;
      claude-desktop-with-fhs = pkgs.buildFHSEnv {
        name = "claude-desktop";
        targetPkgs =
          pkgs': with pkgs'; [
            docker
            glibc
            openssl
            nodejs
            uv
          ];
        runScript = "${claude-desktop}/bin/claude-desktop";
        extraInstallCommands = ''
          mkdir -p $out/share/applications
          cp ${claude-desktop}/share/applications/claude.desktop $out/share/applications/

          mkdir -p $out/share/icons
          cp -r ${claude-desktop}/share/icons/* $out/share/icons/
        '';
      };
    };

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
            inherit (packageFor prev) claude-desktop claude-desktop-with-fhs;
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
