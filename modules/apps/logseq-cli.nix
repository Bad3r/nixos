/*
  Package: logseq-cli
  Description: CLI tool for Logseq DB graph management and MCP server
  Homepage: https://logseq.com/
  Repository: https://github.com/logseq/logseq

  Summary:
    * Command-line interface for managing Logseq database graphs.
    * Provides MCP server functionality for programmatic access.

  Options:
    logseq-cli: Run the Logseq CLI tool.

  Example Usage:
    * `logseq-cli --help` -- Show available commands.
*/
{ inputs, ... }:
let
  LogseqCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.logseq-cli.extended;
    in
    {
      options.programs.logseq-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the Logseq CLI.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.nix-logseq-git-flake.packages.${pkgs.stdenv.hostPlatform.system}.logseq-cli;
          description = "The logseq-cli package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.logseq-cli = LogseqCliModule;
}
