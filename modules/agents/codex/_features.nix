/*
  Codex feature flags from codex-rs/features/src/lib.rs and feature_configs.rs,
  Bad3r/codex main b1573f102413e96a6481087922bf425231222dee.
  Active entries are site policy. Commented entries show upstream defaults;
  uncomment to pin a value. Covers flags read by the CLI, TUI, app-server, or the
  desktop app (modules/apps/chatgpt), which shares this config. Omitted: removed,
  deprecated, and Windows-only flags, and flags nothing reads.
  A recognized under-development flag can still require server-side enablement.
  Commented `{ ... }` lines are the [features.<name>] table form; use one form per
  flag. code_mode, multi_agent_v2, network_proxy, sleep_tool, and
  runtime_agent_instances merge bool and table across config layers; other tables
  replace lower layers whole (config/src/merge.rs).
*/
{
  # Enable shared discussion tools for an agent tree.
  # agent_message_board = false; # UnderDevelopment; upstream: false

  # Expose a tree-scoped in-memory message board through HTTP MCP.
  # agent_message_board_mcp = false; # UnderDevelopment; upstream: false

  # Preview consumer five-hour and weekly allowance history.
  # analytics_plan_history = false; # Experimental; upstream: false

  # Forward explicit programs with builtin OpenAI API keys.
  # api_key_cyber_access_programs = true; # Stable; upstream: true

  # Discover model catalogs for OpenAI API-key authentication.
  # api_key_model_discovery = true; # Stable; upstream: true

  # Enable negotiated zstd compression for app-server WebSocket and UDS connections.
  # app_server_websocket_compression = false; # UnderDevelopment; upstream: false

  # Stream structured progress while apply_patch input is being generated.
  apply_patch_streaming_events = false; # UnderDevelopment; upstream: false

  # Enable apps.
  apps = true; # Stable; upstream: true

  # Let host-owned Apps catalog reads overlap the initial tool inventory.
  # apps_early_resource_discovery = false; # UnderDevelopment; upstream: false

  # Prepare remote compaction in the background before the foreground limit is reached.
  # async_compaction = false; # UnderDevelopment; upstream: false
  # Threshold is a percent of the full context window; off while token_budget is on.
  # async_compaction = { enabled = false; model_async_compact_threshold_percent = 65; };

  # Restrict background compaction to the root session.
  # async_compaction_root_only = false; # UnderDevelopment; upstream: false

  # Prompt Codex Apps connector auth failures through MCP URL elicitations.
  auth_elicitation = false; # Stable; upstream: true

  # Migrate legacy local rollout files to paginated history in the background.
  # background_paginated_rollout_migration = false; # UnderDevelopment; upstream: false

  # Offer Amazon Bedrock setup during TUI sign-in onboarding.
  # bedrock_setup_wizard = true; # Stable; upstream: true

  # Allow websites to open and customize annotation tools in desktop apps.
  # Ordinary user-driven annotation is independent of this gate.
  # Desktop app. Upstream marks it a requirements.toml gate; false here also
  # applies, while true still needs a managed requirement or the app's rollout.
  # browser_annotation_api = true; # Stable; upstream: true

  # Allow Browser Use agent integration in desktop apps.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # browser_use = true; # Stable; upstream: true

  # Allow Browser Use integration with external browsers.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # browser_use_external = true; # Stable; upstream: true

  # Use Apps usage instructions from the selected model's catalog entry.
  # catalog_apps_instructions = false; # UnderDevelopment; upstream: false

  # Enable the Chronicle sidecar for passive screen-context memories.
  # Desktop app; codex-rs has no reader.
  chronicle = false; # UnderDevelopment; upstream: false

  # Enable Daybreak controls and automatic access-program selection in CLI clients.
  # cli_daybreak = true; # Stable; upstream: true

  # Restrict CLI resume of attributed local threads to their creator.
  # cli_resume_account_check = false; # UnderDevelopment; upstream: false

  # Enable JavaScript code mode backed by the standalone host process.
  code_mode = false; # UnderDevelopment; upstream: false
  # code_mode = {
  #   enabled = false;
  #   default_exec_yield_time_ms = 30000;
  #   experimental_show_cell_overhead = false;
  #   tool_input_schema_max_bytes = 16000; # also the minimum
  #   excluded_tool_namespaces = [ ];
  #   direct_only_tool_namespaces = [ ];
  # };

  # Use the code-mode host bundled with the Codex package.
  code_mode_host = true; # Stable; upstream: true
  # code_mode_host = { enabled = true; disable_in_process_fallback = false; };

  # Use gRPC over stdio for the process-owned code-mode host.
  # code_mode_host_grpc = true; # Stable; upstream: true

  # Truncate output in the process-owned code-mode host before sending it to Core.
  # code_mode_host_output_truncation = true; # Stable; upstream: true

  # Terminate active code mode cells when their turn is interrupted.
  # code_mode_interrupt = true; # Stable; upstream: true

  # Restrict model-visible tools to code mode entrypoints (`exec`, `wait`).
  code_mode_only = false; # UnderDevelopment; upstream: false

  # Keep eligible MCP/app and dynamic tools deferred in exec, only in Code Mode Only.
  # Ignores deferLoading, omit_tools_from, and namespace skip settings.
  # code_mode_only_strict_3p_tools = false; # UnderDevelopment; upstream: false

  # Establish the code-mode host connection during session startup.
  # code_mode_prewarm = false; # UnderDevelopment; upstream: false

  # Expose ranked tool discovery inside JavaScript code mode.
  # code_mode_tool_search = false; # UnderDevelopment; upstream: false

  # Enable MCP protocol version 2026-07-28 for the host-owned Codex Apps server.
  # codex_apps_mcp_2026_07_28 = false; # UnderDevelopment; upstream: false

  # Publish retained command sessions through incremental world state.
  # command_sessions_world_state = false; # UnderDevelopment; upstream: false

  # Include retained images in the remote compaction context budget.
  # compaction_image_budget = true; # Stable; upstream: true

  # Allow Codex Computer Use.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # computer_use = true; # Stable; upstream: true

  # Request sequential cutoff reasoning summary delivery.
  # concurrent_reasoning_summaries = false; # UnderDevelopment; upstream: false

  # Send per-content-entry classifications in internal Responses metadata.
  # content_item_kinds = true; # Stable; upstream: true

  # Enables experimental context management.
  # context_management = false; # UnderDevelopment; upstream: false
  # Toggled by experimental_mode, not enabled; forces token_budget on for Plus/Pro plans.
  # context_management = { experimental_mode = false; };

  # Mask credentials and inject them through an already enabled network proxy.
  # credential_masking = false; # UnderDevelopment; upstream: false

  # Capture internal direct-tool dependency paths for turn attribution.
  # critical_path_timing = false; # UnderDevelopment; upstream: false

  # Add current-time reminders to model-visible context.
  # current_time_reminder = false; # UnderDevelopment; upstream: false
  # current_time_reminder = {
  #   enabled = false;
  #   reminder_interval_seconds = 1;
  #   clock_source = "system"; # system | external
  #   delivery_mode = "any_inference"; # any_inference | after_user_or_tool_output
  #   sleep_tool = false; # clock.sleep in model_driven mode
  # };

  # Use the current working directory for turn diff display paths.
  # cwd_relative_turn_diffs = false; # UnderDevelopment; upstream: false

  # Keep launches on the selected package and its current environment.
  daemon_auto_start = false; # Stable; upstream: true

  # Capture the saved Daybreak choice for a native helper and its turns.
  # daybreak_program_propagation = false; # UnderDevelopment; upstream: false

  # Allow request_user_input in Default collaboration mode.
  default_mode_request_user_input = true; # UnderDevelopment; upstream: false

  # Keep sampling through reasoning and commentary boundaries when agent mail arrives.
  # Pending mail is delivered at the next normal input boundary instead.
  # defer_mailbox_preemption = false; # UnderDevelopment; upstream: false

  # Allow turns to start while selected executors are still starting.
  # deferred_executor = false; # UnderDevelopment; upstream: false

  # Describe deferred tool namespaces in the model-visible world state.
  # deferred_tool_world_state = true; # Stable; upstream: true

  # Enable MCP apps.
  enable_mcp_apps = false; # UnderDevelopment; upstream: false

  # Compress request bodies (zstd) when sending streaming requests to codex-backend.
  enable_request_compression = false; # Stable; upstream: true

  # Allow exec tools to request additional permissions while staying sandboxed.
  exec_permission_approvals = true; # UnderDevelopment; upstream: false

  # Record model-attempted tool calls in internal Responses metadata.
  # executed_tool_call_metadata = false; # UnderDevelopment; upstream: false

  # Discover selected-root plugin and skill manifests through one high-level
  # exec-server RPC.
  # executor_capability_discovery = false; # UnderDevelopment; upstream: false

  # Acquire V2 executor inventories without publishing or activating their capabilities.
  # executor_capability_discovery_v2 = false; # UnderDevelopment; upstream: false

  # Enable importing project-scoped memory from external agents.
  # external_agent_memory_import = false; # UnderDevelopment; upstream: false

  # Enable Fast mode selection in the TUI and request layer.
  fast_mode = true; # Stable; upstream: true

  # Allow this host's attachment store to prepare fresh tool audio before persistence.
  # file_backed_tool_audio = false; # UnderDevelopment; upstream: false

  # Offer custom gateway setup during TUI sign-in onboarding.
  # gateway_setup_wizard = false; # Stable; upstream: false

  # Offer Google Cloud Vertex AI setup during TUI sign-in onboarding.
  # gcp_setup_wizard = false; # Stable; upstream: false

  # Enable persisted thread goals and automatic goal continuation.
  goals = true; # Stable; upstream: true

  # Enable automatic review for approval prompts.
  guardian_approval = true; # Stable; upstream: true

  # Give Guardian access to the root conversation's message history tools.
  # guardian_conversation_history_tools = false; # UnderDevelopment; upstream: false

  # Resample a synchronous Guardian denial once before publishing it.
  # guardian_denial_reconsideration = false; # UnderDevelopment; upstream: false

  # Include completed node_repl or cua_repl Code Mode responses in Guardian reviews.
  # guardian_enhanced_node_repl_transcripts = false; # UnderDevelopment; upstream: false

  # Include standalone additional-context tool outputs in Guardian review history.
  # guardian_include_additional_context = true; # Stable; upstream: true

  # Review state-changing MAv2 calls and preserve native calls in Guardian history.
  # guardian_native_multi_agent_history = false; # UnderDevelopment; upstream: false

  # Include completed node_repl or cua_repl Code Mode response images in Guardian
  # reviews.
  # guardian_node_repl_transcript_images = false; # UnderDevelopment; upstream: false

  # Forward private reviewer items and interruptions to raw-event observers.
  # guardian_recorded_items = false; # UnderDevelopment; upstream: false

  # Reuse encrypted parent compaction when restarting Guardian review sessions.
  # guardian_reuse_parent_compaction = true; # Stable; upstream: true

  # Limit worker Guardian root evidence to preceding root communication windows.
  # guardian_root_handoff_context = false; # UnderDevelopment; upstream: false

  # Trust connector identities from the plugin service orchestrator in Guardian V2.
  # guardian_trust_orchestrator_connectors = false; # UnderDevelopment; upstream: false

  # Enable Guardian V2 automatic approval reviews.
  # guardianv2 = false; # UnderDevelopment; upstream: false
  # Elastic budgeting also takes {sync,async}_elastic_sections maps.
  # guardianv2 = {
  #   enabled = false;
  #   transcript_mode = "line"; # line | json
  #   sync_elastic_budgeting = false;
  #   async_elastic_budgeting = false;
  #   async_classifier_conversation_token_limit = 100000;
  #   persist_scores = false;
  #   classifier_instructions = ""; # unset uses the bundled prompt
  #   review_threshold = 0.5; # 0.8 when classifier_instructions is set
  #   max_tool_call_lag = 2;
  #   reasoning_effort = "low";
  #   max_action_tokens = 10000;
  #   max_parent_compaction_tokens = 25000;
  #   max_classifier_instruction_tokens = 100000; # example; unset means no cap
  #   reuse_parent_compaction = true;
  #   review_scope = { computer_use_only = true; sandboxed_exec_commands = false; };
  #   transcript = {
  #     sources = [ "tool_calls" "tool_outputs" ]; # also reasoning
  #     include_images = true;
  #     max_message_entry_tokens = 2000;
  #     max_tool_entry_tokens = 1000;
  #     max_message_transcript_tokens = 10000;
  #     max_tool_transcript_tokens = 10000;
  #     max_recent_non_user_entries = 40;
  #   };
  # };

  # Run Decisions alongside Guardian V2 for measurement without changing approvals.
  # guardianv2_decisions_comparison = false; # UnderDevelopment; upstream: false

  # Enable Guardian V3 integrations.
  # guardianv3 = false; # UnderDevelopment; upstream: false

  # Enable Claude-style lifecycle hooks loaded from hooks.json files.
  hooks = true; # Stable; upstream: true

  # Let the host authorize MCP search independently of native search through
  # per-turn policy.
  # hosted_search_policy = false; # UnderDevelopment; upstream: false

  # Enable extension-backed image generation.
  image_generation = true; # Stable; upstream: true

  # Allow the image-generation tool to request a backend-assembled GIF.
  # image_generation_animation = false; # UnderDevelopment; upstream: false

  # Tell the model when a prompt image was resized and include its dimensions.
  # image_resize_notice = false; # UnderDevelopment; upstream: false

  # Allow the in-app browser pane in desktop apps.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # in_app_browser = true; # Stable; upstream: true

  # Allow the in-app chat pane in desktop apps.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # in_app_chat = true; # Stable; upstream: true

  # Allow in-app dictation in desktop apps.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # in_app_dictation = true; # Stable; upstream: true

  # Allow desktop apps to run local automations.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # in_app_local_automation = true; # Stable; upstream: true

  # Allow desktop apps to perform in-app updates.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # in_app_updates = true; # Stable; upstream: true

  # Allow in-app Voice in desktop apps.
  # Permission does not establish Voice availability or provider support.
  # Desktop app. Upstream marks it a requirements.toml gate; user config also applies.
  # in_app_voice = true; # Stable; upstream: true

  # Diff CodeModeOnly exec definitions within the incremental tool catalog.
  # incremental_exec_tools = false; # UnderDevelopment; upstream: false

  # Track top-level tool definitions in world state and emit incremental context
  # updates.
  # incremental_tools = true; # Stable; upstream: true

  # Publish incremental tool declarations on regular Amazon Bedrock Responses.
  # incremental_tools_legacy = true; # Stable; upstream: true

  # Publish incremental tool declarations on regular GCP Responses.
  # incremental_tools_legacy_gcp = true; # Stable; upstream: true

  # Preempt responses and yield foreground code-mode observations on new user input.
  # instant_interrupt = true; # UnderDevelopment; upstream: true

  # Interrupt upstream inference when a turn is cancelled.
  # interrupt_on_cancel = false; # UnderDevelopment; upstream: false

  # Compress cold local thread-store rollout files, including shared histories.
  # Requires every reader of the Codex home to support compressed shared histories.
  # local_thread_store_compression = false; # UnderDevelopment; upstream: false

  # Restore bundled tools to PATH after Codex's login shell starts.
  # login_shell_package_path = false; # Experimental; upstream: false

  # Enable MCP protocol version 2026-07-28 support.
  # mcp_2026_07_28 = false; # UnderDevelopment; upstream: false

  # Discover and share eligible local stdio connections across chats.
  # mcp_connection_sharing = false; # UnderDevelopment; upstream: false

  # Defer optional stdio server startup in regular chats with a warm tool catalog.
  # mcp_lazy_stdio_startup = false; # UnderDevelopment; upstream: false

  # Let RMCP coordinate OAuth refresh through the configured credential store.
  # mcp_oauth_refresh_coordination = true; # Stable; upstream: true

  # Use the app server's fixed launch directories for shared REPL servers.
  # mcp_shared_repl_cwd = false; # UnderDevelopment; upstream: false

  # Honor ordinary MCP server tool-list notifications within a turn.
  # mcp_tool_list_changed = false; # UnderDevelopment; upstream: false

  # Enable startup memory extraction and file-backed memory consolidation.
  memories = true; # Stable; upstream: false

  # Enable the unified mention popup used by default in the TUI.
  mentions_v2 = true; # Stable; upstream: true

  # Keep spawn model choices in append-only context instead of tool descriptions.
  # model_catalog_in_context = false; # UnderDevelopment; upstream: false

  # Enable task-path-based multi-agent routing.
  multi_agent_v2 = true; # Stable; upstream: false
  # Unset hint texts use the model catalog's; "" suppresses one.
  # multi_agent_v2 = {
  #   enabled = true;
  #   # Includes the root; unset is agents.max_concurrent_threads_per_session + 1, else 4.
  #   max_concurrent_threads_per_session = 4;
  #   min_wait_timeout_ms = 10000;
  #   max_wait_timeout_ms = 3600000;
  #   default_wait_timeout_ms = 30000;
  #   usage_hint_text = "";
  #   root_agent_usage_hint_text = "";
  #   subagent_usage_hint_text = "";
  #   multi_agent_mode_hint_text = "";
  #   subagent_developer_instructions = ""; # unset inherits the parent's
  #   preserve_fork_prefix = true;
  #   tool_namespace = "collaboration";
  #   hide_spawn_agent_metadata = true;
  #   expose_spawn_agent_model_overrides = true;
  #   wait_agent_enabled = true;
  #   disable_native_tools = false;
  #   disable_direct_message = false;
  #   non_code_mode_only = true;
  #   message_board_in_memory = false; # needs agent_message_board
  #   message_board_remote = {
  #     url = "https://example.com/board";
  #     bearer_token_env_var = "EXAMPLE_TOKEN";
  #   };
  # };

  # Inherit client-defined dynamic tools in fresh V2 subagents.
  # multi_agent_v2_dynamic_tools = false; # UnderDevelopment; upstream: false

  # Copy files between explicitly selected execution environments.
  # multi_env_copy_file = false; # UnderDevelopment; upstream: false

  # Keep same-named HTTP servers discovered on different executors separate.
  # multi_environment_mcp = false; # UnderDevelopment; upstream: false

  # Start the managed network proxy for sandboxed sessions.
  network_proxy = false; # Experimental; upstream: false
  # Applies only when the permission profile already allows network access.
  # network_proxy = {
  #   enabled = false;
  #   proxy_url = "http://127.0.0.1:3128";
  #   socks_url = "http://127.0.0.1:8081";
  #   enable_socks5 = true;
  #   enable_socks5_udp = true;
  #   allow_upstream_proxy = true;
  #   mode = "full"; # limited | full
  #   domains = { "example.com" = "allow"; }; # allow | deny
  #   unix_sockets = { "/absolute/path/socket" = "allow"; }; # allow | deny
  #   allow_local_binding = false;
  #   credential_broker = false;
  #   dangerously_allow_non_loopback_proxy = false;
  #   credentials = { }; # credential injection providers
  # };

  # Expose MCP model-visible namespaces without the legacy `mcp__` prefix.
  non_prefixed_mcp_tool_names = false; # UnderDevelopment; upstream: false
  # Unset server_names drops the prefix for every server.
  # non_prefixed_mcp_tool_names = { enabled = false; server_names = [ "example" ]; };

  # Report failed clock reads to the model without failing the turn.
  # nonfatal_clock_read_errors = false; # UnderDevelopment; upstream: false

  # Omit inline image and audio content from app-server item notifications.
  # omit_app_server_notification_media = false; # UnderDevelopment; upstream: false

  # Omit descriptions from the model-visible available-skills catalog.
  # omit_skill_descriptions = false; # UnderDevelopment; upstream: false

  # Request encrypted sampled output for token-preserving replay.
  # output_token_replay = false; # UnderDevelopment; upstream: false

  # Describe each selected environment's filesystem and permissions separately.
  # per_environment_context = false; # UnderDevelopment; upstream: false

  # Enable remote plugin sharing flows.
  plugin_sharing = true; # Stable; upstream: true

  # Enable plugins.
  plugins = true; # Stable; upstream: true

  # Expose the selected PowerShell execution host's bounded major/minor version.
  # powershell_shell_version = false; # UnderDevelopment; upstream: false

  # Preserve inherited tool declarations in MCP-disabled prediction forks.
  # prediction_preserve_parent_tools = true; # Stable; upstream: true

  # Prevent idle system sleep while a turn is actively running.
  prevent_idle_sleep = false; # Experimental; upstream: false

  # Route first-party ChatGPT requests through PSP.
  # psp = false; # UnderDevelopment; upstream: false

  # Append trusted response configuration items when the selected reasoning effort
  # changes.
  # reasoning_effort_override = true; # Stable; upstream: true

  # Include recommended plugins in model-visible context.
  # recommended_plugins = false; # Stable; upstream: false

  # Enable the PS-backed remote plugin catalog.
  remote_plugin = false; # Stable; upstream: true

  # Expose the built-in request_permissions tool.
  request_permissions_tool = false; # UnderDevelopment; upstream: false

  # Respect host system proxy settings for Codex-owned network clients.
  # respect_system_proxy = false; # Experimental; upstream: false

  # Retain client-authored developer messages across compacted context windows.
  # retain_client_developer_messages = false; # UnderDevelopment; upstream: false

  # Honor client-requested tool-output retention across context windows.
  # retain_client_tool_outputs = true; # Stable; upstream: true

  # Track and report a shared token budget across a session's agent threads.
  # rollout_budget = false; # UnderDevelopment; upstream: false
  # rollout_budget = {
  #   enabled = false;
  #   limit_tokens = 1000000; # example; required when enabled
  #   reminder_at_remaining_tokens = [ 100000 ]; # example
  #   sampling_token_weight = 1.0;
  #   prefill_token_weight = 1.0;
  #   enforce_limit = true;
  # };

  # Register an ephemeral runtime for OpenAI request authentication.
  # runtime_agent_instances = false; # UnderDevelopment; upstream: false
  # runtime_agent_instances = {
  #   enabled = false;
  #   mode = "dual_header"; # dual_header | assertion_only
  # };

  # Runtime snapshots follow local capture in _settings.nix and _telemetry.nix.
  # runtime_metrics = false; # UnderDevelopment; upstream: false

  # Normalize prompt images with the reviewed image sanitizer.
  # safe_image_decoder = false; # UnderDevelopment; upstream: false

  # Store CLI auth in the encrypted local secrets backend when keyring storage is
  # selected.
  # secret_auth_storage = false; # Stable; upstream: false

  # Allow root agents to send async user messages without model catalog support.
  # send_message_to_user_async = false; # UnderDevelopment; upstream: false

  # Experimental shell snapshotting.
  shell_snapshot = true; # Stable; upstream: true

  # Keep policy-filtered shell snapshots entirely in executor memory.
  # shell_snapshot_v2 = false; # UnderDevelopment; upstream: false

  # Enable the default shell tool.
  shell_tool = true; # Stable; upstream: true

  # Use concise developer hints for explicitly selected plugins.
  # simplified_selection_hints = false; # UnderDevelopment; upstream: false

  # Append skill additions and edits within a cumulative context budget.
  # skill_catalog_deltas = false; # UnderDevelopment; upstream: false

  # Allow prompting and installing missing MCP dependencies.
  skill_mcp_dependency_install = true; # Stable; upstream: true

  # Run cheap skill-search methods in shadow mode and emit experiment metrics.
  # skill_search = true; # Stable; upstream: true

  # Skip host skill snapshots when no registered contributor requires them.
  # skip_host_skill_discovery = false; # UnderDevelopment; upstream: false

  # Allow registration of the built-in sleep tool.
  # sleep_tool = true; # Stable; upstream: true
  # sleep_tool = {
  #   enabled = true;
  #   mode = "model_driven"; # model_driven | always_on
  # };

  # Expose the extension-backed standalone web search tool; kagi-search-webrun
  # answers it (home.nix).
  standalone_web_search = true; # UnderDevelopment; upstream: false

  # Enable explicitly requested model changes for later step captures.
  # step_model_switching = false; # UnderDevelopment; upstream: false

  # Use each subagent model's default context window and auto-compaction threshold.
  # subagent_default_context_limits = false; # UnderDevelopment; upstream: false

  # Inherit configured thread environments instead of temporary turn selections.
  # subagent_thread_environments = false; # UnderDevelopment; upstream: false

  # Suppress the model ID announcement in incremental context after a model switch.
  # suppress_model_change_announcements = false; # Stable; upstream: false

  # Retry eligible bootstrap requests through the system proxy after normal routing
  # fails.
  # system_proxy_fallback = true; # Stable; upstream: true

  # Add terminal-specific visualization guidance to TUI developer instructions.
  # terminal_visualization_instructions = false; # UnderDevelopment; upstream: false

  # Add current context-window metadata to model-visible context.
  # token_budget = false; # UnderDevelopment; upstream: false
  # token_budget = {
  #   enabled = false;
  #   use_history_notes_extension = false;
  #   context_window_as_tool_output = false;
  #   reminder_threshold_tokens = 20000; # example; unset uses the model catalog's
  #   reminder_message_template = "{n_remaining} tokens left"; # example; unset is bundled
  #   guidance_message = ""; # unset means none
  #   # Set together: note-taking before an automatic context-window rollover.
  #   auto_compact_fallback_prompt = "";
  #   auto_compact_fallback_buffer_tokens = 4000; # example
  # };

  # Route MCP tool approval prompts through the MCP elicitation request path.
  tool_call_mcp_elicitation = true; # Stable; upstream: true

  # Tool registry checks; table only, `tool_registry = true` fails.
  # turn_metadata_includes_tool_info applies only to use_responses_lite models.
  # tool_registry = { error_on_tool_collisions = false; turn_metadata_includes_tool_info = false; };

  # Enable discoverable tool suggestions for apps.
  tool_suggest = true; # Stable; upstream: true

  # Allow the TUI to discover and select among multiple conversation backends.
  # tui_multi_backend = false; # UnderDevelopment; upstream: false

  # Enable workspace behavior for side conversations in the owned TUI.
  # tui_workspace = true; # Stable; upstream: true

  # Enable Ultra Fast mode independently of Fast mode.
  # ultrafast_mode = true; # Stable; upstream: true

  # Keep active sampling turns alive until a failed network connection recovers.
  # unbounded_connection_retries = true; # Stable; upstream: true

  # Use the single unified PTY-backed exec tool.
  unified_exec = true; # Stable; upstream: true

  # Allow unified exec commands to allocate an interactive terminal.
  # unified_exec_tty = true; # Stable; upstream: true

  # Apply one shared pixel and token budget to every image, regardless of legacy
  # detail hints.
  # unified_image_budget = true; # Stable; upstream: true

  # Render client-supplied untrusted context as standalone named tool outputs.
  # untrusted_as_tool_output = true; # Stable; upstream: true

  # Use Agent Identity for ChatGPT-authenticated sessions.
  # use_agent_identity = false; # UnderDevelopment; upstream: false

  # Enable enterprise refresh-token authorization for configured MCP resources.
  # use_xaa = false; # UnderDevelopment; upstream: false

  # Enable the built-in local image viewer.
  # view_image = true; # Stable; upstream: true

  # Allow agent messages to wake idle root sessions after a completed turn.
  # wake_on_agent_messages = false; # UnderDevelopment; upstream: false

  # Enable workspace dependency support.
  # Desktop app: "Allow ChatGPT to install and expose bundled Node.js and Python
  # tools". codex-rs has no reader.
  workspace_dependencies = true; # Stable; upstream: true

  # Require approval before writing input to escalated unified-exec terminals.
  # write_stdin_approval = true; # Stable; upstream: true

}
