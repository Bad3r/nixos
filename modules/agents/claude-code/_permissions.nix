# Permission and MCP server policy keys for ~/.claude/settings.json.
# Uncomment a key and set its value to enable it. Every key set here replaces
# Claude's copy on each switch; commenting it out again removes it.
#
# Rules evaluate deny -> ask -> allow; first match wins, so an ask/deny rule
# overrides a broader allow. `Edit(path)` covers every file-editing tool
# (Edit, Write, MultiEdit, NotebookEdit), hence `Edit(**)` and no `Write(**)`.
let
  # Canonical Bash prefix rule; the trailing ` *` keeps a word boundary, so
  # `Bash(git *)` matches `git`/`git status` but not `github`.
  bash = cmd: "Bash(${cmd} *)";

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

  # Destructive or history-rewriting commands that must ask first; ask is
  # evaluated before allow, so these override the broad `git *` allow even
  # under acceptEdits/auto/bypassPermissions. Mirrors the codex execpolicy
  # prompt rules (modules/agents/codex/_exec-policy.nix) so both agents gate
  # the same operations; `git checkout --` is the discard form codex's
  # prefix-only matcher cannot express.
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
    # These wrapping forms must ask, or every rule above is bypassable
    # through `bash -c '...'`.
    "bash scripts/prune-old-stashes.sh"
    "bash ./scripts/prune-old-stashes.sh"
    "bash -c"
    "bash -lc"
    "zsh -c"
    "zsh -lc"
  ];

  # coreutils rm bypasses the PATH shim that routes bare `rm` to trash-cli, so
  # deny the common absolute paths and keep deletions recoverable.
  bashDeny = [
    "/bin/rm"
    "/usr/bin/rm"
    "/run/current-system/sw/bin/rm"
  ];

  # Read(**)/Edit(**) cover the working tree. The parent-relative Read rules
  # reach the repo-root and global CLAUDE.md from nested worktrees, which the
  # cwd-anchored Read(**) does not.
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
  # Enterprise allowlist of MCP servers that can be used. Applies to all
  # scopes including enterprise servers from managed-mcp.json. If undefined,
  # all servers are allowed. If empty array, no servers are allowed. Denylist
  # takes precedence - if a server is on both lists, it is denied.
  # allowedMcpServers = [ ]; # [array]

  # Enterprise denylist of MCP servers that are explicitly blocked. If a server
  # is on the denylist, it will be blocked across all scopes including
  # enterprise. Denylist takes precedence over allowlist - if a server is on
  # both lists, it is denied.
  #
  # Blocks claude.ai account connectors that local config cannot otherwise
  # remove. serverName is the exact display name in /mcp, so a connector
  # renamed on claude.ai, or suffixed " (N)" after a collision, needs updating.
  deniedMcpServers = map (serverName: { inherit serverName; }) [
    "claude.ai Cloudflare Developer Platform"
    "claude.ai Gmail"
    "claude.ai Google Calendar"
    "claude.ai Google Drive"
    "claude.ai Indeed"
    "claude.ai JobDataLake"
    "claude.ai Jobs and Careers"
    "claude.ai Todoist"
  ];

  # Disable auto mode
  # disableAutoMode = "disable"; # [disable]

  # When true in any settings source, claude.ai MCP cloud connectors are not
  # auto-fetched or connected. Only gates auto-fetched connectors - a
  # claudeai-proxy server passed explicitly (e.g. via --mcp-config or the SDK
  # mcpServers option) still follows the normal MCP config trust flow.
  # Any-source-true wins: a project can opt out, but a project-level false
  # cannot override a user-level true.
  # disableClaudeAiConnectors = true; # [boolean]

  # Disable inline shell execution in skills and custom slash commands from
  # user, project, or plugin sources. Commands are replaced with a
  # placeholder instead of being run.
  # disableSkillShellExecution = true; # [boolean]

  # List of rejected MCP servers from .mcp.json
  # disabledMcpjsonServers = [ ]; # [array]

  # Whether to automatically approve all MCP servers in the project
  enableAllProjectMcpServers = false;

  # List of approved MCP servers from .mcp.json
  # enabledMcpjsonServers = [ ]; # [array]

  # Set allow, ask, and deny rules and the starting permission mode
  permissions = {
    allow = fileWebAllow ++ map bash bashAllow;
    ask = map bash bashAsk;
    deny = map bash bashDeny;
    defaultMode = "auto";
  };

  # Isolate Bash commands from your filesystem and network on macOS, Linux,
  # and WSL2 (https://code.claude.com/docs/en/sandboxing).
  # sandbox = { }; # [object]

  # Whether the user has accepted the bypass permissions mode dialog
  # skipDangerousModePermissionPrompt = true; # [boolean]

  # Skip the WebFetch blocklist check for enterprise environments with
  # restrictive security policies
  # skipWebFetchPreflight = true; # [boolean]

  # --- Undocumented (2.1.222 binary schema) ---

  # Require explicit approval before SendMessage can reach a peer session on
  # another machine via Remote Control
  # isolatePeerMachines = true; # [boolean]

  # --- Managed settings only: no effect in ~/.claude/settings.json ---

  # When true (and set in managed settings), claude.ai cloud MCP connectors
  # load alongside managed-mcp.json instead of being suppressed by its
  # exclusive-control lockdown. Default off preserves the lockdown. Read from
  # managed settings only.
  # allowAllClaudeAiMcps = true; # [boolean]

  # When true (and set in managed settings), only hooks from managed settings
  # run. User, project, and local hooks are ignored.
  # allowManagedHooksOnly = true; # [boolean]

  # When true (and set in managed settings), allowedMcpServers is only read
  # from managed settings. deniedMcpServers still merges from all sources, so
  # users can deny servers for themselves. Users can still add their own MCP
  # servers, but only the admin-defined allowlist applies.
  # allowManagedMcpServersOnly = true; # [boolean]

  # When true (and set in managed settings), only permission rules
  # (allow/deny/ask) from managed settings are respected. User, project,
  # local, and CLI argument permission rules are ignored.
  # allowManagedPermissionRulesOnly = true; # [boolean]
}
