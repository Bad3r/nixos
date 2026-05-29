/*
  Package: sidecar
  Description: Terminal-based development companion for AI coding agents.
  Homepage: https://github.com/marcus/sidecar
  Documentation: https://marcus.github.io/sidecar/
  Repository: https://github.com/marcus/sidecar

  Summary:
    * Runs a terminal UI for project git status, files, conversations, tasks, and workspaces.
    * Tracks supported coding agent sessions and can launch agents from managed workspaces.

  Options:
    --config: Use an explicit config file path.
    --project: Select the project root directory.
    --debug: Enable debug logging.
    --version: Print the version and exit.
    -v: Print the version and exit.
    --enable-feature: Enable one or more comma-separated feature flags.
    --disable-feature: Disable one or more comma-separated feature flags.

  Notes:
    * Package sourced from llm-agents.nix flake (github:Bad3r/llm-agents.nix).
*/
{ inputs, ... }:
let
  SidecarModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sidecar.extended;
    in
    {
      options.programs.sidecar.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sidecar.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.sidecar;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.sidecar";
          description = "The sidecar package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sidecar = SidecarModule;
}
