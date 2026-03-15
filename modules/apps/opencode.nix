/*
  Package: opencode
  Description: Open source AI coding agent built for the terminal.
  Homepage: https://opencode.ai/
  Documentation: https://opencode.ai/docs/cli/
  Repository: https://github.com/anomalyco/opencode

  Summary:
    * Runs as a terminal-first AI coding agent and can also attach to headless server and web sessions.
    * Supports provider-backed coding workflows, session continuation, MCP server management, and non-interactive automation.

  Options:
    run [message..]: Run opencode with a message in non-interactive mode.
    serve: Start a headless opencode server.
    web: Start the opencode server and open the web interface.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
*/
{ inputs, ... }:
let
  OpencodeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.opencode.extended;
    in
    {
      options.programs.opencode.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable opencode.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.opencode";
          description = "The opencode package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.opencode = OpencodeModule;
}
