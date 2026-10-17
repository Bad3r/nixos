/*
  Package: claude-desktop
  Description: Official desktop application for Claude.
  Homepage: https://claude.ai/
  Documentation: https://support.claude.com/en/articles/10065433-installing-claude-for-desktop
  Repository: nil

  Summary:
    * Provides Claude chat, Cowork, and Claude Code sessions with MCP server and desktop extension support.
    * Installs Anthropic's Linux build, repackaged from its APT repository.

  Options:
    claude-desktop: Launch the desktop application.
    claude-desktop claude://claude.ai/new: Open a new chat.
    claude-desktop claude://code/new: Open a new Claude Code session.

  Notes:
    * Package sourced from llm-agents.nix flake (github:Bad3r/llm-agents.nix).
    * The package's FHS environment keeps the host PATH, so MCP servers launched through npx, uvx, or docker use the system profile's tools.
    * Cowork's precheck finds qemu-system-x86_64 on PATH: the installed launcher prefixes PATH with qemu_kvm, which stays off the
      system profile. OVMF firmware and virtiofsd come from the FHS environment.
    * Cowork needs read-write /dev/kvm and /dev/vhost-vsock.
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
          wrapProgram $out/bin/claude-desktop --prefix PATH : ${lib.makeBinPath [ pkgs.qemu_kvm ]}
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
