/*
  Package: codex
  Description: Lightweight coding agent that runs in your terminal.
  Homepage: https://github.com/openai/codex
  Documentation: https://github.com/openai/codex/tree/main/docs
  Repository: https://github.com/openai/codex

  Summary:
    * Provides an interactive TUI that orchestrates code edits, tests, and tooling via OpenAI Codex with sandboxed execution and approvals.
    * Supports non-interactive automation, session resume, Model Context Protocol servers, and configurable instructions through `config.toml` and `AGENTS.md`.

  Options:
    --cd <path>: Set the working directory Codex should operate in before executing tasks.
    --profile <name>: Select a saved profile configuration for the current session.
    --approval-policy <mode>: Override the approval policy (for example `never`, `always`, `manual`).
    --sandbox-mode <mode>: Adjust the sandbox level for commands launched by Codex.

  Notes:
    * MCP servers configured via flake.lib.agents.mcp (modules/agents/mcp.nix)
    * Skills configured via flake.lib.agents.skills (modules/agents/skills.nix)
    * Config is split across private helpers in modules/agents/codex/
    * Package installation handled by NixOS module (modules/apps/codex.nix) via llm-agents.nix.
    * Config is split into three TOML files merged at launch by the codex wrapper:
      - config.base.toml: nix-managed base settings (read-only)
      - projects.nix.toml: nix-managed trusted project paths (read-only)
      - trusted-projects.toml: user-managed trusted project paths (mutable)
    * To trust a new project, add it to ~/.config/codex/trusted-projects.toml:
        [projects."/path/to/project"]
        trust_level = "trusted"
*/

_: {
  flake.homeManagerModules.apps.codex =
    {
      osConfig,
      pkgs,
      config,
      lib,
      agents,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "codex" "extended" "enable" ] false osConfig;
      codexPkg = lib.attrByPath [ "programs" "codex" "extended" "package" ] pkgs.codex osConfig;
      homeDir = config.home.homeDirectory;
      configDir = "${config.xdg.configHome}/codex";
      agentsDir = "${config.xdg.configHome}/agents";

      execPolicy = import ./_exec-policy.nix {
        inherit lib pkgs;
      };

      codexSettings = import ./_settings.nix {
        inherit
          agents
          homeDir
          lib
          pkgs
          ;
        inherit (execPolicy) codexZshWrapper;
      };

      codexRuntime = import ./_wrapper.nix {
        inherit
          configDir
          codexPkg
          lib
          pkgs
          ;
        inherit (codexSettings)
          baseSettings
          nixProjectSettings
          ;
      };

      commitSkillDir = (agents.skills.commit.codex pkgs).dir;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.codex = {
          enable = true;
          package = null; # Installed via wrapper below
          settings = lib.mkForce { }; # Config handled by merge workflow
          custom-instructions = "";
        };

        home = {
          packages = [ codexRuntime.codexWrapped ];

          # Seed user-managed trusted projects file on first activation
          activation = {
            codexTrustedProjectsSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              userProjects="${configDir}/trusted-projects.toml"
              if [ ! -f "$userProjects" ]; then
                cat > "$userProjects" << 'EOF'
              # User-managed trusted project paths for Codex.
              # Merged with nix-managed config on each codex launch.
              # Changes take effect immediately - no rebuild required.
              #
              # Format:
              # [projects."/path/to/project"]
              # trust_level = "trusted"
              EOF
              fi
            '';

            codexExecPolicySeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              rulesDir="${configDir}/rules"
              defaultRules="$rulesDir/default.rules"

              run mkdir -p "$rulesDir"
              if [ ! -f "$defaultRules" ]; then
                cat > "$defaultRules" << 'EOF'
              # User-managed execpolicy amendments for Codex.
              # Runtime-approved command prefixes are appended here.
              EOF
              fi
            '';

            # Codex discovers user skills in ~/.agents/skills
            codexAgentsHomeLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              agentsHome="${homeDir}/.agents"
              legacyBackupBase="${homeDir}/.agents.pre-xdg-migration"
              maxLegacyBackups=8
              maxBackupAttempts=32

              # If ~/.agents is a real directory, migrate its contents into
              # ~/.config/agents and archive the legacy directory before linking.
              if [ -d "$agentsHome" ] && [ ! -L "$agentsHome" ]; then
                run mkdir -p "${agentsDir}"
                run cp -a "$agentsHome/." "${agentsDir}/"

                existingLegacyBackups=0
                for candidate in "$legacyBackupBase" "$legacyBackupBase"-*; do
                  if [ -e "$candidate" ]; then
                    existingLegacyBackups=$((existingLegacyBackups + 1))
                  fi
                done
                if [ "$existingLegacyBackups" -ge "$maxLegacyBackups" ]; then
                  echo "codex-activation: ERROR: refusing to create more than $maxLegacyBackups legacy backups matching $legacyBackupBase*" >&2
                  exit 1
                fi

                backupPath="$legacyBackupBase"
                if [ -e "$backupPath" ]; then
                  i=0
                  while [ "$i" -lt "$maxBackupAttempts" ]; do
                    candidate="''${legacyBackupBase}-$$-$i"
                    if [ ! -e "$candidate" ]; then
                      backupPath="$candidate"
                      break
                    fi
                    i=$((i + 1))
                  done
                  if [ "$i" -ge "$maxBackupAttempts" ]; then
                    echo "codex-activation: ERROR: exhausted $maxBackupAttempts backup name attempts for $legacyBackupBase" >&2
                    exit 1
                  fi
                fi
                run mv "$agentsHome" "$backupPath"
              fi

              run mkdir -p "${agentsDir}/skills"
              run ln -sfnT "${agentsDir}" "$agentsHome"
            '';
          };

          sessionVariables = {
            CODEX_HOME = lib.mkDefault configDir;
            CODEX_DISABLE_UPDATE_CHECK = "1";
          };
        };

        xdg.configFile = {
          # Base config (nix-managed, read-only symlink to store)
          "codex/config.base.toml".source = codexRuntime.baseConfigFile;

          # Nix-managed trusted projects (read-only symlink to store)
          "codex/projects.nix.toml".source = codexRuntime.nixProjectsFile;

          # Nix-managed execpolicy rules (read-only symlink to store)
          "codex/rules/20-managed.rules".source = execPolicy.execPolicyManagedRulesFile;

          # User-level Codex instructions under XDG config home
          "codex/AGENTS.md".text = ''
            If you are unsure how to do something, use `gh_grep` to search code examples from GitHub.
            Always set `timeout_ms` explicitly for shell commands because sandboxed commands can hit a short default timeout.
            Use `60000` ms when no command-specific timeout is obvious, and increase it further for builds, installs, tests, or other long-running commands.
          '';

          # Commit skill (user-scoped, discovered by SkillsManager at ~/.agents/skills/)
          "agents/skills/commit".source = commitSkillDir;
        };
      };
    };
}
