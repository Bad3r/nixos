/*
  Upstream-shaped Claude Code defaults.

  Source of truth for default ~/.claude/settings.json keys, ~/.claude.json
  UI preferences, and ~/.claude/keybindings.json. Values that depend on runtime
  evaluation (enabledPlugins, mcpServers) are injected by _settings.nix; this
  attrset only carries the static portion shared across hosts.

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
in
assert
  deadAllow == [ ]
  || throw "modules/agents/claude-code/_default-settings.nix: ${builtins.concatStringsSep ", " deadAllow} are in both bashAllow and bashAsk; ask wins, so drop them from bashAllow rather than leaving the two lists disagreeing";
{
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
    # Persisted effort accepts low|medium|high|xhigh only. `max` is session-scoped
    # (/effort, --effort, CLAUDE_CODE_EFFORT_LEVEL) and rejected by the settings schema.
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
