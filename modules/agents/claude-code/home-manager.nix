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
    * LSP plugin enablement and binary installation are governed by
      programs.claude-code.extended.lspPlugins in modules/apps/claude-code.nix.
    * Additional non-LSP plugins are governed by
      programs.claude-code.extended.extraPlugins in modules/apps/claude-code.nix.
    * Blocked MCP servers, mainly the claude.ai account connectors that local
      config cannot otherwise remove, are governed by
      programs.claude-code.extended.deniedMcpServers in modules/apps/claude-code.nix.
    * Per-skill availability for standalone Claude Code skills is governed by
      programs.claude-code.extended.skillOverrides in modules/apps/claude-code.nix.
    * `enabledPlugins` keys end with `@<marketplace>`. The marketplace must be
      registered first: declaratively via _default-settings.nix's
      claudeSettingsBase.extraKnownMarketplaces (as chrome-devtools-plugins
      is), or out of band in ~/.claude/plugins/known_marketplaces.json (as
      claude-plugins-official is, installed once with
      `claude-plugins install anthropics/claude-plugins-official`). `builtin`
      needs no registration; entries naming an unregistered marketplace are
      silently ignored.
    * Config is split across private helpers in modules/agents/claude-code/:
        _default-settings.nix  static defaults for settings.json, .claude.json,
                               and keybindings.json
        _activation.nix        activation snippets (jq merge + optional bun install)
        _launcher.nix          shell launcher environment and binary selection
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

      defaults = import ./_default-settings.nix;
      claudeEnv = import ./_env.nix;
      registryClaudeSkills = lib.filterAttrs (_name: skill: skill ? claude) agents.skills.list;
      managedClaudeSkillNames = lib.attrNames registryClaudeSkills;
      configuredSkillOverrides = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "skillOverrides"
      ] { } osConfig;
      unknownSkillOverrides = lib.attrNames (
        builtins.removeAttrs configuredSkillOverrides managedClaudeSkillNames
      );
      skillOverrides = configuredSkillOverrides;

      # MCP servers via compiled agents.mcp client profile
      mcpServers = agents.mcp.clients.claude.servers pkgs;

      # Display names blocked via settings.json deniedMcpServers, mainly the
      # claude.ai account connectors that local config cannot otherwise remove.
      deniedMcpServers =
        lib.attrByPath
          [
            "programs"
            "claude-code"
            "extended"
            "deniedMcpServers"
          ]
          [ ]
          osConfig;

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

      lspPlugins = lib.attrByPath [ "programs" "claude-code" "extended" "lspPlugins" ] { } osConfig;
      extraPlugins = lib.attrByPath [ "programs" "claude-code" "extended" "extraPlugins" ] { } osConfig;
      enabledPlugins =
        lib.mapAttrs' (key: lib.nameValuePair "${key}@claude-plugins-official") lspPlugins // extraPlugins;

      settingsJson = mergeParts [
        defaults.claudeSettingsBase
        {
          inherit enabledPlugins skillOverrides;
          deniedMcpServers = map (serverName: { inherit serverName; }) deniedMcpServers;
        }
      ];
      claudeJson = mergeParts [
        defaults.claudeJsonConfigBase
        { inherit mcpServers; }
      ];
      claudeSettingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON settingsJson);
      claudeJsonConfigFile = pkgs.writeText "claude-json-config.json" (builtins.toJSON claudeJson);

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

      # settingsMergeJq, settingsMergeJqArgs, and claudeJsonMergeJq are all
      # unused here; checks."claude-code/settings-merge" and
      # checks."claude-code/claude-json-merge" in checks.nix import _activation.nix
      # separately to exercise them against fixtures.
      activationResult = import ./_activation.nix {
        inherit
          lib
          pkgs
          osConfig
          config
          managedClaudeSkillNames
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
            assertion = unknownSkillOverrides == [ ];
            message = "programs.claude-code.extended.skillOverrides has unknown skill names: ${lib.concatStringsSep ", " unknownSkillOverrides}. Managed Claude Code skills: ${lib.concatStringsSep ", " managedClaudeSkillNames}.";
          }
          {
            assertion = !(claudeEnv.vars ? CLAUDE_CODE_SHELL);
            message = "modules/agents/claude-code/_env.nix sets CLAUDE_CODE_SHELL, which the launcher points at the controlled bash; a settings.json value is applied in-process and would bypass the rm shim.";
          }
        ];

        home = {
          file = {
            ".claude/CLAUDE.md".text = claudeInstructions;

            ".claude/keybindings.json".text = builtins.toJSON defaults.claudeKeybindingsBase;

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
