/*
  Upstream-shaped Claude Code defaults.

  Source of truth for default ~/.claude/settings.json keys, ~/.claude.json
  UI preferences, and ~/.claude/keybindings.json. Values that depend on runtime
  evaluation (enabledPlugins, deniedMcpServers, mcpServers) are injected by
  _settings.nix; this attrset only carries the static portion shared across
  hosts.

  Permission rule semantics (code.claude.com/docs/en/permissions):
    * Rules evaluate deny -> ask -> allow; first match wins, so an ask/deny
      rule overrides a broader allow.
    * `Bash(cmd *)` is the canonical prefix rule: the trailing ` *` keeps a word
      boundary, so `Bash(git *)` matches `git`/`git status` but not `github`.
    * `Edit(path)` covers every file-editing tool (Edit, Write, MultiEdit,
      NotebookEdit). A `Write(path)` rule is accepted but never matched by the
      file checks and warns at startup, hence `Edit(**)` and no `Write(**)`.
*/
let
  claudeEnv = import ./_env.nix;

  # Canonical Bash prefix rule (matches the bare command and any arguments).
  bashPrefix = cmd: "Bash(${cmd} *)";

  # Command prefixes auto-approved without a permission prompt.
  bashAllow = [
    "awk"
    "bash"
    "biome"
    "cat"
    "cd"
    "coverage"
    "cp"
    "curl"
    "cut"
    "diff"
    "echo"
    "fd"
    "find"
    "gh"
    "git"
    "grep"
    "head"
    "jq"
    "ls"
    "make"
    "mkdir"
    "nix"
    "npm run"
    "nvim"
    "patch"
    "pkill"
    "pwd"
    "pytest"
    "pyright"
    "python"
    "rg"
    "ruff"
    "sed"
    "sort"
    "source"
    "tail"
    "tee"
    "touch"
    "uniq"
    "uv"
    "wc"
    "zsh"
  ];

  # Destructive or history-rewriting commands that must ask first. Claude
  # evaluates ask before allow, so these override the broad `git *` allow even
  # under acceptEdits/auto/bypassPermissions. Mirrors the codex execpolicy
  # prompt rules (modules/agents/codex/_exec-policy.nix) so both agents gate the
  # same operations. `git checkout -- ` is the discard form codex's prefix-only
  # matcher cannot express; the positional wildcard leaves branch switches
  # (`git checkout main`) untouched.
  # Imported rather than transcribed: this list and the codex prompt rules
  # gated different spellings twice in #399, and nothing failed when they
  # diverged. See that file for why the coverage is best-effort.
  stashHelperAsk = map (argv: builtins.concatStringsSep " " argv) (
    import ../_stash-helper-invocations.nix
  );

  bashAsk = [
    "git clean"
    "git reset"
    "git rebase"
    "git restore"
    "git checkout --"
    "git stash drop"
    "git stash clear"
    "git stash pop"
    "git branch -d"
    "git branch -D"
    "git branch --delete"
    "git tag -d"
    "git tag --delete"
    "git worktree remove"
    "git remote prune"
    "git filter-branch"
    "git filter-repo"
    "git gc"
    "git prune"
    "git reflog expire"
    "git push -f"
    "git push --force"
    "git push --force-with-lease"
    "git push --mirror"
    "git push --delete"
    "git push --prune"
    "gh repo delete"
    "gh pr close --delete-branch"
  ]
  ++ stashHelperAsk
  ++ [
    # No codex counterpart: `bash` is in bashAllow here and deliberately not in
    # codex's allowAllCommands, and codex hands the inner script of a wrapped
    # invocation back to execpolicy while this layer does not. The wrapping
    # forms themselves must ask, or every rule above is bypassable through
    # `bash -c '...'`.
    "bash scripts/prune-old-stashes.sh"
    "bash ./scripts/prune-old-stashes.sh"
    "bash -c"
    "bash -lc"
    "zsh -c"
    "zsh -lc"
    # The same bypass without a shell: each takes a program name as its first
    # operand, so `timeout 60 <cmd>` reaches every rule above without matching
    # any of them. Gated here and absent from bashAllow, since ask wins and an
    # allow entry for the same prefix would only be a dead rule claiming the
    # opposite.
    #
    # Best-effort, like the shared invocation list: `find -exec`, `make`,
    # `nix develop -c`, `nix run`, `nvim`, `python` and `source` reach an
    # arbitrary program too and stay allowed, because gating them would prompt
    # on this repo's ordinary use of each. The three below are the ones whose
    # only purpose is to run one.
    "timeout"
    "time"
    "xargs"
  ];

  # coreutils rm bypasses the PATH shim that routes bare `rm` to trash-cli, so
  # deny the common absolute paths and keep deletions recoverable. Parity with
  # codex forbiddenRmRules.
  bashDeny = [
    "/bin/rm"
    "/usr/bin/rm"
    "/run/current-system/sw/bin/rm"
  ];

  # Read/Edit/WebFetch grants. `Read(**)`/`Edit(**)` cover the working tree, and
  # `Edit(**)` also covers Write/MultiEdit/NotebookEdit. The parent-relative
  # Read rules reach the repo-root and global CLAUDE.md from nested worktrees,
  # which the cwd-anchored `Read(**)` does not.
  fileWebAllow = [
    "Read(~/.claude/CLAUDE.md)"
    "Read(../../.claude/CLAUDE.md)"
    "Read(../../../.claude/CLAUDE.md)"
    "WebFetch(domain:docs.anthropic.com)"
    "WebFetch(domain:*.github.com)"
    "Read(**)"
    "Edit(**)"
  ];

  # Both lists become `Bash(<cmd> *)`, and ask is evaluated first, so a prefix
  # present in both leaves an allow rule that can never match while stating the
  # opposite of the one that does. Exact strings only: `bash` in bashAllow and
  # `bash -c` in bashAsk are different rules, and both are live.
  deadAllow = builtins.filter (cmd: builtins.elem cmd bashAsk) bashAllow;

  # Keys retired from existing ~/.claude/settings.json and ~/.claude.json files.
  retired = {
    settings = [ ];
    claudeJson = [ "autocheckpointingEnabled" ];
  };

  # Runtime-owned keys are merged over these static bases by _settings.nix.
  # Keep these lists aligned with that producer so retirement cannot delete a
  # key that the same activation pass just injected.
  injectedSettings = [
    "enabledPlugins"
    "deniedMcpServers"
  ];
  injectedClaudeJson = [ "mcpServers" ];

  claudeSettingsBase = {
    cleanupPeriodDays = 30;
    # Disables + bash knobs from the shared source
    # (modules/agents/claude-code/_env.nix).
    env = claudeEnv.settings;
    includeCoAuthoredBy = false;
    permissions = {
      allow = fileWebAllow ++ map bashPrefix bashAllow;
      ask = map bashPrefix bashAsk;
      deny = map bashPrefix bashDeny;
      defaultMode = "plan";
    };
    model = "claude-opus-5"; # Default model
    alwaysThinkingEnabled = true;
    # Persisted effort accepts low|medium|high|xhigh only; `max` is silently
    # dropped by the schema's .catch(). CLAUDE_CODE_EFFORT_LEVEL in `env` pins
    # max and outranks this, which stays as the floor if that var is unset.
    effortLevel = "xhigh";
    enableAllProjectMcpServers = true;
    fileCheckpointingEnabled = true; # Snapshot files before edits so /rewind can restore them
    language = "en"; # Language
    outputStyle = "Proactive"; # Output style
    respectGitignore = false; # Respect .gitignore in file picker
    spinnerTipsEnabled = true; # Show tips
    terminalProgressBarEnabled = true; # Terminal progress bar
    useAutoModeDuringPlan = false; # Use auto mode during plan
  };

  # UI preferences for ~/.claude.json (merged with existing config in _settings.nix)
  claudeJsonConfigBase = {
    hasTrustDialogAccepted = true;
    hasCompletedProjectOnboarding = true;
    bypassPermissionsModeAccepted = true;
    autoCompactEnabled = true; # Auto-compact
    autoConnectIde = false; # Auto-connect to IDE
    autoUpdates = false; # Auto-updates
    claudeInChromeDefaultEnabled = true; # Chrome enabled by default
    defaultToAgentsView = true; # Open agents view by default
    diffTool = "diff"; # Diff tool
    editorMode = "vim"; # Editor mode
    externalEditorContext = true; # Show last response in external editor
    preferredNotifChannel = "iterm2_with_bell"; # Notifications
    theme = "dark"; # Theme
    verbose = true; # Verbose output
  };
  retiredJsonButLive = builtins.filter (
    name: builtins.hasAttr name claudeJsonConfigBase || builtins.elem name injectedClaudeJson
  ) retired.claudeJson;
  retiredSettingsButLive = builtins.filter (
    name: builtins.hasAttr name claudeSettingsBase || builtins.elem name injectedSettings
  ) retired.settings;
