/*
  Package: antigravity-cli
  Description: CLI for Google Antigravity, an agentic development platform.
  Homepage: https://antigravity.google/
  Documentation: https://antigravity.google/cli
  Repository: nil

  Summary:
    * Provides the `agy` CLI wrapped with `--disable_telemetry`, disabled auto-updates, the controlled agent shell, rm -> trash shim, and per-session TMPDIR.
    * Supports interactive sessions, non-interactive prompts, workspace directory additions, sandboxed execution, and plugin management.

  Options:
    -p, --print: Run a single prompt non-interactively and print the response.
    -i, --prompt-interactive: Run an initial prompt interactively and continue the session.
    --add-dir: Add a directory to the workspace.
    --sandbox: Run with terminal sandbox restrictions enabled.
    plugin: Manage plugins.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * User configuration managed by Home Manager module (modules/agents/antigravity-cli/home.nix).
*/
{ config, inputs, ... }:
let
  inherit (config.flake.lib.agents) scratchDir;

  AntigravityCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."antigravity-cli".extended;
      shell = import ./_shell.nix { inherit lib pkgs scratchDir; };
      telemetry = import ./_telemetry.nix;
    in
    {
      imports = [ (import ../_plugin-options.nix "antigravity-cli") ];

      options.programs."antigravity-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity-cli.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.antigravity-cli";
          description = "The antigravity-cli package to use.";
        };

        finalPackage = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "The antigravity-cli package wrapped with disabled telemetry and auto-updates, the controlled agent shell, and rm shim.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs."antigravity-cli".extended.finalPackage = telemetry.wrapAgy {
          inherit
            lib
            pkgs
            shell
            scratchDir
            ;
          inherit (cfg) package;
        };

        environment.systemPackages = [ cfg.finalPackage ];
      };
    };
in
{
  flake.nixosModules.apps."antigravity-cli" = AntigravityCliModule;
}
