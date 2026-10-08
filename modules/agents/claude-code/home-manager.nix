/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Notes:
    * MCP servers configured via flake.lib.agents.mcp (modules/agents/mcp.nix)
    * Agent skills configured via flake.lib.agents.skills (modules/agents/skills.nix)
    * User-level instructions generated via flake.lib.agents.systemPrompt
      (modules/agents/system-prompt.nix)
    * Optional Context7 API key can be provisioned via SOPS at `sops.secrets."context7/api-key"`
    * Plugins, LSP plugins included, are enabledPlugins in _plugins.nix; an
      enabled *-lsp entry also installs its language server
      (modules/apps/claude-code.nix). skillOverrides sits in the same file.
    * Blocked MCP servers, mainly the claude.ai account connectors that local
      config cannot otherwise remove, are deniedMcpServers in _permissions.nix.
    * `enabledPlugins` keys end with `@<marketplace>`. The marketplace must be
      registered first: declaratively via extraKnownMarketplaces in
      _plugins.nix (as chrome-devtools-plugins is), or out of band in
      ~/.claude/plugins/known_marketplaces.json (as claude-plugins-official
      is, installed once with
      `claude-plugins install anthropics/claude-plugins-official`). `builtin`
      needs no registration; entries naming an unregistered marketplace are
      silently ignored.
    * Data files in modules/agents/claude-code/, one per concern:
        _settings.nix          settings.json keys the next two files do not hold
        _plugins.nix           plugins, marketplaces, and skill settings
        _permissions.nix       permissions and MCP server policy
        _env.nix               environment variables
        _claude-json.nix       ~/.claude.json preferences
        _keybindings.nix       ~/.claude/keybindings.json
      Plumbing: _activation.nix (jq merge and optional bun install) and
      _launcher.nix (launcher environment and binary selection).
*/

_: {
  flake.homeManagerModules.apps."claude-code" =
    {
      config,
      osConfig,
      lib,
      pkgs,
      agents,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "claude-code" "extended" "enable" ] false osConfig;
      claudePkg = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "package"
      ] pkgs.claude-code osConfig;
      installMethods = lib.attrByPath [ "programs" "claude-code" "extended" "installMethods" ] {
        nix.enable = false;
        bun.enable = false;
      } osConfig;

      claudeEnv = import ./_env.nix;
      registryClaudeSkills = lib.filterAttrs (_name: skill: skill ? claude) agents.skills.list;

      # MCP servers via compiled agents.mcp client profile
      mcpServers = agents.mcp.clients.claude.servers pkgs;

      # Merges parts that must not declare the same top-level key.
      mergeParts =
        parts:
        let
          names = lib.concatMap lib.attrNames parts;
          duplicates = lib.unique (lib.filter (name: lib.count (n: n == name) names > 1) names);
        in
        assert lib.assertMsg (
          duplicates == [ ]
        ) "claude-code: ${lib.concatStringsSep ", " duplicates} declared by more than one settings part";
        lib.foldl' (acc: part: acc // part) { } parts;

      settingsJson = mergeParts [
        (import ./_settings.nix)
        (import ./_plugins.nix)
        (import ./_permissions.nix)
        { env = builtins.removeAttrs claudeEnv.vars claudeEnv.launchOnly; }
      ];
      claudeJson = mergeParts [
        (import ./_claude-json.nix)
        { inherit mcpServers; }
      ];
      claudeSettingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON settingsJson);
      claudeJsonConfigFile = pkgs.writeText "claude-json-config.json" (builtins.toJSON claudeJson);

      # The top-level keys this switch writes; the next switch deletes any it
      # no longer declares.
      stateFile = pkgs.writeText "claude-nix-managed.json" (
        builtins.toJSON {
          version = 1;
          settings = lib.attrNames settingsJson;
          claudeJson = lib.attrNames (builtins.removeAttrs claudeJson [ "mcpServers" ]);
          mcpServers = lib.attrNames mcpServers;
        }
      );

      bunInstallDir = "${config.xdg.dataHome}/bun";
      configuredExternalBinary = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "externalBinary"
      ] null osConfig;
      externalBinary =
        if configuredExternalBinary == null then
          "${bunInstallDir}/bin/claude"
        else
          configuredExternalBinary;

      activationResult = import ./_activation.nix {
        inherit
          lib
          pkgs
          osConfig
          config
          stateFile
          claudeSettingsFile
          claudeJsonConfigFile
          ;
      };
      inherit (activationResult) activation;

      claudeRuntime = import ./_launcher.nix {
        inherit
          lib
          pkgs
          claudePkg
          bunInstallDir
          externalBinary
          installMethods
          ;
      };

      claudeInstructions = agents.systemPrompt.render {
        vars.questionTool = "AskUserQuestion";
      };

      # Install every compiled skill that ships a Claude profile at
      # ~/.claude/skills/<name>/SKILL.md, keyed off the shared registry so new
      # skills need no per-client wiring here.
      claudeSkillFiles = lib.mapAttrs' (
        name: skill: lib.nameValuePair ".claude/skills/${name}/SKILL.md" { text = skill.claude; }
      ) registryClaudeSkills;
    in
    {
      config = lib.mkIf nixosEnabled {
        assertions = [
          {
            assertion = !(claudeEnv.vars ? CLAUDE_CODE_SHELL);
            message = "modules/agents/claude-code/_env.nix sets CLAUDE_CODE_SHELL, which the launcher points at the controlled bash; a settings.json value is applied in-process and would bypass the rm shim.";
          }
        ];

        home = {
          file = {
            ".claude/CLAUDE.md".text = claudeInstructions;

            ".claude/keybindings.json".text = builtins.toJSON (import ./_keybindings.nix);

            ".local/bin/claude" = {
              source = lib.getExe claudeRuntime.claudeWrapped;
              executable = true;
            };

            # Same launcher with the telemetry opt-out lifted, which is what
            # `claude rc` needs; see launchOnly in _env.nix.
            ".local/bin/claude-rc" = {
              source = lib.getExe claudeRuntime.claudeRcWrapped;
              executable = true;
            };
          }
          // claudeSkillFiles;

          inherit activation;

          # bun puts its global bin on home.sessionPath; mkBefore orders
          # ~/.local/bin ahead of it so the wrapper shadows a bun-global claude.
          sessionPath = lib.mkBefore [ "${config.home.homeDirectory}/.local/bin" ];

          # launchOnly names stay included: claude-rc unsets them before exec, so
          # this keeps the opt-out live for a bun binary run outside the launcher.
          sessionVariables = claudeEnv.vars;
        };
      };
    };
}
