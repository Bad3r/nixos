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
      basePackage = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.spec-kit;
      # Temporary until MCP requests an IPv4 port for its IPv4-only cleanup test.
      python = pkgs.python3.override {
        self = python;
        packageOverrides = _final: prev: {
          mcp = prev.mcp.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./spec-kit/mcp-ipv4-stream-cleanup-test.patch ];
          });
        };
      };
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
          default = basePackage.override { python3 = python; };
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.spec-kit.override { python3 = ...; }";
          description = "The spec-kit package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
