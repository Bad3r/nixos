/*
  Codex config.toml catalog. Uncomment an optional setting and supply its value;
  commented settings use Codex's default. _settings.nix owns site overrides,
  _features.nix owns feature flags, and _env.nix owns launch environment values.
  Covers options read by the CLI, TUI, app-server, or the desktop app
  (modules/apps/chatgpt), which shares this config.

  Source: Bad3r/codex main b1573f102413e96a6481087922bf425231222dee,
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
  # chatgpt_base_url = "https://chatgpt.com/backend-api/";
  # oss_provider = "ollama"; # ollama | lmstudio; example
  # model_catalog_json = "/absolute/path/models.json";
  # model_reasoning_effort = "high"; # example; unset uses the model's
  # plan_mode_reasoning_effort = "high"; # example
  # Reasoning summaries require model support; omission avoids forcing a format.
  # model_reasoning_summary = "auto"; # auto | concise | detailed | none; example
  model_verbosity = "medium"; # low | medium | high
  # service_tier = "priority"; # default | priority | flex; example
  # Daybreak access-program preference for new threads; needs features.cli_daybreak.
  # daybreak = false;
  # Additional metadata attached to Responses requests.
  # responses_api_metadata = { };

  # Context and instructions
  # model_context_window = 200000; # example; unset uses the model's
  # model_auto_compact_token_limit = 180000; # example; unset uses the model's
  # model_auto_compact_token_limit_scope = "total"; # total | body_after_prefix
  # model_post_turn_compact_threshold_percent = 90; # example; unset or 0 is off
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
  # include_environment_context_time = true;
  # project_doc_max_bytes = 32768;
  # project_doc_fallback_filenames = [ ];
  project_root_markers = [ ".git" ];
  projects = { };
  # tool_output_token_limit = 10000; # example; unset uses the model's truncation policy

  # Approval and execution policy
  # approval_policy = "on-request"; # on-request | never | { granular = { ... }; }
  # approvals_reviewer = "user"; # user | auto_review
  # auto_review = {
  #   policy = "";
  #   timeout_ms = 90000; # zero waits without a review deadline
  #   circuit_break_action = "default"; # default | strict
  #   experimental_conversation_history_prompt = "";
  #   conversation_history_max_output_tokens = 4000;
  # };
  # Selects a named permissions profile; definitions are composed in _settings.nix.
  # default_permissions = "workspace"; # example
  # permissions = { };
  # Legacy sandbox, ignored while permission profiles are active; the default
  # follows project trust.
  # sandbox_mode = "read-only"; # read-only | workspace-write | danger-full-access
  # Applies only to legacy workspace-write and the implicit :workspace profile;
  # ignored while permission profiles are active.
  # sandbox_workspace_write = {
  #   writable_roots = [ ];
  #   network_access = false;
  #   exclude_tmpdir_env_var = false;
  #   exclude_slash_tmp = false;
  # };
  allow_login_shell = true;
  background_terminal_max_timeout = 300000;
  # Shell tool inheritance is independent of the Codex launch environment.
  # shell_environment_policy = {
  #   "inherit" = "all"; # all | core | none
  #   ignore_default_excludes = true;
  #   filters = { "EXAMPLE_*" = "exclude"; }; # include | exclude
  #   # Legacy include_only and exclude lists of case-insensitive `*`/`?` patterns
  #   # still parse, but not together with filters.
  #   set = { };
  #   experimental_use_profile = false;
  # };

  # Authentication and storage
  cli_auth_credentials_store = "auto"; # auto | file | keyring | ephemeral
  # forced_login_method = "chatgpt"; # chatgpt | api; example, unset allows both
  # forced_chatgpt_workspace_id = "";
  # sqlite_home = "/absolute/path/state";
  # log_dir = "/absolute/path/logs";
  # Seconds before app-server unloads an idle thread; requires a server restart.
  # thread_unload_delay_secs = 60;
  history = {
    persistence = "save-all"; # save-all | none
    # max_bytes = 104857600; # example; unset means no limit
  };

  # MCP and integrations
  # Server records are compiled per client by ../mcp.nix.
  # Codex accepts command/args for stdio or url for HTTP, with no type field.
  mcp_servers = { };
  mcp_oauth_credentials_store = "auto"; # auto | file | keyring
  # mcp_oauth_callback_port = 8765; # example; unset binds an OS-chosen port
  # mcp_oauth_callback_url = "https://example.com/callback";
  # Initial tool-catalog grace period; zero waits for each server's timeout.
  # mcp_optional_startup_grace_ms = 1000;
  # Enterprise IdP shared by EMA-enabled MCP servers and plugins. A client_secret
  # set here would land in the Nix store with the rendered config; a public
  # client omits it, and token_endpoint_auth_method requires one.
  # mcp_enterprise_managed_auth.idp = {
  #   issuer = "";
  #   client_id = "";
  #   token_endpoint_auth_method = "client_secret_basic"; # client_secret_basic | client_secret_post
  # };
  # _default covers every app; app IDs override it and also take its keys.
  # apps = {
  #   _default = {
  #     enabled = true;
  #     destructive_enabled = true;
  #     open_world_enabled = true;
  #     default_tools_approval_mode = "auto"; # auto | prompt | writes | approve
  #     approvals_reviewer = "user"; # user | auto_review; unset follows approvals_reviewer
  #   };
  #   example = {
  #     omit_tools_from = [ ]; # code_mode | deferred | direct
  #     # Unset by default; an explicit value applies to every tool and skips the
  #     # destructive and open-world filters.
  #     default_tools_enabled = true;
  #     tools."repos/list" = { enabled = true; approval_mode = "auto"; };
  #     links.example = { approvals_reviewer = "user"; default_tools_approval_mode = "auto"; };
  #   };
  # };
  apps = { };
  # apps_mcp_product_sku = "";
  # Plugin enablement and per-server tool policies, keyed by name@marketplace.
  # plugins = {
  #   _default.enabled = true; # without _default, source enablement decides
  #   "example@marketplace" = {
  #     enabled = true;
  #     remote_plugin_id = "";
  #     release_id = "";
  #     auto_provision = false;
  #     mcp_servers = { };
  #     apps = { };
  #   };
  # };
  # marketplaces.example = {
  #   source_type = "git"; # git | local
  #   source = "";
  #   ref = "";
  #   sparse_paths = [ ];
  # };
  # tool_suggest = { disabled_tools = [ ]; discoverables = [ ]; };
  # Account-provided skills and MCP controls.
  # cloud = { skills.enabled = true; };
  # orchestrator = { mcp.enabled = true; };

  # Agents, skills, memory, and hooks
  # Agent roles are also discovered from agents/**/*.toml under the config directory.
  # agents = {
  #   enabled = true; # an enabled features.multi_agent_v2 takes precedence
  #   # V1 default 6. Under multi_agent_v2 the default is 4 threads including the root
  #   # (3 spawned), and N here becomes N+1 total unless [features.multi_agent_v2] sets its own.
  #   max_concurrent_threads_per_session = 6;
  #   max_depth = 1; # V1 only
  #   default_subagent_model = ""; # unset inherits the parent
  #   default_subagent_reasoning_effort = "high"; # example; unset inherits the parent
  #   interrupt_message = true;
  #   example = {
  #     description = "";
  #     config_file = "/absolute/path/role.toml";
  #     nickname_candidates = [ ];
  #   };
  # };
  # goals = { max_goal_token_budget = 1000000; }; # example; unset means no cap
  # _settings.nix sets memory use, generation, and retention.
  # memories = {
  #   # Fresh homes with memories on get v2 unless dual_write = false keeps v1.
  #   version = "v1"; # v1 | v2
  #   dual_write = false;
  #   disable_on_external_context = false;
  #   dedicated_tools = false;
  #   max_rollout_age_days = 10;
  #   max_rollouts_per_startup = 2;
  #   min_rollout_idle_hours = 6;
  #   min_rate_limit_remaining_percent = 25;
  #   extract_model = ""; # unset uses the provider default
  #   consolidation_model = ""; # unset uses the provider default
  #   consolidation_service_tier = "default"; # default | priority | flex
  # };
  # skills = {
  #   bundled.enabled = true;
  #   include_instructions = true;
  #   max_context_tokens = 10000; # cap for set values; unset uses 2% of the context window
  #   config = [ ];
  # };
  # Inline lifecycle hooks use the hooks.json event schema.
  # hooks = { };

  # Browser, computer, and web tools
  web_search = "cached"; # disabled | cached | indexed | live
  # Browser Use policy for the desktop app's browser plugin. A deny here or in
  # requirements.toml wins; unset actions are allowed.
  # browser_use = {
  #   allow_history_access = true; # false blocks history access
  #   default_origin_policy = {
  #     access = "allow"; # allow | deny
  #     downloads = "allow"; # allow | deny
  #     uploads = "allow"; # allow | deny
  #     full_cdp_access = "allow"; # allow | deny
  #   };
  #   origins."https://example.com" = { access = "deny"; };
  # };
  # computer_use = { };
  # tools = {
  #   # Fallback only when the model selects no search provider; unset then means
  #   # no client search.
  #   client_search_provider = "standalone"; # standalone | search_mcp
  #   web_search = {
  #     context_size = "medium"; # low | medium | high
  #     # Omission is unrestricted; any list, even an empty one, is an allow-list.
  #     allowed_domains = [ "example.com" ];
  #     location = { country = ""; region = ""; city = ""; timezone = ""; };
  #   };
  #   experimental_request_user_input.enabled = true;
  #   update_plan.enabled = false; # the task-progress status line item needs it
  # };
  # Idle seconds between code-mode host heartbeats; zero disables them.
  # code_mode.heartbeat_interval_s = 0;

  # Realtime and experimental storage
  # audio = {
  #   microphone = ""; # unset uses the system default
  #   speaker = ""; # unset uses the system default
  #   microphone_channel = [ 1 ]; # example; 1-based int or list, unset mixes all inputs
  # };
  # realtime = {
  #   version = "v2"; # v1 | v2 | v3
  #   type = "conversational"; # conversational | transcription
  #   # Unset: cove for v1, marin for v2 and v3; ChatGPT-backend WebRTC calls use cove.
  #   voice = "marin";
  # };
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
    # metrics_exporter = "statsig"; # none | statsig | { otlp-http = { ... }; } | { otlp-grpc = { ... }; }
    log_user_prompt = false;
    # log_agent_responses = false;
    # log_guardian_assessments = false;
    # log_sse_deltas = true;
    # Prints a JSON header map for explicit OTLP HTTP exporters; runs from CODEX_HOME.
    # headers_helper = "/absolute/path/to/program";
    # headers_helper_refresh_interval_ms = 1740000;
    # span_attributes = { };
    # tracestate = { };
    # tool_result.max_bytes = 2048;
  };

  # Terminal UI
  hide_agent_reasoning = false;
  show_raw_agent_reasoning = false;
  # notify = [ "/absolute/path/to/program" ]; # gets the turn's JSON payload as its last argument
  # Notice acknowledgements are written by Codex; desktop holds the desktop app's
  # own settings (git-branch-prefix, git-worktree-root, ...), written by the app.
  # notice = { };
  # desktop = { };
  tui = {
    alternate_screen = "auto"; # auto | always | never
    animations = true;
    disable_paste_burst = false;
    notification_method = "auto"; # auto | osc9 | osc777 | bel
    # notification_condition = "unfocused"; # unfocused | always
    # notifications = true; # Boolean or list of event names.
    raw_output_mode = false;
    show_tooltips = true;
    status_line_use_colors = true;
    vim_mode_default = false;
    # status_line = [ "model-with-reasoning" "current-dir" "thread-name" ];
    # terminal_title = [ "activity" "thread-name" "project-name" ];
    # theme = "one-half-dark"; # example; unset follows terminal light/dark detection
    # resume_cwd = "current"; # current | session; example, unset prompts when they differ
    # auto_recap = true;
    # fullscreen_transcript = true;
    # collapse_turn_details = false;
    # session_picker_view = "dense"; # dense | comfortable
    # show_server_version_notice = true;
    # question_esc_back = true;
    # sidebar_width_percent = 33; # example; unset uses one third
    # mouse_scroll_speed = 1.0;
    # copy_on_select = "auto"; # auto | always | never
    # copy_on_select_clear_selection = false;
    # right_click_paste = "auto"; # auto | on | off
    # Set zero for unlimited resize replay; omission selects a terminal default.
    # terminal_resize_reflow_max_rows = 0;
    # Individual effects also require animations; content rendering is separate.
    # effects = {
    #   starfield = true;
    #   shimmer = true;
    #   welcome = true;
    #   effort = true;
    #   progress = true;
    #   title = true;
    # };
    # rendering = { mermaid = true; math = true; tables = true; lists = true; };
    # Keymap contexts and action names come from config/src/tui_keymap.rs.
    # keymap = { global.toggle_vim_mode = "alt-v"; }; # example
    # Saved prompts and slash commands keyed 0 through 9.
    # presets = { "1" = { input = ""; label = ""; }; };
    # pet = "";
    # pet_anchor = "composer"; # composer | screen-bottom
  };
}
