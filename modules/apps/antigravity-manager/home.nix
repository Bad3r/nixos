/*
  Package: antigravity-manager
  Description: Antigravity account manager and local Anthropic, OpenAI, and Gemini API proxy.
  Homepage: https://github.com/lbjlaq/Antigravity-Manager
  Documentation: https://github.com/lbjlaq/Antigravity-Manager#readme
  Repository: https://github.com/lbjlaq/Antigravity-Manager

  Summary:
    * Runs `antigravity-server` as a user service bound to 127.0.0.1, with its state in ~/.antigravity_tools.
    * `antigravity-manager-key` prints the proxy API key the server keeps in gui_config.json.
    * `claude-antigravity` starts the Claude Code launcher against the proxy instead of the Anthropic subscription.
    * `codex --profile antigravity` points Codex at the proxy's Responses endpoint.
*/
_: {
  flake.homeManagerModules.apps."antigravity-manager" =
    {
      osConfig,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = osConfig.services."antigravity-manager".extended;
      baseUrl = "http://127.0.0.1:${toString cfg.port}";
      guiConfig = "${config.home.homeDirectory}/.antigravity_tools/gui_config.json";
      claudeEnabled = lib.attrByPath [ "programs" "claude-code" "extended" "enable" ] false osConfig;
      codexEnabled = lib.attrByPath [ "programs" "codex" "extended" "enable" ] false osConfig;

      keyHelper = pkgs.writeShellApplication {
        name = "antigravity-manager-key";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          config=${lib.escapeShellArg guiConfig}
          if ! jq -er '.proxy.api_key | select(type == "string" and length > 0)' "$config" 2>/dev/null; then
            echo "antigravity-manager-key: no proxy.api_key in $config; start antigravity-manager.service first" >&2
            exit 1
          fi
        '';
      };

      # An env token outranks the claude.ai login, which stays stored for plain `claude`.
      claudeLauncher = pkgs.writeShellApplication {
        name = "claude-antigravity";
        text = ''
          token=$(${lib.getExe keyHelper})
          export ANTHROPIC_BASE_URL=${lib.escapeShellArg baseUrl}
          export ANTHROPIC_AUTH_TOKEN="$token"
          unset ANTHROPIC_API_KEY
          exec ${lib.escapeShellArg "${config.home.homeDirectory}/.local/bin/claude"} "$@"
        '';
      };

      codexProfile = (pkgs.formats.toml { }).generate "codex-antigravity.config.toml" {
        model_provider = "antigravity-manager";
        model = cfg.codexModel;
        model_providers.antigravity-manager = {
          name = "Antigravity Manager";
          base_url = "${baseUrl}/v1";
          wire_api = "responses";
          auth.command = lib.getExe keyHelper;
        };
      };
    in
    {
      config = lib.mkIf cfg.enable {
        home.file = {
          ".local/bin/antigravity-manager-key".source = lib.getExe keyHelper;
        }
        // lib.optionalAttrs claudeEnabled {
          ".local/bin/claude-antigravity".source = lib.getExe claudeLauncher;
        };

        # Codex layers $CODEX_HOME/<name>.config.toml over the merged config for `--profile <name>`.
        xdg.configFile."codex/antigravity.config.toml" = lib.mkIf codexEnabled {
          source = codexProfile;
        };

        systemd.user.services.antigravity-manager = {
          Unit.Description = "Antigravity Manager API proxy and web UI";
          Service = {
            # --host 127.0.0.1 also turns off LAN access in gui_config.json.
            ExecStart = "${lib.getExe' cfg.package "antigravity-server"} --host 127.0.0.1 --port ${toString cfg.port}";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}
