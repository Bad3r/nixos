/*
  Package: claude-desktop
  Description: Official desktop application for Claude.
  Homepage: https://claude.ai/
  Documentation: https://support.claude.com/en/articles/10065433-installing-claude-for-desktop
  Repository: nil

  Summary:
    * Provides Claude chat, Cowork, and Claude Code sessions with MCP server and desktop extension support.

  Notes:
    * MCP servers run with the system PATH.
    * Cowork needs read-write /dev/kvm and /dev/vhost-vsock.
    * Stores secrets in GNOME Keyring.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.claude-desktop =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      cfg = config.programs.claude-desktop.extended;
      owner = metaOwner.username;
      package = pkgs.symlinkJoin {
        inherit (cfg.package) name;
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/claude-desktop \
            --prefix PATH : ${lib.makeBinPath [ pkgs.qemu_kvm ]} \
            --add-flags --password-store=gnome-libsecret
        '';
      };
    in
    {
      options.programs.claude-desktop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Claude Desktop.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.claude-desktop";
          description = "The Claude Desktop package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ package ];

        boot.kernelModules = [ "vhost_vsock" ];

        users.users.${owner}.extraGroups = lib.mkAfter [ "kvm" ];
      };
    };
}
