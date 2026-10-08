/*
  Codex config.toml catalog. Uncomment an optional setting and supply its value;
  commented settings use Codex's default. _settings.nix owns site overrides,
  _features.nix owns feature flags, and _env.nix owns launch environment values.

  Source: openai/codex 58670eeac4b0bdb9fcb86929d8631c14aee0d9f6,
  codex-rs/config/src/{config_toml,types}.rs and core/config.schema.json.
  The pinned executable is checked by codex/config at build time.
*/
{
  # Models and providers
  # Model identifiers and effort levels depend on the active provider's catalog.
  # model = "";
  # review_model = "";
  model_provider = "openai";
  model_providers = { };
  # openai_base_url = "https://api.openai.com/v1";
  # chatgpt_base_url = "https://chatgpt.com/backend-api";
  # oss_provider = "ollama"; # ollama | lmstudio
  # model_catalog_json = "/absolute/path/models.json";
  # model_reasoning_effort = "high";
  # plan_mode_reasoning_effort = "high";
  # Reasoning summaries require model support; omission avoids forcing a format.
  # model_reasoning_summary = "auto"; # auto | concise | detailed | none
  model_verbosity = "medium"; # low | medium | high
  # service_tier = "priority"; # default | priority | flex
  # Additional metadata attached to Responses requests.
  # responses_api_metadata = { };

  # Context and instructions
  # model_context_window = 200000;
  # model_auto_compact_token_limit = 180000;
  # model_auto_compact_token_limit_scope = "total"; # total | body_after_prefix
  # model_post_turn_compact_threshold_percent = 90;
  # Replaces the model's instructions; developer_instructions adds another layer.
  # model_instructions_file = "/absolute/path/instructions.md";
  # developer_instructions = "";
  # instructions = "";
  # compact_prompt = "";
  # experimental_compact_prompt_file = "/absolute/path/compact.md";
  # Controls which context sections are included in the model prompt.
  # include_permissions_instructions = true;
  # include_apps_instructions = true;
  # include_collaboration_mode_instructions = true;
  # include_environment_context = true;
  # project_doc_max_bytes = 32768;
  # project_doc_fallback_filenames = [ ];
  project_root_markers = [ ".git" ];
  projects = { };
  # tool_output_token_limit = 10000;

  # Approval and execution policy
  approval_policy = "on-request";
  # approvals_reviewer = "user"; # user | guardian
  # auto_review = { policy = ""; };
  # Selects a named permissions profile; definitions are composed in _settings.nix.
  # default_permissions = "workspace";
  # permissions = { };
  allow_login_shell = true;
  background_terminal_max_timeout = 300000;
  # Shell tool inheritance is independent of the Codex launch environment.
  # shell_environment_policy = {
  #   "inherit" = "all"; # all | core | none
  #   ignore_default_excludes = true;
  #   filters = { "EXAMPLE_*" = "exclude"; }; # include | exclude
  #   set = { };
  #   experimental_use_profile = false;
  # };

  # Authentication and storage
  cli_auth_credentials_store = "auto"; # auto | file | keyring | ephemeral
  # forced_login_method = "chatgpt"; # chatgpt | api
  # forced_chatgpt_workspace_id = "";
  # sqlite_home = "/absolute/path/state";
  # log_dir = "/absolute/path/logs";
  # Seconds before app-server unloads an idle thread; requires a server restart.
  # thread_unload_delay_secs = 60;
  history = {
    persistence = "save-all"; # save-all | none
    # max_bytes = 104857600;
  };

  # MCP and integrations
  # Server records are compiled per client by ../mcp.nix.
  # Codex accepts command/args for stdio or url for HTTP, with no type field.
  mcp_servers = { };
  mcp_oauth_credentials_store = "auto"; # auto | file | keyring
  # mcp_oauth_callback_port = 0;
  # mcp_oauth_callback_url = "https://example.com/callback";
  # Initial tool-catalog grace period; zero waits for each server's timeout.
  # mcp_optional_startup_grace_ms = 1000;
  # mcp_enterprise_managed_auth = { };
  apps = { };
  # apps_mcp_product_sku = "";
  # Plugin enablement and per-server tool policies, keyed by name@marketplace.
  # plugins = { };
  # marketplaces = { };
  # tool_suggest = { disabled_tools = [ ]; discoverables = [ ]; };
  # Account-provided skills and MCP controls.
  # cloud = { skills.enabled = true; };
  # orchestrator = { mcp.enabled = true; };

  # Agents, skills, memory, and hooks
  # agents = { };
  # goals = { };
  # memories = { };
  # skills = { config = [ ]; };
  # Inline lifecycle hooks use the hooks.json event schema.
  # hooks = { };

  # Browser, computer, and web tools
  web_search = "cached"; # disabled | cached | indexed | live
  # tools = { view_image = true; };
  # browser_use = { };
  # computer_use = { };

  # Realtime and experimental storage
  # audio = { };
  # realtime = { };
  # experimental_realtime_ws_base_url = "";
  # experimental_realtime_webrtc_call_base_url = "";
  # experimental_realtime_ws_model = "";
  # experimental_realtime_ws_backend_prompt = "";
  # experimental_realtime_ws_startup_context = "";
  # experimental_realtime_start_instructions = "";
  # experimental_thread_store = { type = "local"; };

  # Telemetry and maintenance
  analytics.enabled = true;
  feedback.enabled = true;
  check_for_update_on_startup = true;
  suppress_unstable_features_warning = false;
  otel = {
    environment = "dev";
    exporter = "none";
    trace_exporter = "none";
    log_user_prompt = false;
  };

  # Terminal UI
  file_opener = "vscode";
  hide_agent_reasoning = false;
  show_raw_agent_reasoning = false;
  # notify = [ "notify-send" ];
  # Notice acknowledgements and desktop state are written by Codex itself.
  # notice = { };
  # desktop = { };
  tui = {
    alternate_screen = "auto"; # auto | always | never
    animations = true;
    disable_paste_burst = false;
    notification_method = "auto"; # auto | osc9 | bel
    # notification_condition = "unfocused"; # unfocused | always
    # notifications = true; # Boolean or list of event names.
    raw_output_mode = false;
    show_tooltips = true;
    status_line_use_colors = true;
    vim_mode_default = false;
    # status_line = [ "model-with-reasoning" "current-dir" "thread-name" ];
    # terminal_title = [ "activity" "thread-name" "project-name" ];
    # theme = "one-half-dark";
    # resume_cwd = "current"; # current | session
    # auto_recap = true;
    # prompt_suggestions = false;
    # fullscreen_transcript = true;
    # copy_on_select = "auto"; # auto | on | off
    # right_click_paste = "auto"; # auto | on | off
    # Set zero for unlimited resize replay; omission selects a terminal default.
    # terminal_resize_reflow_max_rows = 0;
    # Individual effects also require animations; content rendering is separate.
    # effects = { shimmer = true; progress = true; };
    # rendering = { mermaid = true; math = true; tables = true; lists = true; };
    # Keymap contexts and action names come from config/src/tui_keymap.rs.
    # keymap = { global.toggle_vim_mode = "alt-v"; };
  };
}
