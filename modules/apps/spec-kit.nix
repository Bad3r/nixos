/*
  Package: spec-kit
  Description: Specify CLI for Spec-Driven Development with AI coding assistants.
  Homepage: https://github.com/github/spec-kit
  Documentation: https://github.github.io/spec-kit/
  Repository: https://github.com/github/spec-kit

  Summary:
    * Bootstrap projects for Spec-Driven Development (SDD) workflows.
    * Integrates with Claude Code and other AI coding assistants.

  Options:
    specify init: Initialize a new spec-kit project.
    specify generate: Generate specifications from templates.
    -h, --help: Show usage information.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
*/
{ inputs, ... }:
{
  flake.nixosModules.apps."spec-kit" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."spec-kit".extended;
    in
    {
      options.programs."spec-kit".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable spec-kit.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.spec-kit;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.spec-kit";
          description = "The spec-kit package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
