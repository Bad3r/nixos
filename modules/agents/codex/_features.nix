/*
  Codex feature flags from codex-rs/features/src/lib.rs and feature_configs.rs,
  openai/codex 58670eeac4b0bdb9fcb86929d8631c14aee0d9f6.
  Active entries are site policy. Commented entries show upstream defaults;
  uncomment to pin a value. Removed, deprecated, and Windows-only flags are omitted.
  A recognized under-development flag can still require server-side enablement.
*/
{
  # Enable shared discussion tools for an agent tree.
  # agent_message_board = false; # UnderDevelopment; upstream: false

  # Preview consumer five-hour and weekly allowance history.
  # analytics_plan_history = false; # Experimental; upstream: false

  # Discover model catalogs for OpenAI API-key authentication.
  # api_key_model_discovery = false; # UnderDevelopment; upstream: false

  # Preserve existing line endings when apply_patch updates files.
  # apply_patch_preserve_line_endings = false; # UnderDevelopment; upstream: false

  # Stream structured progress while apply_patch input is being generated.
  apply_patch_streaming_events = false; # UnderDevelopment; upstream: false

  # Enable apps.
  apps = true; # Stable; upstream: true

  # Enable native artifact tools.
  artifact = false; # UnderDevelopment; upstream: false

  # Prompt Codex Apps connector auth failures through MCP URL elicitations.
  auth_elicitation = false; # Stable; upstream: true

  # Migrate legacy local rollout files to paginated history in the background.
  # background_paginated_rollout_migration = false; # UnderDevelopment; upstream: false

  # Offer Amazon Bedrock setup during TUI sign-in onboarding.
  # bedrock_setup_wizard = false; # UnderDevelopment; upstream: false

  # Enable the Chronicle sidecar for passive screen-context memories.
  chronicle = false; # UnderDevelopment; upstream: false

  # Enable JavaScript code mode backed by the standalone host process.
  code_mode = false; # UnderDevelopment; upstream: false

  # Use the code-mode host installed by _packaged-codex.nix.
  code_mode_host = true; # Stable; upstream: true

  # Terminate active code mode cells when their turn is interrupted.
  # code_mode_interrupt = false; # UnderDevelopment; upstream: false

  # Restrict model-visible tools to code mode entrypoints (`exec`, `wait`).
  code_mode_only = false; # UnderDevelopment; upstream: false

  # Establish the code-mode host connection during session startup.
  # code_mode_prewarm = false; # UnderDevelopment; upstream: false

  # Enable MCP protocol version 2026-07-28 for the host-owned Codex Apps server.
  # codex_apps_mcp_2026_07_28 = false; # UnderDevelopment; upstream: false

  # Include retained images in the remote compaction context budget.
  # compaction_image_budget = true; # Stable; upstream: true

  # Request sequential cutoff reasoning summary delivery.
  # concurrent_reasoning_summaries = false; # UnderDevelopment; upstream: false

  # Send per-content-entry classifications in internal Responses metadata.
  # content_item_kinds = true; # Stable; upstream: true

  # Enables experimental context management.
  # context_management = false; # UnderDevelopment; upstream: false

  # Add current-time reminders to model-visible context.
  # current_time_reminder = false; # UnderDevelopment; upstream: false

  # Use the current working directory for turn diff display paths.
  # cwd_relative_turn_diffs = false; # UnderDevelopment; upstream: false

  # Automatically start the shared local daemon for eligible interactive launches.
  # daemon_auto_start = true; # Stable; upstream: true

  # Allow request_user_input in Default collaboration mode.
  default_mode_request_user_input = true; # UnderDevelopment; upstream: false

  # Keep sampling through reasoning and commentary boundaries when agent mail arrives.
  # Pending mail is delivered at the next normal input boundary instead.
  # defer_mailbox_preemption = false; # UnderDevelopment; upstream: false

  # Allow turns to start while selected executors are still starting.
  # deferred_executor = false; # UnderDevelopment; upstream: false

  # Describe deferred tool namespaces in the model-visible world state.
  # deferred_tool_world_state = false; # UnderDevelopment; upstream: false

  # Enable MCP apps.
  enable_mcp_apps = false; # UnderDevelopment; upstream: false

  # Compress request bodies (zstd) when sending streaming requests to codex-backend.
  enable_request_compression = false; # Stable; upstream: true

  # Allow exec tools to request additional permissions while staying sandboxed.
  exec_permission_approvals = true; # UnderDevelopment; upstream: false

  # Record model-attempted tool calls in internal Responses metadata.
  # executed_tool_call_metadata = false; # UnderDevelopment; upstream: false

  # Discover selected-root plugin and skill manifests through one high-level exec-
  # server RPC.
  # executor_capability_discovery = false; # UnderDevelopment; upstream: false

  # Enable importing project-scoped memory from external agents.
  # external_agent_memory_import = false; # UnderDevelopment; upstream: false

  # Enable Fast mode selection in the TUI and request layer.
  fast_mode = true; # Stable; upstream: true

  # Enable persisted thread goals and automatic goal continuation.
  goals = true; # Stable; upstream: true

  # Enable automatic review for approval prompts.
  guardian_approval = true; # Stable; upstream: true

  # Include completed node_repl or cua_repl Code Mode responses in Guardian reviews.
  # guardian_enhanced_node_repl_transcripts = false; # UnderDevelopment; upstream: false

  # Include completed node_repl or cua_repl Code Mode response images in Guardian
  # reviews.
  # guardian_node_repl_transcript_images = false; # UnderDevelopment; upstream: false

  # Reuse encrypted parent compaction when restarting Guardian review sessions.
  # guardian_reuse_parent_compaction = true; # Stable; upstream: true

  # Enable Guardian V2 automatic approval reviews.
  # guardianv2 = false; # UnderDevelopment; upstream: false

  # Enable Claude-style lifecycle hooks loaded from hooks.json files.
  hooks = true; # Stable; upstream: true

  # Enable extension-backed image generation.
  image_generation = true; # Stable; upstream: true

  # Tell the model when a prompt image was resized and include its dimensions.
  # image_resize_notice = false; # UnderDevelopment; upstream: false

  # Preempt responses and yield foreground code-mode observations on new user input.
  # instant_interrupt = false; # UnderDevelopment; upstream: false

  # Compress cold local thread-store rollout files, including shared histories.
  # Requires every reader of the Codex home to support compressed shared histories.
  # local_thread_store_compression = false; # UnderDevelopment; upstream: false

  # Enable MCP protocol version 2026-07-28 support.
  # mcp_2026_07_28 = false; # UnderDevelopment; upstream: false

  # Let RMCP coordinate OAuth refresh through the configured credential store.
  # mcp_oauth_refresh_coordination = false; # UnderDevelopment; upstream: false

  # Enable startup memory extraction and file-backed memory consolidation.
  memories = true; # Stable; upstream: false

  # Enable the unified mention popup used by default in the TUI.
  mentions_v2 = true; # Stable; upstream: true

  # Enable collab tools.
  multi_agent = true; # Stable; upstream: true

  # Enable task-path-based multi-agent routing.
  multi_agent_v2 = false; # Stable; upstream: false

  # Start the managed network proxy for sandboxed sessions.
  network_proxy = false; # Experimental; upstream: false

  # Expose MCP model-visible namespaces without the legacy `mcp__` prefix.
  non_prefixed_mcp_tool_names = false; # UnderDevelopment; upstream: false

  # Report failed clock reads to the model without failing the turn.
  # nonfatal_clock_read_errors = false; # UnderDevelopment; upstream: false

  # Omit inline image and audio content from app-server item notifications.
  # omit_app_server_notification_media = false; # UnderDevelopment; upstream: false

  # Enable remote plugin sharing flows.
  plugin_sharing = true; # Stable; upstream: true

  # Enable plugins.
  plugins = true; # Stable; upstream: true

  # Keep the host awake while a thread runs; experimental on Linux and macOS.
  prevent_idle_sleep = false; # Experimental; upstream: false

  # Route first-party ChatGPT requests through PSP.
  # psp = false; # UnderDevelopment; upstream: false

  # Enable voice conversations in the TUI.
  realtime_conversation = true; # Stable; upstream: true

  # Append trusted response configuration items when the selected reasoning effort
  # changes.
  # reasoning_effort_override = false; # UnderDevelopment; upstream: false

  # Include recommended plugins in model-visible context.
  # recommended_plugins = false; # Stable; upstream: false

  # Enable the PS-backed remote plugin catalog.
  remote_plugin = false; # Stable; upstream: true

  # Expose the built-in request_permissions tool.
  request_permissions_tool = false; # UnderDevelopment; upstream: false

  # Respect host system proxy settings for Codex-owned network clients.
  # respect_system_proxy = false; # UnderDevelopment; upstream: false

  # Retain client-authored developer messages across compacted context windows.
  # retain_client_developer_messages = false; # UnderDevelopment; upstream: false

  # Track and report a shared token budget across a session's agent threads.
  # rollout_budget = false; # UnderDevelopment; upstream: false

  # Enable runtime metrics snapshots via a manual reader.
  runtime_metrics = false; # UnderDevelopment; upstream: false

  # Allow root agents to send async user messages without model catalog support.
  # send_message_to_user_async = false; # UnderDevelopment; upstream: false

  # Experimental shell snapshotting.
  shell_snapshot = true; # Stable; upstream: true

  # Keep policy-filtered shell snapshots entirely in executor memory.
  # shell_snapshot_v2 = false; # UnderDevelopment; upstream: false

  # Enable the default shell tool.
  shell_tool = true; # Stable; upstream: true

  # Use the zsh fork execution path. _wrapper.nix supplies a controlled bash shell.
  shell_zsh_fork = false; # UnderDevelopment; upstream: false

  # Allow prompting and installing missing MCP dependencies.
  skill_mcp_dependency_install = true; # Stable; upstream: true

  # Run cheap skill-search methods in shadow mode and emit experiment metrics.
  # skill_search = true; # Stable; upstream: true

  # Skip host skill snapshots when no registered contributor requires them.
  # skip_host_skill_discovery = false; # UnderDevelopment; upstream: false

  # Allow registration of the built-in sleep tool.
  # sleep_tool = true; # Stable; upstream: true

  # Expose the extension-backed standalone web search tool.
  standalone_web_search = false; # UnderDevelopment; upstream: false

  # Enable explicitly requested model changes for later step captures.
  # step_model_switching = false; # UnderDevelopment; upstream: false

  # Retry eligible bootstrap requests through the system proxy after normal routing
  # fails.
  # system_proxy_fallback = true; # Stable; upstream: true

  # Add terminal-specific visualization guidance to TUI developer instructions.
  # terminal_visualization_instructions = false; # UnderDevelopment; upstream: false

  # Add current context-window metadata to model-visible context.
  # token_budget = false; # UnderDevelopment; upstream: false

  # Route MCP tool approval prompts through the MCP elicitation request path.
  tool_call_mcp_elicitation = true; # Stable; upstream: true

  # Enable discoverable tool suggestions for apps.
  tool_suggest = true; # Stable; upstream: true

  # Keep active sampling turns alive until a failed network connection recovers.
  # unbounded_connection_retries = true; # Stable; upstream: true

  # Use the single unified PTY-backed exec tool.
  unified_exec = true; # Stable; upstream: true

  # Allow unified exec commands to allocate an interactive terminal.
  # unified_exec_tty = true; # Stable; upstream: true

  # Apply one shared pixel and token budget to every image, regardless of legacy
  # detail hints.
  # unified_image_budget = false; # UnderDevelopment; upstream: false

  # Use Agent Identity for ChatGPT-authenticated sessions.
  # use_agent_identity = false; # UnderDevelopment; upstream: false

  # Enable enterprise refresh-token authorization for configured MCP resources.
  # use_xaa = false; # UnderDevelopment; upstream: false

  # Enable the built-in local image viewer.
  # view_image = true; # Stable; upstream: true

  # Enable workspace dependency support.
  workspace_dependencies = true; # Stable; upstream: true

  # Enable managed worktree creation and repository-aware sessions.
  # worktrees = true; # Stable; upstream: true

  # Require approval before writing input to escalated unified-exec terminals.
  # write_stdin_approval = true; # Stable; upstream: true

}
