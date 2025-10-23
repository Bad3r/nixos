/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Notes:
    * Assumes Context7 API key is provisioned via SOPS at `sops.secrets."context7/api-key"`.
*/

{
  flake.homeManagerModules.apps."claude-code" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      defaultModel = "opus";

      mcp = import ../../lib/mcp-servers.nix {
        inherit lib pkgs config;
        defaultVariants = {
          deepwiki = "http";
        };
      };

      claudeMcpServers = mcp.select {
        sequential-thinking = true;
        time = true;
        cfdocs = true;
        cfbuilds = false;
        cfobservability = false;
        cfradar = false;
        cfcontainers = false;
        cfbrowser = true;
        cfgraphql = false;
        deepwiki = true;
        context7 = true;
      };

      defaultServers = claudeMcpServers;

      # Claude Code settings.json configuration
      claudeSettings = {
        cleanupPeriodDays = 30;
        env = {
          DISABLE_AUTOUPDATER = "1";
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
          DISABLE_TELEMETRY = "1";
          CLAUDE_CODE_ENABLE_TELEMETRY = "0";
          DISABLE_ERROR_REPORTING = "1";
          CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
          BASH_DEFAULT_TIMEOUT_MS = "240000";
          BASH_MAX_TIMEOUT_MS = "4800000";
          MAX_THINKING_TOKENS = "32768";
        };
        includeCoAuthoredBy = false;
        permissions = {
          allow = [
            "Read(~/.claude/CLAUDE.md)"
            "Read(../../.config/claude/CLAUDE.md)"
            "Read(../../.claude/CLAUDE.md)"
            "Read(../../../.claude/CLAUDE.md)"
            "WebFetch(domain:docs.anthropic.com)"
            "WebFetch(domain:*.github.com)"
            "Bash(find *)"
            "Bash(xargs *)"
            "Bash(sort *)"
            "Bash(uniq *)"
            "Bash(pytest *)"
            "Bash(grep *)"
            "Bash(head *)"
            "Bash(pkill *)"
            "Bash(tee *)"
            "Bash(bash *)"
            "Bash(ls *)"
            "Bash(biome *)"
            "Bash(curl *)"
            "Bash(diff *)"
            "Bash(patch *)"
            "Bash(touch *)"
            "Bash(cp *)"
            "Bash(pwd *)"
            "Bash(mkdir *)"
            "Bash(cut *)"
            "Bash(awk *)"
            "Bash(cat *)"
            "Bash(cd *)"
            "Bash(coverage *)"
            "Bash(echo *)"
            "Bash(fd *)"
            "Bash(git *)"
            "Bash(jq *)"
            "Bash(make *)"
            "Bash(npm run *)"
            "Bash(nvim *)"
            "Bash(python *)"
            "Bash(pyright *)"
            "Bash(rg *)"
            "Bash(ruff *)"
            "Bash(sed *)"
            "Bash(source *)"
            "Bash(tail *)"
            "Bash(time *)"
            "Bash(timeout *)"
            "Bash(uv *)"
            "Bash(wc *)"
            "Bash(zsh *)"
            "Read(**)"
            "Write(**)"
            "Edit(**)"
          ];
          deny = [ ];
          defaultMode = "plan";
        };
        statusLine = {
          type = "command";
          command = "input=$(cat); dir=$(echo \"$input\" | jq -r '.workspace.current_dir'); dir_display=\${dir/#$HOME/\\~}; git_branch=$(cd \"$dir\" 2>/dev/null && git -c core.fileMode=false branch --show-current 2>/dev/null); git_status=\"\"; if [ -n \"$git_branch\" ]; then cd \"$dir\" && git_modified=$(git -c core.fileMode=false status --porcelain 2>/dev/null | grep -c '^.[MD]'); git_untracked=$(git -c core.fileMode=false status --porcelain 2>/dev/null | grep -c '^??'); git_staged=$(git -c core.fileMode=false status --porcelain 2>/dev/null | grep -c '^[MADRC]'); [ \"$git_modified\" -gt 0 ] && git_status=\"\${git_status}!\"; [ \"$git_untracked\" -gt 0 ] && git_status=\"\${git_status}?\"; [ \"$git_staged\" -gt 0 ] && git_status=\"\${git_status}+\"; git_info=$(printf '\\033[35m on \\033[0m\\033[1;35m%s%s\\033[0m' \"$git_branch\" \"$git_status\"); else git_info=\"\"; fi; printf '\\033[36m%s\\033[0m%s' \"$dir_display\" \"$git_info\"";
        };
        model = defaultModel;
        alwaysThinkingEnabled = true;
        enableAllProjectMcpServers = true;
        mcpServers = defaultServers;
      };

    in
    {
      config = {
        programs.claude-code.enable = lib.mkDefault true;
        home.file.".claude/settings.json" = {
          text = builtins.toJSON claudeSettings;
          onChange = ''
            # Ensure Claude Code picks up the new settings
            echo "✢ Claude Code: settings updated"
          '';
        };

        home.sessionVariables = {
          ANTHROPIC_MODEL = defaultModel;
          DISABLE_AUTOUPDATER = "1";
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
          DISABLE_TELEMETRY = "1";
          CLAUDE_CODE_ENABLE_TELEMETRY = "0";
          DISABLE_ERROR_REPORTING = "1";
          DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
          CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
          CLAUDE_BASH_DEFAULT_TIMEOUT_MS = "240000";
          CLAUDE_BASH_MAX_TIMEOUT_MS = "4800000";
          BASH_MAX_OUTPUT_LENGTH = "1024";
          MAX_THINKING_TOKENS = "32768";
          CLAUDE_CODE_MAX_OUTPUT_TOKENS = "1";
          MAX_MCP_OUTPUT_TOKENS = "32000";
          CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "1";
          CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL = "1";
          DISABLE_BUG_COMMAND = "1";
          USE_BUILTIN_RIPGREP = "0";

        };
      };
    };
}
