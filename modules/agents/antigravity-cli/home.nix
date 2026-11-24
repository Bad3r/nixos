/*
  Package: antigravity-cli
  Description: Home Manager configuration for Google Antigravity CLI and Hub.
  Homepage: https://antigravity.google/
  Documentation: https://antigravity.google/docs
  Repository: nil

  Notes:
    * Shared customization root ~/.gemini/config/ serves both antigravity-cli (`agy`) and antigravity-hub (`antigravity`).
    * CLI-specific settings (~/.gemini/antigravity-cli/settings.json) are merged only when antigravity-cli is enabled.
    * Hub UI storage (~/.config/Antigravity/app_storage.json) disables background update checks when antigravity-hub is enabled.
    * Hub theme seeds, theme mode, and typeface follow Stylix when antigravity-hub is enabled.
    * MCP servers come from flake.lib.agents.mcp (modules/agents/mcp.nix).
    * Agent skills come from flake.lib.agents.skills (modules/agents/skills.nix).
    * Hooks come from flake.lib.agents.hooks (modules/agents/hooks.nix).
    * User instructions (~/.gemini/config/AGENTS.md) come from flake.lib.agents.systemPrompt (modules/agents/system-prompt.nix).
    * Marketplace plugin selections come from programs."antigravity-cli".extended.plugins (defaults in modules/agents/_plugins.nix).
*/
_: {
  flake.homeManagerModules.apps."antigravity-cli" =
    {
      config,
      osConfig,
      lib,
      pkgs,
      agents,
      ...
    }:
    let
      telemetry = import ./_telemetry.nix;
      cliEnabled = lib.attrByPath [ "programs" "antigravity-cli" "extended" "enable" ] false osConfig;
      hubEnabled = lib.attrByPath [ "programs" "antigravity-hub" "extended" "enable" ] false osConfig;
      anyEnabled = cliEnabled || hubEnabled;

      agyPkg =
        if cliEnabled then
          lib.attrByPath [ "programs" "antigravity-cli" "extended" "finalPackage" ] (lib.attrByPath [
            "programs"
            "antigravity-cli"
            "extended"
            "package"
          ] null osConfig) osConfig
        else
          null;

      sbxEnabled = agents.skills.sbx.enabledOn osConfig;
      mcpServers = agents.mcp.clients.antigravity.servers {
        inherit pkgs osConfig;
        sopsSecrets = config.sops.secrets or { };
      };
      hooks = agents.hooks.clients.antigravity pkgs;

      enabledPlugins = lib.attrByPath [
        "programs"
        "antigravity-cli"
        "extended"
        "plugins"
      ] { } osConfig;

      parsedPlugins = lib.mapAttrsToList (
        key: enabled:
        let
          parts = lib.splitString "@" key;
          name = builtins.elemAt parts 0;
          marketplace = builtins.elemAt parts 1;
        in
        assert lib.assertMsg (
          lib.length parts == 2 && name != "" && marketplace != ""
        ) "antigravity-cli: invalid plugin key '${key}'; expected name@marketplace";
        {
          inherit
            key
            name
            marketplace
            enabled
            ;
        }
      ) enabledPlugins;

      # Hub-only hosts have no `agy` binary to install marketplace plugins, so
      # only builtin plugin state applies unless the CLI is also enabled.
      activePlugins = lib.filter (p: cliEnabled || p.marketplace == "builtin") parsedPlugins;

      pluginDirNames = map (p: p.name) activePlugins;
      duplicatePluginDirs = lib.unique (
        lib.filter (name: lib.count (candidate: candidate == name) pluginDirNames > 1) pluginDirNames
      );

      pluginsByDir =
        assert lib.assertMsg (duplicatePluginDirs == [ ])
          "antigravity-cli: multiple plugins share directory name(s): ${lib.concatStringsSep ", " duplicatePluginDirs}";
        lib.listToAttrs (map (p: lib.nameValuePair p.name p.enabled) activePlugins);

      marketplacePlugins = map (p: {
        inherit (p) name marketplace;
        ref = p.key;
      }) (lib.filter (p: p.enabled && p.marketplace != "builtin") activePlugins);

      permissions = import ./_permissions.nix {
        homeDir = config.home.homeDirectory;
        inherit (agents) scratchDir;
        sbx = sbxEnabled;
        mcpAutoApproved = agents.mcp.clients.antigravity.autoApproved osConfig;
      };

      colors = config.lib.stylix.colors.withHashtag;
      light = config.stylix.polarity == "light";
      # The Hub's Default preset draws its palette from these seeds.
      hubTheme = lib.optionalAttrs hubEnabled {
        themeMode = if light then "THEME_MODE_LIGHT" else "THEME_MODE_DARK";
        ${if light then "customThemeSeedsLight" else "customThemeSeedsDark"} = {
          background = colors.base00;
          foregroundOverride = colors.base05;
          primary = (import ../../stylix/_vscode-dark-2026.nix)."statusBarItem.prominentBackground";
        };
      };
      # "system" renders with system-ui, the fontconfig sans-serif face, instead
      # of Google Sans from fonts.googleapis.com.
      hubStorage = telemetry.hubStorage // {
        "jetski.typeface" = "system";
      };

      cliSettingsJson = (import ./_settings.nix) // {
        inherit permissions;
      };

      mcpServersFile = pkgs.writeText "antigravity-mcp-servers.json" (builtins.toJSON mcpServers);
      hooksFile = pkgs.writeText "antigravity-hooks.json" (builtins.toJSON hooks);
      pluginsFile = pkgs.writeText "antigravity-plugins.json" (builtins.toJSON pluginsByDir);
      userSettingsFile = pkgs.writeText "antigravity-user-settings.json" (
        builtins.toJSON ({ globalPermissionGrants = permissions; } // hubTheme)
      );
      cliSettingsFile =
        if cliEnabled then
          pkgs.writeText "antigravity-cli-settings.json" (builtins.toJSON cliSettingsJson)
        else
          null;
      hubStorageFile =
        if hubEnabled then
          pkgs.writeText "antigravity-hub-storage.json" (builtins.toJSON hubStorage)
        else
          null;

      stateFile = pkgs.writeText "antigravity-nix-managed.json" (
        builtins.toJSON {
          version = 1;
          mcpServers = lib.attrNames mcpServers;
          hooks = lib.attrNames hooks;
          plugins = lib.attrNames pluginsByDir;
          cliSettings = lib.optionals cliEnabled (lib.attrNames cliSettingsJson);
          userSettings = lib.attrNames hubTheme;
        }
      );

      activationResult = import ./_activation.nix {
        inherit
          lib
          pkgs
          mcpServersFile
          hooksFile
          pluginsFile
          userSettingsFile
          stateFile
          cliSettingsFile
          hubStorageFile
          cliEnabled
          agyPkg
          marketplacePlugins
          ;
        xdgConfigHome = config.xdg.configHome;
      };

      antigravityInstructions = agents.systemPrompt.render {
        vars = {
          questionTool = "ask_question";
          sbx = sbxEnabled;
        };
      };

      registryAntigravitySkills = lib.filterAttrs (
        _name: skill: skill ? antigravity && skill.enabledOn osConfig
      ) agents.skills.list;

      antigravitySkillFiles = lib.mapAttrs' (
        name: skill:
        lib.nameValuePair ".gemini/config/skills/${name}/SKILL.md" { text = skill.antigravity; }
      ) registryAntigravitySkills;

      packAntigravitySkillFiles = lib.mapAttrs' (
        name: dir:
        lib.nameValuePair ".gemini/config/skills/${name}" {
          source = dir;
          recursive = true;
        }
      ) (agents.skills.packDirsFor "antigravity" osConfig);
    in
    {
      config = lib.mkIf anyEnabled {
        home = {
          file = {
            ".gemini/config/AGENTS.md".text = antigravityInstructions;
          }
          // antigravitySkillFiles
          // packAntigravitySkillFiles;

          inherit (activationResult) activation;
        };
      };
    };
}
