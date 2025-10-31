/*
  Package: coderabbit-cli
  Description: CodeRabbit's terminal client for AI-powered code reviews and repository automation.
  Homepage: https://coderabbit.ai/
  Documentation: https://docs.coderabbit.ai/docs/cli
  Repository: https://github.com/coderabbitai/coderabbit-cli

  Summary:
    * Authenticates with CodeRabbit to request AI code reviews, summaries, and guidance for pull requests or local diffs.
    * Supports interactive terminal UI and plain text output suitable for CI pipelines or chat integrations.

  Options:
    coderabbit auth login: Sign into CodeRabbit and store credentials locally.
    coderabbit review --repo <path>: Generate an AI review for changes in the specified repository or diff.
    coderabbit update: Upgrade the CLI to the latest released version.

  Example Usage:
    * `coderabbit auth login` — Launch the browser flow to connect your CodeRabbit account.
    * `coderabbit review --pr 128 --format markdown` — Request a markdown-formatted review for PR #128.
    * `coderabbit review --staged --output report.md` — Review currently staged changes and save the response to a file.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  CoderabbitCliModule = { config, lib, pkgs, ... }:
  let
    cfg = config.programs."coderabbit-cli".extended;
  in
  {
    options.programs."coderabbit-cli".extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable coderabbit-cli.";
      };

      package = lib.mkPackageOption pkgs "coderabbit-cli" { };
    };

    config = lib.mkIf cfg.enable {
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "coderabbit-cli" ];

      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps."coderabbit-cli" = CoderabbitCliModule;
}
