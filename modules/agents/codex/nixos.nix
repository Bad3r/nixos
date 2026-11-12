/*
  Package: codex
  Description: Lightweight coding agent that runs in your terminal.
  Homepage: https://github.com/openai/codex
  Documentation: https://github.com/openai/codex#readme
  Repository: https://github.com/openai/codex

  Summary:
    * Provides an interactive TUI that orchestrates code edits, tests, and tooling via OpenAI models with sandboxed execution and approvals.
    * Supports non-interactive automation, session resume, Model Context Protocol servers, and configurable instructions through config.toml and AGENTS.md.

  Options:
    --model <model>: Select the OpenAI model to use (default: o4-mini).
    --approval-policy <mode>: Override the approval policy (suggest, auto-edit, full-auto).
    --sandbox-mode <mode>: Adjust the sandbox level for commands (docker, seatbelt, none).

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * `codeMode.enable` and `voice.enable` build the code-mode host (prebuilt V8) and the voice host (GStreamer) into the default package; both default to off.
    * Home Manager installs a wrapper around `package` and manages the configuration (modules/agents/codex/home.nix).
    * Hooks from the shared registry (modules/agents/hooks.nix) go in /etc/codex/hooks.json: the system layer is trusted without the per-hash review that user-layer hooks need, which a store path would reset on every rebuild.
*/
{ config, inputs, ... }:
let
  inherit (config.flake.lib) agents;
in
{
  flake.nixosModules.apps.codex =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.codex.extended;
      basePackage = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;
    in
    {
      options.programs.codex.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable codex.";
        };

        codeMode.enable = lib.mkEnableOption "JavaScript code mode, run by codex-code-mode-host on a prebuilt V8";

        voice.enable = lib.mkEnableOption "realtime voice through codex-voice-host and GStreamer";

        package = lib.mkOption {
          type = lib.types.package;
          default = basePackage.override {
            withCodeMode = cfg.codeMode.enable;
            withVoice = cfg.voice.enable;
          };
          defaultText = lib.literalExpression ''
            inputs.llm-agents.packages.''${system}.codex.override {
              withCodeMode = config.programs.codex.extended.codeMode.enable;
              withVoice = config.programs.codex.extended.voice.enable;
            }
          '';
          description = "The codex package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.etc."codex/hooks.json".text = builtins.toJSON {
          hooks = agents.hooks.clients.codex pkgs;
        };
        # web.run is answered by kagi-search-webrun.
        programs.kagi-search.extended.enable = lib.mkOverride 1050 true;
      };
    };
}
