/*
  Upstream-shaped Claude Code defaults.

  Source of truth for default ~/.claude/settings.json keys and ~/.claude.json
  UI preferences. Values that depend on runtime evaluation (enabledPlugins,
  mcpServers) are injected by _settings.nix; this attrset only carries the
  static portion shared across hosts.

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
    "time"
    "timeout"
    "touch"
    "uniq"
    "uv"
    "wc"
    "xargs"
    "zsh"
  ];

  # Destructive or history-rewriting commands that must ask first. Claude
  # evaluates ask before allow, so these override the broad `git *` allow even
  # under acceptEdits/auto/bypassPermissions. Mirrors the codex execpolicy
  # prompt rules (modules/agents/codex/_exec-policy.nix) so both agents gate the
  # same operations. `git checkout -- ` is the discard form codex's prefix-only
  # matcher cannot express; the positional wildcard leaves branch switches
  # (`git checkout main`) untouched.
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
in
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
    # model = defaultModel; # Model (leave unset for default)
    alwaysThinkingEnabled = true;
    enableAllProjectMcpServers = true;
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
    autocheckpointingEnabled = true; # Rewind code (checkpoints)
    autoConnectIde = false; # Auto-connect to IDE
    autoUpdates = false; # Auto-updates
    claudeInChromeDefaultEnabled = true; # Chrome enabled by default
    defaultToAgentsView = true; # Open agents view by default
    diffTool = "diff"; # Diff tool
    editorMode = "vim"; # Editor mode
    externalEditorContext = true; # Show last response in external editor
    preferredNotifChannel = "iterm2_with_bell"; # Notifications
    theme = "dark"; # Theme
    thinkingEnabled = true; # Thinking mode
    verbose = true; # Verbose output
  };
}