in
assert
  deadAllow == [ ]
  || throw "modules/agents/claude-code/_default-settings.nix: ${builtins.concatStringsSep ", " deadAllow} are in both bashAllow and bashAsk; ask wins, so drop them from bashAllow rather than leaving the two lists disagreeing";
assert
  retiredJsonButLive == [ ]
  || throw "modules/agents/claude-code/_default-settings.nix: ${builtins.concatStringsSep ", " retiredJsonButLive} are both retired and live; remove the name from retired, claudeJsonConfigBase, or the _settings.nix injected keys";
assert
  retiredSettingsButLive == [ ]
  || throw "modules/agents/claude-code/_default-settings.nix: ${builtins.concatStringsSep ", " retiredSettingsButLive} are both retired and live; remove the name from retired, claudeSettingsBase, or the _settings.nix injected keys";
{
  inherit claudeJsonConfigBase claudeSettingsBase retired;

  # === Undocumented settings.json keys (2.1.222 binary schema) ==============
  # Present in the binary's settings schema but absent from the published settings
  # docs. Descriptions are the schema's own .describe() text. Activate a key by
  # moving the line into claudeSettingsBase above; leaving it here keeps Claude's
  # default.
  #   Enable background memory consolidation (auto-dream). When set, overrides
  #   the server-side default.
  #   autoDreamEnabled = true;  # [boolean]
  #
  #   Mirror local sessions to claude.ai as view-only (no remote control)
  #   autoUploadSessions = true;  # [boolean]
  #
  #   Show a friendly nudge after sustained continuous use (default false). Must
  #   be true for the reminder to fire.
  #   breakReminder = "";  # [object]
  #
  #   When no background service is running: 'transient' spawns one for this
  #   login session; 'ask' offers to install it persistently
  #   daemonColdStart = "transient";  # transient | ask
  #
  #   @internal When true, Claude keeps working until the PR is ready for you to
  #   merge, a cron/Monitor is armed to resume later, or it hands you a self-
  #   contained next step.
  #   doneMeansMerged = true;  # [boolean]
  #
  #   Enable or disable the Workflows feature for this user. Unset = default by
  #   plan once the feature is available.
  #   enableWorkflows = true;  # [boolean]
  #
  #   Model-drafted feedback (the SendFeedback tool). "notify" (default) shows a
  #   one-line notice when a draft is queued; "quiet" shows only the footer
  #   counter; "off" disables the tool entirely so drafts are never queued.
  #   feedbackDrafts = "notify";  # notify | quiet | off
  #
  #   Require explicit approval before SendMessage can reach a peer session on
  #   another machine via Remote Control
  #   isolatePeerMachines = true;  # [boolean]
  #
  #   Precompute the compaction summary in the background before it is needed.
  #   Only applies when auto-compact is on.
  #   precomputeCompactionEnabled = true;  # [boolean]
  #
  #   When false, prompt suggestions are disabled. When absent or true, prompt
  #   suggestions are enabled.
  #   promptSuggestionEnabled = true;  # [boolean]
  #
  #   Shell command that outputs a Proxy-Authorization header value (EAP)
  #   proxyAuthHelper = "";  # [string]
  #
  #   Show a one-time nudge when you start or keep using the CLI inside your
  #   quiet-hours window (default false).
  #   quietHours = "";  # [object]
  #
  #   Stamp each message with its arrival time
  #   showMessageTimestamps = true;  # [boolean]
  #
  #   @internal Whether the user has accepted the multi-agent workflow usage
  #   warning. Until set, auto permission mode prompts before running a
  #   workflow.
  #   skipWorkflowUsageWarning = true;  # [boolean]
  #
  #   Custom per-subagent status line shown in the agent panel; receives row
  #   context as JSON on stdin
  #   subagentStatusLine = "";  # [object]
  #
  #   Whether /rename updates the terminal tab title (defaults to true). Set to
  #   false to keep auto-generated topic titles.
  #   terminalTitleFromRename = true;  # [boolean]
  #
  #   Enable the todo / task tracking panel
  #   todoFeatureEnabled = true;  # [boolean]
  #
  #   @internal Emit a <total_tokens>N tokens left</total_tokens> block in the
  #   system prompt, after each tool result, and (when
  #   totalTokensReminderAfterUserTurn is on) after each regular user prompt.
  #   'infinite' uses the literal value Infinite, 'fixed' uses 5000000,
  #   'countdown' uses the live remaining context-window tokens, 'padded-
  #   countdown' counts down from totalTokensReminderBudget (re-anchoring to the
  #   full budget on each regular user prompt when
  #   totalTokensReminderAfterUserTurn is on - task-budget semantics).
  #   Defaults to off. Env var CLAUDE_CODE_TOTAL_TOKENS_REMINDER overrides.
  #   totalTokensReminder = "off";  # off | infinite | fixed | countdown | padded-countdown
  #
  #   @internal When true, emit the totalTokensReminder block after each regular
  #   user prompt and (for 'padded-countdown') re-anchor the task budget to the
  #   full configured value at the start of each user turn. When false, the
  #   reminder appears only in the system prompt and after each tool-result
  #   batch, and 'padded-countdown' counts down over the whole session. Defaults
  #   to off. Env var CLAUDE_CODE_TOTAL_TOKENS_REMINDER_AFTER_USER_TURN
  #   overrides; server-controlled via GrowthBook tengu_lapis_anchor_user_turn.
  #   totalTokensReminderAfterUserTurn = true;  # [boolean]
  #
  #   @internal Starting budget (tokens) for totalTokensReminder 'padded-
  #   countdown' mode. Defaults to 15000000. Server-controlled via GrowthBook;
  #   env var CLAUDE_CODE_TOTAL_TOKENS_REMINDER_BUDGET overrides.
  #   totalTokensReminderBudget = 0;  # [number]
  #

  # === Documented settings.json keys not set above (2.1.222 schema) =========
  # Every remaining top-level key in the binary's settings schema. Descriptions
  # are the schema's own .describe() text, falling back to the published docs.
  # Activate a key by moving the line into claudeSettingsBase above; omitting
  # keeps the default.
  #   Advisor model for the server-side advisor tool.
  #   advisorModel = "";                                # [string]
  #
  #   Name of an agent (built-in or custom) to use for the main thread. Applies
  #   the agent's system prompt, tool restrictions, and model.
  #   agent = "";                                       # [string]
  #
  #   Allow Claude to push proactive mobile notifications
  #   agentPushNotifEnabled = true;                     # [boolean]
  #
  #   When true (and set in managed settings), claude.ai cloud MCP connectors
  #   load alongside managed-mcp.json instead of being suppressed by its
  #   exclusive-control lockdown. Default off preserves the lockdown. Read from
  #   managed settings only.
  #   allowAllClaudeAiMcps = true;                      # [boolean]
  #
  #   When true (and set in managed settings), only hooks from managed settings
  #   run. User, project, and local hooks are ignored.
  #   allowManagedHooksOnly = true;                     # [boolean]
  #
  #   When true (and set in managed settings), allowedMcpServers is only read
  #   from managed settings. deniedMcpServers still merges from all sources, so
  #   users can deny servers for themselves. Users can still add their own MCP
  #   servers, but only the admin-defined allowlist applies.
  #   allowManagedMcpServersOnly = true;                # [boolean]
  #
  #   When true (and set in managed settings), only permission rules
  #   (allow/deny/ask) from managed settings are respected. User, project,
  #   local, and CLI argument permission rules are ignored.
  #   allowManagedPermissionRulesOnly = true;           # [boolean]
  #
  #   Managed-org allowlist of channel plugins. When set, replaces the
  #   default Anthropic allowlist - admins decide which plugins may push
  #   inbound messages. Undefined falls back to the default. Requires
  #   channelsEnabled: true.
  #   allowedChannelPlugins = [ ];                      # [array]
  #
  #   Allowlist of URL patterns that HTTP hooks may target. Supports * as a
  #   wildcard (e.g. "https://hooks.example.com/*"). When set, HTTP hooks with
  #   non-matching URLs are blocked. If undefined, all URLs are allowed. If
  #   empty array, no HTTP hooks are allowed. Arrays merge across settings
  #   sources (same semantics as allowedMcpServers).
  #   allowedHttpHookUrls = [ ];                        # [array]
  #
  #   Enterprise allowlist of MCP servers that can be used. Applies to all
  #   scopes including enterprise servers from managed-mcp.json. If undefined,
  #   all servers are allowed. If empty array, no servers are allowed. Denylist
  #   takes precedence - if a server is on both lists, it is denied.
  #   allowedMcpServers = [ ];                          # [array]
  #
  #   Path to a script that outputs authentication values
  #   apiKeyHelper = "";                                # [string]
  #
  #   Idle time before Claude's questions auto-continue with any answers
  #   selected so far. Defaults to never - auto-continue only runs
  #   when explicitly set to 60s/5m/10m.
  #   askUserQuestionTimeout = "60s";                   # [60s | 5m | 10m | never]
  #
  #   Attribution text for git commits, including any trailers. Empty string
  #   hides attribution.
  #   attribution = { };                                # [object]
  #
  #   Automatically compact conversation when context fills
  #   autoCompactEnabled = true;                        # [boolean] ACTIVE in claudeJsonConfigBase
  #
  #   Auto-compact window size
  #   autoCompactWindow = 0;                            # [number]
  #
  #   Custom directory path for auto-memory storage. Supports ~/ prefix for home
  #   directory expansion. Ignored if set in projectSettings (checked-in
  #   .claude/settings.json) for security. When unset, defaults to
  #   ~/.claude/projects/<sanitized-cwd>/memory/.
  #   autoMemoryDirectory = "";                         # [string]
  #
  #   Enable auto-memory for this project. When false, Claude will not read from
  #   or write to the auto-memory directory.
  #   autoMemoryEnabled = true;                         # [boolean]
  #
  #   Auto-scroll the conversation view to bottom (fullscreen mode only)
  #   autoScrollEnabled = true;                         # [boolean]
  #
  #   Release channel for auto-updates (latest or stable)
  #   autoUpdatesChannel = "latest";                    # [latest | stable | rc]
  #
  #   Allowlist of models that users can select. Accepts family aliases ("opus"
  #   allows any opus version), version prefixes ("opus-4-5" allows only that
  #   version), and full model IDs. If undefined, all models are available. If
  #   empty array, only the default model is available. Typically set in managed
  #   settings by enterprise administrators.
  #   availableModels = [ ];                            # [array]
  #
  #   @internal When false, the session recap (shown when you return after being
  #   away for 5+ minutes) is disabled. When absent or true, recap is enabled.
  #   Hidden from public SDK types until external launch.
  #   awaySummaryEnabled = true;                        # [boolean]
  #
  #   Path to a script that refreshes AWS authentication
  #   awsAuthRefresh = "";                              # [string]
  #
  #   Path to a script that exports AWS credentials
  #   awsCredentialExport = "";                         # [string]
  #
  #   Enterprise blocklist of marketplace sources. When set in managed settings,
  #   these exact sources are blocked from being added as marketplaces. The
  #   check happens BEFORE downloading, so blocked sources never touch the
  #   filesystem.
  #   blockedMarketplaces = [ ];                        # [array]
  #
  #   Managed-org opt-in for channel notifications (MCP servers with the
  #   claude/channel capability pushing inbound messages). claude.ai
  #   Teams/Enterprise: default off. Console: default on unless managed settings
  #   exist. Set true to allow; users then select servers via --channels.
  #   channelsEnabled = true;                           # [boolean]
  #
  #   CLAUDE.md-style instructions injected as organization-managed memory. Only
  #   honored from managed/policy settings.
  #   claudeMd = "";                                    # [string]
  #
  #   Glob patterns or absolute paths of CLAUDE.md files to exclude from
  #   loading. Patterns are matched against absolute file paths using picomatch.
  #   Only applies to User, Project, and Local memory types (Managed/policy
  #   files cannot be excluded). Examples: "/home/user/monorepo/CLAUDE.md",
  #   "**/code/CLAUDE.md", "**/some-dir/.claude/rules/**"
  #   claudeMdExcludes = [ ];                           # [array]
  #
  #   Company announcements to display at startup (one will be randomly selected
  #   if multiple are provided)
  #   companyAnnouncements = [ ];                       # [array]
  #
  #   Default shell for input-box ! commands. Defaults to 'bash' on all
  #   platforms (no Windows auto-flip).
  #   defaultShell = "bash";                            # [bash | powershell]
  #
  #   Enterprise denylist of MCP servers that are explicitly blocked. If a
  #   server is on the denylist, it will be blocked across all scopes including
  #   enterprise. Denylist takes precedence over allowlist - if a server is on
  #   both lists, it is denied.
  #   deniedMcpServers = [ ];                           # [array]    SET BY _settings.nix (programs.claude-code.extended.deniedMcpServers)
  #
  #   Disable agent view (`claude agents`, `--bg`, /background, the on-demand
  #   daemon). Typically set in managed settings. Equivalent to
  #   CLAUDE_CODE_DISABLE_AGENT_VIEW=1.
  #   disableAgentView = true;                          # [boolean]
  #
  #   Disable all hooks and statusLine execution
  #   disableAllHooks = true;                           # [boolean]
  #
  #   Disable the Artifact tool (also via CLAUDE_CODE_DISABLE_ARTIFACT).
  #   disableArtifact = true;                           # [boolean]
  #
  #   Disable auto mode
  #   disableAutoMode = "disable";                      # [disable]
  #
  #   Disable the skills and workflows that ship with Claude Code: bundled
  #   skills and workflows are removed entirely; built-in slash commands stay
  #   typable but are hidden from the model. Plugins, .claude/skills/, and
  #   .claude/commands/ are unaffected. Equivalent to
  #   CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1.
  #   disableBundledSkills = true;                      # [boolean]
  #
  #   When true in any settings source, claude.ai MCP cloud connectors are not
  #   auto-fetched or connected. Only gates auto-fetched connectors - a
  #   claudeai-proxy server passed explicitly (e.g. via --mcp-config or the
  #   SDK mcpServers option) still follows the normal MCP config trust flow.
  #   Any-source-true wins: a project can opt out, but a project-level false
  #   cannot override a user-level true.
  #   disableClaudeAiConnectors = true;                 # [boolean]
  #
  #   Disable Remote Control (claude.ai/code, `claude remote-control`,
  #   `--remote-control`/`--rc`, auto-start, and the in-session toggle).
  #   Typically set in managed settings.
  #   disableRemoteControl = true;                      # [boolean]
  #
  #   When true (and set in managed settings), rejects the --plugin-dir,
  #   --plugin-url, --agents, and non-sdk --mcp-config CLI flags at startup.
  #   Closes the CLI-flag bypass of strictKnownMarketplaces. Pair with
  #   allowedMcpServers for per-server MCP control; this setting does not gate
  #   other MCP entry points (SDK setMcpServers, claude mcp add, .mcp.json).
  #   Also blocks surfaces that spawn the CLI with these flags internally (see
  #   settings documentation). Only honored from managed settings; ignored in
  #   user/project/local settings.
  #   disableSideloadFlags = true;                      # [boolean]
  #
  #   Disable inline shell execution in skills and custom slash commands from
  #   user, project, or plugin sources. Commands are replaced with a placeholder
  #   instead of being run.
  #   disableSkillShellExecution = true;                # [boolean]
  #
  #   Disable the Workflows feature (also via CLAUDE_CODE_DISABLE_WORKFLOWS).
  #   disableWorkflows = true;                          # [boolean]
  #
  #   List of rejected MCP servers from .mcp.json
  #   disabledMcpjsonServers = [ ];                     # [array]
  #
  #   Key binding mode for the prompt input
  #   editorMode = "";                                  # [enum]    ACTIVE in claudeJsonConfigBase
  #
  #   When false, the :emoji: shortcode typeahead (the suggestion popup and the
  #   :name: inline replacement) is disabled. When absent or true, it is
  #   enabled.
  #   emojiCompletionEnabled = true;                    # [boolean]
  #
  #   Enable or disable the Artifact tool for this user. Unset defaults to
  #   enabled once the feature is available.
  #   enableArtifact = true;                            # [boolean]
  #
  #   List of approved MCP servers from .mcp.json
  #   enabledMcpjsonServers = [ ];                      # [array]
  #
  #   Enabled plugins using plugin-id@marketplace-id format. Example: {
  #   "formatter@anthropic-tools": true }. Also supports extended format with
  #   version constraints. Settings precedence is user < project < local < flag
  #   < policy, so to disable a plugin that project settings enable, set it to
  #   false in .claude/settings.local.json - setting false in
  #   ~/.claude/settings.json is overridden by the project.
  #   enabledPlugins = { };                             # [record]   SET BY _settings.nix (programs.claude-code.extended.extraPlugins / lspPlugins)
  #
  #   When true and availableModels is a non-empty array, the Default model
  #   selection is also constrained: if the default model for the user tier is
  #   not in availableModels, Default resolves to the first allowed
  #   availableModels entry instead. Has no effect when availableModels is unset
  #   or an empty array. Typically set in managed settings by enterprise
  #   administrators.
  #   enforceAvailableModels = true;                    # [boolean]
  #
  #   Additional marketplaces to make available for this repository. Typically
  #   used in repository .claude/settings.json to ensure team members have
  #   required plugin sources.
  #   extraKnownMarketplaces = { };                     # [record]
  #
  #   Fallback model(s) tried in order when the primary model is overloaded or
  #   unavailable. Each element accepts a model name or alias; "default" expands
  #   to the default model. CLI --fallback-model takes precedence.
  #   fallbackModel = [ ];                              # [array]
  #
  #   When true, fast mode is enabled. When absent or false, fast mode is off.
  #   fastMode = true;                                  # [boolean]
  #
  #   When true, fast mode does not persist across sessions. Each session starts
  #   with fast mode off.
  #   fastModePerSessionOptIn = true;                   # [boolean]
  #
  #   Probability (0-1) that the session quality survey appears when
  #   eligible. 0.05 is a reasonable starting point.
  #   feedbackSurveyRate = 0;                           # [number]
  #
  #   Custom file suggestion configuration for @ mentions
  #   fileSuggestion = { };                             # [object]
  #
  #   Extra clickable footer badges that appear when a regex matches turn output
  #   (tool results and assistant responses). Read from user, flag, and managed
  #   settings only; ignored in project .claude/settings.json and local
  #   .claude/settings.local.json. At most 5 badges render; the oldest is
  #   displaced by newer matches and /clear removes them. Use to surface IDs
  #   printed by project CLIs as session links.
  #   footerLinksRegexes = [ ];                         # [array]
  #
  #   @internal Cloud gateway URL to pre-fill and auto-connect to during login.
  #   Typically set in local managed settings alongside forceLoginMethod:
  #   "gateway" so users never type the URL. Hidden from public SDK types until
  #   Cloud gateway is documented.
  #   forceLoginGatewayUrl = "";                        # [string]
  #
  #   Force a specific login method: "claudeai" for Claude Pro/Max, "console"
  #   for Console billing, "gateway" for the Cloud gateway OIDC device flow
  #   forceLoginMethod = "claudeai";                    # [claudeai | console | gateway]
  #
  #   Organization UUID to require for OAuth login. Accepts a single UUID string
  #   or an array of UUIDs (any one is permitted). When set in managed settings,
  #   login fails if the authenticated account does not belong to a listed
  #   organization.
  #   forceLoginOrgUUID = "";                           # [union]
  #
  #   When set in managed settings, the CLI blocks startup until remote managed
  #   settings are freshly fetched, and exits if the fetch fails
  #   forceRemoteSettingsRefresh = true;                # [boolean]
  #
  #   Command to refresh GCP authentication (e.g., gcloud auth application-
  #   default login)
  #   gcpAuthRefresh = "";                              # [string]
  #
  #   Custom commands to run before/after tool executions
  #   hooks = "";                                       # [?]
  #
  #   Allowlist of environment variable names HTTP hooks may interpolate into
  #   headers. When set, each hook's effective allowedEnvVars is the
  #   intersection with this list. If undefined, no restriction is applied.
  #   Arrays merge across settings sources (same semantics as
  #   allowedMcpServers).
  #   httpHookAllowedEnvVars = [ ];                     # [array]
  #
  #   Include built-in commit and PR workflow instructions in Claude's system
  #   prompt (default: true)
  #   includeGitInstructions = true;                    # [boolean]
  #
  #   Push to mobile when a permission prompt or question is waiting
  #   inputNeededNotifEnabled = true;                   # [boolean]
  #
  #   Minimum version to stay on - prevents downgrades when switching to stable
  #   channel
  #   minimumVersion = "";                              # [string]
  #
  #   Override mapping from Anthropic model ID (e.g. "claude-opus-4-6") to
  #   provider-specific model ID (e.g. a Bedrock inference profile ARN).
  #   Typically set in managed settings by enterprise administrators.
  #   modelOverrides = { };                             # [record]
  #
  #   Path to a script that outputs OpenTelemetry headers
  #   otelHeadersHelper = "";                           # [string]
  #
  #   (Managed settings only) **Default**: `"first-wins"`. Controls whether
  #   managed settings supplied programmatically by an embedding host process,
  #   such as the Agent SDK or an IDE extension, apply when an admin-deployed
  #   managed tier is also present. `"first-wins"`: the parent-supplied settings
  #   are dropped and only the admin tier applies. `"merge"`: the parent-
  #   supplied settings apply under the admin tier through a restrictive-only
  #   filter. Only the highest-priority managed source's value of this key is
  #   read. Unless the `allowManaged*Only` locks are set, allow-direction
  #   entries such as permission allow rules and sandbox allowlists still apply;
  #   see Restrict parent settings. Has no effect when no admin tier is
  #   deployed, or when a `policyHelper` is configured: the helper's output
  #   replaces every other managed source and parent settings are never merged.
  #   Requires Claude Code v2.1.133 or later
  #   parentSettingsBehavior = "first-wins";            # [first-wins | merge]
  #
  #   Custom directory for plan files, relative to project root. If not set,
  #   defaults to ~/.claude/plans/
  #   plansDirectory = "";                              # [string]
  #
  #   User configuration values for MCP servers keyed by server name
  #   pluginConfigs = { };                              # [record]
  #
  #   Marketplace names whose plugins may surface as contextual install
  #   suggestions (relevance-based tips). No marketplace-declared suggestions
  #   surface without this allowlist; the built-in first-party frontend-design
  #   tip is unaffected. Only honored when set in managed settings (policy
  #   scope); the key is ignored in user, project, and local settings. A name
  #   only takes effect when the marketplace is registered on the machine AND
  #   its registered source is also declared in managed settings, either as the
  #   extraKnownMarketplaces entry for that name or as an entry of
  #   strictKnownMarketplaces. A marketplace registered from a different source
  #   under an allowlisted name is ignored. The official marketplace is exempt
  #   from the source requirement: allowlisting its name alone suffices, since
  #   that name can only register from the official Anthropic source.
  #   pluginSuggestionMarketplaces = [ ];               # [array]
  #
  #   Custom message to append to the plugin trust warning shown before
  #   installation. Only read from policy settings (managed-settings.json /
  #   MDM). Useful for enterprise administrators to add organization-specific
  #   context (e.g., "All plugins from our internal marketplace are vetted and
  #   approved.").
  #   pluginTrustMessage = "";                          # [string]
  #
  #   Executable that computes managed settings at startup. Honored only from
  #   admin-controlled policy sources.
  #   policyHelper = "";                                # [?]
  #
  #   URL template for PR links in the footer link badges and inline messages.
  #   The detected git PR is rendered as the first footer-link badge.
  #   Placeholders: {host} {owner} {repo} {number} {url}. Example:
  #   "https://reviews.example.com/{owner}/{repo}/pull/{number}"
  #   prUrlTemplate = "";                               # [string]
  #
  #   Preferred OS notification channel
  #   preferredNotifChannel = "";                       # [enum]    ACTIVE in claudeJsonConfigBase
  #
  #   Reduce or disable animations for accessibility (spinner shimmer, flash
  #   effects, etc.)
  #   prefersReducedMotion = true;                      # [boolean]
  #
  #   Corporate launcher argv prefix for the background-agent supervisor, the
  #   sessions and workers it hosts, and the other covered background processes
  #   listed in the Claude Code corporate-launcher documentation. Equivalent to
  #   the CLAUDE_CODE_PROCESS_WRAPPER environment variable, which takes
  #   precedence when set. Honored from managed settings, a --settings/SDK-
  #   supplied settings file, and user settings, in that precedence order;
  #   project and local settings are ignored.
  #   processWrapper = "";                              # [string]
  #
  #   Default environment ID to use for cloud sessions
  #   remote = { };                                     # [object]
  #
  #   Start Remote Control bridge automatically each session
  #   remoteControlAtStartup = true;                    # [boolean]
  #
  #   Maximum Claude Code version allowed to start. If the running version is
  #   newer, Claude Code exits at startup with instructions to install an
  #   approved version. Only enforced from managed (policy) settings.
  #   requiredMaximumVersion = "";                      # [string]
  #
  #   Minimum Claude Code version required to start. If the running version is
  #   older, Claude Code exits at startup with instructions to update. Only
  #   enforced from managed (policy) settings.
  #   requiredMinimumVersion = "";                      # [string]
  #
  #   Whether Claude responds after an input-box ! bash command runs. Set to
  #   false to add the command output to context without a response. Default:
  #   true.
  #   respondToBashCommands = true;                     # [boolean]
  #
  #   `sandbox` still applies. Applies in v2.1.191 and later; before v2.1.221,
  #   every invalid entry was stripped. |
  #   sandbox = "";                                     # [?]
  #
  #   When true, the plan-approval dialog offers a "clear context" option.
  #   Defaults to false.
  #   showClearContextOnPlanAccept = true;              # [boolean]
  #
  #   Request API-side thinking summaries and show them in the conversation and
  #   in the transcript view (ctrl+o). Set explicitly to override the default
  #   for your install.
  #   showThinkingSummaries = true;                     # [boolean]
  #
  #   Show "Cooked for Nm Ns" after each assistant turn
  #   showTurnDuration = true;                          # [boolean]
  #
  #   Fraction of the context window (in characters) reserved for the skill
  #   listing sent to Claude (default: 0.01 = 1%). When the listing exceeds
  #   this, descriptions are shortened to fit. Raise to opt in to higher per-
  #   turn context cost.
  #   skillListingBudgetFraction = 0;                   # [number]
  #
  #   Per-skill description character cap in the skill listing sent to Claude
  #   (default: 1536). Descriptions longer than this are truncated. Raise to opt
  #   in to higher per-turn context cost.
  #   skillListingMaxDescChars = 0;                     # [number]
  #
  #   Per-skill listing overrides keyed by skill name. "name-only" lists the
  #   skill without its description; "user-invocable-only" hides it from the
  #   model but keeps /name; "off" hides it from both. Absent = on.
  #   skillOverrides = { };                             # [record]
  #
  #   Whether the user has accepted the bypass permissions mode dialog
  #   skipDangerousModePermissionPrompt = true;         # [boolean]
  #
  #   Skip the WebFetch blocklist check for enterprise environments with
  #   restrictive security policies
  #   skipWebFetchPreflight = true;                     # [boolean]
  #
  #   Override spinner tips. tips: array of tip strings. excludeDefault: if
  #   true, only show custom tips (default: false).
  #   spinnerTipsOverride = { };                        # [object]
  #
  #   Customize spinner verbs. mode: "append" adds verbs to defaults, "replace"
  #   uses only your verbs.
  #   spinnerVerbs = { };                               # [object]
  #
  #   Unique identifier for this SSH config. Used to match configs across
  #   settings sources.
  #   sshConfigs = [ ];                                 # [array]
  #
  #   Re-run the status line command every N seconds in addition to event-driven
  #   updates
  #   statusLine = { };                                 # [object]
  #
  #   Enterprise strict list of allowed marketplace sources. When set in managed
  #   settings, ONLY these exact sources can be added as marketplaces. The check
  #   happens BEFORE downloading, so blocked sources never touch the filesystem.
  #   Note: this is a policy gate only - it does NOT register
  #   marketplaces. To pre-register allowed marketplaces for users, also set
  #   extraKnownMarketplaces.
  #   strictKnownMarketplaces = [ ];                    # [array]
  #
  #   (Managed settings only) Block skills, agents, hooks, and MCP servers from
  #   user and project sources, so they can only come from plugins or managed
  #   settings. `true` locks all four surfaces; an array locks only the named
  #   ones. See `strictPluginOnlyCustomization`
  #   strictPluginOnlyCustomization = "";               # [preprocess]
  #
  #   When safeguards flag a message, automatically switch to a different model
  #   to keep chatting. When off, your session will pause instead.
  #   switchModelsOnFlag = true;                        # [boolean]
  #
  #   Whether to disable syntax highlighting in diffs
  #   syntaxHighlightingDisabled = true;                # [boolean]
  #
  #   How spawned teammates execute (tmux, iterm2, in-process, auto)
  #   teammateMode = "";                                # [enum]
  #
  #   Color theme for the UI
  #   theme = "";                                       # [union]   ACTIVE in claudeJsonConfigBase
  #
  #   Terminal UI renderer. "fullscreen" uses the flicker-free alt-screen
  #   renderer with virtualized scrollback (equivalent to
  #   CLAUDE_CODE_NO_FLICKER=1). "default" uses the classic main-screen
  #   renderer.
  #   tui = "default";                                  # [default | fullscreen]
  #
  #   Enable ultracode for the session: xhigh effort plus standing dynamic-
  #   workflow orchestration. Session-scoped - typically provided via
  #   --settings or the apply_flag_settings control request; interactive
  #   toggles never persist it. Requires workflows to be enabled and an xhigh-
  #   capable model.
  #   ultracode = true;                                 # [boolean]
  #
  #   Show full tool output instead of truncated summaries
  #   verbose = true;                                   # [boolean] ACTIVE in claudeJsonConfigBase
  #
  #   Default transcript view mode on startup
  #   viewMode = "default";                             # [default | verbose | focus]
  #
  #   Vim INSERT-mode key-sequence remaps, e.g. {"jj": "<Esc>"}. Each key is
  #   exactly two printable characters typed in sequence; "<Esc>" (return to
  #   NORMAL mode) is the only supported target. Applies when editorMode is
  #   "vim".
  #   vimInsertModeRemaps = { };                        # [record]
  #
  #   'hold' (default): hold to talk. 'tap': tap to start, tap to stop+submit.
  #   voice = { };                                      # [object]
  #
  #   Ramp mouse-wheel scroll speed during fast scrolls (fullscreen mode only)
  #   wheelScrollAccelerationEnabled = true;            # [boolean]
  #
  #   Enable the "ultracode" keyword trigger: including the keyword in a prompt
  #   opts that turn into the Workflow tool. Set to false to disable the
  #   trigger. Default: true.
  #   workflowKeywordTriggerEnabled = true;             # [boolean]
  #
  #   Advisory size guideline for the dynamic workflows Claude writes: "small"
  #   aims for fewer than 5 agents, "medium" (the default) fewer than 15,
  #   "large" fewer than 50, and "unrestricted" sends no guideline. A value here
  #   - including from managed settings - takes precedence over the
  #   "Dynamic workflow size" choice in /config, and that /config row is hidden
  #   while a settings file provides the key. This is a guideline, not an
  #   enforced limit.
  #   workflowSizeGuideline = "unrestricted";           # [unrestricted | small | medium | large]
  #
  #   Directories to symlink from main repository to worktrees to avoid disk
  #   bloat. Must be explicitly configured - no directories are symlinked by
  #   default. Common examples: "node_modules", ".cache", ".bin"
  #   worktree = { };                                   # [object]
  #
  #   When set to true in either admin-only Windows source - the HKLM
  #   SOFTWARE/Policies/ClaudeCode registry key or C:/Program
  #   Files/ClaudeCode/managed-settings.json - WSL reads managed settings
  #   from the full Windows policy chain (HKLM, C:/Program Files/ClaudeCode via
  #   DrvFs, HKCU) in addition to /etc/claude-code. Windows sources take
  #   priority. The flag is also required in HKCU itself for HKCU policy to
  #   apply on WSL (double opt-in: admin enables the chain, user confirms HKCU).
  #   On native Windows the flag has no effect.
  #   wslInheritsWindowsSettings = true;                # [boolean]
  #

  # ~/.claude/keybindings.json. Claude only reads this file, so Home Manager can
  # own it outright instead of jq-merging like settings.json.
  #
  # chat:thinkingToggle turns thinking off for the session on one keypress, and
  # a disabled toggle makes the API reject effort `max`
  # (400 output_config.effort 'max' is not supported when thinking is disabled).
  # Upstream binds it to `meta+t`; Linux canonicalizes meta to alt, so `alt+t`
  # is the form that matches and clears the default. /config keeps a deliberate
  # path to the same setting.
  claudeKeybindingsBase = {
    "$schema" = "https://www.schemastore.org/claude-code-keybindings.json";
    "$docs" = "https://code.claude.com/docs/en/keybindings";
    bindings = [
      {
        context = "Chat";
        bindings."alt+t" = null;
      }
    ];
  };
}
