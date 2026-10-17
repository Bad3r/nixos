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
    --profile <name>: Layer `$CODEX_HOME/<name>.config.toml` on top of the base user config for the session.
    --ask-for-approval <mode>: Override command approval policy.
    --sandbox <mode>: Override command sandbox policy.
    --strict-config: Reject unrecognized configuration fields.

  Notes:
    * MCP servers configured via flake.lib.agents.mcp (modules/agents/mcp.nix)
    * Skills configured via flake.lib.agents.skills (modules/agents/skills.nix)
    * User-level instructions generated via flake.lib.agents.systemPrompt
      (modules/agents/system-prompt.nix)
    * Private helpers: _default-settings.nix (settings catalog), _settings.nix
      (site policy and MCP composition), _features.nix (feature flags),
      _env.nix (process environment), _wrapper.nix (runtime config merge).
    * Installs the wrapper around programs.codex.extended.package (modules/apps/codex.nix), which comes from llm-agents.nix.
    * Config is split into three TOML files merged at launch by the codex wrapper:
      - config.base.toml: nix-managed base settings (read-only)
      - projects.nix.toml: nix-managed trusted project paths (read-only)
      - trusted-projects.toml: user-managed trusted project paths (mutable)
    * `codex -p local` layers local.config.toml, a copy generated from the Magnitude endpoint in
      programs.magnitude.extended.client (modules/apps/magnitude.nix).
    * Execpolicy is separate from config.toml and is loaded from the rules/ directory under CODEX_HOME.
      The nix-managed layer is written to codex/rules/20-managed.rules.
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
      codexEnv = import ./_env.nix;

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
      };

      codexRuntime = import ./_wrapper.nix {
        inherit
          configDir
          codexPkg
          homeDir
          lib
          pkgs
          ;
        inherit (execPolicy) codexBashWrapper;
        inherit (codexSettings)
          baseSettings
          nixProjectSettings
          ;
      };

      codexInstructions = agents.systemPrompt.render {
        vars.questionTool = "request_user_input";
      };

      # Install every compiled skill that ships a Codex profile under
      # ~/.config/agents/skills/<name> (discovered by Codex at ~/.agents/skills),
      # keyed off the shared registry so new skills need no per-client wiring.
      codexSkillDirs = lib.mapAttrs' (
        name: skill: lib.nameValuePair "agents/skills/${name}" { source = (skill.codex pkgs).dir; }
      ) (lib.filterAttrs (_name: skill: skill ? codex) agents.skills.list);

      magnitudeClient = lib.attrByPath [ "programs" "magnitude" "extended" "client" ] {
        endpoint = null;
      } osConfig;

      # Layered over config.toml by `codex -p local`. Codex has no metadata for
      # Magnitude model IDs and otherwise assumes a cloud-sized context window.
      codexLocalProfile = (pkgs.formats.toml { }).generate "codex-local.config.toml" {
        inherit (magnitudeClient) model;
        review_model = magnitudeClient.model;
        model_provider = "magnitude";
        model_context_window = magnitudeClient.contextWindow;
        # The flag gates startup extraction; generate_memories excludes local threads from it.
        features.memories = false;
        memories.generate_memories = false;
        model_providers.magnitude = {
          name = "Magnitude";
          base_url = "${magnitudeClient.endpoint}/inference/v1";
          wire_api = "responses";
        }
        // lib.optionalAttrs (magnitudeClient.apiKeyFile != null) {
          auth = {
            command = lib.getExe' pkgs.coreutils "cat";
            args = [ magnitudeClient.apiKeyFile ];
          };
        };
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.codex = {
          enable = true;
          package = null; # Installed via wrapper below
          settings = lib.mkForce { }; # Config handled by merge workflow
          context = "";
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
          }
          // lib.optionalAttrs (magnitudeClient.endpoint != null) {
            # A copy, not a store link: under `-p local` Codex saves config edits to the profile.
            codexLocalProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run install -D -m 0644 ${codexLocalProfile} "${configDir}/local.config.toml"
            '';
          };

          sessionVariables = codexEnv.vars // {
            CODEX_HOME = lib.mkDefault configDir;
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
          "codex/AGENTS.md".text = codexInstructions;
        }
        # Skills (user-scoped, discovered by SkillsManager at ~/.agents/skills/)
        // codexSkillDirs;
      };
    };
}
