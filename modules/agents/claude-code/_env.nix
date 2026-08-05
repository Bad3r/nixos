/*
  Single source of truth for the Claude Code environment variables that were
  otherwise hand-duplicated across the binary postFixup, settings.json, the
  Home Manager session variables, and the launch wrapper. Each consumer pulls
  exactly the subset it needs:

    * binary    baked into the Nix binary via wrapProgram (postFixup in
                modules/apps/claude-code.nix) so a bare `claude` that bypasses
                the ~/.local/bin wrapper still gets the privacy/update disables.
    * settings  ~/.claude/settings.json `env`, read by Claude at runtime
                regardless of launch path (binary disables + bash knobs).
    * all       full shell environment exported by the wrapper and the Home
                Manager session variables.

  Keeping the layers as one expression makes the belt-and-suspenders coverage
  explicit and removes the drift risk between sites.

  Two catalogs and an evidence list follow the active groups. The first
  enumerates every environment variable documented at
  https://code.claude.com/docs/en/env-vars for Claude Code 2.1.222, with its
  accepted values and default. The second lists type-resolved variables read by
  the 2.1.222 binary that the published docs do not mention. A final
  unconfirmed-identifiers list preserves extraction names whose accessor type
  could not be resolved. Activate a catalog entry by moving it into a group
  above; leaving it commented keeps Claude's own default.
*/
let
  # Privacy, telemetry, error-reporting, and update disables baked into the binary.
  binary = {
    DISABLE_AUTOUPDATER = "1";
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    DISABLE_ERROR_REPORTING = "1";
    DISABLE_TELEMETRY = "1";
    DISABLE_INSTALLATION_CHECKS = "1";
  };

  # Bash tool knobs Claude also reads from settings.json `env`.
  bashRuntime = {
    CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
    BASH_DEFAULT_TIMEOUT_MS = "240000";
    BASH_MAX_TIMEOUT_MS = "4800000";
  };

  # Model/effort routing. CLAUDE_CODE_SUBAGENT_MODEL overrides every spawned
  # subagent, including built-in agents whose definition pins `model: haiku`
  # (review, claude-code-guide); it beats agent frontmatter, which is the only
  # lever that reaches them. CLAUDE_CODE_EFFORT_LEVEL carries `max`, which the
  # persisted `effortLevel` schema rejects (see _default-settings.nix).
  modelRouting = {
    CLAUDE_CODE_SUBAGENT_MODEL = "claude-sonnet-5";
    CLAUDE_CODE_EFFORT_LEVEL = "max";
    # Repoints the `haiku` alias, which also backs background work the subagent
    # override does not reach (titles, summarization, classifiers).
    ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-sonnet-5";
    ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME = "Sonnet 5";
  };

  # Shell-level vars not needed in settings.json.
  shellOnly = {
    BASH_MAX_OUTPUT_LENGTH = "1024";
    CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL = "1";
    DISABLE_BUG_COMMAND = "1";
    USE_BUILTIN_RIPGREP = "0";
  };

  # Names removed from managed environment groups. These stay out of
  # `settings` and `all`; activation and launch wrappers delete old values.
  retired = [
    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE"
    "CLAUDE_CODE_ENABLE_TELEMETRY"
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS"
  ];
  retiredButLive = builtins.filter (
    name: builtins.hasAttr name (binary // bashRuntime // modelRouting // shellOnly)
  ) retired;

  # === Catalog: every documented Claude Code environment variable ===========
  # Entries marked ACTIVE are already set in a group above. Entries marked
  # RETIRED are intentionally removed from managed environments and old files.

  # Authentication and providers (30)
  # ------------------------------------
  # API key sent as X-Api-Key header.
  # ANTHROPIC_API_KEY = "";
  # Custom value for the Authorization header (the value you set here will be prefixed with Bearer ).
  # ANTHROPIC_AUTH_TOKEN = "";
  # Workspace API key for Claude Platform on AWS, generated in the AWS Console.
  # ANTHROPIC_AWS_API_KEY = "";
  # Override the Claude Platform on AWS endpoint URL. Use for custom regions or when routing through an LLM gateway.
  # ANTHROPIC_AWS_BASE_URL = "";
  # Required for Claude Platform on AWS. Sent on every request as the anthropic-workspace-id header.
  # ANTHROPIC_AWS_WORKSPACE_ID = "";
  # Override the Amazon Bedrock endpoint URL. Use for custom Amazon Bedrock endpoints or when routing through an LLM gateway.
  # ANTHROPIC_BEDROCK_BASE_URL = "";
  # Override the Amazon Bedrock Mantle endpoint URL. See Mantle endpoint.
  # ANTHROPIC_BEDROCK_MANTLE_BASE_URL = "";
  # Amazon Bedrock service tier (default, flex, or priority).
  # ANTHROPIC_BEDROCK_SERVICE_TIER = "";
  # Comma-separated list of additional anthropic-beta header values to include in API requests.
  # ANTHROPIC_BETAS = "";
  # Custom headers to add to requests (Name: Value format, newline-separated for multiple headers).
  # ANTHROPIC_CUSTOM_HEADERS = "";
  # API key for Microsoft Foundry authentication (see Microsoft Foundry).
  # ANTHROPIC_FOUNDRY_API_KEY = "";
  # Bearer token for Microsoft Foundry authentication, such as a Microsoft Entra access token.
  # ANTHROPIC_FOUNDRY_AUTH_TOKEN = "";
  # Full base URL for the Microsoft Foundry resource (for example, https://my-resource.services.ai.azure.com/anthropic).
  # ANTHROPIC_FOUNDRY_BASE_URL = "";
  # Microsoft Foundry resource name (for example, my-resource).
  # ANTHROPIC_FOUNDRY_RESOURCE = "";
  # Override Google Cloud's Agent Platform endpoint URL. Use for custom Google Cloud's Agent Platform endpoints or when routing through an LLM gateway.
  # ANTHROPIC_VERTEX_BASE_URL = "";
  # GCP project ID for Google Cloud's Agent Platform requests.
  # ANTHROPIC_VERTEX_PROJECT_ID = "";
  # Workspace ID for workload identity federation.
  # ANTHROPIC_WORKSPACE_ID = "";
  # Amazon Bedrock API key for authentication (see Amazon Bedrock API keys).
  # AWS_BEARER_TOKEN_BEDROCK = "";
  # Skip client-side authentication for Claude Platform on AWS, for gateways that sign requests themselves.
  # CLAUDE_CODE_SKIP_ANTHROPIC_AWS_AUTH = "";
  # Skip AWS authentication for Amazon Bedrock (for example, when using an LLM gateway).
  # CLAUDE_CODE_SKIP_BEDROCK_AUTH = "";
  # Skip Azure authentication for Microsoft Foundry, for a proxy or gateway that injects its own Authorization header.
  # CLAUDE_CODE_SKIP_FOUNDRY_AUTH = "";
  # Skip AWS authentication for Amazon Bedrock Mantle (for example, when using an LLM gateway).
  # CLAUDE_CODE_SKIP_MANTLE_AUTH = "";
  # Skip Google authentication for Google Cloud's Agent Platform (for example, when using an LLM gateway).
  # CLAUDE_CODE_SKIP_VERTEX_AUTH = "";
  # Use Claude Platform on AWS.
  # CLAUDE_CODE_USE_ANTHROPIC_AWS = "";
  # Use Amazon Bedrock.
  # CLAUDE_CODE_USE_BEDROCK = "";
  # Use Microsoft Foundry.
  # CLAUDE_CODE_USE_FOUNDRY = "";
  # Use the Amazon Bedrock Mantle endpoint.
  # CLAUDE_CODE_USE_MANTLE = "";
  # Set to 1 to discover custom commands, subagents, and output styles using Node.js file APIs instead of ripgrep. [1 or unset]
  # CLAUDE_CODE_USE_NATIVE_FILE_SEARCH = "1";
  # Controls the PowerShell tool.
  # CLAUDE_CODE_USE_POWERSHELL_TOOL = "";
  # Use Google Cloud's Agent Platform.
  # CLAUDE_CODE_USE_VERTEX = "";

  # Model selection and routing (26)
  # -----------------------------------
  # Model ID to add as a custom entry in the /model picker.
  # ANTHROPIC_CUSTOM_MODEL_OPTION = "";
  # Display description for the custom model entry in the /model picker.
  # ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = "";
  # Display name for the custom model entry in the /model picker.
  # ANTHROPIC_CUSTOM_MODEL_OPTION_NAME = "";
  # Comma-separated list of capabilities the custom model supports, for example effort,thinking.
  # ANTHROPIC_CUSTOM_MODEL_OPTION_SUPPORTED_CAPABILITIES = "";
  # Model ID that the fable alias resolves to, and the ID Claude Code recognizes as Fable 5 for automatic model fallback on third-party providers.
  # ANTHROPIC_DEFAULT_FABLE_MODEL = "";
  # Display description for the pinned Fable model in the /model picker.
  # ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION = "";
  # Display name for the pinned Fable model in the /model picker.
  # ANTHROPIC_DEFAULT_FABLE_MODEL_NAME = "";
  # Comma-separated list of capabilities the pinned Fable model supports, for example effort,thinking.
  # ANTHROPIC_DEFAULT_FABLE_MODEL_SUPPORTED_CAPABILITIES = "";
  # Model ID that the haiku alias resolves to, also used for background functionality.
  # ANTHROPIC_DEFAULT_HAIKU_MODEL = "";   # ACTIVE above
  # Display description for the pinned Haiku model in the /model picker.
  # ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION = "";
  # Display name for the pinned Haiku model in the /model picker.
  # ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME = "";   # ACTIVE above
  # Comma-separated list of capabilities the pinned Haiku model supports, for example effort,thinking.
  # ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES = "";
  # Model ID that the opus alias resolves to, and that opusplan uses while Plan Mode is active.
  # ANTHROPIC_DEFAULT_OPUS_MODEL = "";
  # Display description for the pinned Opus model in the /model picker.
  # ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION = "";
  # Display name for the pinned Opus model in the /model picker.
  # ANTHROPIC_DEFAULT_OPUS_MODEL_NAME = "";
  # Comma-separated list of capabilities the pinned Opus model supports, for example effort,thinking.
  # ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES = "";
  # Model ID that the sonnet alias resolves to, and that opusplan uses when Plan Mode is not active.
  # ANTHROPIC_DEFAULT_SONNET_MODEL = "";
  # Display description for the pinned Sonnet model in the /model picker.
  # ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION = "";
  # Display name for the pinned Sonnet model in the /model picker.
  # ANTHROPIC_DEFAULT_SONNET_MODEL_NAME = "";
  # Comma-separated list of capabilities the pinned Sonnet model supports, for example effort,thinking.
  # ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES = "";
  # Name of the model setting to use (see Model Configuration).
  # ANTHROPIC_MODEL = "";
  # Override AWS region for the Haiku-class model when using Amazon Bedrock or Amazon Bedrock Mantle.
  # ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION = "";
  # Set to 1 to prevent automatic remapping of Opus 4.0 and 4.1 to the current
  # Opus version on the Anthropic API. Use when you intentionally want to pin
  # an older model. [1 or unset]
  # CLAUDE_CODE_DISABLE_LEGACY_MODEL_REMAP = "1";
  # Set to 1 to populate the /model picker from your gateway's /v1/models
  # endpoint when ANTHROPIC_BASE_URL points at an Anthropic-compatible gateway.
  # Off by default because a shared gateway key could expose every model it can
  # access. [1 or unset]
  # CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
  # The model Claude Code uses for all subagents, agent teams, and agents in a workflow.
  # CLAUDE_CODE_SUBAGENT_MODEL = "";   # ACTIVE above
  # Set to any non-empty value, such as 1, to make every model stop retrying
  # with a repeated-overload error when no fallback model is configured.
  # Setting it to 0 or false still enables this, unlike most on/off variables;
  # unset the variable to restore the default retry behavior.
  # FALLBACK_FOR_ALL_PRIMARY_MODELS = "";

  # Effort, thinking, context, memory (17)
  # -----------------------------------------
  # Set the percentage (1-100) of the auto-compact window at which auto-compaction triggers.
  # CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "";
  # Set to 1 to send the effort parameter with every request, even when Claude Code does not recognize the model ID as effort-capable. [1 or unset]
  # CLAUDE_CODE_ALWAYS_ENABLE_EFFORT = "1";
  # Set the auto-compact window in tokens, from 100000 to 1000000. [numeric]
  # CLAUDE_CODE_AUTO_COMPACT_WINDOW = "";
  # Set to 1 to disable 1M context window support. [1 or unset]
  # CLAUDE_CODE_DISABLE_1M_CONTEXT = "1";
  # Set to 1 to disable adaptive reasoning on Opus 4.6 and Sonnet 4.6 and fall
  # back to the fixed thinking budget controlled by MAX_THINKING_TOKENS.
  # [1 or unset]
  # CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
  # Set to 1 to disable auto memory. [1 or unset]
  # CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
  # Set to 1 to omit the thinking parameter from API requests entirely. [1 or unset]
  # CLAUDE_CODE_DISABLE_THINKING = "1";
  # Set the effort level for supported models.
  # CLAUDE_CODE_EFFORT_LEVEL = "";   # ACTIVE above
  # Override the default token limit for file reads.
  # CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS = "";
  # Override the context window size Claude Code assumes for the active model.
  # CLAUDE_CODE_MAX_CONTEXT_TOKENS = "";
  # Set the maximum number of output tokens for most requests.
  # CLAUDE_CODE_MAX_OUTPUT_TOKENS = "";
  # Maximum age in milliseconds of the last transcript message for a session
  # that ended mid-turn to continue automatically on resume. [numeric]
  # CLAUDE_CODE_RESUME_INTERRUPTED_TURN_MAX_AGE_MS = "";
  # Set to 1 to disable automatic compaction when approaching the context limit. [1 or unset]
  # DISABLE_AUTO_COMPACT = "1";
  # Set to 1 to disable all compaction: both automatic compaction and the manual /compact command. [1 or unset]
  # DISABLE_COMPACT = "1";
  # Set to 1 to prevent sending the interleaved-thinking beta header. [1 or unset]
  # DISABLE_INTERLEAVED_THINKING = "1";
  # Maximum number of tokens allowed in MCP tool responses.
  # MAX_MCP_OUTPUT_TOKENS = "";
  # Fixed token budget for extended thinking. [0 or unset]
  # MAX_THINKING_TOKENS = "0";

  # Privacy, telemetry, updates (25)
  # -----------------------------------
  # Set to any non-empty value, such as 1, to disable nonessential network
  # traffic: auto-updates, telemetry, error reporting, the /feedback command,
  # release notes, model discovery refreshes, and availability checks. Setting
  # it to 0 or false still disables this traffic; unset the variable to allow
  # it again.
  # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "";   # ACTIVE above
  # Set to 1 to enable OpenTelemetry data collection for metrics and logging. [1 or unset]
  # CLAUDE_CODE_ENABLE_TELEMETRY = "1";   # RETIRED below
  # Maximum length of content-bearing OpenTelemetry attributes (model
  # responses, tool content, system prompts, raw API bodies), including the
  # truncation marker, in UTF-16 code units (default: 61440, or 60 KB).
  # CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH = "";
  # Set to 1 to write OpenTelemetry exporter diagnostic errors to stderr. [1 or unset]
  # CLAUDE_CODE_OTEL_DIAG_STDERR = "1";
  # Timeout in milliseconds for flushing pending OpenTelemetry spans (default: 5000). [numeric]
  # CLAUDE_CODE_OTEL_FLUSH_TIMEOUT_MS = "";
  # Interval for refreshing dynamic OpenTelemetry headers in milliseconds (default: 1740000 / 29 minutes). [numeric]
  # CLAUDE_CODE_OTEL_HEADERS_HELPER_DEBOUNCE_MS = "";
  # Timeout in milliseconds for the OpenTelemetry exporter to finish on shutdown (default: 2000). [numeric]
  # CLAUDE_CODE_OTEL_SHUTDOWN_TIMEOUT_MS = "";
  # Set to 1 to let Claude Code run your package manager's upgrade command in the background when a new version is available. [1 or unset]
  # CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE = "1";
  # Set to 1 to disable automatic background updates. [1 or unset]
  # DISABLE_AUTOUPDATER = "1";   # ACTIVE above
  # Set to any non-empty value, such as 1, to opt out of error reporting.
  # **Setting it to 0 or false still opts out**, unlike most on/off variables;
  # unset the variable to turn error reporting back on.
  # DISABLE_ERROR_REPORTING = "";   # ACTIVE above
  # Set to 1 to disable installation warnings. [1 or unset]
  # DISABLE_INSTALLATION_CHECKS = "1";   # ACTIVE above
  # Set to any non-empty value, such as 1, to opt out of telemetry. **Setting
  # it to 0 or false still opts out**, unlike most on/off variables; unset the
  # variable to turn telemetry back on.
  # DISABLE_TELEMETRY = "";   # ACTIVE above
  # Set to 1 to block all updates including manual claude update and claude install. [1 or unset]
  # DISABLE_UPDATES = "1";
  # Set to 1 to force plugin auto-updates even when the main auto-updater is disabled via DISABLE_AUTOUPDATER. [1 or unset]
  # FORCE_AUTOUPDATE_PLUGINS = "1";
  # Standard OpenTelemetry SDK limit on attribute value length.
  # OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT = "";
  # Set to 1 to include the model's response text on assistant_response OpenTelemetry log events. [1 or unset]
  # OTEL_LOG_ASSISTANT_RESPONSES = "1";
  # Emit Anthropic Messages API request and response JSON as api_request_body / api_response_body log events. [1 or unset]
  # OTEL_LOG_RAW_API_BODIES = "1";
  # Set to 1 to include tool input and output content in OpenTelemetry span events. [1 or unset]
  # OTEL_LOG_TOOL_CONTENT = "1";
  # Set to 1 to include tool input arguments, MCP server names, user-authored
  # workflow names, raw error strings on tool failures, refusal categories, and
  # other tool details in OpenTelemetry traces and logs. Disabled by default to
  # protect PII. [1 or unset]
  # OTEL_LOG_TOOL_DETAILS = "1";
  # Set to 1 to include user prompt text in OpenTelemetry traces and logs. [1 or unset]
  # OTEL_LOG_USER_PROMPTS = "1";
  # Set to false to exclude account UUID from metrics attributes (default: included).
  # OTEL_METRICS_INCLUDE_ACCOUNT_UUID = "";
  # Set to true to include the session entrypoint in metrics attributes (default: excluded).
  # OTEL_METRICS_INCLUDE_ENTRYPOINT = "";
  # As of v2.1.161, Claude Code attaches OTEL_RESOURCE_ATTRIBUTES keys to metric datapoint labels.
  # OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES = "";
  # Set to false to exclude session ID from metrics attributes (default: included).
  # OTEL_METRICS_INCLUDE_SESSION_ID = "";
  # Set to true to include Claude Code version in metrics attributes (default: excluded).
  # OTEL_METRICS_INCLUDE_VERSION = "";

  # Bash, tools, sandbox (20)
  # ----------------------------
  # Default timeout for long-running bash commands (default: 120000, or 2 minutes).
  # BASH_DEFAULT_TIMEOUT_MS = "";   # ACTIVE above
  # Maximum number of characters of bash output that Claude Code reads back into a command's result (default: 30000; maximum: 150000).
  # BASH_MAX_OUTPUT_LENGTH = "";   # ACTIVE above
  # Maximum timeout the model can set for long-running bash commands (default: 600000, or 10 minutes).
  # BASH_MAX_TIMEOUT_MS = "";   # ACTIVE above
  # Maximum number of read-only tools and subagents that can execute in
  # parallel (default: 10). Higher values increase parallelism but consume
  # more resources.
  # CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY = "";
  # How many subagents can be running in one session before the Agent tool refuses to spawn another (default: 20).
  # CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS = "";
  # Cap on the number of subagents one session can spawn with the Agent tool (default: 200).
  # CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION = "";
  # Number of subagent layers allowed below the main conversation (default: 3).
  # CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH = "";
  # Cap the number of agentic turns when no explicit limit is passed. [numeric]
  # CLAUDE_CODE_MAX_TURNS = "";
  # Cap on the total number of WebSearch calls one session can make (default: 200).
  # CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION = "";
  # Maximum number of characters in subagent output before truncation (default: 32000, maximum: 160000).
  # TASK_MAX_OUTPUT_LENGTH = "";
  # Return to the original working directory after each Bash or PowerShell command in the main session.
  # CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "";   # ACTIVE above
  # Set to 1 to disable the advisor tool. [1 or unset]
  # CLAUDE_CODE_DISABLE_ADVISOR_TOOL = "1";
  # Set to 1 to stop Claude Code from terminating background shell commands when the operating system reports memory pressure. [1 or unset]
  # CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP = "1";
  # Controls whether tool call inputs stream from the API as Claude generates them. [1 or unset]
  # CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING = "1";
  # Windows only: path to the Git Bash executable (bash.exe).
  # CLAUDE_CODE_GIT_BASH_PATH = "";
  # Set to 1 to stop Claude Code from passing -ExecutionPolicy Bypass when
  # spawning PowerShell for tool calls, hooks, and status line commands, and
  # respect the machine's effective execution policy instead. By default Claude
  # Code bypasses execution policy at process scope. [1 or unset]
  # CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY = "1";
  # Set the shell Claude Code uses to run Bash tool commands.
  # CLAUDE_CODE_SHELL = "";   # SET BY _wrapper.nix (controlled bash + rm shim); do not activate here
  # Command prefix that wraps shell commands Claude Code spawns: Bash tool
  # calls, hook commands, status line commands, and stdio MCP server startup
  # commands. Useful for logging or auditing.
  # CLAUDE_CODE_SHELL_PREFIX = "";
  # Override the character budget for skill metadata shown to the Skill tool.
  # SLASH_COMMAND_TOOL_CHAR_BUDGET = "";
  # Set to 0 to use system-installed rg instead of rg included with Claude Code. [0 or unset]
  # USE_BUILTIN_RIPGREP = "0";   # ACTIVE above

  # MCP (14)
  # -----------
  # Set to 1 to skip the mcp__<server>__ prefix on tool names from SDK-created MCP servers. [1 or unset]
  # CLAUDE_AGENT_SDK_MCP_NO_PREFIX = "1";
  # Set to 1 to spawn stdio MCP servers with only a safe baseline environment
  # plus the server's configured env, instead of inheriting your shell
  # environment. [1 or unset]
  # CLAUDE_CODE_MCP_ALLOWLIST_ENV = "1";
  # Elapsed time in milliseconds before a still-running MCP tool call moves to a background task (default: 120000, or 2 minutes). [0 or unset]
  # CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS = "0";
  # Idle timeout in milliseconds for MCP tool calls. [0 or unset]
  # CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT = "0";
  # Set to false to disable claude.ai MCP servers in Claude Code.
  # ENABLE_CLAUDEAI_MCP_SERVERS = "";
  # Controls MCP tool search.
  # ENABLE_TOOL_SEARCH = "";
  # OAuth client secret for MCP servers that require pre-configured credentials.
  # MCP_CLIENT_SECRET = "";
  # Controls whether startup waits for MCP servers to connect before the first query. [0 or unset]
  # MCP_CONNECTION_NONBLOCKING = "0";
  # How long blocking MCP startup waits, in milliseconds, for the connection batch before snapshotting the tool list (default: 5000). [numeric]
  # MCP_CONNECT_TIMEOUT_MS = "";
  # Fixed port for the OAuth redirect callback, as an alternative to --callback-port when adding an MCP server with pre-configured credentials.
  # MCP_OAUTH_CALLBACK_PORT = "";
  # Maximum number of remote MCP servers (HTTP/SSE) to connect in parallel during startup (default: 20).
  # MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE = "";
  # Maximum number of local MCP servers (stdio) to connect in parallel during startup (default: 3).
  # MCP_SERVER_CONNECTION_BATCH_SIZE = "";
  # Timeout in milliseconds for MCP server startup (default: 30000, or 30 seconds). [numeric]
  # MCP_TIMEOUT = "";
  # Timeout in milliseconds for MCP tool execution (default: 100000000, about 28 hours). [numeric]
  # MCP_TOOL_TIMEOUT = "";

  # Network, proxy, TLS, timeouts (25)
  # -------------------------------------
  # Override the API endpoint to route requests through a proxy or gateway.
  # ANTHROPIC_BASE_URL = "";
  # Override the 5-minute idle timeout that aborts a streaming model response when no bytes arrive. [1 or unset]
  # API_FORCE_IDLE_TIMEOUT = "1";
  # Timeout for API requests in milliseconds (default: 600000, or 10 minutes; maximum: 2147483647). [numeric]
  # API_TIMEOUT_MS = "";
  # Override the number of times to retry failed API requests (default: 10).
  # CLAUDE_CODE_MAX_RETRIES = "";
  # How many milliseconds of idle time before an unanswered AskUserQuestion dialog auto-continues without you. [numeric]
  # CLAUDE_AFK_TIMEOUT_MS = "";
  # Stall timeout in milliseconds for background subagents. [numeric]
  # CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS = "";
  # Time in milliseconds Claude Code waits for the AWS default credential
  # provider chain to produce credentials before the request fails with an AWS
  # default-chain credential resolve timeout (default: 60000). Raise it when a
  # chain step legitimately needs longer, such as browser-based SSO with MFA.
  # [numeric]
  # CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS = "";
  # Comma-separated list of CA certificate sources for TLS connections. bundled
  # is the Mozilla CA set shipped with Claude Code. system is the operating
  # system trust store. Default is bundled,system.
  # CLAUDE_CODE_CERT_STORE = "";
  # Path to client certificate file for mTLS authentication.
  # CLAUDE_CODE_CLIENT_CERT = "";
  # Path to client private key file for mTLS authentication.
  # CLAUDE_CODE_CLIENT_KEY = "";
  # Passphrase for encrypted CLAUDE\_CODE\_CLIENT\_KEY (optional).
  # CLAUDE_CODE_CLIENT_KEY_PASSPHRASE = "";
  # Timeout in seconds for Glob tool file discovery.
  # CLAUDE_CODE_GLOB_TIMEOUT_SECONDS = "";
  # Timeout in milliseconds for git operations when installing or updating plugins (default: 120000). [numeric]
  # CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS = "";
  # Set to 1 to clone GitHub owner/repo shorthand sources over HTTPS instead of
  # SSH. Applies to plugin install and update, and to /plugin marketplace add
  # and update. [1 or unset]
  # CLAUDE_CODE_PLUGIN_PREFER_HTTPS = "1";
  # Set to 1 to allow the proxy to perform DNS resolution instead of the caller. [1 or unset]
  # CLAUDE_CODE_PROXY_RESOLVES_HOSTS = "1";
  # Set to 1 for unattended sessions such as eval harnesses, CI jobs, or remote workers. [1 or unset]
  # CLAUDE_CODE_RETRY_WATCHDOG = "1";
  # Override the time budget in milliseconds for SessionEnd hooks. [numeric]
  # CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS = "";
  # Timeout in milliseconds for synchronous plugin installation. [numeric]
  # CLAUDE_CODE_SYNC_PLUGIN_INSTALL_TIMEOUT_MS = "";
  # Timeout in milliseconds for a mid-session skills resync when CLAUDE_CODE_SYNC_SKILLS is set (default: 30000). [numeric]
  # CLAUDE_CODE_SYNC_SKILLS_INSTALL_TIMEOUT_MS = "";
  # Timeout in milliseconds for the first query to wait on the initial skills sync when CLAUDE_CODE_SYNC_SKILLS is set (default: 5000). [numeric]
  # CLAUDE_CODE_SYNC_SKILLS_WAIT_TIMEOUT_MS = "";
  # Override, in milliseconds, how long a non-interactive session waits at exit for its agent team to finish tearing down. [numeric]
  # CLAUDE_CODE_TEAM_TEARDOWN_PARK_TIMEOUT_MS = "";
  # Timeout in milliseconds before the streaming idle watchdog closes a stalled connection. [numeric]
  # CLAUDE_STREAM_IDLE_TIMEOUT_MS = "";
  # Specify HTTPS proxy server for network connections.
  # HTTPS_PROXY = "";
  # Specify HTTP proxy server for network connections.
  # HTTP_PROXY = "";
  # List of domains and IPs to which requests will be directly issued, bypassing proxy.
  # NO_PROXY = "";

  # Terminal, rendering, accessibility (16)
  # ------------------------------------------
  # Set to 1 to render screen-reader friendly output: flat text without decorative borders or animations. [1 or unset]
  # CLAUDE_AX_SCREEN_READER = "1";
  # Set to 1 to keep the native terminal cursor visible and disable the inverted-text cursor indicator. [1 or unset]
  # CLAUDE_CODE_ACCESSIBILITY = "1";
  # Set to 1 to repaint the entire screen on every frame in fullscreen rendering instead of sending incremental updates. [1 or unset]
  # CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT = "1";
  # Override automatic IDE connection.
  # CLAUDE_CODE_AUTO_CONNECT_IDE = "";
  # Set to 1 to disable fullscreen rendering and use the classic main-screen renderer. [1 or unset]
  # CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = "1";
  # Set to 1 to disable automatic terminal title updates based on conversation context. [1 or unset]
  # CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "1";   # RETIRED below
  # Set to 1 to hide the working directory in the startup logo. [1 or unset]
  # CLAUDE_CODE_HIDE_CWD = "1";
  # Override the host address used to connect to the IDE extension.
  # CLAUDE_CODE_IDE_HOST_OVERRIDE = "";
  # Set to 1 to skip auto-installation of IDE extensions. [1 or unset]
  # CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL = "1";   # ACTIVE above
  # Set to 1 to skip validation of IDE lockfile entries during connection. [1 or unset]
  # CLAUDE_CODE_IDE_SKIP_VALID_CHECK = "1";
  # Set to 1 to show the terminal's own cursor at the input caret instead of a drawn block. [1 or unset]
  # CLAUDE_CODE_NATIVE_CURSOR = "1";
  # Set to 1 to enable fullscreen rendering, a research preview that reduces flicker and keeps memory flat in long conversations. [1 or unset]
  # CLAUDE_CODE_NO_FLICKER = "1";
  # Set by host platforms that embed Claude Code and manage model provider routing on its behalf.
  # CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST = "";
  # Set to false to disable syntax highlighting in diff output.
  # CLAUDE_CODE_SYNTAX_HIGHLIGHT = "";
  # Set to any non-empty value, such as 1, to allow 24-bit truecolor output
  # inside tmux. **Setting it to 0 or false still allows truecolor**, unlike
  # most on/off variables; unset the variable to restore the 256-color clamp.
  # [1 or unset]
  # CLAUDE_CODE_TMUX_TRUECOLOR = "";
  # Number of times to retry when the model's response fails validation against the --json-schema in non-interactive mode (the -p flag).
  # MAX_STRUCTURED_OUTPUT_RETRIES = "";

  # Feature toggles (55)
  # -----------------------
  # Set to 1 to disable all built-in subagent types such as Explore and Plan. [1 or unset]
  # CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS = "1";
  # Set to 1 to turn off background agents and agent view: claude agents, --bg, /background, and the on-demand supervisor. [1 or unset]
  # CLAUDE_CODE_DISABLE_AGENT_VIEW = "1";
  # Set to 1 to disable the Artifact tool, which publishes session output as a private web page on claude.ai. [1 or unset]
  # CLAUDE_CODE_DISABLE_ARTIFACT = "1";
  # Set to 1 to disable attachment processing. [1 or unset]
  # CLAUDE_CODE_DISABLE_ATTACHMENTS = "1";
  # Set to 1 to disable all background task functionality, including the
  # run_in_background parameter on Bash and subagent tools, auto-backgrounding,
  # and the Ctrl+B shortcut. [1 or unset]
  # CLAUDE_CODE_DISABLE_BACKGROUND_TASKS = "1";
  # Set to 1 to skip the check that an Amazon Bedrock streaming response carries the application/vnd.amazon.eventstream content-type. [1 or unset]
  # CLAUDE_CODE_DISABLE_BEDROCK_CONTENT_TYPE_GUARD = "1";
  # Set to 1 to stop a background session's running background shell commands,
  # dynamic workflows, and background subagents when the supervisor stops,
  # restarts, or updates that session's process, instead of handing them to the
  # session's next process. [1 or unset]
  # CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF = "1";
  # Set to 1 to disable the skills and workflows included with Claude Code.
  # Bundled skills and workflows are removed entirely, while built-in commands
  # remain available but hidden from the model. [1 or unset]
  # CLAUDE_CODE_DISABLE_BUNDLED_SKILLS = "1";
  # Set to 1 to prevent loading any CLAUDE.md memory files into context, including user, project, and auto-memory files. [1 or unset]
  # CLAUDE_CODE_DISABLE_CLAUDE_MDS = "1";
  # Set to 1 to disable scheduled tasks. [1 or unset]
  # CLAUDE_CODE_DISABLE_CRON = "1";
  # Set to 1 to strip Anthropic-specific anthropic-beta request headers and beta
  # tool-schema fields, such as defer_loading and eager_input_streaming, from
  # API requests. [1 or unset]
  # CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = "1";
  # Set to 1 to disable the built-in Explore and Plan subagents. [1 or unset]
  # CLAUDE_CODE_DISABLE_EXPLORE_PLAN_AGENTS = "1";
  # Set to 1 to disable fast mode. [1 or unset]
  # CLAUDE_CODE_DISABLE_FAST_MODE = "1";
  # Set to 1 to disable the "How is Claude doing?" session quality surveys. [1 or unset]
  # CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
  # Set to 1 to disable file checkpointing. [1 or unset]
  # CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING = "1";
  # Set to 1 to remove built-in commit and PR workflow instructions and the git status snapshot from Claude's system prompt. [1 or unset]
  # CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = "1";
  # Set to 1 to disable mouse tracking in fullscreen rendering. [1 or unset]
  # CLAUDE_CODE_DISABLE_MOUSE = "1";
  # Set to 1 to disable click, drag, and hover handling in fullscreen rendering while keeping mouse-wheel scrolling. [1 or unset]
  # CLAUDE_CODE_DISABLE_MOUSE_CLICKS = "1";
  # Set to 1 to disable the non-streaming fallback when a streaming request fails mid-stream. [1 or unset]
  # CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = "1";
  # Set to 1 to send the PushNotification tool's desktop notification even while you are typing in or focused on the terminal. [1 or unset]
  # CLAUDE_CODE_DISABLE_NOTIFICATION_PRESENCE_CHECK = "1";
  # Set to 1 to disable automatic registration of the official plugin marketplace. [1 or unset]
  # CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL = "1";
  # Set to 1 to skip loading skills from the system-wide managed skills directory. [1 or unset]
  # CLAUDE_CODE_DISABLE_POLICY_SKILLS = "1";
  # Set to 1 to disable virtual scrolling in fullscreen rendering and render every message in the transcript. [1 or unset]
  # CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL = "1";
  # Set to 1 to disable workflows. [1 or unset]
  # CLAUDE_CODE_DISABLE_WORKFLOWS = "1";
  # Set to 1 to enable appending extra text to the end of every subagent's system prompt. [1 or unset]
  # CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT = "1";
  # Accepted for compatibility with older releases and has no effect.
  # CLAUDE_CODE_ENABLE_AUTO_MODE = "";
  # Override session recap availability. [1 or unset]
  # CLAUDE_CODE_ENABLE_AWAY_SUMMARY = "1";
  # Set to 1 to refresh plugin state at turn boundaries in non-interactive mode after a background install completes. [1 or unset]
  # CLAUDE_CODE_ENABLE_BACKGROUND_PLUGIN_REFRESH = "1";
  # Set to 1 to route the "How is Claude doing?" session quality survey to your
  # own OpenTelemetry collector when Anthropic-bound nonessential traffic is
  # blocked. Survey ratings are emitted only as OTEL events to your configured
  # collector. [1 or unset]
  # CLAUDE_CODE_ENABLE_FEEDBACK_SURVEY_FOR_OTEL = "1";
  # Set to false to disable prompt suggestions (the "Prompt suggestions" toggle in /config).
  # CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION = "";
  # Controls whether sessions use the structured Task tools (TaskCreate, TaskUpdate, TaskGet, TaskList) or the legacy TodoWrite tool. [0 or unset]
  # CLAUDE_CODE_ENABLE_TASKS = "0";
  # Set to 1 to turn off the in-process cache of credentials resolved from the
  # AWS default credential provider chain, so Claude Code resolves the chain on
  # every API request. [1 or unset]
  # CLAUDE_CODE_SKIP_AWS_CRED_CACHE = "1";
  # Set to 1 to treat a failed fast mode availability check as available, for networks that block the check's direct request to api.anthropic.com. [1 or unset]
  # CLAUDE_CODE_SKIP_FAST_MODE_NETWORK_ERRORS = "1";
  # Set to 1 to skip the client-side fast mode availability check, for proxies that intercept the check's request rather than refuse it. [1 or unset]
  # CLAUDE_CODE_SKIP_FAST_MODE_ORG_CHECK = "1";
  # Set to 1 to skip writing prompt history and session transcripts to disk. [1 or unset]
  # CLAUDE_CODE_SKIP_PROMPT_HISTORY = "1";
  # Set to 1 to stop in-flight background work instead of carrying it over when you background a session by pressing or with /background. [1 or unset]
  # CLAUDE_DISABLE_ADOPT = "1";
  # Set to 1 to force-enable the byte-level streaming idle watchdog, or set to 0 to force-disable it. [1 or unset]
  # CLAUDE_ENABLE_BYTE_WATCHDOG = "1";
  # Set to 1 to enable the byte-level streaming idle watchdog on Amazon Bedrock vnd.amazon.eventstream responses. [1 or unset]
  # CLAUDE_ENABLE_BYTE_WATCHDOG_BEDROCK = "1";
  # Set to 0 to force-disable the event-level streaming idle watchdog, or set to 1 to force-enable it. [0 or unset]
  # CLAUDE_ENABLE_STREAM_WATCHDOG = "0";
  # Set to 1 to disable cost warning messages. [1 or unset]
  # DISABLE_COST_WARNINGS = "1";
  # Set to 1 to hide the /doctor setup checkup skill and its /checkup alias. [1 or unset]
  # DISABLE_DOCTOR_COMMAND = "1";
  # Set to 1 to hide the /usage-credits command that lets users purchase additional usage beyond rate limits. [1 or unset]
  # DISABLE_EXTRA_USAGE_COMMAND = "1";
  # Set to 1 to disable the /feedback command. [1 or unset]
  # DISABLE_FEEDBACK_COMMAND = "1";
  # Set to 1 to disable GrowthBook feature-flag fetching and use code defaults for every flag. [1 or unset]
  # DISABLE_GROWTHBOOK = "1";
  # Set to 1 to hide the /install-github-app command. [1 or unset]
  # DISABLE_INSTALL_GITHUB_APP_COMMAND = "1";
  # Set to 1 to hide the /login command. [1 or unset]
  # DISABLE_LOGIN_COMMAND = "1";
  # Set to 1 to hide the /logout command. [1 or unset]
  # DISABLE_LOGOUT_COMMAND = "1";
  # Set to 1 to disable prompt caching for all models (takes precedence over per-model settings). [1 or unset]
  # DISABLE_PROMPT_CACHING = "1";
  # Set to 1 to disable prompt caching for Fable models. [1 or unset]
  # DISABLE_PROMPT_CACHING_FABLE = "1";
  # Set to 1 to disable prompt caching for Haiku models. [1 or unset]
  # DISABLE_PROMPT_CACHING_HAIKU = "1";
  # Set to 1 to disable prompt caching for Opus models. [1 or unset]
  # DISABLE_PROMPT_CACHING_OPUS = "1";
  # Set to 1 to disable prompt caching for Sonnet models. [1 or unset]
  # DISABLE_PROMPT_CACHING_SONNET = "1";
  # Set to 1 to hide the /upgrade command. [1 or unset]
  # DISABLE_UPGRADE_COMMAND = "1";
  # Set to 1 to request a 1-hour prompt cache TTL instead of the default 5 minutes. [1 or unset]
  # ENABLE_PROMPT_CACHING_1H = "1";
  # Deprecated.
  # ENABLE_PROMPT_CACHING_1H_BEDROCK = "";

  # Other (69)
  # -------------
  # Set to 1 to force claude --cloud to bundle and upload your local repository even when GitHub access is available. [1 or unset]
  # CCR_FORCE_BUNDLE = "1";
  # Set to 1 in subprocesses Claude Code spawns (Bash and PowerShell tools, tmux
  # sessions, hook commands, status line commands, and stdio MCP server
  # subprocesses). Use to detect when a script is running inside a subprocess
  # spawned by Claude Code. [1 or unset]
  # CLAUDECODE = "1";
  # How many milliseconds before auto-continue the on-screen countdown appears on an unanswered AskUserQuestion dialog. [numeric]
  # CLAUDE_AFK_COUNTDOWN_MS = "";
  # Set to 1 to force-enable automatic backgrounding of long-running agent tasks. [1 or unset]
  # CLAUDE_AUTO_BACKGROUND_TASKS = "1";
  # Path to a file that an external tool, such as a screen-lock listener, creates when you unlock your screen and deletes when you lock it.
  # CLAUDE_CLIENT_PRESENCE_FILE = "";
  # Set to 1 to load memory files from directories specified with --add-dir. [1 or unset]
  # CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = "1";
  # Interval in milliseconds at which credentials should be refreshed (when using apiKeyHelper). [numeric]
  # CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "";
  # Set to 0 to stop Claude Code from opening the browser automatically when a new artifact is published. [0 or unset]
  # CLAUDE_CODE_ARTIFACT_AUTO_OPEN = "0";
  # Set to 0 to omit the attribution block, which carries the client version and a prompt fingerprint, from the start of the system prompt. [0 or unset]
  # CLAUDE_CODE_ATTRIBUTION_HEADER = "0";
  # Override the debug log file path.
  # CLAUDE_CODE_DEBUG_LOGS_DIR = "";
  # Minimum log level written to the debug log file.
  # CLAUDE_CODE_DEBUG_LOG_LEVEL = "";
  # Time in milliseconds to wait after the query loop becomes idle before automatically exiting. [numeric]
  # CLAUDE_CODE_EXIT_AFTER_STOP_DELAY = "";
  # Set to 1 to enable agent teams. [1 or unset]
  # CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
  # JSON object to merge into the top level of every API request body.
  # CLAUDE_CODE_EXTRA_BODY = "";
  # Set to 1 to force transcript persistence, prompt history, and claude agents
  # registration even when this claude was launched from inside another Claude
  # Code session. [1 or unset]
  # CLAUDE_CODE_FORCE_SESSION_PERSISTENCE = "1";
  # Set to 1 to force strikethrough rendering for ~~text~~ in Claude's
  # responses when your terminal supports it but is not auto-detected, such as
  # over SSH without TERM_PROGRAM forwarded. [1 or unset]
  # CLAUDE_CODE_FORCE_STRIKETHROUGH = "1";
  # Set to 1 to force-enable DEC private mode 2026 synchronized output when your terminal supports it but is not auto-detected. [1 or unset]
  # CLAUDE_CODE_FORCE_SYNC_OUTPUT = "1";
  # Set to 1 to let Claude spawn forked subagents, or 0 to disable them, overriding any server-side rollout. [1 or unset]
  # CLAUDE_CODE_FORK_SUBAGENT = "1";
  # Set to 1 to emit subagent text and thinking blocks in claude -p
  # --output-format stream-json output, the same behavior as the
  # --forward-subagent-text flag. [1 or unset]
  # CLAUDE_CODE_FORWARD_SUBAGENT_TEXT = "1";
  # Set to false to exclude dotfiles from results when Claude invokes the Glob tool.
  # CLAUDE_CODE_GLOB_HIDDEN = "";
  # Set to false to make the Glob tool respect .gitignore patterns.
  # CLAUDE_CODE_GLOB_NO_IGNORE = "";
  # Set to 1 to make /init run an interactive setup flow. [1 or unset]
  # CLAUDE_CODE_NEW_INIT = "1";
  # OAuth refresh token for Claude.ai authentication.
  # CLAUDE_CODE_OAUTH_REFRESH_TOKEN = "";
  # Space-separated OAuth scopes the refresh token was issued with, such as
  # "user:profile user:inference user:sessions:claude_code". Required when
  # CLAUDE_CODE_OAUTH_REFRESH_TOKEN is set.
  # CLAUDE_CODE_OAUTH_SCOPES = "";
  # OAuth access token for Claude.ai authentication.
  # CLAUDE_CODE_OAUTH_TOKEN = "";
  # Set to 1 to enable Perforce-aware write protection. [1 or unset]
  # CLAUDE_CODE_PERFORCE_MODE = "1";
  # Override the plugins root directory.
  # CLAUDE_CODE_PLUGIN_CACHE_DIR = "";
  # Set to 1 to skip the re-clone attempt and keep using the existing marketplace cache when a git pull fails. [1 or unset]
  # CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE = "1";
  # Path to one or more read-only plugin seed directories, separated by : on
  # Unix or ; on Windows. Use this to bundle a pre-populated plugins directory
  # into a container image.
  # CLAUDE_CODE_PLUGIN_SEED_DIR = "";
  # Maximum time in milliseconds that non-interactive mode with the -p flag
  # waits after the final turn for background subagents and workflows whose
  # result is part of the output. [0 or unset | default 600000, or 10 minutes.
  # When the cap is exceeded, remaining background tasks are terminated and the
  # process exits. Set to 0 to wait indefinitely. This cap is separate from the
  # five-second grace period that applies to plain background shells]
  # CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS = "0";
  # Launch the processes Claude Code starts from its own binary, such as the
  # background service that hosts agent view sessions, through a corporate
  # launcher given as an argv prefix like /opt/corp/launcher. Set it in the env
  # block of user or managed settings so the detached background service
  # inherits it.
  # CLAUDE_CODE_PROCESS_WRAPPER = "";
  # Set to 1 to propagate W3C trace context when ANTHROPIC_BASE_URL points at a custom proxy. [1 or unset]
  # CLAUDE_CODE_PROPAGATE_TRACEPARENT = "1";
  # Set to 1 to automatically resume if the previous session ended mid-turn. [1 or unset]
  # CLAUDE_CODE_RESUME_INTERRUPTED_TURN = "1";
  # Override the continuation message injected when resuming a session that ended mid-turn.
  # CLAUDE_CODE_RESUME_PROMPT = "";
  # Set to 1 to start in safe mode: CLAUDE.md, skills, plugins, hooks, MCP
  # servers, custom commands and agents, output styles, workflows, custom
  # themes, custom keybindings, status line and file-suggestion commands, LSP
  # servers, and auto-memory do not load. [1 or unset]
  # CLAUDE_CODE_SAFE_MODE = "1";
  # JSON object limiting how many times specific scripts may be invoked per session when CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is set. [numeric]
  # CLAUDE_CODE_SCRIPT_CAPS = "";
  # Set the mouse wheel scroll multiplier in fullscreen rendering.
  # CLAUDE_CODE_SCROLL_SPEED = "";
  # Set to 1 to run with a minimal system prompt and only the Bash, file read, and file edit tools. [1 or unset]
  # CLAUDE_CODE_SIMPLE = "1";
  # Set to 1 to use a shorter system prompt and abbreviated tool descriptions on any model. [1 or unset]
  # CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT = "1";
  # Maximum number of consecutive times a Stop or SubagentStop hook may block
  # the turn from ending before Claude Code overrides it and ends the turn
  # anyway (default: 8). Set to 0 to disable the cap. [0 or unset]
  # CLAUDE_CODE_STOP_HOOK_BLOCK_CAP = "0";
  # Set to 1 to strip Anthropic and cloud provider credentials from subprocess environments (Bash tool, hooks, MCP stdio servers). [1 or unset]
  # CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1";
  # Set to 1 in non-interactive mode (the -p flag) to wait for plugin installation to complete before the first query. [1 or unset]
  # CLAUDE_CODE_SYNC_PLUGIN_INSTALL = "1";
  # Set to 1 to download your enabled claude.ai skills into ~/.claude/skills/ before the first query and resync every 10 minutes. [1 or unset]
  # CLAUDE_CODE_SYNC_SKILLS = "1";
  # Share a task list across sessions.
  # CLAUDE_CODE_TASK_LIST_ID = "";
  # Override the temp directory used for internal temp files. [default /tmp on macOS, os.tmpdir() on Linux and Windows. As of v2.1.161, on macOS and Linux, sandboxed Bash subprocesses receive a short fallback $TMPDIR under the system default when your override is a long path, since some tools fail when temp paths get too long. Unsandboxed Bash commands inherit your shell's $TMPDIR unchanged. Claude Code's own temp files always use your override]
  # CLAUDE_CODE_TMPDIR = "/tmp";
  # Override the configuration directory (default: ~/.claude).
  # CLAUDE_CONFIG_DIR = "";
  # Path to a shell script whose contents Claude Code runs before each Bash
  # command in the same shell process, so exports in the file are visible to
  # the command. Use to persist virtualenv or conda activation across commands.
  # CLAUDE_ENV_FILE = "";
  # Prefix for auto-generated Remote Control session names when no explicit name is provided.
  # CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX = "";
  # Set to 1 to enable debug mode, equivalent to launching with --debug. [1 or unset]
  # DEBUG = "1";
  # Set to 1 to opt out of telemetry, with the same effect as DISABLE_TELEMETRY, including making Remote Control unavailable. [1 or unset]
  # DO_NOT_TRACK = "1";
  # Set to 1 to enable clickable OSC 8 hyperlinks when your terminal supports them but isn't auto-detected, or 0 to disable them. [1 or unset]
  # FORCE_HYPERLINK = "1";
  # Set to 1 to force the 5-minute prompt cache TTL even when 1-hour TTL would otherwise apply. [1 or unset]
  # FORCE_PROMPT_CACHING_5M = "1";
  # Set to any non-empty value, such as 1, to enable demo mode: hides your email
  # and organization name from the header and /status output, and skips
  # onboarding. [1 or unset]
  # IS_DEMO = "";
  # Override region for Claude 3.5 Haiku when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_3_5_HAIKU = "";
  # Override region for Claude 3.5 Sonnet when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_3_5_SONNET = "";
  # Override region for Claude 3.7 Sonnet when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_3_7_SONNET = "";
  # Override region for Claude 4.0 Opus when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_0_OPUS = "";
  # Override region for Claude 4.0 Sonnet when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_0_SONNET = "";
  # Override region for Claude 4.1 Opus when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_1_OPUS = "";
  # Override region for Claude Opus 4.5 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_5_OPUS = "";
  # Override region for Claude Sonnet 4.5 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_5_SONNET = "";
  # Override region for Claude Opus 4.6 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_6_OPUS = "";
  # Override region for Claude Sonnet 4.6 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_6_SONNET = "";
  # Override region for Claude Opus 4.7 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_7_OPUS = "";
  # Override region for Claude Opus 4.8 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_4_8_OPUS = "";
  # Override region for Claude Opus 5 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_5_OPUS = "";
  # Override region for Claude Sonnet 5 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_5_SONNET = "";
  # Override region for Claude Fable 5 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_FABLE_5 = "";
  # Override region for Claude Haiku 4.5 when using Google Cloud's Agent Platform.
  # VERTEX_REGION_CLAUDE_HAIKU_4_5 = "";

  # Read-only (exported by Claude Code; do not set) (7)
  # -------------------------------------------------------
  # Set automatically in Bash tool and hook command subprocesses while the
  # session has an active Remote Control connection, and removed when the
  # connection ends. The value is the session ID in session_ form, which can
  # link a script back to the session transcript.
  # CLAUDE_CODE_BRIDGE_SESSION_ID = "";
  # Set to 1 in subprocesses Claude Code spawns via the Bash, PowerShell, and Monitor tools, hook commands, and status line commands. [1 or unset]
  # CLAUDE_CODE_CHILD_SESSION = "1";
  # Set automatically to true when Claude Code is running as a cloud session.
  # CLAUDE_CODE_REMOTE = "";
  # Set automatically in cloud sessions to the current session's ID. Read this to construct a link back to the session transcript.
  # CLAUDE_CODE_REMOTE_SESSION_ID = "";
  # Set automatically to the current session ID in Bash and PowerShell tool subprocesses, hook command subprocesses, and stdio MCP server subprocesses.
  # CLAUDE_CODE_SESSION_ID = "";
  # Set automatically in Bash tool subprocesses and hook commands to the active effort level for the turn: low, medium, high, xhigh, or max.
  # CLAUDE_EFFORT = "";
  # Claude Code sets this to its own process ID in the subprocesses it spawns: Bash and PowerShell tool commands and hook commands.
  # CLAUDE_PID = "";

  # === Undocumented: type-resolved variables read by the 2.1.222 binary =====
  # Extracted from the binary's env accessor registry. There is no official
  # description, so semantics are inferred from the name only and are
  # unverified. Unsupported surface: it can change without a changelog entry.

  # Auth, providers, gateway (50)
  # AGENT_PROXY_AUTH_TOKEN = "";                                  # string
  # ANTHROPIC_FEDERATION_RULE_ID = "";                            # string
  # ANTHROPIC_GOOGLE_CLOUD_BASE_URL = "";                         # string
  # ANTHROPIC_GOOGLE_CLOUD_LOCATION = "";                         # string
  # ANTHROPIC_GOOGLE_CLOUD_PROJECT = "";                          # string
  # ANTHROPIC_GOOGLE_CLOUD_WORKSPACE_ID = "";                     # string
  # ANTHROPIC_ORGANIZATION_ID = "";                               # string
  # ANTHROPIC_PROFILE = "";                                       # string
  # CLAUDE_BG_AUTH_SNAPSHOT_PATH = "";                            # string
  # CLAUDE_BG_CLAIM_AUTH = "";                                    # string
  # CLAUDE_BG_PTY_AUTH = "";                                      # string
  # CLAUDE_BG_RV_AUTH = "";                                       # string
  # CLAUDE_BG_SOCKET_TOKENS_PATH = "";                            # string
  # CLAUDE_BRIDGE_OAUTH_TOKEN = "";                               # string
  # CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR = "";                     # string
  # CLAUDE_CODE_ARTIFACTS_API_TOKEN = "";                         # string
  # CLAUDE_CODE_AUTH_FAIL_EXIT_MS = "";                           # int {min:0}
  # CLAUDE_CODE_CUSTOM_OAUTH_URL = "";                            # string
  # CLAUDE_CODE_DESIGN_OAUTH_CLIENT_ID = "";                      # string
  # CLAUDE_CODE_ENABLE_PROXY_AUTH_HELPER = "";                    # bool
  # CLAUDE_CODE_ENABLE_TOKEN_USAGE_ATTACHMENT = "";               # bool
  # CLAUDE_CODE_HFI_BEARER_TOKEN = "";                            # string
  # CLAUDE_CODE_HOST_AUTH_ENV_VAR = "";                           # string
  # CLAUDE_CODE_HOST_AUTH_REFRESH_TIMEOUT_MS = "";                # int {min:1}
  # CLAUDE_CODE_IDLE_TOKEN_THRESHOLD = "";                        # int
  # CLAUDE_CODE_OAUTH_401_WAIT_MS = "";                           # int {min:0}
  # CLAUDE_CODE_OAUTH_CLIENT_ID = "";                             # string
  # CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR = "";                 # string
  # CLAUDE_CODE_ORGANIZATION_UUID = "";                           # string
  # CLAUDE_CODE_PROFILE_QUERY = "";                               # bool
  # CLAUDE_CODE_PROFILE_STARTUP = "";                             # bool
  # CLAUDE_CODE_PROXY_AUTH_HELPER_TTL_MS = "";                    # int
  # CLAUDE_CODE_RESUME_TOKEN_THRESHOLD = "";                      # int
  # CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH = "";                   # bool
  # CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH = "";                       # bool
  # CLAUDE_CODE_SESSION_ACCESS_TOKEN = "";                        # string
  # CLAUDE_CODE_SKIP_ANTHROPIC_GOOGLE_CLOUD_AUTH = "";            # bool
  # CLAUDE_CODE_TOTAL_TOKENS_REMINDER = "";                       # string
  # CLAUDE_CODE_TOTAL_TOKENS_REMINDER_AFTER_USER_TURN = "";       # true | false | unset
  # CLAUDE_CODE_TOTAL_TOKENS_REMINDER_BUDGET = "";                # int
  # CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD = "";                  # bool
  # CLAUDE_CODE_WEBSOCKET_AUTH_FILE_DESCRIPTOR = "";              # string
  # CLAUDE_CODE_WORKFLOW_SIZE_WARNING_TOKENS = "";                # int {min:1}
  # CLAUDE_LOCAL_OAUTH_API_BASE = "";                             # string
  # CLAUDE_LOCAL_OAUTH_APPS_BASE = "";                            # string
  # CLAUDE_LOCAL_OAUTH_CONSOLE_BASE = "";                         # string
  # CLAUDE_SESSION_INGRESS_TOKEN_FILE = "";                       # string
  # CLAUDE_TRUSTED_DEVICE_TOKEN = "";                             # string
  # MCP_OAUTH_CLIENT_METADATA_URL = "";                           # string
  # MCP_XAA_IDP_CLIENT_SECRET = "";                               # string

  # Model, effort, thinking (6)
  # CLAUDE_CODE_AUTO_MODE_MODEL = "";                             # string
  # CLAUDE_CODE_BG_CLASSIFIER_MODEL = "";                         # string
  # CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK = "";                    # bool
  # CLAUDE_CODE_NO_MODEL_FALLBACK = "";                           # bool
  # CLAUDE_CODE_REFUSAL_FALLBACK_CATCH_ALL = "";                  # true | false | unset
  # CLAUDE_CONTEXT_COLLAPSE_MODEL = "";                           # string

  # Agents, tasks, workflows (31)
  # AGENT_PROXY_URL = "";                                         # string
  # CCR_AGENT_PROXY_ENABLED = "";                                 # bool
  # CCR_AGENT_PROXY_INCLUDE_HOSTS = "";                           # string
  # CCR_AGENT_PROXY_RELAY_MODE = "";                              # string
  # CLAUDE_AGENTS_SELECT = "";                                    # string
  # CLAUDE_AGENT_SDK_CLIENT_APP = "";                             # string
  # CLAUDE_AGENT_SDK_VERSION = "";                                # string
  # CLAUDE_BG_BACKEND = "";                                       # string
  # CLAUDE_BG_ISOLATION = "";                                     # string
  # CLAUDE_BG_MEMORY_TOGGLED_OFF = "";                            # string
  # CLAUDE_BG_POST_CLEAR_RESPAWN = "";                            # bool
  # CLAUDE_BG_RENDEZVOUS_SOCK = "";                               # string
  # CLAUDE_BG_SESSION_PERMISSION_RULES = "";                      # string
  # CLAUDE_BG_SOURCE = "";                                        # string
  # CLAUDE_BG_STARTUP_WEDGE_MS = "";                              # int
  # CLAUDE_BG_TCC_DISCLAIMED = "";                                # string
  # CLAUDE_CODE_AGENT = "";                                       # string
  # CLAUDE_CODE_AGENT_PROXY_GH_SHIM = "";                         # bool
  # CLAUDE_CODE_AGENT_PROXY_GIT_CONFIG = "";                      # bool
  # CLAUDE_CODE_BG_TASKS_REPORT_RUNNING = "";                     # bool
  # CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS = "";                # bool
  # CLAUDE_CODE_PLAN_V2_AGENT_COUNT = "";                         # int
  # CLAUDE_CODE_PLAN_V2_EXPLORE_AGENT_COUNT = "";                 # int
  # CLAUDE_CODE_SUBAGENT_CACHE_EVICT = "";                        # bool
  # CLAUDE_CODE_WORKFLOWS = "";                                   # true | false | unset
  # CLAUDE_CODE_WORKFLOW_SIZE_WARNING_AGENTS = "";                # int {min:1}
  # CLAUDE_REMOTE_WORKFLOW_ARGS = "";                             # string
  # CLAUDE_REMOTE_WORKFLOW_SCRIPT = "";                           # string
  # CLAUDE_SUBAGENT_BG_SHELL_MAX_MS = "";                         # int {min:1}
  # CLAUDE_WORKFLOW_NAME_ONLY = "";                               # bool
  # ENABLE_SESSION_BACKGROUNDING = "";                            # bool

  # Memory, context, compaction (29)
  # CLAUDE_AFTER_LAST_COMPACT = "";                               # string
  # CLAUDE_BRIDGE_REATTACH_SESSION = "";                          # string
  # CLAUDE_BRIDGE_SESSION_INGRESS_URL = "";                       # string
  # CLAUDE_CODE_COLD_COMPACT = "";                                # bool
  # CLAUDE_CODE_DISABLE_MEMORY_BULK_INFLATE = "";                 # bool
  # CLAUDE_CODE_DISABLE_MEMORY_MASS_DELETE_HOLD = "";             # bool
  # CLAUDE_CODE_DISABLE_MEMORY_PERIODIC_RESYNC = "";              # bool
  # CLAUDE_CODE_DISABLE_MEMORY_STREAM_LIST = "";                  # bool
  # CLAUDE_CODE_DISABLE_ORG_MEMORY = "";                          # bool
  # CLAUDE_CODE_DISABLE_PRECOMPACT_SKIP = "";                     # bool
  # CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS = "";                   # bool
  # CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING = "";               # bool
  # CLAUDE_CODE_FORCE_EVALUATE_MEMORY = "";                       # bool
  # CLAUDE_CODE_FORCE_MEMORY_SURVEY = "";                         # bool
  # CLAUDE_CODE_MEMORY_PUSH_DELETE_MODE = "";                     # enum ["corroborate","immediate","never"]
  # CLAUDE_CODE_REMOTE_MEMORY_DIR = "";                           # string
  # CLAUDE_CODE_REMOTE_SESSION_ORIGIN = "";                       # string
  # CLAUDE_CODE_RESUME_FROM_SESSION = "";                         # string
  # CLAUDE_CODE_SESSION_KIND = "";                                # string
  # CLAUDE_CODE_SESSION_LOG = "";                                 # string
  # CLAUDE_CODE_SESSION_NAME = "";                                # string
  # CLAUDE_CODE_SYNC_SESSION_REFS = "";                           # bool
  # CLAUDE_CODE_TMUX_SESSION = "";                                # string
  # CLAUDE_CONTEXT_COLLAPSE = "";                                 # bool
  # CLAUDE_COWORK_MEMORY_EXTRA_GUIDELINES = "";                   # string
  # CLAUDE_COWORK_MEMORY_GUIDELINES = "";                         # string
  # CLAUDE_COWORK_MEMORY_INDEX_CONTENT = "";                      # string
  # CLAUDE_COWORK_MEMORY_PATH_OVERRIDE = "";                      # string
  # ENABLE_SESSION_PERSISTENCE = "";                              # bool

  # Tools, bash, sandbox (12)
  # CLAUDE_CODE_BASH_SANDBOX_SHOW_INDICATOR = "";                 # bool
  # CLAUDE_CODE_DIAGNOSTICS_FILE = "";                            # string
  # CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES = "";                     # bool
  # CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL = "";            # bool
  # CLAUDE_CODE_ENABLE_REFRESH_MCP_TOOLS = "";                    # bool
  # CLAUDE_CODE_PEWTER_OWL_TOOL = "";                             # true | false | unset
  # CLAUDE_CODE_REMOTE_RAW_EVENTS_FILE = "";                      # string
  # CLAUDE_CODE_SANDBOXED = "";                                   # bool
  # CLAUDE_CODE_TERMINAL_MCP_TOOLS = "";                          # string
  # CLAUDE_STAGE_FILE_ROOT = "";                                  # string
  # ENABLE_LSP_TOOL = "";                                         # bool
  # ENABLE_MCP_LARGE_OUTPUT_FILES = "";                           # true | false | unset

  # MCP (8)
  # CLAUDE_CODE_SKIP_PLUGIN_MCP_SERVERS = "";                     # bool
  # CLAUDE_CODE_SKIP_PLUGIN_MCP_SERVERS_EXCEPT = "";              # string
  # MCP_DISCOVERY_CACHE = "";                                     # true | false | unset
  # MCP_DISCOVERY_CACHE_MAX_STALE_S = "";                         # int {min:1}
  # MCP_DISCOVERY_CACHE_TTL_S = "";                               # int {min:1}
  # MCP_PROTOCOL_NEGOTIATION = "";                                # string
  # MCP_SDK_GENERATION = "";                                      # string
  # MCP_TRUNCATION_PROMPT_OVERRIDE = "";                          # string

  # Network, proxy, timeouts (36)
  # ANTHROPIC_UNIX_SOCKET = "";                                   # string
  # CLAUDE_BRIDGE_BASE_URL = "";                                  # string
  # CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS = "";                      # int {min:1}
  # CLAUDE_CODE_API_BASE_URL = "";                                # string
  # CLAUDE_CODE_ARTIFACTS_API_BASE_URL = "";                      # string
  # CLAUDE_CODE_ARTIFACT_ASSET_BASE_URL = "";                     # string
  # CLAUDE_CODE_ARTIFACT_LIVE_BASE_URL = "";                      # string
  # CLAUDE_CODE_DEV_RAW_CHANGELOG_URL = "";                       # string
  # CLAUDE_CODE_FABLE_BRIDGE_DIALOG_TIMEOUT_MS = "";              # int
  # CLAUDE_CODE_GB_BASE_URL = "";                                 # string
  # CLAUDE_CODE_PWSH_PARSE_TIMEOUT_MS = "";                       # int
  # CLAUDE_CODE_REPORT_FINDINGS = "";                             # bool
  # CLAUDE_CODE_SIMULATE_PROXY_USAGE = "";                        # bool
  # CLAUDE_CODE_SSE_PORT = "";                                    # int
  # CLAUDE_CODE_SYNC_PLUGINS_INSTALL_TIMEOUT_MS = "";             # int {min:1}
  # CLAUDE_CODE_USER_DIALOG_TIMEOUT_MS = "";                      # int
  # CLAUDE_CODE_WEBFETCH_USE_CCR_PROXY = "";                      # bool
  # CLAUDE_CODE_WEBSEARCH_USE_CCR_PROXY = "";                     # bool
  # CLAUDE_IMPORT_CONVERSATIONS = "";                             # bool
  # CLAUDE_SERVE_DRAIN_TIMEOUT_MS = "";                           # int {min:1}
  # OTEL_EXPORTER_OTLP_ENDPOINT = "";                             # string
  # OTEL_EXPORTER_OTLP_HEADERS = "";                              # string
  # OTEL_EXPORTER_OTLP_LOGS_ENDPOINT = "";                        # string
  # OTEL_EXPORTER_OTLP_LOGS_PROTOCOL = "";                        # string
  # OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = "";                     # string
  # OTEL_EXPORTER_OTLP_METRICS_PROTOCOL = "";                     # string
  # OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "";       # string
  # OTEL_EXPORTER_OTLP_PROTOCOL = "";                             # string
  # OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "";                      # string
  # OTEL_EXPORTER_OTLP_TRACES_PROTOCOL = "";                      # string
  # OTEL_LOGS_EXPORTER = "";                                      # string
  # OTEL_LOGS_EXPORT_INTERVAL = "";                               # int
  # OTEL_METRICS_EXPORTER = "";                                   # string
  # OTEL_METRIC_EXPORT_INTERVAL = "";                             # int
  # OTEL_TRACES_EXPORTER = "";                                    # string
  # OTEL_TRACES_EXPORT_INTERVAL = "";                             # int

  # Terminal, UI, IDE (11)
  # CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE = "";                     # string
  # CLAUDE_CODE_EXIT_AFTER_FIRST_RENDER = "";                     # bool
  # CLAUDE_CODE_FORCE_FULLSCREEN_UPSELL = "";                     # bool
  # CLAUDE_CODE_HIDE_SETTINGS_HINT = "";                          # string
  # CLAUDE_CODE_OVERRIDE_DATE = "";                               # string
  # CLAUDE_CODE_RELAUNCH_TERMINAL_SIZE = "";                      # string
  # CLAUDE_CODE_TERMINAL_RECORDING = "";                          # string
  # CLAUDE_CODE_TUI_JUST_SWITCHED = "";                           # string
  # CLAUDE_RUNNER_DISABLE_AWAITING_ACTION_OVERRIDE = "";          # bool
  # FORCE_CODE_TERMINAL = "";                                     # bool
  # FORCE_COLOR = "";                                             # string

  # Telemetry, logging, debug (13)
  # CLAUDE_CODE_COMMIT_LOG = "";                                  # string
  # CLAUDE_CODE_DD_ERROR_TRACKING_FLUSH_INTERVAL_MS = "";         # int {min:1}
  # CLAUDE_CODE_DEBUG_REPAINTS = "";                              # bool
  # CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = "";                     # bool
  # CLAUDE_CODE_FORCE_FULL_LOGO = "";                             # bool
  # CLAUDE_CODE_FRAME_TIMING_LOG = "";                            # string
  # CLAUDE_CODE_GB_DISK_CACHE_WHEN_TELEMETRY_OFF = "";            # bool
  # CLAUDE_CODE_PERFETTO_TRACE = "";                              # string
  # CLAUDE_DEBUG = "";                                            # bool
  # CLAUDE_GATEWAY_LOG_LEVEL = "";                                # string
  # OTEL_LOGRECORD_ATTRIBUTE_VALUE_LENGTH_LIMIT = "";             # int {min:0}
  # OTEL_RESOURCE_ATTRIBUTES = "";                                # string
  # OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT = "";                  # int {min:0}

  # Remote control, cloud, sharing (17)
  # CCR_ENABLE_BUNDLE = "";                                       # bool
  # CCR_ON_BRANCH_DEFAULT_GUARD = "";                             # enum ["enforce","observe","off"]
  # CLAUDE_BRIDGE_REATTACH_GROUPING = "";                         # string
  # CLAUDE_BRIDGE_REATTACH_OUTBOUND_ONLY = "";                    # bool
  # CLAUDE_BRIDGE_REATTACH_SEQ = "";                              # int
  # CLAUDE_CODE_ARTIFACT = "";                                    # string
  # CLAUDE_CODE_ARTIFACT_COMMENTS = "";                           # true | false | unset
  # CLAUDE_CODE_ARTIFACT_COMMENTS_AUTOREACT = "";                 # true | false | unset
  # CLAUDE_CODE_ARTIFACT_DIRECT_UPLOAD = "";                      # bool
  # CLAUDE_CODE_ENABLE_REMOTE_RECAP = "";                         # true | false | unset
  # CLAUDE_CODE_FORCE_BRIDGE = "";                                # bool
  # CLAUDE_CODE_MOCK_REMOTE_SETTINGS = "";                        # bool
  # CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE = "";                     # string
  # CLAUDE_CODE_REMOTE_HERMETIC_MODE = "";                        # bool
  # CLAUDE_CODE_REMOTE_SEND_KEEPALIVES = "";                      # bool
  # CLAUDE_CODE_REMOTE_SETTINGS_PATH = "";                        # string
  # CLAUDE_CODE_REMOTE_SETTINGS_POLL_MS = "";                     # int

  # Other (136)
  # ANTHROPIC_CONFIG_DIR = "";                                    # string
  # CLAUDE_AX_STARTUP_QUIET_MS = "";                              # int {min:0}
  # CLAUDE_CHROME_CLASSIFIER_FLOOR = "";                          # true | false | unset
  # CLAUDE_CHROME_PERMISSION_MODE = "";                           # string
  # CLAUDE_CODE_ACCOUNT_TAGGED_ID = "";                           # string
  # CLAUDE_CODE_ACCOUNT_UUID = "";                                # string
  # CLAUDE_CODE_ACTION = "";                                      # string
  # CLAUDE_CODE_ACT_DONT_REDERIVE = "";                           # true | false | unset
  # CLAUDE_CODE_ADDITIONAL_PROTECTION = "";                       # bool
  # CLAUDE_CODE_AMBER_ASTROLABE = "";                             # bool
  # CLAUDE_CODE_AUTO_MODE_EXTERNAL_PERMISSIONS = "";              # bool
  # CLAUDE_CODE_BASALT_COVE = "";                                 # bool
  # CLAUDE_CODE_BASE_REF = "";                                    # string
  # CLAUDE_CODE_BASE_REFS = "";                                   # string
  # CLAUDE_CODE_BENCH_LIVE_COUNTS = "";                           # bool
  # CLAUDE_CODE_BISON_CAIRN = "";                                 # bool
  # CLAUDE_CODE_BRIEF = "";                                       # bool
  # CLAUDE_CODE_BRIEF_UPLOAD = "";                                # bool
  # CLAUDE_CODE_BUBBLEWRAP = "";                                  # bool
  # CLAUDE_CODE_BYOC_ENABLE_DATADOG = "";                         # bool
  # CLAUDE_CODE_CLASSIFIER_SUMMARY = "";                          # string
  # CLAUDE_CODE_CONTAINER_ID = "";                                # string
  # CLAUDE_CODE_DAEMON_COLD_START = "";                           # bool
  # CLAUDE_CODE_DATADOG_FLUSH_INTERVAL_MS = "";                   # int {min:1}
  # CLAUDE_CODE_DECSTBM = "";                                     # string
  # CLAUDE_CODE_DISABLE_CLAUDE_API_SKILL = "";                    # bool
  # CLAUDE_CODE_DISABLE_CLAUDE_CODE_SKILL = "";                   # bool
  # CLAUDE_CODE_DISABLE_EXPLORE_INHERIT_CAP = "";                 # bool
  # CLAUDE_CODE_DISABLE_LAUNCH_COMPOSER = "";                     # bool
  # CLAUDE_CODE_DISABLE_NESTED_CHAIN_IDLE = "";                   # bool
  # CLAUDE_CODE_DISABLE_WORKING_SYNC = "";                        # bool
  # CLAUDE_CODE_DONT_INHERIT_ENV = "";                            # bool
  # CLAUDE_CODE_EAGER_FLUSH = "";                                 # bool
  # CLAUDE_CODE_ENABLE_CFC = "";                                  # true | false | unset
  # CLAUDE_CODE_ENABLE_DESIGN_SYNC = "";                          # bool
  # CLAUDE_CODE_ENABLE_LAUNCH_COMPOSER = "";                      # bool
  # CLAUDE_CODE_ENABLE_MENU_KIND_LANES = "";                      # bool
  # CLAUDE_CODE_ENABLE_XAA = "";                                  # bool
  # CLAUDE_CODE_ENVIRONMENT_KIND = "";                            # string
  # CLAUDE_CODE_ENVIRONMENT_RUNNER_VERSION = "";                  # string
  # CLAUDE_CODE_EXTRA_METADATA = "";                              # string
  # CLAUDE_CODE_FLEETVIEW_SIMPLE = "";                            # bool
  # CLAUDE_CODE_FORCE_MID_CONVERSATION_SYSTEM = "";               # bool
  # CLAUDE_CODE_FORCE_TIP_ID = "";                                # string
  # CLAUDE_CODE_FORCE_WINDOWS_CREDMAN = "";                       # string
  # CLAUDE_CODE_FRAME_TIMING_SAMPLE_EVERY = "";                   # int
  # CLAUDE_CODE_GAULT_KESTREL = "";                               # bool
  # CLAUDE_CODE_GB_REFRESH_INTERVAL_MS = "";                      # int
  # CLAUDE_CODE_GORSE_PLOVER = "";                                # bool
  # CLAUDE_CODE_GZIP_REQUEST_BODIES = "";                         # true | false | unset
  # CLAUDE_CODE_HERON_TALLOW = "";                                # bool
  # CLAUDE_CODE_HOST_PLATFORM = "";                               # string
  # CLAUDE_CODE_IDLE_THRESHOLD_MINUTES = "";                      # int
  # CLAUDE_CODE_INCLUDE_PARTIAL_MESSAGES = "";                    # bool
  # CLAUDE_CODE_INVESTIGATE_FIRST = "";                           # bool
  # CLAUDE_CODE_IS_COWORK = "";                                   # bool
  # CLAUDE_CODE_JSONL_TRANSCRIPT = "";                            # string
  # CLAUDE_CODE_JUNIPER_SUNDIAL = "";                             # int {min:1,digitsOnly:!0}
  # CLAUDE_CODE_KB_COHESION_FIXES = "";                           # bool
  # CLAUDE_CODE_LANTERN_PRISM = "";                               # bool
  # CLAUDE_CODE_LOOP_KEEPALIVE = "";                              # bool
  # CLAUDE_CODE_LOOP_PERSISTENT = "";                             # bool
  # CLAUDE_CODE_MANAGED_SETTINGS_PATH = "";                       # string
  # CLAUDE_CODE_MARL_CORMORANT = "";                              # bool
  # CLAUDE_CODE_MOCK_TRIAL = "";                                  # bool
  # CLAUDE_CODE_NANKEEN_KESTREL = "";                             # bool
  # CLAUDE_CODE_PARKED_PERMISSION_WAIT_MS = "";                   # int {min:0}
  # CLAUDE_CODE_PERFETTO_WRITE_INTERVAL_S = "";                   # int
  # CLAUDE_CODE_PEWTER_OWL = "";                                  # true | false | unset
  # CLAUDE_CODE_PLAN_MODE_REQUIRED = "";                          # bool
  # CLAUDE_CODE_PLUGIN_BINARY_ASSETS = "";                        # bool
  # CLAUDE_CODE_PLUGIN_USE_ZIP_CACHE = "";                        # bool
  # CLAUDE_CODE_POWERUP_ONBOARDING = "";                          # string
  # CLAUDE_CODE_PROACTIVE = "";                                   # bool
  # CLAUDE_CODE_QUESTION_PREVIEW_FORMAT = "";                     # string
  # CLAUDE_CODE_RATE_LIMIT_TIER = "";                             # string
  # CLAUDE_CODE_REPL = "";                                        # true | false | unset
  # CLAUDE_CODE_REPO_CHECKOUTS = "";                              # string
  # CLAUDE_CODE_RESUME_SOURCE_ALIVE = "";                         # string
  # CLAUDE_CODE_RESUME_THRESHOLD_MINUTES = "";                    # int
  # CLAUDE_CODE_SEND_FEEDBACK = "";                               # true | false | unset
  # CLAUDE_CODE_SKIP_HFI_VERSION_CHECK = "";                      # bool
  # CLAUDE_CODE_SKIP_PROJECT_BACKFILL = "";                       # bool
  # CLAUDE_CODE_SKIP_REPO_UPLOAD = "";                            # bool
  # CLAUDE_CODE_SLOW_OPERATION_THRESHOLD_MS = "";                 # int
  # CLAUDE_CODE_SPAWN_TIMESTAMP_MS = "";                          # int
  # CLAUDE_CODE_SUBSCRIPTION_TYPE = "";                           # string
  # CLAUDE_CODE_SUPERVISED = "";                                  # bool
  # CLAUDE_CODE_SYNC_PLUGINS = "";                                # bool
  # CLAUDE_CODE_SYNC_PLUGINS_BUFFERED_DOWNLOAD = "";              # bool
  # CLAUDE_CODE_SYNC_PLUGINS_DOWNLOAD_STALL_MS = "";              # int {min:1}
  # CLAUDE_CODE_SYSTEM_PROMPT_GB_FEATURE = "";                    # string
  # CLAUDE_CODE_TAGS = "";                                        # string
  # CLAUDE_CODE_TAG_ISMETA_MESSAGES = "";                         # bool
  # CLAUDE_CODE_TEE_SDK_STDOUT = "";                              # bool
  # CLAUDE_CODE_THISTLE_GREBE = "";                               # string
  # CLAUDE_CODE_THRIFTY_SONIC = "";                               # true | false | unset
  # CLAUDE_CODE_TMUX_PREFIX = "";                                 # string
  # CLAUDE_CODE_TMUX_PREFIX_CONFLICTS = "";                       # bool
  # CLAUDE_CODE_TODO_REMINDER_MODE = "";                          # enum ["baseline","off"]
  # CLAUDE_CODE_TRANSCRIPT_LOCAL_GC = "";                         # true | false | unset
  # CLAUDE_CODE_TRIGGER_ID = "";                                  # string
  # CLAUDE_CODE_TWO_STAGE_CLASSIFIER = "";                        # bool
  # CLAUDE_CODE_USER_EMAIL = "";                                  # string
  # CLAUDE_CODE_USE_COWORK_PLUGINS = "";                          # bool
  # CLAUDE_CODE_USE_GATEWAY = "";                                 # bool
  # CLAUDE_CODE_VOICE_FORWARD_INTERIMS_TYPED = "";                # bool
  # CLAUDE_CODE_WALNUT_SPIRE = "";                                # bool
  # CLAUDE_CODE_WORKER_EPOCH = "";                                # int
  # CLAUDE_CODE_WORKSPACE_HOST_PATHS = "";                        # string
  # CLAUDE_FORCE_DISPLAY_SURVEY = "";                             # bool
  # CLAUDE_GATEWAY_ALLOW_LOOPBACK = "";                           # bool
  # CLAUDE_JOB_DIR = "";                                          # string
  # CLAUDE_MOCK_HEADERLESS_429 = "";                              # bool
  # CLAUDE_PREVIEW_CLASSIFIER_FLOOR = "";                         # true | false | unset
  # CLAUDE_PROJECT_UUID = "";                                     # string
  # CLAUDE_PTY_HEARTBEAT_MS = "";                                 # int {min:1}
  # CLAUDE_PTY_HOST_EXEC = "";                                    # string
  # CLAUDE_PTY_ORPHAN_CHECK_MS = "";                              # int {min:1}
  # CLAUDE_PTY_RECORD = "";                                       # string
  # CLAUDE_REPL_VARIANT = "";                                     # string
  # CLAUDE_RUNNER_ACTIVITY_FD = "";                               # int {min:3}
  # CLAUDE_RUNNER_FETCH_DEPTH = "";                               # string
  # CLAUDE_SECURESTORAGE_CONFIG_DIR = "";                         # string
  # CLAUDE_SLOW_FIRST_BYTE_MS = "";                               # int {min:1}
  # CLAUDE_SNIP = "";                                             # string
  # CLAUDE_SSH_LOCAL_BINARY = "";                                 # string
  # CLAUDE_SSH_VERSION = "";                                      # string
  # CLAUDE_TMPDIR = "";                                           # string
  # DISABLE_BRIEF_MODE_STOP_HOOK = "";                            # bool
  # DISABLE_BUG_COMMAND = "";                                     # bool   ACTIVE above
  # DISABLE_PROMPT_CACHING_MYTHOS = "";                           # bool
  # ENABLE_BETA_TRACING_DETAILED = "";                            # bool
  # ENABLE_LOCKLESS_UPDATES = "";                                 # bool
  # ENABLE_PID_BASED_VERSION_LOCKING = "";                        # true | false | unset
  # FORCE_VCR = "";                                               # bool

  # Test-only harness hooks (7)
  # CLAUDE_CODE_DOWNLOAD_DEADLINE_MS_FOR_TESTING = "";            # string
  # CLAUDE_CODE_STALL_TIMEOUT_MS_FOR_TESTING = "";                # string
  # CLAUDE_CODE_TEST_FIXTURES_ROOT = "";                          # string
  # CLAUDE_CODE_TEST_FORCE_DENY = "";                             # bool
  # CLAUDE_CODE_TEST_NO_GIT_BASH = "";                            # string
  # CLAUDE_CODE_TEST_NO_PWSH = "";                                # string
  # CLAUDE_CODE_ULTRAREVIEW_PREFLIGHT_FIXTURE = "";               # string

  # Internal state markers (4)
  # CLAUDE_CODE_3P_PROBE_WROTE_OPUS_DEFAULT = "";                 # string
  # CLAUDE_CODE_3P_PROBE_WROTE_SONNET_DEFAULT = "";               # string
  # CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME = "";                     # string
  # CLAUDE_INTERNAL_FC_OVERRIDES = "";                            # string

  # === Unconfirmed identifiers ==============================================
  # These names appeared in the binary extraction, but their accessor type
  # could not be resolved. They are retained as evidence only, not as
  # environment variables. Do not activate them without verifying the binary.

  # Auth, providers, gateway (3)
  # CLAUDE_AI_OAUTH_SCOPES = "";
  # CLAUDE_AI_PROFILE_SCOPE = "";
  # MAX_TOTAL_TAG_TOKENS = "";

  # Agents, tasks, workflows (5)
  # AGENT_VIEW_RELAUNCH_ENV_KEY = "";
  # CLAUDE_AGENT = "";
  # MAX_TASK_OUTPUT_BYTES = "";
  # MAX_TASK_OUTPUT_BYTES_DISPLAY = "";
  # MCP_TASK = "";

  # Memory, context, compaction (2)
  # CLAUDE_CODE_SUPPRESS_SESSION_ATTRIBUTION = "";
  # CLAUDE_MEMORY_STORES = "";

  # Tools, bash, sandbox (3)
  # CLAUDE_CODE_HOST_CREDS_FILE = "";
  # CLAUDE_IN_CHROME_DOMAIN_RULE_TOOL = "";
  # MAX_WORKING_FILE_BYTES = "";

  # MCP (7)
  # CLAUDE_CODE_SYNC_PLUGINS_MCP_TIMEOUT_MS = "";
  # CLAUDE_IN_CHROME_MCP_SERVER_NAME = "";
  # MAX_MCP_CONFIG_BYTES = "";
  # MCP_CLIENT_METADATA_URL = "";
  # MCP_SCHEMA_BY_TYPE = "";
  # MCP_SETTINGS_SCOPES = "";
  # MCP_TREE_ID = "";

  # Network, proxy, timeouts (1)
  # CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL = "";

  # Telemetry, logging, debug (2)
  # ENABLE_ENHANCED_TELEMETRY_BETA = "";
  # MAX_DECLARED_DIALOG_KINDS = "";

  # Remote control, cloud, sharing (2)
  # CCR_BYOC_BETA = "";
  # MAX_ARTIFACT_BYTES = "";

  # Other (16)
  # CLAUDE_AI_INFERENCE_SCOPE = "";
  # CLAUDE_API_SKILL_DESCRIPTION = "";
  # CLAUDE_CODE_ENTRYPOINT = "";
  # CLAUDE_CODE_LARCH_CISTERN = "";
  # CLAUDE_CODE_SKILL_NAME = "";
  # MAX_ESTIMATED_NESTING = "";
  # MAX_LAUNCH_BUNDLE_BYTES = "";
  # MAX_MARKDOWN_LENGTH = "";
  # MAX_PERSIST_BINARY_BYTES = "";
  # MAX_QUEUED_EVENTS = "";
  # MAX_SANE_EPOCH_MS = "";
  # MAX_SANITIZED_LENGTH = "";
  # MAX_SCAN_ENTRIES = "";
  # MAX_SCAN_WORK = "";
  # MAX_TOTAL_OPEN_TAGS = "";
  # MAX_TRANSCRIPT_READ_BYTES = "";

in
assert
  retiredButLive == [ ]
  || throw "modules/agents/claude-code/_env.nix: ${builtins.concatStringsSep ", " retiredButLive} are both retired and live; remove the name from retired or its live group";
{
  inherit binary retired;
  settings = binary // bashRuntime // modelRouting;
  all = binary // bashRuntime // modelRouting // shellOnly;
}
