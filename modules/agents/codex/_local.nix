{
  lib,
  pkgs,
  codexPkg,
  baseSettings,
  localClient,
  catalogPath,
}:
let
  # A static catalog stops Codex from fetching /v1/models, whose llama.cpp shape it cannot
  # decode. Each entry mirrors Codex's fallback metadata for unknown models; the schema
  # requires the instructions inline. A slug outside it gets a cloud-sized fallback window.
  catalog =
    pkgs.runCommand "codex-local-models.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        models = builtins.toJSON (
          lib.mapAttrsToList (slug: window: {
            inherit slug;
            display_name = slug;
            # max_context_window caps a model_context_window from another config layer.
            context_window = window;
            max_context_window = window;
            supported_reasoning_levels = [ ];
            shell_type = "unified_exec";
            visibility = "list";
            supported_in_api = true;
            priority = 0;
            include_apps_usage_instructions = false;
            default_reasoning_summary = "auto";
            support_verbosity = false;
            web_search_tool_type = "text";
            truncation_policy = {
              mode = "bytes";
              limit = 10000;
            };
            experimental_supported_tools = [ ];
          }) localClient.contextWindows
        );
      }
      ''
        jq -n --argjson models "$models" \
          --rawfile prompt ${codexPkg.src}/codex-rs/models-manager/prompt.md \
          '{models: [$models[] + {model_messages: {instructions_template: $prompt}}]}' > "$out"
      '';

  settings = {
    inherit (localClient) model;
    review_model = localClient.model;
    model_provider = "llama-cpp";
    model_catalog_json = catalogPath;
    # The auto reviewer asks this provider for `codex-auto-review` and fails closed on the 400.
    # MCP elicitations default to it whenever guardian_approval is on, whatever the reviewer.
    approvals_reviewer = "user";
    features.guardian_approval = false;
    # The flag gates startup extraction; generate_memories excludes local threads from it.
    features.memories = false;
    memories.generate_memories = false;
    model_providers.llama-cpp = {
      name = "llama.cpp";
      base_url = "${localClient.endpoint}/v1";
      wire_api = "responses";
    }
    // lib.optionalAttrs (localClient.apiKeyFile != null) {
      auth = {
        command = lib.getExe' pkgs.coreutils "cat";
        args = [ localClient.apiKeyFile ];
      };
    };
  };
in
{
  inherit catalog;
  baseConfigFile = (pkgs.formats.toml { }).generate "codex-local-config-base" (
    lib.recursiveUpdate baseSettings settings
  );
}
