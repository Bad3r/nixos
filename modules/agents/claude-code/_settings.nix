# ~/.claude/settings.json keys that _plugins.nix and _permissions.nix do not
# hold. Uncomment a key and set its value to enable it. Every key set here
# replaces Claude's copy on each switch; commenting it out again removes it.
#
# autoCompactEnabled, editorMode, preferredNotifChannel, theme, and verbose
# stay commented below; their live values are in _claude-json.nix.
{
  # Advisor model for the server-side advisor tool.
  # advisorModel = ""; # [string]

  # Name of an agent (built-in or custom) to use for the main thread. Applies
  # the agent's system prompt, tool restrictions, and model.
  # agent = ""; # [string]

  # Allow Claude to push proactive mobile notifications
  # agentPushNotifEnabled = true; # [boolean]

  # Allowlist of URL patterns that HTTP hooks may target. Supports * as a
  # wildcard (e.g. "https://hooks.example.com/*"). When set, HTTP hooks with
  # non-matching URLs are blocked. If undefined, all URLs are allowed. If
  # empty array, no HTTP hooks are allowed. Arrays merge across settings
  # sources (same semantics as allowedMcpServers).
  # allowedHttpHookUrls = [ ]; # [array]

  # When false, thinking is disabled. When absent or true, thinking is enabled
  # automatically for supported models.
  alwaysThinkingEnabled = true;

  # Path to a script that outputs authentication values
  # apiKeyHelper = ""; # [string]

  # Idle time before Claude's questions auto-continue with any answers
  # selected so far. Defaults to never - auto-continue only runs
  # when explicitly set to 60s/5m/10m.
  # askUserQuestionTimeout = "60s"; # [60s | 5m | 10m | never]

  # Attribution text for git commits, including any trailers. Empty string
  # hides attribution.
  # attribution = { }; # [object]

  # Automatically compact conversation when context fills
  # autoCompactEnabled = true; # [boolean]

  # Auto-compact window size
  # autoCompactWindow = 0; # [number]

  # Custom directory path for auto-memory storage. Supports ~/ prefix for home
  # directory expansion. Ignored if set in projectSettings (checked-in
  # .claude/settings.json) for security. When unset, defaults to
  # ~/.claude/projects/<sanitized-cwd>/memory/.
  # autoMemoryDirectory = ""; # [string]

  # Enable auto-memory for this project. When false, Claude will not read from
  # or write to the auto-memory directory.
  # autoMemoryEnabled = true; # [boolean]

  # Auto-scroll the conversation view to bottom (fullscreen mode only)
  # autoScrollEnabled = true; # [boolean]

  # Release channel for auto-updates (latest or stable)
  # autoUpdatesChannel = "latest"; # [latest | stable | rc]

  # Allowlist of models that users can select. Accepts family aliases ("opus"
  # allows any opus version), version prefixes ("opus-4-5" allows only that
  # version), and full model IDs. If undefined, all models are available. If
  # empty array, only the default model is available. Typically set in managed
  # settings by enterprise administrators.
  # availableModels = [ ]; # [array]

  # @internal When false, the session recap (shown when you return after being
  # away for 5+ minutes) is disabled. When absent or true, recap is enabled.
  # Hidden from public SDK types until external launch.
  # awaySummaryEnabled = true; # [boolean]

  # Path to a script that refreshes AWS authentication
  # awsAuthRefresh = ""; # [string]

  # Path to a script that exports AWS credentials
  # awsCredentialExport = ""; # [string]

  # Glob patterns or absolute paths of CLAUDE.md files to exclude from
  # loading. Patterns are matched against absolute file paths using picomatch.
  # Only applies to User, Project, and Local memory types (Managed/policy
  # files cannot be excluded). Examples: "/home/user/monorepo/CLAUDE.md",
  # "**/code/CLAUDE.md", "**/some-dir/.claude/rules/**"
  # claudeMdExcludes = [ ]; # [array]

  # Number of days to retain chat transcripts before automatic cleanup (default:
  # 30). Minimum 1. Use a large value for long retention; use --no-session-
  # persistence to disable transcript writes entirely.
  cleanupPeriodDays = 30;

  # Company announcements to display at startup (one will be randomly selected
  # if multiple are provided)
  # companyAnnouncements = [ ]; # [array]

  # Default shell for input-box ! commands. Defaults to 'bash' on all
  # platforms (no Windows auto-flip).
  # defaultShell = "bash"; # [bash | powershell]

  # Disable agent view (`claude agents`, `--bg`, /background, the on-demand
  # daemon). Typically set in managed settings. Equivalent to
  # CLAUDE_CODE_DISABLE_AGENT_VIEW=1.
  # disableAgentView = true; # [boolean]

  # Disable all hooks and statusLine execution
  # disableAllHooks = true; # [boolean]

  # Disable the Artifact tool (also via CLAUDE_CODE_DISABLE_ARTIFACT).
  # disableArtifact = true; # [boolean]

  # Disable Remote Control (claude.ai/code, `claude remote-control`,
  # `--remote-control`/`--rc`, auto-start, and the in-session toggle).
  # Typically set in managed settings.
  # disableRemoteControl = true; # [boolean]

  # Disable the Workflows feature (also via CLAUDE_CODE_DISABLE_WORKFLOWS).
  # disableWorkflows = true; # [boolean]

  # Key binding mode for the prompt input
  # editorMode = ""; # [enum]

  # Accepts low|medium|high|xhigh only; CLAUDE_CODE_EFFORT_LEVEL in _env.nix pins max and outranks it.
  effortLevel = "xhigh";

  # When false, the :emoji: shortcode typeahead (the suggestion popup and the
  # :name: inline replacement) is disabled. When absent or true, it is
  # enabled.
  # emojiCompletionEnabled = true; # [boolean]

  # Enable or disable the Artifact tool for this user. Unset defaults to
  # enabled once the feature is available.
  # enableArtifact = true; # [boolean]

  # When true and availableModels is a non-empty array, the Default model
  # selection is also constrained: if the default model for the user tier is
  # not in availableModels, Default resolves to the first allowed
  # availableModels entry instead. Has no effect when availableModels is unset
  # or an empty array. Typically set in managed settings by enterprise
  # administrators.
  # enforceAvailableModels = true; # [boolean]

  # Fallback model(s) tried in order when the primary model is overloaded or
  # unavailable. Each element accepts a model name or alias; "default" expands
  # to the default model. CLI --fallback-model takes precedence.
  # fallbackModel = [ ]; # [array]

  # When true, fast mode is enabled. When absent or false, fast mode is off.
  # fastMode = true; # [boolean]

  # When true, fast mode does not persist across sessions. Each session starts
  # with fast mode off.
  # fastModePerSessionOptIn = true; # [boolean]

  # Probability (0-1) that the session quality survey appears when
  # eligible. 0.05 is a reasonable starting point.
  # feedbackSurveyRate = 0; # [number]

  # Snapshot files before edits so /rewind can restore them
  fileCheckpointingEnabled = true;

  # Custom file suggestion configuration for @ mentions
  # fileSuggestion = { }; # [object]

  # Extra clickable footer badges that appear when a regex matches turn output
  # (tool results and assistant responses). Read from user, flag, and managed
  # settings only; ignored in project .claude/settings.json and local
  # .claude/settings.local.json. At most 5 badges render; the oldest is
  # displaced by newer matches and /clear removes them. Use to surface IDs
  # printed by project CLIs as session links.
  # footerLinksRegexes = [ ]; # [array]

  # Force a specific login method: "claudeai" for Claude Pro/Max, "console"
  # for Console billing, "gateway" for the Cloud gateway OIDC device flow
  # forceLoginMethod = "claudeai"; # [claudeai | console | gateway]

  # Organization UUID to require for OAuth login. Accepts a single UUID string
  # or an array of UUIDs (any one is permitted). When set in managed settings,
  # login fails if the authenticated account does not belong to a listed
  # organization.
  # forceLoginOrgUUID = ""; # [union]

  # Command to refresh GCP authentication (e.g., gcloud auth application-
  # default login)
  # gcpAuthRefresh = ""; # [string]

  # Custom commands to run before/after tool executions
  # hooks = ""; # [?]

  # Allowlist of environment variable names HTTP hooks may interpolate into
  # headers. When set, each hook's effective allowedEnvVars is the
  # intersection with this list. If undefined, no restriction is applied.
  # Arrays merge across settings sources (same semantics as
  # allowedMcpServers).
  # httpHookAllowedEnvVars = [ ]; # [array]

  # Deprecated: Use attribution instead. Whether to include Claude's co-authored
  # by attribution in commits and PRs (defaults to true)
  includeCoAuthoredBy = false;

  # Include built-in commit and PR workflow instructions in Claude's system
  # prompt (default: true)
  # includeGitInstructions = true; # [boolean]

  # Push to mobile when a permission prompt or question is waiting
  # inputNeededNotifEnabled = true; # [boolean]

  # Have Claude respond in a language other than English
  language = "en";

  # Minimum version to stay on - prevents downgrades when switching to stable
  # channel
  # minimumVersion = ""; # [string]

  # Override the default model used by Claude Code
  model = "claude-opus-5";

  # Override mapping from Anthropic model ID (e.g. "claude-opus-4-6") to
  # provider-specific model ID (e.g. a Bedrock inference profile ARN).
  # Typically set in managed settings by enterprise administrators.
  # modelOverrides = { }; # [record]

  # Path to a script that outputs OpenTelemetry headers
  # otelHeadersHelper = ""; # [string]

  # Controls the output style for assistant responses
  outputStyle = "Proactive";

  # Custom directory for plan files, relative to project root. If not set,
  # defaults to ~/.claude/plans/
  # plansDirectory = ""; # [string]

  # URL template for PR links in the footer link badges and inline messages.
  # The detected git PR is rendered as the first footer-link badge.
  # Placeholders: {host} {owner} {repo} {number} {url}. Example:
  # "https://reviews.example.com/{owner}/{repo}/pull/{number}"
  # prUrlTemplate = ""; # [string]

  # Preferred OS notification channel
  # preferredNotifChannel = ""; # [enum]

  # Reduce or disable animations for accessibility (spinner shimmer, flash
  # effects, etc.)
  # prefersReducedMotion = true; # [boolean]

  # Corporate launcher argv prefix for the background-agent supervisor, the
  # sessions and workers it hosts, and the other covered background processes
  # listed in the Claude Code corporate-launcher documentation. Equivalent to
  # the CLAUDE_CODE_PROCESS_WRAPPER environment variable, which takes
  # precedence when set. Honored from managed settings, a --settings/SDK-
  # supplied settings file, and user settings, in that precedence order;
  # project and local settings are ignored.
  # processWrapper = ""; # [string]

  # Default environment ID to use for cloud sessions
  # remote = { }; # [object]

  # Start Remote Control bridge automatically each session
  # remoteControlAtStartup = true; # [boolean]

  # Whether file picker should respect .gitignore files (default: true). Note:
  # .ignore files are always respected.
  respectGitignore = false;

  # Whether Claude responds after an input-box ! bash command runs. Set to
  # false to add the command output to context without a response. Default:
  # true.
  # respondToBashCommands = true; # [boolean]

  # When true, the plan-approval dialog offers a "clear context" option.
  # Defaults to false.
  # showClearContextOnPlanAccept = true; # [boolean]

  # Request API-side thinking summaries and show them in the conversation and
  # in the transcript view (ctrl+o). Set explicitly to override the default
  # for your install.
  # showThinkingSummaries = true; # [boolean]

  # Show "Cooked for Nm Ns" after each assistant turn
  # showTurnDuration = true; # [boolean]

  # Whether to show tips in the spinner
  spinnerTipsEnabled = true;

  # Override spinner tips. tips: array of tip strings. excludeDefault: if
  # true, only show custom tips (default: false).
  # spinnerTipsOverride = { }; # [object]

  # Customize spinner verbs. mode: "append" adds verbs to defaults, "replace"
  # uses only your verbs.
  # spinnerVerbs = { }; # [object]

  # Unique identifier for this SSH config. Used to match configs across
  # settings sources.
  # sshConfigs = [ ]; # [array]

  # Re-run the status line command every N seconds in addition to event-driven
  # updates
  # statusLine = { }; # [object]

  # When safeguards flag a message, automatically switch to a different model
  # to keep chatting. When off, your session will pause instead.
  # switchModelsOnFlag = true; # [boolean]

  # Whether to disable syntax highlighting in diffs
  # syntaxHighlightingDisabled = true; # [boolean]

  # How spawned teammates execute (tmux, iterm2, in-process, auto)
  # teammateMode = ""; # [enum]

  # Emit OSC 9;4 progress sequences during long operations
  terminalProgressBarEnabled = true;

  # Color theme for the UI
  # theme = ""; # [union]

  # Terminal UI renderer. "fullscreen" uses the flicker-free alt-screen
  # renderer with virtualized scrollback (equivalent to
  # CLAUDE_CODE_NO_FLICKER=1). "default" uses the classic main-screen
  # renderer.
  # tui = "default"; # [default | fullscreen]

  # Enable ultracode for the session: xhigh effort plus standing dynamic-
  # workflow orchestration. Session-scoped - typically provided via
  # --settings or the apply_flag_settings control request; interactive
  # toggles never persist it. Requires workflows to be enabled and an xhigh-
  # capable model.
  # ultracode = true; # [boolean]

  # Whether plan mode uses auto mode semantics when auto mode is available
  # (default: true)
  useAutoModeDuringPlan = false;

  # Show full tool output instead of truncated summaries
  # verbose = true; # [boolean]

  # Default transcript view mode on startup
  # viewMode = "default"; # [default | verbose | focus]

  # Vim INSERT-mode key-sequence remaps, e.g. {"jj": "<Esc>"}. Each key is
  # exactly two printable characters typed in sequence; "<Esc>" (return to
  # NORMAL mode) is the only supported target. Applies when editorMode is
  # "vim".
  # vimInsertModeRemaps = { }; # [record]

  # 'hold' (default): hold to talk. 'tap': tap to start, tap to stop+submit.
  # voice = { }; # [object]

  # Ramp mouse-wheel scroll speed during fast scrolls (fullscreen mode only)
  # wheelScrollAccelerationEnabled = true; # [boolean]

  # Enable the "ultracode" keyword trigger: including the keyword in a prompt
  # opts that turn into the Workflow tool. Set to false to disable the
  # trigger. Default: true.
  # workflowKeywordTriggerEnabled = true; # [boolean]

  # Advisory size guideline for the dynamic workflows Claude writes: "small"
  # aims for fewer than 5 agents, "medium" (the default) fewer than 15,
  # "large" fewer than 50, and "unrestricted" sends no guideline. A value here
  # - including from managed settings - takes precedence over the
  # "Dynamic workflow size" choice in /config, and that /config row is hidden
  # while a settings file provides the key. This is a guideline, not an
  # enforced limit.
  # workflowSizeGuideline = "unrestricted"; # [unrestricted | small | medium | large]

  # Directories to symlink from main repository to worktrees to avoid disk
  # bloat. Must be explicitly configured - no directories are symlinked by
  # default. Common examples: "node_modules", ".cache", ".bin"
  # worktree = { }; # [object]

  # --- Undocumented (2.1.222 binary schema) ---

  # Enable background memory consolidation (auto-dream). When set, overrides
  # the server-side default.
  # autoDreamEnabled = true; # [boolean]

  # Mirror local sessions to claude.ai as view-only (no remote control)
  # autoUploadSessions = true; # [boolean]

  # Show a friendly nudge after sustained continuous use (default false). Must
  # be true for the reminder to fire.
  # breakReminder = ""; # [object]

  # When no background service is running: 'transient' spawns one for this
  # login session; 'ask' offers to install it persistently
  # daemonColdStart = "transient"; # transient | ask

  # @internal When true, Claude keeps working until the PR is ready for you to
  # merge, a cron/Monitor is armed to resume later, or it hands you a self-
  # contained next step.
  # doneMeansMerged = true; # [boolean]

  # Enable or disable the Workflows feature for this user. Unset = default by
  # plan once the feature is available.
  # enableWorkflows = true; # [boolean]

  # Model-drafted feedback (the SendFeedback tool). "notify" (default) shows a
  # one-line notice when a draft is queued; "quiet" shows only the footer
  # counter; "off" disables the tool entirely so drafts are never queued.
  # feedbackDrafts = "notify"; # notify | quiet | off

  # Precompute the compaction summary in the background before it is needed.
  # Only applies when auto-compact is on.
  # precomputeCompactionEnabled = true; # [boolean]

  # When false, prompt suggestions are disabled. When absent or true, prompt
  # suggestions are enabled.
  # promptSuggestionEnabled = true; # [boolean]

  # Shell command that outputs a Proxy-Authorization header value (EAP)
  # proxyAuthHelper = ""; # [string]

  # Show a one-time nudge when you start or keep using the CLI inside your
  # quiet-hours window (default false).
  # quietHours = ""; # [object]

  # Stamp each message with its arrival time
  # showMessageTimestamps = true; # [boolean]

  # @internal Whether the user has accepted the multi-agent workflow usage
  # warning. Until set, auto permission mode prompts before running a
  # workflow.
  # skipWorkflowUsageWarning = true; # [boolean]

  # Custom per-subagent status line shown in the agent panel; receives row
  # context as JSON on stdin
  # subagentStatusLine = ""; # [object]

  # Whether /rename updates the terminal tab title (defaults to true). Set to
  # false to keep auto-generated topic titles.
  # terminalTitleFromRename = true; # [boolean]

  # Enable the todo / task tracking panel
  # todoFeatureEnabled = true; # [boolean]

  # @internal Emit a <total_tokens>N tokens left</total_tokens> block in the
  # system prompt, after each tool result, and (when
  # totalTokensReminderAfterUserTurn is on) after each regular user prompt.
  # 'infinite' uses the literal value Infinite, 'fixed' uses 5000000,
  # 'countdown' uses the live remaining context-window tokens, 'padded-
  # countdown' counts down from totalTokensReminderBudget (re-anchoring to the
  # full budget on each regular user prompt when
  # totalTokensReminderAfterUserTurn is on - task-budget semantics).
  # Defaults to off. Env var CLAUDE_CODE_TOTAL_TOKENS_REMINDER overrides.
  # totalTokensReminder = "off"; # off | infinite | fixed | countdown | padded-countdown

  # @internal When true, emit the totalTokensReminder block after each regular
  # user prompt and (for 'padded-countdown') re-anchor the task budget to the
  # full configured value at the start of each user turn. When false, the
  # reminder appears only in the system prompt and after each tool-result
  # batch, and 'padded-countdown' counts down over the whole session. Defaults
  # to off. Env var CLAUDE_CODE_TOTAL_TOKENS_REMINDER_AFTER_USER_TURN
  # overrides; server-controlled via GrowthBook tengu_lapis_anchor_user_turn.
  # totalTokensReminderAfterUserTurn = true; # [boolean]

  # @internal Starting budget (tokens) for totalTokensReminder 'padded-
  # countdown' mode. Defaults to 15000000. Server-controlled via GrowthBook;
  # env var CLAUDE_CODE_TOTAL_TOKENS_REMINDER_BUDGET overrides.
  # totalTokensReminderBudget = 0; # [number]

  # --- Managed settings only: no effect in ~/.claude/settings.json ---

  # CLAUDE.md-style instructions injected as organization-managed memory. Only
  # honored from managed/policy settings.
  # claudeMd = ""; # [string]

  # @internal Cloud gateway URL to pre-fill and auto-connect to during login.
  # Typically set in local managed settings alongside forceLoginMethod:
  # "gateway" so users never type the URL. Hidden from public SDK types until
  # Cloud gateway is documented.
  # forceLoginGatewayUrl = ""; # [string]

  # When set in managed settings, the CLI blocks startup until remote managed
  # settings are freshly fetched, and exits if the fetch fails
  # forceRemoteSettingsRefresh = true; # [boolean]

  # (Managed settings only) **Default**: `"first-wins"`. Controls whether
  # managed settings supplied programmatically by an embedding host process,
  # such as the Agent SDK or an IDE extension, apply when an admin-deployed
  # managed tier is also present. `"first-wins"`: the parent-supplied settings
  # are dropped and only the admin tier applies. `"merge"`: the parent-
  # supplied settings apply under the admin tier through a restrictive-only
  # filter. Only the highest-priority managed source's value of this key is
  # read. Unless the `allowManaged*Only` locks are set, allow-direction
  # entries such as permission allow rules and sandbox allowlists still apply;
  # see Restrict parent settings. Has no effect when no admin tier is
  # deployed, or when a `policyHelper` is configured: the helper's output
  # replaces every other managed source and parent settings are never merged.
  # Requires Claude Code v2.1.133 or later
  # parentSettingsBehavior = "first-wins"; # [first-wins | merge]

  # Executable that computes managed settings at startup. Honored only from
  # admin-controlled policy sources.
  # policyHelper = ""; # [?]

  # Maximum Claude Code version allowed to start. If the running version is
  # newer, Claude Code exits at startup with instructions to install an
  # approved version. Only enforced from managed (policy) settings.
  # requiredMaximumVersion = ""; # [string]

  # Minimum Claude Code version required to start. If the running version is
  # older, Claude Code exits at startup with instructions to update. Only
  # enforced from managed (policy) settings.
  # requiredMinimumVersion = ""; # [string]

  # When set to true in either admin-only Windows source - the HKLM
  # SOFTWARE/Policies/ClaudeCode registry key or C:/Program
  # Files/ClaudeCode/managed-settings.json - WSL reads managed settings
  # from the full Windows policy chain (HKLM, C:/Program Files/ClaudeCode via
  # DrvFs, HKCU) in addition to /etc/claude-code. Windows sources take
  # priority. The flag is also required in HKCU itself for HKCU policy to
  # apply on WSL (double opt-in: admin enables the chain, user confirms HKCU).
  # On native Windows the flag has no effect.
  # wslInheritsWindowsSettings = true; # [boolean]
}
