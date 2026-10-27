/*
  Package: qwen-code
  Description: Terminal coding agent for OpenAI-compatible, Anthropic, and Gemini model APIs.
  Homepage: https://qwenlm.github.io/qwen-code-docs/
  Documentation: https://qwenlm.github.io/qwen-code-docs/en/users/overview/
  Repository: https://github.com/QwenLM/qwen-code

  Summary:
    * Runs an interactive coding agent with file edits, shell commands, MCP servers, skills, and subagents.
    * Runs one-shot prompts non-interactively with `-p`.

  Options:
    -p, --prompt <prompt>: Run a prompt in non-interactive mode.
    -m, --model <model>: Select the model for the session.
    --approval-mode <mode>: Set tool approval behavior (plan, default, auto-edit, auto, yolo).

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * /etc/qwen-code/system-defaults.json holds the Nix-managed defaults; ~/.qwen/settings.json
      stays writable and overrides them.
    * With programs.llama-cpp.extended.client.endpoint set (modules/apps/llama-cpp.nix), the
      defaults select that server's OpenAI-compatible API and `client.model`, register every
      model in `client.models` for `qwen -m`, and `qwen` reads the API key from
      `client.apiKeyFile` at launch.
*/
{ inputs, ... }:
let
  QwenCodeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."qwen-code".extended;
      client = lib.attrByPath [ "programs" "llama-cpp" "extended" "client" ] {
        endpoint = null;
      } config;
      useLocalServer = client.endpoint != null;
      keyVar = "LLAMA_CPP_API_KEY";

      settings = {
        # The current schema version; an older or missing one makes qwen rewrite the file.
        "$version" = 4;
        general.enableAutoUpdate = false;
        privacy.usageStatisticsEnabled = false;
        # The upstream default, `auto`, lets an LLM classifier approve tool calls.
        tools.approvalMode = "default";
      }
      // lib.optionalAttrs useLocalServer {
        security.auth.selectedType = "openai";
        model.name = client.model;
        modelProviders.openai = lib.mapAttrsToList (id: contextWindowSize: {
          inherit id;
          name = "${id} (llama.cpp)";
          envKey = keyVar;
          baseUrl = "${client.endpoint}/v1";
          generationConfig = { inherit contextWindowSize; };
        }) client.models;
      };

      launcher = pkgs.writeShellApplication {
        name = "qwen";
        text = ''
          ${
            if client.apiKeyFile == null then
              "${keyVar}=llama-cpp-local"
            else
              "${keyVar}=$(<${lib.escapeShellArg client.apiKeyFile})"
          }
          export ${keyVar}
          exec ${lib.getExe cfg.package} "$@"
        '';
      };
    in
    {
      options.programs."qwen-code".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable qwen-code.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.qwen-code;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.qwen-code";
          description = "The qwen-code package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ (if useLocalServer then launcher else cfg.package) ];
          etc."qwen-code/system-defaults.json".source =
            (pkgs.formats.json { }).generate "qwen-code-system-defaults.json"
              settings;
        };
      };
    };
in
{
  flake.nixosModules.apps."qwen-code" = QwenCodeModule;
}
